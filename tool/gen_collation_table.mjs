// 生成 japanese collation 的字符权重表。
//
// 表的内容不能手排：手写权重实测比码位排序更差（79.4% vs 81.3%）。这里的做法是
// 让 ICU 自己给字符排序 —— 对每个字符单独跑 localeCompare(.., 'ja')，得到的次序
// 就是 ICU 的 ja 主权重序，再固化成 Dart 常量。
//
// 用法（需要带完整 ICU 的 Node，Node 13+ 默认就是）：
//   node tool/gen_collation_table.mjs
//
// 产物（都会直接写盘 / 改写，不要手改结果）：
//   1) lib/src/domain.dart 里的 `_collationOrder` —— 符号 / 数字 / 拉丁。
//      字符集 = ASCII 可打印串 + 日文标点 + **随包曲库里出现过的所有
//      非假名非汉字字符**（、。“”×∀→ 这些）。不自动收录的话它们会掉进
//      1000+rune 兜底，排到所有汉字之后。
//   2) lib/src/collation_han.dart —— 汉字表，按 ICU 主权重序。
//
// 汉字表只收「随包快照里出现过的汉字」。曲库更新引入新字符时重跑一次即可；
// 表外字符退回码位比较。
import fs from 'node:fs';

const BS = '\\';
const esc = (ch) => {
  const o = ch.codePointAt(0);
  if (ch === "'") return BS + "'";
  if (ch === BS) return BS + BS;
  if (ch === '$') return BS + '$';
  if (o === 0x20 || o < 0x21 || o > 0x7e) {
    return BS + 'u' + o.toString(16).padStart(4, '0');
  }
  return ch;
};

const DATASET = 'assets/songs-2026.10.15.json';
const raw = JSON.parse(fs.readFileSync(DATASET, 'utf8'));
const songs = raw.songs || raw;
const titles = new Set(songs.map((s) => s.title));

const isKana = (o) => (o >= 0x3041 && o <= 0x3096) || (o >= 0x30a1 && o <= 0x30ff);
const isHan = (o) => o >= 0x4e00 && o <= 0x9fff;

// ---- 1) 符号 / 数字 / 拉丁 ----
// 数据集里出现的非假名非汉字字符，还要按 ICU 再分成两层：排在汉字**之前**的
// （标点、符号）留在符号表；排在汉字**之后**的（希腊、西里尔等字母表脚本）
// 单独一层。实测 ICU：∀ < 亜 < α < Я，混在一层会全排到汉字前面。
const HAN_REF = '亜';
const symbolSet = new Set();
for (let c = 0x20; c <= 0x7e; c++) symbolSet.add(String.fromCharCode(c));
for (const ch of '〜・ー　！？…＠＆☆★♪') symbolSet.add(ch);

const afterHanSet = new Set();
for (const t of titles) {
  for (const ch of t) {
    const o = ch.codePointAt(0);
    if (isKana(o) || isHan(o)) continue;
    if (ch.localeCompare(HAN_REF, 'ja') < 0) symbolSet.add(ch);
    else afterHanSet.add(ch);
  }
}
const symbols = [...symbolSet].sort((a, b) => a.localeCompare(b, 'ja'));
const symbolLiteral = symbols.map(esc).join('');
const afterHan = [...afterHanSet].sort((a, b) => a.localeCompare(b, 'ja'));
const afterHanLiteral = afterHan.map(esc).join('');

// 改写 domain.dart 里的两个常量，避免手工粘贴出错。
const DOMAIN = 'lib/src/domain.dart';
const domainSrc = fs.readFileSync(DOMAIN, 'utf8');

const patch = (src, name, literal) => {
  // 允许「单行 ''」与「多行拼接」两种写法，替换后统一写成多行拼接。
  const one = "'(?:[^'\\\\]|\\\\.)*'";
  const many = `(?:${one})(?:\\s*\\n\\s*${one})*`;
  const re = new RegExp(`const ${name} =\\s*${many}\\s*;`);
  if (!re.test(src)) throw new Error(`domain.dart 里找不到 ${name}，模式失效了`);
  return src.replace(re, `const ${name} =\n    '${literal}';`);
};

let nextDomain = patch(domainSrc, '_collationOrder', symbolLiteral);
nextDomain = patch(nextDomain, '_collationAfterHan', afterHanLiteral);
fs.writeFileSync(DOMAIN, nextDomain);
console.log(
  `patched ${DOMAIN}: _collationOrder ${symbols.length} chars, ` +
    `_collationAfterHan ${afterHan.length} chars (${afterHan.join('')})`,
);

// ---- 2) 汉字 ----
const han = new Set();
for (const t of titles) {
  for (const ch of t) if (isHan(ch.codePointAt(0))) han.add(ch);
}
const rankedHan = [...han].sort((a, b) => a.localeCompare(b, 'ja'));

// 40 字一行，方便 diff 与人工抽查。
const CHUNK = 40;
const lines = [];
for (let i = 0; i < rankedHan.length; i += CHUNK) {
  lines.push(`    '${rankedHan.slice(i, i + CHUNK).join('')}'`);
}

const dart = `// 由 tool/gen_collation_table.mjs 生成，不要手改。
//
// 内容：随包曲库快照（${DATASET.split('/').pop()}）里出现过的
// ${rankedHan.length} 个汉字，按 ICU 的 \`ja\` 主权重序排列。
//
// 为什么需要这张表：Dart 没有 locale 排序 API，直接按码位比汉字会和 ICU 差很远。
// ICU 的 ja 汉字主权重来自 CLDR 的 unihan 数据，大致按读音排，和码位序大量互逆：
//   ICU 序  亜 < 一   日 > 月   火 < 月   花 < 鳥
//   码位序  一 < 亜   日 < 月   月 < 火   花 < 鳥
// 用这张表做主权重，实测把含汉字标题的相邻次序一致度从 68.0% 拉到 99.0%，
// 全库从 73.1% 拉到 99.2%（指标见 tool/_cmp_order.mjs）。
//
// 表外汉字仍退回码位比较，会排在本表所有字之后 —— 曲库更新后重跑生成器即可。
const hanCollationOrder =
${lines.join('\n')};

/// 汉字 → 主权重序。表外汉字查不到，由调用方退回码位。
final Map<int, int> hanCollationRanks = {
  for (final (index, rune) in hanCollationOrder.runes.indexed) rune: index,
};
`;

fs.writeFileSync('lib/src/collation_han.dart', dart);
console.log(
  `wrote lib/src/collation_han.dart (${rankedHan.length} chars, ${dart.length} bytes)`,
);
