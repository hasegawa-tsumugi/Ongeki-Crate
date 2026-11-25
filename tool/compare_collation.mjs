// 把 Dart 侧导出的 title 排序（build/_dart_order.json）和 ICU 真值核对。
//   node tool/compare_collation.mjs
//
// 前置：先跑 `flutter test test/collation_export_test.dart` 生成导出文件。
//
// 两个指标：
//   * 相邻对 —— 以 ICU 序为基准，比较相邻且不相等的标题对。挑剔度低但直观。
//   * 全对（Kendall）—— 所有 C(n,2) 对里相对次序一致的比例。严格得多，
//     一个标题排错位置会被它跨过的所有对计一次。
import fs from 'node:fs';

const raw = JSON.parse(fs.readFileSync('assets/songs-2026.10.15.json', 'utf8'));
const songs = raw.songs || raw;
const titles = [...new Set(songs.map((s) => s.title))];

const icuSorted = [...titles].sort((a, b) => a.localeCompare(b, 'ja'));
const cpSorted = [...titles].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
const dartSorted = JSON.parse(fs.readFileSync('build/_dart_order.json', 'utf8'));

const hasHan = (t) => /[\u4e00-\u9fff]/.test(t);

/** 以 icuSorted 的相邻对为基准，统计 `order` 的相对次序一致率。 */
function adjacent(order, subset) {
  const pos = new Map();
  order.forEach((t, i) => pos.has(t) || pos.set(t, i));
  let hit = 0;
  let total = 0;
  for (let i = 0; i + 1 < icuSorted.length; i++) {
    const a = icuSorted[i];
    const b = icuSorted[i + 1];
    if (a === b) continue;
    if (subset && !(subset(a) || subset(b))) continue;
    const pa = pos.get(a);
    const pb = pos.get(b);
    if (pa === undefined || pb === undefined) continue;
    total++;
    if (pa < pb) hit++;
  }
  return { hit, total };
}

/** Kendall 型：所有对里相对次序一致的比例。 */
function allPairs(order) {
  const pos = new Map();
  order.forEach((t, i) => pos.has(t) || pos.set(t, i));
  const n = icuSorted.length;
  let hit = 0;
  let total = 0;
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      if (icuSorted[i] === icuSorted[j]) continue;
      total++;
      if (pos.get(icuSorted[i]) < pos.get(icuSorted[j])) hit++;
    }
  }
  return { hit, total };
}

const pct = (r) => `${((100 * r.hit) / r.total).toFixed(2)}% (${r.hit}/${r.total})`;
const pad = (s, n) => String(s).padEnd(n);

console.log(`unique titles: ${titles.length}\n`);
console.log(pad('实现', 18), pad('相邻对·全部', 22), pad('相邻对·含汉字', 22), '全对·Kendall');
for (const [label, order] of [
  ['纯码位 (baseline)', cpSorted],
  ['Dart (当前实现)', dartSorted],
]) {
  console.log(
    pad(label, 18),
    pad(pct(adjacent(order)), 22),
    pad(pct(adjacent(order, hasHan)), 22),
    pct(allPairs(order)),
  );
}

// 报几个 Dart 侧仍然与 ICU 不一致的相邻对，便于判断是不是还能救。
const pos = new Map();
dartSorted.forEach((t, i) => pos.has(t) || pos.set(t, i));
const misses = [];
for (let i = 0; i + 1 < icuSorted.length && misses.length < 8; i++) {
  const a = icuSorted[i];
  const b = icuSorted[i + 1];
  if (a === b) continue;
  if (pos.get(a) > pos.get(b)) misses.push([a, b]);
}
if (misses.length) {
  console.log('\n仍不一致的相邻对（ICU 序 a 在 b 前，Dart 反了）:');
  for (const [a, b] of misses) console.log(`  ${a}  |  ${b}`);
} else {
  console.log('\n相邻对全部一致。');
}
