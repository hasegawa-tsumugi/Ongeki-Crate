# -*- coding: utf-8 -*-
"""生成「整词断行 + 文字底面」这一轮的可视预览（单文件 HTML，图片全内联）。

用法：
    python tool/pack_fix_preview.py

截图来源：build/official-screenshots/（由 test/official_visual_test.dart 生成）
输出：D:\\WorkBuddy space\\outputs\\songquery-wordwrap-settings-preview.html
"""

import base64
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "build", "official-screenshots")
OUT = r"D:\WorkBuddy space\outputs\songquery-wordwrap-settings-preview.html"

# (文件, 标题, 说明)
GROUPS = [
    (
        "一 · 列表卡片：拉丁词不再拦腰断",
        [
            (
                "card_real_320_2.0",
                "「ＧＯ！ＧＯ！」——320 宽 / 2.0 字号",
                "改前断成「ＧＯ！Ｇ / Ｏ！ラブ」，一个词劈成两行。现在整段在一行，"
                "曲名占两行：ＧＯ！ＧＯ！ / ラブリズム♥。",
            ),
            (
                "card_real_320_1.0",
                "同一样张 320 宽 / 1.0 字号",
                "1.0 字号本来就放得下，字号一个没动 —— 这轮只影响「真的放不下」的档。",
            ),
            (
                "card_320_2.0",
                "「Sugarfull:Overbloom」——断词下限",
                "17 个字符的单元要整行放下，字号得压到 13px 以下（比作者名还小），"
                "所以停在 72% 下限、仍会断。这是刻意的：宁可断一次，也不让标题比正文小。",
            ),
            (
                "home_320_2.0",
                "首页列表整体（320 / 2.0）",
                "320 宽 + 2.0 字号时封面从 88 收到 64，把 24dp 让给文字列 —— 否则曲名"
                "要缩到和作者名一样大（26.7 vs 26），标题层级就没了。",
            ),
        ],
    ),
    (
        "二 · 设置页：文字收进卡片，不再被斜带横穿",
        [
            (
                "settings_320_2.0",
                "320 宽 / 2.0 字号",
                "改前「官方混排」的说明被黄绿斜带劈成两半。斜带位置是定死的配色没动，"
                "改的是把文字放进不透明卡片（和「关于」页同一个做法）。",
            ),
            (
                "settings_320_1.0",
                "320 宽 / 1.0 字号",
                "同样的问题在 1.0 字号也存在（「全部系统字体」整行压在黄带上），"
                "一并解决。",
            ),
        ],
    ),
    (
        "三 · 搜索页：同款问题顺手修掉",
        [
            (
                "search_320_2.0",
                "320 宽 / 2.0 字号",
                "「列表排序 · 默认（固定规则）」「结果 1112 首 · 筛选 0 项」两行黑字"
                "原来正被斜带压住，现在放进卡片。这一处是我额外发现的，不同意可以撤。",
            ),
        ],
    ),
    (
        "四 · 详情页：曲名单行不拆",
        [
            (
                "detail_320_2.0",
                "320 宽 / 2.0 字号",
                "头部曲名走单行缩放，整段「ＧＯ！ＧＯ！ラブリズム♥」在一行里，没有断词。",
            ),
        ],
    ),
]


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def b64(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def card(name, title, note):
    path = os.path.join(SHOTS, name + ".png")
    if not os.path.exists(path):
        raise SystemExit("缺少截图：" + path)
    w, h = png_size(path)
    ratio = min(1.0, 260.0 / w)
    return f"""
    <figure class="shot">
      <img src="data:image/png;base64,{b64(path)}"
           style="width:{w * ratio:.0f}px" alt="{name}">
      <figcaption><b>{title}</b><span>{note}</span></figcaption>
    </figure>"""


def main():
    parts = []
    for heading, items in GROUPS:
        parts.append(f'<h2>{heading}</h2><div class="row">')
        parts.extend(card(*item) for item in items)
        parts.append("</div>")

    html = f"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>曲库 App · 整词断行与文字底面</title>
<style>
  :root {{
    --bg:#141414; --panel:#1e1e1e; --line:#333; --ink:#f2f2f4;
    --muted:#a9a9b2; --magenta:#e84a92; --yellow:#faff00;
  }}
  * {{ box-sizing:border-box; }}
  body {{
    margin:0; padding:32px 24px 64px; background:var(--bg); color:var(--ink);
    font:15px/1.65 "MiSans","M PLUS 1p","Microsoft YaHei",system-ui,sans-serif;
  }}
  header {{ max-width:1180px; margin:0 auto 8px; }}
  h1 {{ font-size:26px; margin:0 0 6px; letter-spacing:.02em; }}
  h1 em {{ font-style:normal; color:var(--magenta); }}
  .lede {{ color:var(--muted); margin:0 0 4px; max-width:820px; }}
  .rule {{ max-width:1180px; margin:22px auto; height:3px;
           background:linear-gradient(90deg,var(--yellow) 0 33%,#32c63a 33% 66%,var(--magenta) 66% 100%); }}
  h2 {{ max-width:1180px; margin:34px auto 12px; font-size:18px; color:var(--magenta); }}
  .row {{ max-width:1180px; margin:0 auto; display:flex; flex-wrap:wrap; gap:22px; align-items:flex-start; }}
  .shot {{ margin:0; background:var(--panel); border:1px solid var(--line); border-radius:10px;
           padding:10px 10px 12px; }}
  .shot img {{ display:block; border-radius:6px; background:#000; }}
  figcaption {{ max-width:260px; margin-top:10px; display:flex; flex-direction:column; gap:5px; }}
  figcaption b {{ font-size:13.5px; }}
  figcaption span {{ font-size:12.5px; color:var(--muted); }}
  .compare {{ max-width:1180px; margin:10px auto 0; background:var(--panel); border:1px solid var(--line);
              border-radius:10px; padding:14px 18px; }}
  .compare p {{ margin:6px 0; }}
  code {{ background:#2b2b2b; padding:1px 6px; border-radius:4px; font-size:13px; }}
  .bad {{ color:#ff8ab0; }}
  .good {{ color:#7ee08a; }}
  footer {{ max-width:1180px; margin:40px auto 0; color:var(--muted); font-size:13px; }}
</style></head><body>
<header>
  <h1>曲库 App · <em>整词断行</em> 与 <em>文字底面</em></h1>
  <p class="lede">两件事一起改：①拉丁词不再被从中间劈开；②压在背景黄绿斜带上的文字
  全部收进不透明卡片。截图全部是 1:1 渲染，除手机宽度与字号档位外没有做任何缩放。</p>
</header>
<div class="compare">
  <p><b>改前 / 改后（同一首，320 宽 · 2.0 字号）</b></p>
  <p class="bad">改前：<code>ＧＯ！Ｇ / Ｏ！ラブ / リズム♥</code> —— 一个词被切成两行</p>
  <p class="good">改后：<code>ＧＯ！ＧＯ！ / ラブリズム♥</code> —— 断点只落在中日文之间</p>
</div>
<div class="rule"></div>
{''.join(parts)}
<footer>
  判定依据：234 条测试全通过（含新增 10 条：切分规则 / 缩字比例 / 卡片真的用了整词换行 /
  设置页每个 Text 的祖先里必须有卡片）。<br>
  尚未改动、等你决定的两处：中文/日文词本身仍会在任意两字之间折行（如「チュウマ / イ」），
  以及行首禁则（「…オンザみ / んマンション」的「ん」落在行首）。
</footer>
</body></html>"""

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(html)
    print("written:", OUT, len(html) // 1024, "KB")


if __name__ == "__main__":
    main()
