"""生成「2.0 字号排版修复」预览页（单文件 HTML，图片内联 base64）。

用法：
    python tool/pack_2x_preview.py

读 build/official-screenshots/{page}_{320,390}_{1.0,2.0}.png
（由 test/official_visual_test.dart 生成）
写成 D:\\WorkBuddy space\\outputs\\songquery-2x-textscale-preview.html
"""

import base64
import io
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "build", "official-screenshots")
OUT = r"D:\WorkBuddy space\outputs\songquery-2x-textscale-preview.html"

PAGES = [
    ("search", "搜索与筛选", "标题「搜索与筛选」在 320 宽 + 2.0 字号下折成「搜索与筛 / 选」，末字孤零零占一行；输入框提示被截成「曲名／读音／别…」。",
     "标题改单行自适应缩放；提示放宽到两行。"),
    ("home", "首页列表", "卡片底部「Character : 星咲 あかり」被压成「Character 星咲 あか / : / り」——冒号独占一行。",
     "2.0 字号时标签与角色名分行，冒号回到标签行末尾。"),
    ("detail", "详情页", "131 字符作者完整排 11 行，信息条 2×2，「チュウマイ」等词不被拆开。",
     "这轮只补测 2.0，未改代码 —— 之前去截断时已经顺手做对了。"),
    ("settings", "设置", "说明文字整段压在黄绿斜带上（2.0 下内容变高，正好穿过背景条纹）。",
     "未修。这是背景与内容的层叠关系，要动得改斜带位置或加底板，属视觉决策。"),
]


def png(path):
    with open(path, "rb") as f:
        head = f.read(24)
    w, h = struct.unpack(">II", head[16:24])
    raw = base64.b64encode(open(path, "rb").read()).decode()
    return w, h, "data:image/png;base64," + raw


def main():
    cards = []
    for key, title, before, after in PAGES:
        small = png(os.path.join(SHOTS, "%s_320_1.0.png" % key))
        big = png(os.path.join(SHOTS, "%s_320_2.0.png" % key))
        cards.append({"key": key, "title": title, "before": before,
                      "after": after, "s": small, "b": big})

    blocks = []
    for c in cards:
        blocks.append("""
<section>
  <h2>%s</h2>
  <p class="sym"><b>改前症状</b>：%s<br><b>处理</b>：%s</p>
  <div class="pair">
    <figure><figcaption>320 宽 · 字号 1.0（基准，一直正常）</figcaption>
      <img src="%s" width="%d" height="%d" alt="1.0"></figure>
    <figure><figcaption>320 宽 · 字号 2.0（系统最大，当前源码）</figcaption>
      <img src="%s" width="%d" height="%d" alt="2.0"></figure>
  </div>
</section>""" % (c["title"], c["before"], c["after"],
                 c["s"][2], 320, c["s"][1],
                 c["b"][2], 320, c["b"][1]))

    html = """<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>2.0 字号排版修复</title>
<style>
body{margin:0;padding:24px;background:#eee;color:#222;font:15px/1.7 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:900px;margin:auto}
h1{font-size:22px;margin:0 0 12px}
h2{font-size:16px;margin:0 0 8px}
section{background:#fff;padding:14px 16px;margin:18px 0;border-left:4px solid #E84A92}
.notice{background:#fff;padding:12px 14px;border-left:4px solid #32C63A}
.sym{font-size:13px;color:#444;margin:0 0 10px}
.pair{display:flex;gap:20px;flex-wrap:wrap}
figure{margin:0}
figcaption{font:12px/1.5 system-ui;color:#666;margin-bottom:6px}
img{display:block;border:1px solid #ddd;max-width:100%;height:auto}
</style>
<main>
<h1>2.0 字号（系统最大）排版修复</h1>
<p class="notice">截图是 <code>flutter_test</code> 里当前源码的真实渲染。左边是 1.0 字号（一直正常，作为基准），右边是 2.0。这轮没有改任何设计，只修大字号下才会出现的排版错误。</p>
__BLOCKS__
<p class="sym">全量 <code>flutter test</code> <b>221 条通过</b>，<code>flutter analyze</code> 无问题。曲绘走网络，测试里是占位方块。</p>
</main>
</html>""".replace("__BLOCKS__", "\n".join(blocks))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with io.open(OUT, "w", encoding="utf-8") as f:
        f.write(html)
    print("wrote", OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    main()
