"""上游数据体检：线路一致性 + 曲绘完整性 + 曲目数不回退。

跑法：
    python tool/check_upstream.py            # 抽样 6 张曲绘
    python tool/check_upstream.py --samples 12

它回答三个问题：
1. 四条数据线路给出的**是不是同一份**文件（字节数与 sha256 完全一致）
2. 抽样的曲绘在三家线路上是不是**同一张完好的图**（PNG 魔数 + 字节数一致）
3. 上游曲目数有没有比随包快照更少（少 = 上游被清过或换源了）

**判据一律用「内容」而不是 HTTP 200**：截断的响应、占位图、被 CDN 替换的错误页
都可能返回 200。这条是有来由的——之前用 `curl -o /dev/null` 量大小，在这个环境里
curl 会提前中止写入，`size_download` 只报前几百字节，看着像 CDN 在给截断包，
其实全是探针自己的问题。所以这里按实际收到的字节数比对。

需要联网，不放在 verify.py 里（那条命令要保持离线可跑）。
"""

import argparse
import hashlib
import io
import json
import os
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET = os.path.join(ROOT, "assets", "songs-2026.10.15.json")

DATA_MIRRORS = [
    "https://fastly.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/data/music-ex.json",
    "https://cdn.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/data/music-ex.json",
    "https://gcore.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/data/music-ex.json",
    "https://raw.githubusercontent.com/hasegawa-tsumugi/otoge-db/main/ongeki/data/music-ex.json",
]

JACKET_MIRRORS = [
    "https://gcore.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/jacket/",
    "https://testingcf.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/jacket/",
    "https://otoge-db.net/ongeki/jacket/",
]

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
failures = []

# 最后一条兜底线路（raw.githubusercontent）在这台机器上下 1.6MB 经常超时。
# 它不可用不影响应用（前三家都正常），所以记 WARN 而不是 FAIL ——
# 体检全红一次两次还能看，永远红就没人看了。
MIN_DATA_MIRRORS = 3


def fetch(url, timeout=40):
    req = urllib.request.Request(url, headers={"User-Agent": "songquery-verify/1"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return res.status, res.read()


def check(label, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {label}{('  ' + detail) if detail else ''}")
    if not ok:
        failures.append(label)


def warn(label, detail=""):
    print(f"[WARN] {label}{('  ' + detail) if detail else ''}")


def main():
    parser = argparse.ArgumentParser(description="上游数据体检")
    parser.add_argument("--samples", type=int, default=6, help="抽样曲绘数量")
    args = parser.parse_args()

    print("== 数据线路一致性 ==")
    digests = {}
    sizes = {}
    for url in DATA_MIRRORS:
        host = url.split("/gh/")[0].split("//")[1]
        try:
            status, body = fetch(url, timeout=25)
            sizes[host] = len(body)
            digests[host] = hashlib.sha256(body).hexdigest()
            check(f"{host} 可下载", status == 200, f"{len(body):,} 字节")
        except (urllib.error.URLError, OSError, TimeoutError) as exc:
            warn(f"{host} 不可用", str(exc)[:60])

    check(
        f"至少 {MIN_DATA_MIRRORS} 条线路可达",
        len(digests) >= MIN_DATA_MIRRORS,
        f"{len(digests)}/{len(DATA_MIRRORS)}",
    )
    if digests:
        unique = set(digests.values())
        # 标签必须按**实际可达的家数**写：只比到 3 家还叫「四家一致」，
        # 就等于把那条线路的超时当成通过了。
        check(
            f"{len(digests)} 条可达线路内容一致",
            len(unique) == 1,
            "sha256 " + next(iter(unique))[:16] + "…"
            if len(unique) == 1
            else f"出现 {len(unique)} 种内容：{sizes}",
        )

    rows = None
    if digests:
        try:
            status, body = fetch(DATA_MIRRORS[0])
            parsed = json.load(io.BytesIO(body))
            rows = len(parsed) if isinstance(parsed, list) else -1
            check("能被解析成行数组", rows > 0, f"{rows} 行")
        except Exception as exc:  # noqa: BLE001 - 体检脚本，任何异常都算不通过
            check("能被解析成行数组", False, str(exc)[:80])

    print("\n== 随包快照 ==")
    with io.open(ASSET, encoding="utf-8") as fh:
        snapshot = json.load(fh)["songs"]
    print(f"     {len(snapshot)} 首")
    if rows:
        # 上游比快照少 = 上游被清过或换了数据源，属于必须有人看一眼的情况。
        check("上游曲目数不少于随包快照", rows >= len(snapshot), f"上游 {rows} / 快照 {len(snapshot)}")

    names = [s["artwork"] for s in snapshot if s.get("artwork")]
    step = max(1, len(names) // max(1, args.samples))
    picked = names[::step][: args.samples]

    print(f"\n== 曲绘抽样（{len(picked)} 张 × {len(JACKET_MIRRORS)} 条线路）==")
    for name in picked:
        per_host = {}
        for base in JACKET_MIRRORS:
            host = base.split("//")[1].split("/")[0]
            try:
                status, body = fetch(base + name)
                good = status == 200 and body.startswith(PNG_MAGIC)
                per_host[host] = len(body) if good else None
                check(f"{name} @ {host}", good, f"{len(body):,} 字节")
            except (urllib.error.URLError, OSError, TimeoutError) as exc:
                per_host[host] = None
                check(f"{name} @ {host}", False, str(exc)[:60])
        got = {v for v in per_host.values() if v}
        if got:
            check(f"{name} 三家一致", len(got) == 1, str(sorted(per_host.items())))

    print()
    if failures:
        print(f"{len(failures)} 项不通过")
        return 1
    print("上游体检通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
