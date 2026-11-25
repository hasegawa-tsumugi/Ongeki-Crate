# -*- coding: utf-8 -*-
"""可交互的概念预览：用真机截图 + 前端还原的卡片做「滑动/缩放」演示。

截图解决「像素级是不是对的」，交互解决「用起来是什么感觉」。两者放在一个
单文件 HTML 里，不依赖任何外网资源。

用法：
    python tool/pack_interactive_preview.py
输出：D:\\WorkBuddy space\\outputs\\songquery-live-preview.html
"""

import base64
import glob
import json
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "build", "official-screenshots")
DATA = os.path.join(ROOT, "assets", "songs-2026.10.15.json")
OUT = r"D:\WorkBuddy space\outputs\songquery-live-preview.html"

# 手机模拟器里可切换的页面（用真机截图）
PHONES = [
    ("home", "首页列表", "320 × 2.0", "整词换行生效：`ＧＯ！ＧＯ！` 一行，断点只落在日文之间。"),
    ("home", "首页列表", "320 × 1.0", "常规字号，与改动前基本一致。"),
    ("card_real", "卡片特写", "320 × 2.0", "封面为了让出文字宽度从 88 收到 64。"),
    ("card", "卡片特写（长英文）", "320 × 2.0", "`Sugarfull:Overbloom` 17 字符缩到 72% 下限后仍需断一次。"),
    ("detail", "详情页", "320 × 2.0", "头部曲名整段单行缩放。"),
    ("settings", "设置页", "320 × 2.0", "整页收进深色卡片，斜带只从卡片之间穿过。"),
    ("settings", "设置页", "320 × 1.0", "同样的问题在 1.0 也存在，一并解决。"),
    ("search", "搜索与筛选", "320 × 2.0", "状态文字收进小卡片。"),
]


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def b64(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def pick_song(songs, needle):
    for song in songs:
        if needle in (song.get("title") or ""):
            return song
    raise SystemExit("找不到样张：" + needle)


def main():
    dataset = json.load(open(DATA, encoding="utf-8"))
    songs = dataset["songs"]

    # 卡片演示只取少量字段，别把 1112 首整个塞进 HTML。
    demo = []
    seen = set()
    for needle in [
        "ＧＯ！ＧＯ！ラブリズム",
        "Sugarfull",
        "7EVENDAYS",
        "Starlight★Limited",
        "2112410403927243233368",
    ]:
        for song in songs:
            title = song.get("title") or ""
            artist = song.get("artist") or ""
            if needle in title or needle in artist:
                if title in seen:
                    break
                seen.add(title)
                demo.append(
                    {
                        "title": title,
                        "artist": artist,
                        "genre": song.get("genre") or "",
                        "levels": [
                            {
                                "name": n,
                                "level": str(c.get("level") or "").strip(),
                            }
                            for n, c in zip(
                                ["BASIC", "ADVANCED", "EXPERT", "MASTER", "LUNATIC"],
                                song.get("charts") or [],
                            )
                            if c
                        ],
                    }
                )
                break

    phones = []
    for name, label, tag, note in PHONES:
        path = os.path.join(SHOTS, f"{name}_{tag.replace(' × ', '_').replace('  ', ' ')}.png")
        # 截图文件名是 `${name}_${width}_${scale}.png`
        parts = tag.replace("×", "").split()
        path = os.path.join(SHOTS, "%s_%s.png" % (name, "_".join(parts)))
        if not os.path.exists(path):
            raise SystemExit("缺少截图：" + path)
        w, h = png_size(path)
        phones.append(
            {"label": label, "tag": tag, "note": note, "w": w, "h": h, "src": b64(path)}
        )

    html = TEMPLATE.replace("__PHONES__", json.dumps(phones, ensure_ascii=False))
    html = html.replace("__SONGS__", json.dumps(demo, ensure_ascii=False))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(html)
    print("written:", OUT, len(html) // 1024, "KB")


TEMPLATE = r"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>曲库 App · 上手看看</title>
<style>
  :root {
    --bg:#131315; --panel:#1c1c1f; --panel2:#232327; --line:#333339;
    --ink:#f2f2f4; --muted:#a3a3ad; --faint:#6f6f7a;
    --magenta:#e84a92; --yellow:#faff00; --green:#32c63a;
    --card:#222222;
  }
  * { box-sizing:border-box; }
  html, body { margin:0; background:var(--bg); color:var(--ink); }
  body {
    padding:28px 22px 60px;
    font:15px/1.65 "MiSans","M PLUS 1p","Microsoft YaHei",system-ui,sans-serif;
  }
  header { max-width:1200px; margin:0 auto 18px; }
  h1 { font-size:25px; margin:0 0 6px; }
  h1 em { font-style:normal; color:var(--magenta); }
  .lede { color:var(--muted); margin:0; max-width:780px; font-size:14px; }

  .stage { max-width:1200px; margin:24px auto 0; display:flex; gap:26px;
           align-items:flex-start; flex-wrap:wrap; }
  .panel { background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:16px; }

  /* ── 手机模拟器 ── */
  .phone-col { flex:0 0 auto; }
  .phone { width:340px; height:660px; border-radius:22px; overflow:hidden;
           background:#000; border:8px solid #2a2a2f; position:relative;
           box-shadow:0 18px 50px rgba(0,0,0,.55); }
  .phone img { width:100%; height:100%; object-fit:contain; object-position:top;
               display:block; background:#000; transition:opacity .18s; }
  .phone .tagline { position:absolute; left:0; right:0; bottom:0; padding:6px 10px;
                    font-size:11.5px; color:var(--muted); background:linear-gradient(transparent,#000c);
                    text-align:center; }
  .phone-name { margin:12px 0 4px; font-size:13px; font-weight:700; }
  .phone-note { margin:0; font-size:12.5px; color:var(--muted); max-width:340px; min-height:3.4em; }
  .tabs { display:flex; flex-wrap:wrap; gap:6px; margin-top:10px; max-width:340px; }
  .tabs button { font:inherit; font-size:12px; padding:5px 9px; cursor:pointer;
                 background:var(--panel2); color:var(--ink); border:1px solid var(--line);
                 border-radius:7px; }
  .tabs button[aria-pressed="true"] { background:var(--magenta); border-color:var(--magenta);
                                      color:#fff; font-weight:700; }

  /* ── 卡片实时重排区 ── */
  .lab { flex:1 1 520px; min-width:min(100%,480px); }
  .lab h2 { font-size:15px; margin:0 0 4px; color:var(--magenta); }
  .lab .hint { margin:0 0 14px; font-size:12.5px; color:var(--muted); }
  .controls { display:flex; flex-wrap:wrap; gap:14px 20px; align-items:center;
              padding:12px 14px; background:var(--panel2); border:1px solid var(--line);
              border-radius:10px; margin-bottom:14px; }
  .controls label { font-size:12.5px; color:var(--muted); display:flex; align-items:center; gap:7px; }
  .controls input[type=range] { width:130px; accent-color:var(--magenta); }
  .controls select { font:inherit; font-size:12.5px; background:#2c2c31; color:var(--ink);
                     border:1px solid var(--line); border-radius:6px; padding:4px 7px; }
  .val { color:var(--ink); font-variant-numeric:tabular-nums; min-width:44px; display:inline-block; }

  .beam { position:relative; overflow:hidden; border-radius:10px; border:1px solid var(--line);
          background:#0b0b0c; padding:14px; }
  .band { position:absolute; left:-40%; width:180%; height:10px; transform:rotate(-20deg);
          opacity:.85; pointer-events:none; }
  .band.y1 { background:var(--yellow); top:26%; }
  .band.g { background:var(--green); top:38%; height:10px; }
  .band.y2 { background:var(--yellow); top:62%; }

  /* 还原卡片外形（chamfer 用 clip-path，与 App 的 18dp 切角对应） */
  .card { position:relative; background:var(--card); margin:0 auto 12px;
          clip-path:polygon(18px 0,100% 0,100% calc(100% - 18px),calc(100% - 18px) 100%,0 100%,0 18px);
          display:flex; flex-direction:column; }
  .card .body { display:flex; gap:12px; padding:12px; }
  .jacket { flex:0 0 auto; background:#353535; border:3px solid #000;
            display:flex; align-items:center; justify-content:center;
            color:#777; font-size:22px; }
  .info { flex:1 1 auto; min-width:0; padding-right:6px; }
  .genre { font-size:12px; line-height:1.4; font-weight:700; color:var(--magenta); }
  .title { font-weight:700; line-height:1.35; margin:4px 0 6px; color:#fff; }
  .artist { color:#d6d6dc; font-weight:500; }
  .levels { display:flex; align-items:center; gap:6px; padding:6px 12px;
            background:rgba(0,0,0,.16); border-top:1px solid #888;
            font-size:12px; color:#ddd; flex-wrap:wrap; min-height:48px; }
  .levels .lv-label { flex:0 0 auto; }
  .ring { min-width:34px; height:34px; padding:0 4px; border-radius:50%; display:flex;
          align-items:center; justify-content:center; font-weight:700; color:#fff;
          font-size:12px; flex:0 0 auto; }
  .char { padding:7px 12px; background:#fff; border:3px solid #000; color:#171717;
          font-weight:700; font-size:13px; line-height:1.25; }
  .char span { color:#666; font-weight:400; }

  .legend { margin-top:14px; font-size:12.5px; color:var(--muted); }
  .legend b { color:var(--ink); }
  .bad { color:#ff8ab0; } .good { color:#7ee08a; }
  footer { max-width:1200px; margin:44px auto 0; color:var(--faint); font-size:12.5px; }
  code { background:#2b2b31; padding:1px 5px; border-radius:4px; }
</style></head><body>

<header>
  <h1>曲库 App · <em>上手看看</em></h1>
  <p class="lede">左边是真机截图（1:1 渲染，只缩了显示尺寸），右边是同一张卡片按当前字号
  重新排版的实时演示 —— 拖动滑块看各档字号下曲名怎么折行，挪「可用宽度」看窄屏挤压。</p>
</header>

<div class="stage">
  <div class="phone-col panel">
    <div class="phone"><img id="shot" alt=""><div class="tagline" id="tagline"></div></div>
    <div class="phone-name" id="pname"></div>
    <p class="phone-note" id="pnote"></p>
    <div class="tabs" id="tabs"></div>
  </div>

  <div class="lab panel">
    <h2>卡片实时重排</h2>
    <p class="hint">这里的排版规则与 App 一致：曲名/作者按「最宽的一段刚好放进文字列」缩字号，
    只缩到 %, 一个字都不删。</p>
    <div class="controls">
      <label>系统字号 <input type="range" id="scale" min="1" max="2" step="0.1" value="2">
        <span class="val" id="scaleVal">2.0</span></label>
      <label>屏宽 <input type="range" id="width" min="300" max="430" step="1" value="320">
        <span class="val" id="widthVal">320</span></label>
      <label>样张 <select id="song"></select></label>
    </div>
    <div class="beam" id="beam">
      <div class="band y1"></div><div class="band g"></div><div class="band y2"></div>
      <div id="cardHost"></div>
    </div>
    <p class="legend" id="metrics"></p>
  </div>
</div>

<footer>
  截图来自 <code>build/official-screenshots/</code>，由 <code>test/official_visual_test.dart</code> 生成；
  实时卡片是前端按同一套规则还原的近似效果（字体用系统字替代，行宽按 1em/字符估算最坏情况的量级）。
</footer>

<script>
const PHONES = __PHONES__;
const SONGS = __SONGS__;

const shot = document.getElementById('shot');
const tagline = document.getElementById('tagline');
const pname = document.getElementById('pname');
const pnote = document.getElementById('pnote');
const tabs = document.getElementById('tabs');

PHONES.forEach((p, i) => {
  const b = document.createElement('button');
  b.textContent = p.label + ' ' + p.tag;
  b.setAttribute('aria-pressed', i === 0 ? 'true' : 'false');
  b.onclick = () => show(i);
  tabs.appendChild(b);
});
function show(i) {
  const p = PHONES[i];
  shot.src = 'data:image/png;base64,' + p.src;
  tagline.textContent = p.tag;
  pname.textContent = p.label;
  pnote.textContent = p.note;
  [...tabs.children].forEach((b, k) => b.setAttribute('aria-pressed', k === i ? 'true' : 'false'));
}
show(0);

// ── 实时卡片 ──
const scaleEl = document.getElementById('scale');
const widthEl = document.getElementById('width');
const scaleVal = document.getElementById('scaleVal');
const widthVal = document.getElementById('widthVal');
const songEl = document.getElementById('song');
const host = document.getElementById('cardHost');
const metrics = document.getElementById('metrics');

const TONES = ['#00C312','#FFD822','#FF0066','#CF3EFF','#42B6FF'];

SONGS.forEach((s, i) => {
  const o = document.createElement('option');
  o.value = i; o.textContent = s.title.slice(0, 18);
  songEl.appendChild(o);
});
songEl.value = '0';

/* 与 lib/src/theme.dart 的 unbreakableUnits 同一条规则：
   空白、中文、假名、半角片假名、全角符号可断；其余（含全角英数）连成一段。 */
const BREAKABLE = /[\u3000-\u303f\u3040-\u309f\u30a0-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff61-\uff9f\uffe0-\uffee\s]/;
function units(text) {
  const out = []; let cur = '';
  for (const ch of text) {
    if (BREAKABLE.test(ch)) { if (cur) { out.push(cur); cur = ''; } out.push(ch); }
    else cur += ch;
  }
  if (cur) out.push(cur);
  return out;
}
/* 只统计「词」：连续英文/数字，日文单独成串并不需要缩。 */
function words(text) {
  return text.split(BREAKABLE).filter(Boolean);
}

function render() {
  const scale = parseFloat(scaleEl.value);
  const screen = parseFloat(widthEl.value);
  scaleVal.textContent = scale.toFixed(1);
  widthVal.textContent = screen;

  const narrow = screen <= 350;
  let jacket = narrow ? (scale >= 1.8 ? 64 : 88) : 104;
  // 卡片宽度 = 屏宽 − 30（列表左右各 15）
  const cardW = screen - 30;
  // 文字列 = 卡片宽 − 内边距 24 − 封面 − 间距(10/12) − 右侧 6
  const textW = cardW - 24 - jacket - (narrow ? 10 : 12) - 6;

  const song = SONGS[+songEl.value];
  const fsTitle = (narrow ? 17 : 18) * scale;
  const fsArtist = 13 * scale;         // 演示统一用常规档，长串降档逻辑略
  const fsGenre = 12 * scale;

  // 与 widestUnitScale 同逻辑：最宽的词 × 1em 估算需要多宽
  const worst = (text, base, min) => {
    const em = base;                      // 已经是缩放后的字号
    let widest = 0;
    for (const w of words(text)) widest = Math.max(widest, w.length * em);
    if (widest <= textW) return base;
    const ratio = textW / widest;
    return ratio >= min ? base * ratio * 0.99 : base * min;
  };
  const tSize = worst(song.title, fsTitle, .72);
  const aSize = worst('ARTIST: ' + song.artist, fsArtist, .62);

  const levels = song.levels.map((l, i) => `
    <div class="ring" style="background:${TONES[i] || '#888'}">${l.level || '—'}</div>`).join('');

  host.innerHTML = `
    <div class="card" style="width:${cardW}px;zoom:1">
      <div class="body">
        <div class="jacket" style="width:${jacket}px;height:${jacket}px">♪</div>
        <div class="info">
          <div class="genre" style="font-size:${fsGenre}px">${song.genre || '　'}</div>
          <div class="title" style="font-size:${tSize.toFixed(2)}px">${esc(song.title)}</div>
          <div class="artist" style="font-size:${aSize.toFixed(2)}px;line-height:1.5">ARTIST: ${esc(song.artist)}</div>
        </div>
      </div>
      <div class="levels">
        <span class="lv-label" style="width:${Math.max(76, 46 * scale) * (scale > 1.2 ? 1 : 0) || (narrow ? 46 : 54)}px;
              font-size:${12 * scale}px">LEVEL</span>
        ${levels}
      </div>
      <div class="char" style="font-size:${13 * scale}px"><span style="font-size:${13 * scale}px">Character : </span>星乃 一歌</div>
    </div>`;

  const shrunk = tSize < fsTitle - 0.01;
  metrics.innerHTML =
    `文字列可用宽度 <b>${textW.toFixed(0)}dp</b> · 曲名 ${fsTitle.toFixed(1)} → ` +
    `<b class="${shrunk ? 'good' : ''}">${tSize.toFixed(1)}</b>px` +
    ` · 最宽的词 <b>${(() => {
        let w = ''; for (const u of words(song.title)) if (u.length > w.length) w = u;
        return w || '—';
      })()}</b>（${(() => {
        let n = 0; for (const u of words(song.title)) n = Math.max(n, u.length);
        return n * fsTitle > textW ? '超宽，按比例缩' : '放得下';
      })()}）`;
}
function esc(s) { return s.replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c])); }

[scaleEl, widthEl, songEl].forEach(el => el.addEventListener('input', render));
render();
</script>
</body></html>
"""


if __name__ == "__main__":
    main()
