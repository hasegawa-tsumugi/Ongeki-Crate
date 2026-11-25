"""检查 release APK 的内容是否自洽 —— 不只看「构建成功」。

构建成功不等于包里是对的东西：多 ABI 会让包体翻几倍、改过的文案可能没进包、
资源可能漏打、拿错包交付。这里按 README 里「交付前必做」那一节逐项校验。

包身份（package / versionName / versionCode）是直接解析二进制 AndroidManifest.xml
读出来的 —— 不从 `libapp.so` 的字符串猜，因为它验的是界面显示，不是安装身份。

用法：
    python tool/check_apk.py [apk 路径]

默认查 build/app/outputs/flutter-apk/app-release.apk。任何一项不过就以非 0 退出。
"""

import hashlib
import io
import os
import re
import struct
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_APK = os.path.join(
    ROOT, "build", "app", "outputs", "flutter-apk", "app-release.apk"
)
PUBSPEC = os.path.join(ROOT, "pubspec.yaml")

EXPECTED_ABI = {"arm64-v8a"}
PACKAGE_ID = "dev.tsumugi.songquery"

# Dart AOT 快照里的字符串是 UTF-16LE，直接按 UTF-8 grep 中文永远 0 命中。
MUST_CONTAIN = ["曲名／读音／别名／ID", "曲库是空的", "字体方案", "使用了 MiSans 字体",
                "应用并返回", "删除确认",
                # 排序三栏 = 表格三组：分组项 + 段内排序项 + 对手榜项，各挑一个做样本。
                # 选项一律用游戏原文（不翻译），这里顺带验「真的没漏成中文」。
                "譜面レベル", "対戦相手のレベル順", "オススメ順", "追加日順", "チャプター順",
                "テクニカルスコア",
                # 底部导航栏：三个页签名。页签名很短（「我的」），
                # 单独 grep 容易撞到别的句子，所以连「设置/关于」入口一起验。
                # 占位页的说明句已删（2026-11-24 用户要求删页内文字解释），
                # 别再拿它当锚点 —— 那会让检查必然失败。
                "主页", "工具", "我的", "设置", "关于"]
# 旧的中文译名必须彻底消失，否则说明某一处还在用翻译版。
MUST_ABSENT = ["曲名・读音", "按难度排序", "推荐顺序", "对手等级", "章节顺",
               # 菜单页已随底栏改造下线：设置/关于现在挂在「我的」页签里。
               # 这个字符串如果还在，说明旧的菜单页又回来了。
               "菜单"]

REQUIRED_ASSETS = [
    "assets/flutter_assets/assets/fonts/MPLUS1p-Bold.ttf",
    "assets/flutter_assets/assets/fonts/MPLUS1p-Medium.ttf",
    "assets/flutter_assets/assets/fonts/LICENSE-MPLUS1p.txt",
    "assets/flutter_assets/assets/tex/bg_mesh.webp",
    "assets/flutter_assets/assets/tex/bg_circuit.webp",
    "assets/flutter_assets/assets/songs-2026.10.15.json",
    # 液态玻璃的折射 shader —— 由 `fluid_glass` 包自带（不是本项目 assets）。
    # 漏打时界面不会崩，只会静默退化成磨砂玻璃，正是那种「看不出来但效果
    # 没了」的失败，必须按资源存在性验。
    "assets/flutter_assets/packages/fluid_glass/shaders/refraction.frag",
    "assets/flutter_assets/assets/fonts/MiSans-Medium.ttf",
    "assets/flutter_assets/assets/fonts/JosefinSans-Bold.ttf",
    "assets/flutter_assets/assets/fonts/SEGA_MaruGothicDB_traced.ttf",
    # 许可文本随包（OFL 要求许可随字体分发；MiSans 要求软件内注明使用）。
    "assets/flutter_assets/assets/fonts/LICENSE-JosefinSans.txt",
    "assets/flutter_assets/assets/fonts/THIRD-PARTY-NOTICES.txt",
]

failures = []
checks = 0


def check(label, ok, detail=""):
    global checks
    checks += 1
    print(f"[{'PASS' if ok else 'FAIL'}] {label}{('  ' + detail) if detail else ''}")
    if not ok:
        failures.append(label)


def decode(data, needle):
    return needle.encode("utf-16-le") in data or needle.encode("utf-8") in data


def pubspec_version():
    """从 pubspec.yaml 读版本名，返回 (name, code)。

    2026-11-24 起 build 号已取消（用户要求「build 不要了」），pubspec 只写
    `0.1.2-beta1` 这种纯版本名，code 恒为 None —— versionCode 改由
    `android/app/build.gradle.kts` 固定，见那里的注释。
    旧格式 `0.1.1+8` 仍兼容，方便拿旧包做反向验证。
    """
    text = io.open(PUBSPEC, encoding="utf-8").read()
    m = re.search(r"^version:\s*(\S+)\s*$", text, re.MULTILINE)
    if not m:
        raise ValueError("pubspec.yaml 里找不到 version 行")
    name, sep, code = m.group(1).partition("+")
    return name, (int(code) if sep and code else None)


def gradle_version_code():
    """从 android/app/build.gradle.kts 读写死的 versionCode。"""
    path = os.path.join(ROOT, "android", "app", "build.gradle.kts")
    text = io.open(path, encoding="utf-8").read()
    m = re.search(r"^\s*versionCode\s*=\s*(\d+)", text, re.MULTILINE)
    if not m:
        raise ValueError("build.gradle.kts 里找不到写死的 versionCode")
    return int(m.group(1))


def manifest_identity(data):
    """直接解析二进制 AndroidManifest.xml，取 manifest 上的 package / versionName / versionCode。

    为什么不 grep 字符串：versionName 只是字符串池里的一条，grep 命中说明不了
    「它真的挂在 manifest 上」；versionCode 是整数，根本不在池里。
    这里按 AXML 的 chunk 结构读属性表 —— 和 `aapt dump badging` 看到的是同一个真值，
    但不依赖 Android SDK 是否装在这台机器上。
    """
    if struct.unpack_from("<H", data, 0)[0] != 0x0003:
        raise ValueError("不是 AXML（文件头不是 0x0003）")
    header = struct.unpack_from("<H", data, 2)[0]

    pool = []
    found = {}
    pos = header
    while pos + 8 <= len(data):
        ctype, _chs, csize = struct.unpack_from("<HHI", data, pos)
        if csize <= 0:
            break
        if ctype == 0x0001:  # string pool
            count, _styles, flags, start = struct.unpack_from("<IIII", data, pos + 8)
            utf8 = bool(flags & (1 << 8))
            offsets = struct.unpack_from("<%dI" % count, data, pos + 28)
            base = pos + start
            for off in offsets:
                p = base + off
                if utf8:
                    p += 2 if data[p] & 0x80 else 1
                    ln = data[p]
                    if ln & 0x80:
                        ln = ((ln & 0x7F) << 8) | data[p + 1]
                        p += 2
                    else:
                        p += 1
                    pool.append(data[p:p + ln].decode("utf-8", "replace"))
                else:
                    ln = struct.unpack_from("<H", data, p)[0]
                    if ln & 0x8000:
                        ln = ((ln & 0x7FFF) << 16) | struct.unpack_from("<H", data, p + 2)[0]
                        p += 4
                    else:
                        p += 2
                    pool.append(data[p:p + ln * 2].decode("utf-16-le", "replace"))
        elif ctype == 0x0102:  # start tag
            _ns, name, attr_start, attr_size, attr_count = struct.unpack_from(
                "<IIHHH", data, pos + 16
            )
            tag = pool[name] if name < len(pool) else ""
            for i in range(attr_count):
                at = pos + 16 + attr_start + i * attr_size
                _ans, aname, raw, _vsize, _vres, vtype, vdata = struct.unpack_from(
                    "<IIIHBBI", data, at
                )
                key = pool[aname] if aname < len(pool) else ""
                if tag == "manifest" and key in ("package", "versionName", "versionCode"):
                    if key == "versionCode" or vtype == 0x10:
                        found[key] = vdata
                    else:
                        found[key] = pool[raw] if raw < len(pool) else str(vdata)
        pos += csize
    return found


def main():
    apk = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_APK
    if not os.path.exists(apk):
        print(f"[FAIL] APK 不存在：{apk}")
        return 1

    raw = io.open(apk, "rb").read()
    size = len(raw)
    digest = hashlib.md5(raw).hexdigest()
    print(f"APK  {apk}")
    print(f"      {size:,} 字节   md5 {digest}\n")

    with zipfile.ZipFile(apk) as z:
        names = z.namelist()

        abis = {
            name.split("/")[1] for name in names if name.startswith("lib/")
        }
        check("只含目标 ABI", abis == EXPECTED_ABI, f"实际 {sorted(abis)}")

        manifest = z.read("AndroidManifest.xml")
        try:
            ident = manifest_identity(manifest)
        except Exception as exc:  # 解析失败必须是 FAIL，不能悄悄放过
            ident = {}
            check("manifest 可解析", False, f"{type(exc).__name__}: {exc}")
        else:
            check("manifest 可解析", True)

        check("包名", ident.get("package") == PACKAGE_ID, str(ident.get("package")))

        # 包身份 = 安装时判定新旧的依据。`libapp.so` 里那条版本标签是界面显示用的，
        # 两者可能不同步（pubspec 改了但构建缓存给出旧 manifest），必须各自断言。
        name, code = pubspec_version()
        check("versionName 与 pubspec 一致", ident.get("versionName") == name,
              f"manifest {ident.get('versionName')} / pubspec {name}")
        # build 号已取消：versionCode 现在由 build.gradle.kts 写死，
        # 不再跟 pubspec 联动（pubspec 里根本没有 +N 了）。
        expected_code = code if code is not None else gradle_version_code()
        check("versionCode 与 build.gradle 一致",
              ident.get("versionCode") == expected_code,
              f"manifest {ident.get('versionCode')} / gradle {expected_code}")

        snapshot = z.read("lib/arm64-v8a/libapp.so")
        # 界面显示的版本标签（version.dart 的 appVersionLabel，如 0.1.2-beta1）。
        # 从 pubspec 推导、不写死进 MUST_CONTAIN，避免两处漂移。
        check(f"包内含版本标签「{name}」", decode(snapshot, name))
        for text in MUST_CONTAIN:
            check(f"包内含「{text}」", decode(snapshot, text))
        for text in MUST_ABSENT:
            check(f"包内不含旧文案「{text}」", not decode(snapshot, text))

        for asset in REQUIRED_ASSETS:
            check(f"资源 {os.path.basename(asset)}", asset in names)

        # shader 必须是编译后的 IPLR（impellerc 产物，头部 magic = IPLR）。
        # 若 pubspec 把 .frag 错放进 assets: 而不是 shaders:，包里会是**源文本**，
        # 文件名照样对、资源照样在，只有运行时的 FragmentProgram.fromAsset 会失败，
        # 然后静默退化成磨砂玻璃 —— 没有这条断言根本发现不了。
        # fluid_glass 的关键 program 都查：折射、色散折射、默认沿边高光、
        # 跟手高光。它们是 ImageFilter.shader / Paint.shader 的输入，
        # 缺一个就静默少一层效果。
        for frag in (
            "refraction.frag",
            "refraction_dispersion.frag",
            "highlight_default.frag",
            "interactive_highlight.frag",
        ):
            shader = f"assets/flutter_assets/packages/fluid_glass/shaders/{frag}"
            if shader in names:
                head = z.read(shader)[:8]
                check(f"shader {frag} 已编译成 IPLR", head[4:8] == b"IPLR",
                      f"头部 {head!r}")
            else:
                check(f"shader {frag} 已编译成 IPLR", False, "包里没有它")

    print()
    if failures:
        print(f"{len(failures)}/{checks} 项不通过")
        return 1
    print(f"{checks}/{checks} 项通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
