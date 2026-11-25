"""生成详情页的可视预览（单文件 HTML，图片全内联 base64）。

用法：
    python tool/pack_detail_preview.py

改后截图：build/official-screenshots/detail_{width}_{scale}.png
          build/extreme-screenshots/{case}_{width}_{scale}.png
改前截图：build/shots-before-author-full/ 下同名文件（出包前手工备份的上版）
写成 D:\\WorkBuddy space\\outputs\\songquery-detail-fulltext-preview.html
"""

import base64
import io
import json
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "build", "official-screenshots")
EXTREME_SHOTS = os.path.join(ROOT, "build", "extreme-screenshots")
BEFORE = os.path.join(ROOT, "build", "shots-before-author-full")
OUT = r"D:\WorkBuddy space\outputs\songquery-detail-fulltext-preview.html"

NORMAL = [(320, "1.0"), (320, "1.6"), (390, "1.0"), (390, "1.6"), (400, "1.0"), (400, "1.6")]

# (文件名前缀, 下拉里的名字, [(宽, 字号)], 备注)
EXTREME = [
    ("artist131", "最长作者（131 字符）", [("320", "1.6"), ("390", "1.0")],
     ["本轮改动的核心：作者名不再截断，131 字符完整排出来。",
      "320@1.6 下会占 9 行，谱面区被挤出首屏 —— 这是「完整」的代价，已确认接受。",
      "改前是 2 行 + 省略号，CV 名单只看到一半。"]),
    ("title52", "最长曲名（52 字符）", [("320", "1.6"), ("390", "1.6")],
     ["曲名也不再 ellipsis：缩不到 70% 以内就完整换行排布。",
      "改前这一档是 maxLines 2 + 省略号，尾字会被吞掉。"]),
    ("minimal", "字段全缺、无谱面", [("390", "1.0")],
     ["DETAILS 整节跟着内容走，全字段为 null 时连标题一起不渲染。",
      "作者为空时不留空行。"]),
    ("designer", "最长谱师名（64 字符）", [("320", "1.0")],
     ["谱面卡片副信息拆成独立 Wrap 项，长谱师名换行后不会在行首挂「·」。"]),
]


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    w, h = struct.unpack(">II", head[16:24])
    return w, h


def b64(path):
    return "data:image/png;base64," + base64.b64encode(open(path, "rb").read()).decode()


def item(path, label, group, notes):
    if not os.path.exists(path):
        raise SystemExit("missing screenshot: %s" % path)
    w, h = png_size(path)
    before = os.path.join(BEFORE, os.path.basename(path))
    bw = bh = 0
    bsrc = None
    if os.path.exists(before):
        bw, bh = png_size(before)
        bsrc = b64(before)
    return {
        "label": label,
        "group": group,
        "wc": w,
        "hc": h,
        "src": b64(path),
        "bwc": bw,
        "bhc": bh,
        "bsrc": bsrc,
        "notes": notes,
    }


def build():
    items = []
    for width, scale in NORMAL:
        notes = ["这一档曲名和作者都短，本来就不会触发截断，所以改前改后应当一致 —— 本轮改动只在「极端数据」里看得出来。"]
        if scale == "1.6":
            notes.append("头部上下堆叠：封面 88dp 在上，曲名在下占满整行")
            notes.append("信息条 2×2，「チュウマイ」「ONGEKI」完整显示")
        elif width == 320:
            notes.append("信息条由 3+1 变为 2×2，四项不再挤成一排")
        else:
            notes.append("信息条保持四列一排")
        notes.append("等级列固定 40dp 右对齐，四张卡片副信息换行位置一致")
        notes.append("BASIC/ADVANCED 缺失项整段省略，不再显示「谱师 —」")
        items.append(item(os.path.join(SHOTS, "detail_%d_%s.png" % (width, scale)),
                          "%d 宽 · 字号 %s" % (width, scale), "常规曲目", notes))
    for prefix, name, combos, notes in EXTREME:
        for width, scale in combos:
            items.append(item(os.path.join(EXTREME_SHOTS, "%s_%s_%s.png" % (prefix, width, scale)),
                              "%s · %s 宽 · 字号 %s" % (name, width, scale), "极端数据", notes))
    return items


HEAD = """<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>详情页 · 文案完整显示对照</title>
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
select{font:inherit;padding:7px 12px;border:1px solid #999;border-radius:5px;background:#fff;max-width:100%}
.pair{display:flex;gap:26px;align-items:flex-start;flex-wrap:wrap;margin-top:16px}
.col{background:#fff;padding:10px;border:1px solid #ccc}
.col h3{font:600 13px/1.4 system-ui;margin:0 0 8px;display:flex;gap:8px;align-items:center}
.tag{font:600 11px/1 system-ui;padding:3px 7px;border-radius:3px;color:#fff}
.bad{background:#c0392b}.good{background:#1e8449}
img{display:block;border:1px solid #ddd;background:#fff;max-width:100%;height:auto}
.notes{background:#fff;padding:14px;border-left:4px solid #32C63A;margin-top:16px}
.notes li{margin:6px 0}
.meta{color:#666;font-size:12px;margin-top:6px}
</style>
<main>
<h1>歌曲详情页 · 文案完整显示（改前 / 改后并排）</h1>
<p class="notice">图片是当前源码在 <code>flutter_test</code> 里真实渲染的截图，不是手绘稿。本轮只做一件事：<b>把详情页所有省略号截断去掉</b>，曲名、读音、作者名、信息条的值一律完整显示，与列表卡片「不截断、自然增高」的规矩统一。左为改前、右为改后。</p>
<h2>本轮改动</h2>
<table>
<tr><th>位置</th><th>改前</th><th>改后</th></tr>
<tr><td>作者名</td><td><code>maxLines: 2</code> + 省略号，131 字符那首只显示前两行</td><td>不限制行数，完整显示；空串仍不占位</td></tr>
<tr><td>曲名</td><td>需要缩到 70% 以下时走 <code>maxLines: 2</code> + 省略号</td><td>改为一律完整换行，尾字不再被吞</td></tr>
<tr><td>信息条的值</td><td><code>maxLines: 2</code> + 省略号，<code>bright MEMORY Act.1</code> 在窄屏会变成 <code>bright MEMORY Ac…</code></td><td>不限制，固定宽度内自然增高</td></tr>
</table>
<p class="meta">代价：131 字符作者在 320@1.6 会排 9 行，首屏只剩曲名和作者，谱面区要靠滚动。这是选「完整」必然的结果，不是回归。</p>
<h2>看渲染</h2>
<label>档位 <select id="pick"></select></label>
<div class="pair">
  <div class="col"><h3><span class="tag bad">改前</span><span id="blabel"></span></h3><img id="bshot" alt="改前"><div class="meta" id="bsize"></div></div>
  <div class="col"><h3><span class="tag good">改后</span><span id="alabel"></span></h3><img id="ashot" alt="改后"><div class="meta" id="asize"></div></div>
</div>
<div class="notes"><b>这一档的情况</b><ul id="notes"></ul></div>
</main>
<script>
const data = __DATA__;
const pick = document.getElementById('pick');
const bshot = document.getElementById('bshot'), ashot = document.getElementById('ashot');
const bsize = document.getElementById('bsize'), asize = document.getElementById('asize');
const blabel = document.getElementById('blabel'), alabel = document.getElementById('alabel');
const notes = document.getElementById('notes');
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
function show(i) {
  const d = data[i];
  ashot.src = d.src; ashot.width = Math.min(d.wc, 400);
  asize.textContent = d.wc + '×' + d.hc + ' px';
  alabel.textContent = d.label;
  if (d.bsrc) {
    bshot.src = d.bsrc; bshot.width = Math.min(d.bwc, 400);
    bsize.textContent = d.bwc + '×' + d.bhc + ' px';
    blabel.textContent = d.label;
  } else {
    bshot.removeAttribute('src'); bshot.removeAttribute('width');
    bsize.textContent = '（这一档没有改前截图）';
    blabel.textContent = '—';
  }
  notes.innerHTML = d.notes.map(n => '<li>' + n + '</li>').join('');
}
pick.onchange = () => show(+pick.value);
show(0);
</script>
</html>"""


def main():
    items = build()
    html = HEAD.replace("__DATA__", json.dumps(items, ensure_ascii=False))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with io.open(OUT, "w", encoding="utf-8") as f:
        f.write(html)
    print("wrote", OUT, os.path.getsize(OUT), "bytes,", len(items), "shots")


if __name__ == "__main__":
    main()
