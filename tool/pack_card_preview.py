"""生成列表卡片「长作者名降字号」的改前/改后对照页（单文件 HTML）。

用法：
    python tool/pack_card_preview.py

数据来源：
    截图 build/card-shots-before/、build/card-shots-after/
    高度 build/_cardshot_before3.log、build/_cardshot_after.log（UTF-16LE）
"""

import base64
import io
import json
import os
import re
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BEFORE = os.path.join(ROOT, "build", "card-shots-before")
AFTER = os.path.join(ROOT, "build", "card-shots-after")
LOG_BEFORE = os.path.join(ROOT, "build", "_cardshot_before3.log")
LOG_AFTER = os.path.join(ROOT, "build", "_card20d.log")
OUT = r"D:\WorkBuddy space\outputs\songquery-card-artist-preview.html"

CASES = [
    ("normal", "常规曲目（对照基准）"),
    ("artist131", "最长作者（131 字符）"),
    ("title52", "最长曲名（52 字符）"),
]
COMBOS = [(320, "1.0"), (320, "1.6"), (320, "2.0"), (390, "1.0"), (390, "1.6"), (390, "2.0")]


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def b64(path):
    return "data:image/png;base64," + base64.b64encode(open(path, "rb").read()).decode()


def heights(path):
    text = io.open(path, "rb").read().decode("utf-16", errors="ignore")
    found = {}
    for line in text.splitlines():
        m = re.search(r"CARD_HEIGHT (\S+) (\d+)x([\d.]+) -> ([\d.]+)dp", line)
        if m:
            found[(m.group(1), int(m.group(2)), m.group(3))] = float(m.group(4))
    return found


def build():
    hb, ha = heights(LOG_BEFORE), heights(LOG_AFTER)
    items, rows = [], []
    for key, name in CASES:
        for width, scale in COMBOS:
            fn = "%s_%d_%s.png" % (key, width, scale)
            bp, ap = os.path.join(BEFORE, fn), os.path.join(AFTER, fn)
            if not os.path.exists(ap):
                raise SystemExit("missing after screenshot: %s" % fn)
            aw, ah = png_size(ap)
            item = {
                "label": "%s · %d 宽 · 字号 %s" % (name, width, scale),
                "group": "常规曲目" if key == "normal" else "极端数据",
                "asrc": b64(ap), "awc": aw, "ahc": ah,
                "bsrc": None, "bwc": 0, "bhc": 0,
            }
            # 2.0 档是这轮新增覆盖的，没有改前截图。
            if os.path.exists(bp):
                bw, bh = png_size(bp)
                item.update({"bsrc": b64(bp), "bwc": bw, "bhc": bh})
            k = (key, width, scale)
            item["bh"] = hb.get(k)
            item["ah"] = ha.get(k)
            items.append(item)
            if item["bh"] and item["ah"]:
                rows.append({"name": name, "w": width, "s": scale,
                             "before": item["bh"], "after": item["ah"],
                             "delta": item["ah"] - item["bh"],
                             "pct": (item["ah"] - item["bh"]) / item["bh"] * 100.0})
            elif item["ah"]:
                rows.append({"name": name, "w": width, "s": scale,
                             "before": None, "after": item["ah"],
                             "delta": 0, "pct": 0.0})
    return items, rows


HEAD = """<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>列表卡片 · 长作者名降字号</title>
<style>
body{margin:0;padding:24px;background:#eee;color:#222;font:15px/1.7 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1080px;margin:auto}
h1{font-size:22px;margin:0 0 12px}
h2{font-size:16px;margin:26px 0 8px}
.notice{background:#fff;padding:12px 14px;border-left:4px solid #E84A92}
table{border-collapse:collapse;background:#fff;font-size:13px;width:100%}
th,td{border:1px solid #ccc;padding:6px 9px;text-align:left;vertical-align:top}
th{background:#f4f4f4;white-space:nowrap}
code{background:#f2f2f2;padding:1px 4px;border-radius:3px;font-size:12px}
.num{text-align:right;font-variant-numeric:tabular-nums}
.ok{color:#1e8449;font-weight:600}
.zero{color:#888}
select{font:inherit;padding:7px 12px;border:1px solid #999;border-radius:5px;background:#fff;max-width:100%}
.pair{display:flex;gap:26px;align-items:flex-start;flex-wrap:wrap;margin-top:16px}
.col{background:#fff;padding:10px;border:1px solid #ccc}
.col h3{font:600 13px/1.4 system-ui;margin:0 0 8px}
.tag{font:600 11px/1 system-ui;padding:3px 7px;border-radius:3px;color:#fff;margin-right:6px}
.bad{background:#c0392b}.good{background:#1e8449}
img{display:block;border:1px solid #ddd;max-width:100%;height:auto}
.meta{color:#666;font-size:12px;margin-top:6px}
</style>
<main>
<h1>列表卡片 · 长作者名降字号（改前 / 改后）</h1>
<p class="notice">卡片规矩是「不截断、自然增高」（11-02 定），这轮<b>一个字都没删</b>，只按作者名长度降一档字号。阈值 55 字符来自数据集分布：1112 首歌的 artist 长度 p50=16、p90=38、p95=55、p99=81、max=131，所以 <b>95% 的卡片视觉完全不变</b>。另外把测试矩阵扩到系统字号上限 <b>2.0</b>，并顺手修了 2.0 下「LEVEL」被断成「LEVE / L」。</p>
<h2>具体改了什么</h2>
<table>
<tr><th>项</th><th>改前</th><th>改后</th></tr>
<tr><td>作者名 &le; 55 字符（95%）</td><td>13px / 行高 1.5</td><td>不变</td></tr>
<tr><td>作者名 &gt; 55 字符（5%）</td><td>13px / 行高 1.5</td><td>11.5px / 行高 1.35</td></tr>
<tr><td>文字内容</td><td>完整</td><td>完整，未截断、未省略</td></tr>
<tr><td>LEVEL 标签宽度</td><td>字号 &gt;1.2 时固定 76dp，2.0 字号下放不下，被硬断成「LEVE / L」</td><td>改为 46 × 字号（下限 76），2.0 下为 92dp，完整显示</td></tr>
</table>
<h2>卡片自然高度（dp）</h2>
<table>
<tr><th>样本</th><th>视口</th><th class="num">改前</th><th class="num">改后</th><th class="num">变化</th></tr>
__ROWS__
</table>
<p class="meta">屏高按 844dp 算。最坏一档 320@1.6 从 735dp（占屏 87%）降到 <b>611dp（72%）</b>。常规卡和曲名长的卡高度一字未变 —— 它们本来就不受影响。<br>
<b>2.0 档是新增覆盖</b>：320@2.0 下 131 字符作者那张卡 <b>871dp，已经超过屏高 844</b>（窄屏 + 系统最大字号 + 全 CV 名单三者叠加），一屏放不下一张卡。这是「不截断」的必然结果，没有靠继续缩字号硬压 —— 调大字号的用户要的是看清楚，缩到比正文还小是本末倒置。</p>
<h2>看渲染</h2>
<label>档位 <select id="pick"></select></label>
<div class="pair">
  <div class="col"><h3><span class="tag bad">改前</span><span id="blabel"></span></h3><img id="bshot" alt="改前"><div class="meta" id="bmeta"></div></div>
  <div class="col"><h3><span class="tag good">改后</span><span id="alabel"></span></h3><img id="ashot" alt="改后"><div class="meta" id="ameta"></div></div>
</div>
<p class="meta">截图是 <code>flutter_test</code> 里用真实字体渲染的卡片本身，不含列表其余部分；曲绘走网络，测试里是占位方块。</p>
</main>
<script>
const data = __DATA__;
const pick = document.getElementById('pick');
const bshot = document.getElementById('bshot'), ashot = document.getElementById('ashot');
const bmeta = document.getElementById('bmeta'), ameta = document.getElementById('ameta');
const blabel = document.getElementById('blabel'), alabel = document.getElementById('alabel');
let lastGroup = null, group = null;
data.forEach((d, i) => {
  if (d.group !== lastGroup) {
    lastGroup = d.group;
    group = document.createElement('optgroup');
    group.label = d.group;
    pick.appendChild(group);
  }
  const o = document.createElement('option');
  o.value = i; o.textContent = d.label;
  group.appendChild(o);
});
function fmt(d, h, w, hgt) {
  return w + '×' + hgt + ' px' + (h == null ? '' : ' · 卡片高 ' + h.toFixed(1) + 'dp');
}
function show(i) {
  const d = data[i];
  ashot.src = d.asrc; ashot.width = Math.min(d.awc, 320);
  ameta.textContent = fmt(d, d.ah, d.awc, d.ahc);
  alabel.textContent = d.label;
  if (d.bsrc) {
    bshot.src = d.bsrc; bshot.width = Math.min(d.bwc, 320);
    bmeta.textContent = fmt(d, d.bh, d.bwc, d.bhc);
    blabel.textContent = d.label;
  } else {
    bshot.removeAttribute('src'); bshot.removeAttribute('width');
    bshot.style.minHeight = '80px';
    bmeta.textContent = '这一档是新增覆盖（2.0 字号），没有改前截图';
    blabel.textContent = '—';
  }
}
pick.onchange = () => show(+pick.value);
show(data.findIndex(d => d.label.includes('131') && d.label.includes('320') && d.label.includes('1.6')));
</script>
</html>"""


def main():
    items, rows = build()
    trs = []
    for r in rows:
        if r["before"] is None:
            trs.append(
                '<tr><td>%s</td><td>%d × %s</td><td class="num">—</td>'
                '<td class="num">%.1f</td><td class="num zero">新增档位</td></tr>'
                % (r["name"], r["w"], r["s"], r["after"])
            )
            continue
        pct = "" if r["delta"] == 0 else "%+.0f%%" % r["pct"]
        cls = "zero" if r["delta"] == 0 else "ok"
        trs.append(
            '<tr><td>%s</td><td>%d × %s</td><td class="num">%.1f</td>'
            '<td class="num">%.1f</td><td class="num %s">%s</td></tr>'
            % (r["name"], r["w"], r["s"], r["before"], r["after"], cls, pct or "不变")
        )
    html = HEAD.replace("__ROWS__", "\n".join(trs))
    html = html.replace("__DATA__", json.dumps(items, ensure_ascii=False))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with io.open(OUT, "w", encoding="utf-8") as f:
        f.write(html)
    print("wrote", OUT, os.path.getsize(OUT), "bytes,", len(items), "shots",
          len(rows), "rows")


if __name__ == "__main__":
    main()
