"""按字体**角色**核对字形覆盖，而不是笼统地算「字体有多少字」。

FontRoles 的映射（lib/src/theme.dart）：
  official → content=SEGA, numeric=Josefin, label=MiSans
  classic  → content=SEGA, numeric=Josefin, label=null(系统)
  system   → 全 null(系统)

所以曲名/读音/角色名一律走 SEGA，中文界面文案走 MiSans，数字与拉丁装饰走 Josefin。
缺字不会报错、只会画成豆腐块或掉到系统字体，所以必须提前量。

界面文案的字符集靠扫描 Dart **字符串字面量**得到：注释里全是中文（还夹着权重表
里的希腊字母），直接全文扫会把它们算成「要渲染的字符」。

用法：
    <managed venv>/Scripts/python.exe tool/check_font_coverage.py
"""

import json
import pathlib
import sys

from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
FONTS = {
    "SEGA": "assets/fonts/SEGA_MaruGothicDB_traced.ttf",
    "Josefin": "assets/fonts/JosefinSans-Bold.ttf",
    "MiSans": "assets/fonts/MiSans-Medium.ttf",
}
# 只有这些文件负责渲染界面文字；domain.dart / collation_han.dart 里的大段字符串
# 是权重表，不是要画给人看的东西。
UI_SOURCES = ["app.dart", "screens.dart", "theme.dart", "repository.dart"]

CJK = lambda c: 0x4E00 <= ord(c) <= 0x9FFF
KANA = lambda c: 0x3040 <= ord(c) <= 0x30FF


def _string_chars(src: str) -> set[str]:
    """扫 Dart 字符串字面量，返回其中的非 ASCII 字符。跳过注释与转义。"""
    out: set[str] = set()
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        two = src[i : i + 2]
        if two == "//":
            i = src.find("\n", i)
            if i < 0:
                break
            continue
        if two == "/*":
            end = src.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        if ch in "'\"":
            quote = ch * 3 if src[i : i + 3] == ch * 3 else ch
            i += len(quote)
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src.startswith(quote, i):
                    i += len(quote)
                    break
                if len(quote) == 1 and src[i] == "\n":
                    break  # 未闭合的单行字符串，别把后面全吞掉
                if ord(src[i]) > 0x7E:
                    out.add(src[i])
                i += 1
            continue
        i += 1
    return out


def load_charsets():
    dataset = json.loads((ROOT / "assets/songs-2026.10.15.json").read_text("utf-8"))
    songs = dataset.get("songs", dataset)

    content = set()  # SEGA：曲名 / 读音 / 角色名 / 版本名
    numeric = set()  # Josefin：定数、物量、难度标号（数字与拉丁）
    for song in songs:
        for key in ("title", "titleKana", "character", "releaseTag", "artist"):
            content.update(song.get(key) or "")
        for chart in song.get("charts") or []:
            numeric.update(str(chart.get("level") or ""))
            numeric.update(str(chart.get("levelDecimal") or ""))
            numeric.update(str(chart.get("noteCount") or ""))
    numeric.update("0123456789.+-/")

    ui = set()  # MiSans：中文界面文案
    for name in UI_SOURCES:
        path = ROOT / "lib" / "src" / name
        if path.exists():
            ui |= _string_chars(path.read_text("utf-8"))

    clean = lambda s: {c for c in s if not c.isspace() and ord(c) > 0x1F}
    return clean(content), clean(numeric), clean(ui)


def cmap_of(path):
    font = TTFont(path, fontNumber=0, lazy=False)
    table = set()
    for sub in font["cmap"].tables:
        if sub.isUnicode():
            table.update(sub.cmap.keys())
    font.close()
    return table


def report(label, rel, charset, kind):
    path = ROOT / rel
    cmap = cmap_of(path)
    missing = sorted(c for c in charset if ord(c) not in cmap)
    covered = len(charset) - len(missing)
    pct = 100 * covered / max(len(charset), 1)
    print(
        f"{label:8} {kind:12} {covered:4}/{len(charset):<4} {pct:5.1f}%  "
        f"字体码位 {len(cmap)}",
        end="",
    )
    if missing:
        print(f"  缺：{''.join(missing)}")
    else:
        print()
    return missing


def main():
    content, numeric, ui = load_charsets()
    size_mb = lambda rel: (ROOT / rel).stat().st_size / 1e6

    print("随包字体与体积：")
    for name, rel in FONTS.items():
        print(f"  {name:8} {size_mb(rel):5.1f} MB  {rel}")
    print(f"  {'合计':8} {sum(size_mb(r) for r in FONTS.values()):5.1f} MB\n")

    print("字形覆盖（按实际渲染角色）：")
    miss = {}
    miss["SEGA"] = report("SEGA", FONTS["SEGA"], content, "曲名/读音/角色")
    report("Josefin", FONTS["Josefin"], numeric, "数字/拉丁")
    miss["MiSans"] = report("MiSans", FONTS["MiSans"], ui, "界面文案")

    # SEGA 缺的字会掉到系统字体（Flutter 有 fallback），不是豆腐块，但字形不一致。
    if miss["SEGA"]:
        print("\nSEGA 缺的曲库字符具体出现在：")
        dataset = json.loads((ROOT / "assets/songs-2026.10.15.json").read_text("utf-8"))
        for ch in miss["SEGA"]:
            titles = [
                s["title"]
                for s in dataset.get("songs", dataset)
                if ch in (s.get("title") or "") + (s.get("titleKana") or "")
            ]
            print(f"  {ch}  {len(titles)} 首：{' / '.join(titles[:3])}")

    print()
    licenses = [
        str(p.relative_to(ROOT))
        for p in ROOT.rglob("*")
        if p.is_file()
        and any(k in p.name.upper() for k in ("LICENSE", "OFL", "COPYING"))
        and ".gradle" not in str(p)
        and "build" not in p.parts
    ]
    print(f"随包许可文件：{licenses or '无（MiSans / SEGA 的许可文本未随包）'}")
    return 0 if not miss["SEGA"] else 1


if __name__ == "__main__":
    sys.exit(main())
