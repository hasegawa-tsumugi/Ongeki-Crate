# -*- coding: utf-8 -*-
"""把 Flutter App 的界面复刻成可点的网页（正式软件形态，不是截图对照页）。

字体做子集化后内联，背景纹理与曲绘（能下到的部分）也内联，产出单文件
HTML，双击就能用：能搜索、能排序、能打开详情、能切字号、能切字体方案。

用法：
    python tool/build_webapp.py
输出：
    D:\\WorkBuddy space\\outputs\\songquery-webapp\\index.html
"""

import base64
from html import escape
import io
import json
import math
import os
import re
import sys
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "songs-2026.10.15.json")
FONTS = os.path.join(ROOT, "assets", "fonts")
TEX = os.path.join(ROOT, "assets", "tex")
ART = os.path.join(ROOT, "build", "webapp-art")
OUT_DIR = r"D:\WorkBuddy space\outputs\songquery-webapp"

ART_BASES = [
    "https://gcore.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/jacket/{}",
    "https://testingcf.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/jacket/{}",
    "https://otoge-db.net/ongeki/jacket/{}",
]

# 星咲 あかり 等角色名、全部曲名、作者、分类、版本、章节都要能显示
CJK = (
    "\u3000\u30fb\u30fc\u2015\u2018\u2019\u201c\u201d\u2026\u3041-\u309f"
    "\u30a0-\u30ff\u4e00-\u9fff\uff01-\uff5e\uff61-\uff9f\u2460-\u24ff"
    "\u2600-\u27bf\u2660-\u2667"
)


def load_songs():
    with open(DATA, encoding="utf-8") as f:
        return json.load(f)["songs"]


UPSTREAM_URLS = [
    "https://fastly.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/data/music-ex.json",
    "https://raw.githubusercontent.com/hasegawa-tsumugi/otoge-db/main/ongeki/data/music-ex.json",
]


def load_upstream_slots():
    """谱师名在本地快照里没有 —— 从上游按 (id, 难度) 取一份。

    `music-ex.json` 是扁平的，每首曲子的四五个难度各自是独立的 `lev_*` 前缀字段，
    所以谱师要从 `lev_{bas,adv,exc,mas,lnt}_designer` 里读。下载失败就退化成
    只显示物量/铃铛，不影响生成。
    """
    cache = os.path.join(ART, "music-ex.json")
    raw = None
    if os.path.exists(cache):
        raw = open(cache, "rb").read()
    else:
        for url in UPSTREAM_URLS:
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
                with urllib.request.urlopen(req, timeout=25) as resp:
                    raw = resp.read()
                os.makedirs(ART, exist_ok=True)
                with open(cache, "wb") as f:
                    f.write(raw)
                break
            except Exception as exc:  # noqa: BLE001
                print("  upstream miss", url.split("/")[2], type(exc).__name__)
    if not raw:
        return {}
    rows = json.loads(raw.decode("utf-8"))
    prefixes = ["bas", "adv", "exc", "mas", "lnt"]
    out = {}
    for row in rows:
        for index, prefix in enumerate(prefixes):
            designer = (row.get("lev_%s_designer" % prefix) or "").strip()
            if designer:
                out[(row["id"], index)] = designer
    return out


def used_text(songs, designers):
    parts = []
    for song in songs:
        parts += [
            song.get("title") or "",
            song.get("titleKana") or "",
            song.get("artist") or "",
            song.get("genre") or "",
            song.get("releaseTag") or "",
            song.get("chapter") or "",
            song.get("character") or "",
            song.get("enemyType") or "",
        ]
        for chart in song.get("charts") or []:
            parts.append(str(chart.get("levelLabel") or chart.get("level") or ""))
            parts.append(designers.get((song.get("id"), chart.get("difficulty", 0)), ""))
    return "".join(parts)


def subset_font(path, text, out_name):
    """子集化 → woff2 → base64。给网页用，不做 Hinting，体积优先。"""
    os.makedirs(ART, exist_ok=True)
    out_path = os.path.join(ART, out_name)
    options = subset.Options()
    options.flavor = "woff2"
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    options.recalc_bounds = True
    options.drop_tables += ["DSIG", "CFF2"]
    font = TTFont(path)
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    font.flavor = "woff2"
    font.save(out_path)
    with open(out_path, "rb") as f:
        data = f.read()
    return base64.b64encode(data).decode("ascii"), len(data)


def b64_file(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def fetch_art(songs, limit=14):
    """曲绘能下就下（用 App 里同一套 CDN 地址），下不到就留空，网页里显示占位。"""
    os.makedirs(ART, exist_ok=True)
    picked, seen = [], set()
    for song in songs:
        artwork = song.get("artwork")
        if not artwork or artwork in seen:
            continue
        seen.add(artwork)
        picked.append(artwork)
        if len(picked) >= limit:
            break
    out = {}
    for artwork in picked:
        local = os.path.join(ART, artwork)
        if not os.path.exists(local):
            for base in ART_BASES:
                url = base.format(artwork)
                try:
                    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
                    with urllib.request.urlopen(req, timeout=12) as resp:
                        blob = resp.read()
                    if blob[:8] == b"\x89PNG\r\n\x1a\n" and len(blob) > 2000:
                        with open(local, "wb") as f:
                            f.write(blob)
                        break
                except Exception as exc:  # noqa: BLE001 - 网络问题不该中断构建
                    print("  art miss", artwork, type(exc).__name__)
        if os.path.exists(local):
            out[artwork] = b64_file(local)
    return out


def build_payload(songs, art, designers):
    """只留网页用得到的字段，把 1112 首压到最小。"""
    rows = []
    for song in songs:
        charts = [
            {
                "d": c.get("difficulty", 0),
                "l": c.get("levelLabel") or str(c.get("level") or ""),
                # levelValue 是排序真值：label 的「13+」用 parseFloat 会读成 13，
                # 实际是 13.7–13.9，直接拿 label 排会和 App 顺序对不上。
                "v": c.get("levelValue"),
                "n": c.get("noteCount"),
                "b": c.get("bells"),
                "g": (
                    c.get("designer")
                    or designers.get((song.get("id"), c.get("difficulty", 0)))
                    or ""
                ),
                "u": c.get("chartLink") or "",
            }
            for c in song.get("charts") or []
            if c.get("enabled", True)
        ]
        rows.append(
            {
                "i": song.get("id"),
                "t": song.get("title") or "",
                "k": song.get("titleKana") or "",
                "a": song.get("artist") or "",
                "g": song.get("genre") or "",
                "b": song.get("bpm"),
                "r": song.get("releaseTag") or "",
                "n": 1 if song.get("isNew") else 0,
                "c": song.get("chapter") or "",
                "cid": song.get("chapterId") or "",
                "p": song.get("character") or "",
                "ci": song.get("characterId") or "",
                "el": song.get("enemyLevel"),
                "e": "%s%s"
                % (
                    "Lv %s " % song.get("enemyLevel") if song.get("enemyLevel") else "",
                    song.get("enemyType") or "",
                ),
                "dd": song.get("dateAdded") or "",
                "w": song.get("wikiUrl") or "",
                "art": song.get("artwork") or "",
                "al": song.get("aliases") or [],
                "ch": charts,
            }
        )
    return rows


def read_app_version():
    """从 pubspec.yaml 取 `version:` 一行。

    网页版一直没有版本标识，同一屏界面截出来分不清是哪次构建 —— 关于页
    补一行「应用版本」，跟着 pubspec 走，不另开一份手写常量。
    """
    with open(os.path.join(ROOT, "pubspec.yaml"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("version:"):
                return line.split(":", 1)[1].strip()
    return "unknown"


def main():
    songs = load_songs()
    print("fetching chart designers ...")
    designers = load_upstream_slots()
    print("  got %d designer slots" % len(designers))
    text = used_text(songs, designers)
    # 界面上的固定文案也要进子集，否则会掉成系统字
    ui = (
        "曲名读音别名ID搜索与筛选关键词默认角色版本重置排序列表排序最高谱面等级"
        "按难度排序条件从上到下逐级比较可留空不指定难度档位谱面等级对手等级高→低新旧"
        "结果首筛选项分类难度与等级全部清除应用返回上一页并保留条件"
        "设置字体方案官方混排旧版游戏圆体系统界面字全部系统字体预览定数物量"
        "外观主题模式跟随系统深色浅色已手动选择当前为更改立即生效并自动保存不依赖设置手机端请从菜单进入直接选择与设置页同步"
        "关于数据更新状态下载中曲目谱面快照曲库来源检查更新删除本地"
        "章节对战角色敌方上架日期更新日期标记新曲版权攻略谱面确认谱面预览外部链接信息曲绘原图内部信息谱师物量铃铛"
        "数据版本错误重试加载中当前数据集没有可用谱面收录信息难度别名"
        "本软件使用了 MiSans 字体。仅个人自用非官方应用"
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        " .,:;!?'\"()[]{}<>/\\|-_+=*&%#@~^`$　、。「」『』（）【】…—・♥★☆◆⇔→›～"
    )
    text += ui + CJK

    fonts = {}
    for name, path in [
        ("Official", "JosefinSans-Bold.ttf"),
        ("MPLUS1p-M", "MPLUS1p-Medium.ttf"),
        ("MPLUS1p-B", "MPLUS1p-Bold.ttf"),
        ("MiSans", "MiSans-Medium.ttf"),
        ("SEGA", "SEGA_MaruGothicDB_traced.ttf"),
    ]:
        data, size = subset_font(os.path.join(FONTS, path), text, name + ".woff2")
        fonts[name] = data
        print("font %-10s %6.1f KB" % (name, size / 1024))

    print("fetching jackets ...")
    art = fetch_art(songs)
    print("  got %d / 14 jackets" % len(art))

    print("fetching chart designers ...")
    payload = build_payload(songs, art, designers)
    html = render(
        payload=payload,
        genre_ids={song['genre']: song['genreId'] for song in songs
                   if song.get('genre') and song.get('genreId')},
        art=art,
        fonts_official=fonts["Official"],
        fonts_mplus1p_m=fonts["MPLUS1p-M"],
        fonts_mplus1p_b=fonts["MPLUS1p-B"],
        fonts_misans=fonts["MiSans"],
        fonts_sega=fonts["SEGA"],
        mesh=b64_file(os.path.join(TEX, "bg_mesh.webp")),
        circuit=b64_file(os.path.join(TEX, "bg_circuit.webp")),
        license_text=escape("\n\n".join(
            open(os.path.join(FONTS, name), encoding="utf-8").read()
            for name in ("THIRD-PARTY-NOTICES.txt", "LICENSE-JosefinSans.txt", "LICENSE-MPLUS1p.txt")
        )),
        data_size="%.1f MB" % (os.path.getsize(DATA) / (1 << 20)),
        app_version=read_app_version(),

    )

    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "index.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    print("written:", out, "%.1f KB" % (len(html.encode()) / 1024))


def render(**kw):
    tpl_path = os.path.join(ROOT, "tool", "webapp", "index.template.html")
    with open(tpl_path, encoding="utf-8") as f:
        tpl = f.read()
    for key, value in kw.items():
        if isinstance(value, str):
            tpl = tpl.replace("{{%s}}" % key.upper(), value)
        else:
            tpl = tpl.replace(
                "{{%s}}" % key.upper(), json.dumps(value, ensure_ascii=False)
            )
    return tpl


if __name__ == "__main__":
    main()
