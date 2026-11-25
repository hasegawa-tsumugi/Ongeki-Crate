"""一条命令跑完交付前体检：analyze → test →（可选）构建 → APK 内容校验。

    python tool/verify.py            # 分析 + 测试 + 校验已有 APK
    python tool/verify.py --build    # 顺带重打 arm64 release APK
    python tool/verify.py --coverage # 测试带覆盖率并打印分文件汇总

逻辑放在 Python 而不是 .bat 里，是因为 cmd 的 label/errorlevel 那套没法自测；
这里每一步都能在本机真实跑通再交付。`verify.bat` 只是给双击用的启动器。
"""

import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APK = os.path.join(ROOT, "build", "app", "outputs", "flutter-apk", "app-release.apk")

FAILED = []


def rule(title):
    print(f"\n=== {title} ===", flush=True)


def fail(step, code):
    FAILED.append(f"{step} (exit {code})")
    print(f"\n[FAIL] {step} → exit {code}", flush=True)


def find_flutter():
    """env 覆盖 → 本机 SDK → PATH。返回可直接调用的命令前缀（list）。"""
    override = os.environ.get("FLUTTER")
    if override:
        return [override]
    local = r"D:\FlutterSDK\flutter\bin\flutter.bat"
    if os.path.exists(local):
        return [local]
    return ["flutter"]


def clean_env(extra_env=None):
    """去掉代理变量再调 flutter。

    `flutter test` 要通过 localhost 的 WebSocket 连 flutter_tester，而本机
    （或 IDE、VPN 客户端）常驻一个 HTTP 代理。继承来的 `http_proxy` 会把这条
    localhost 连接也塞给代理，代理不认识 WebSocket 升级请求，于是**每个**测试
    文件都在「loading」阶段挂掉：

        Unable to connect to flutter_tester process:
        WebSocketException: Invalid WebSocket upgrade request

    这个错看着像代码坏了，其实一条断言都没跑到。既然后台全绿、换台机器也好，
    就该怀疑是环境。做法是彻底清掉代理变量，再把 localhost 加进 NO_PROXY。
    """
    env = {k: v for k, v in os.environ.items()
           if k.lower() not in ("http_proxy", "https_proxy", "all_proxy")}
    env["NO_PROXY"] = env["no_proxy"] = "localhost,127.0.0.1,::1"
    env.update(extra_env or {})
    return env


def run(cmd, step, extra_env=None):
    proc = subprocess.run(cmd, cwd=ROOT, env=clean_env(extra_env))
    if proc.returncode != 0:
        fail(step, proc.returncode)
    return proc.returncode == 0


def main():
    parser = argparse.ArgumentParser(description="songquery-flutter 交付前体检")
    parser.add_argument("--build", action="store_true", help="重打 release APK")
    parser.add_argument("--coverage", action="store_true", help="测试时生成覆盖率")
    args = parser.parse_args()

    flutter = find_flutter()
    # Gradle 需要 JAVA_HOME，而本机 JDK 不在 C:\Program Files。
    java_home = os.environ.get("JAVA_HOME") or r"D:\Java\jdk-17.0.21.0.2+1"
    env = {"JAVA_HOME": java_home} if os.path.exists(java_home) else {}

    rule("1/3  flutter analyze")
    run(flutter + ["analyze"], "analyze")

    rule("2/3  flutter test" + (" (coverage)" if args.coverage else ""))
    test_cmd = flutter + ["test"] + (["--coverage"] if args.coverage else [])
    run(test_cmd, "test")

    if args.build:
        rule("build  release apk (arm64)")
        run(
            flutter
            + ["build", "apk", "--release", "--target-platform", "android-arm64"],
            "build",
            env,
        )

    rule("3/3  apk content")
    if os.path.exists(APK):
        run([sys.executable, os.path.join(ROOT, "tool", "check_apk.py"), APK], "apk")
    else:
        print(f"[SKIP] 还没有 {os.path.relpath(APK, ROOT)}，加 --build 生成")

    if args.coverage and os.path.exists(
        os.path.join(ROOT, "coverage", "lcov.info")
    ):
        print()
        run([sys.executable, os.path.join(ROOT, "tool", "coverage_report.py")], "coverage")

    print()
    if FAILED:
        print("VERIFY FAILED: " + ", ".join(FAILED))
        return 1
    print("VERIFY OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
