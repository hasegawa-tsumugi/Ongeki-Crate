// 双端对拍第二步：拿 App 导出的全量结果，去比对网页端 filtered() 的实际输出。
//
// 用法（按顺序两条命令）：
//   1. flutter test test/parity_export_test.dart      -> build/_parity_app.json
//   2. node tool/check_parity.mjs                     -> 逐首比对，0 差异才 exit 0
//
// 需要先打好网页：python tool/build_webapp.py
// 可用 SONGQUERY_PARITY_HTML 覆盖网页路径，SONGQUERY_PARITY_APP 覆盖 App JSON 路径。
//
// 为什么值得留成常驻工具：网页和 App 是同一套排序规则的两份实现，只靠人工
// 翻两页比对，样本永远太小。曲名兜底那次真 bug（App 用标题原文、网页用读音）
// 只在特定几个曲名上分道扬镳，抽三条样本恰好全中才看得见。这里跑全量 6 组
// × 5 种排序 × 每首曲目，任何一处比较器改动都会立刻现形。
import {spawn} from 'node:child_process';
import {readFile} from 'node:fs/promises';

const APP_JSON = process.env.SONGQUERY_PARITY_APP || 'D:/Ongeki/songquery-flutter/build/_parity_app.json';
const HTML = process.env.SONGQUERY_PARITY_HTML || 'D:/WorkBuddy space/outputs/songquery-webapp/index.html';
const CHROME = process.env.SONGQUERY_CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';

const app = JSON.parse(await readFile(APP_JSON, 'utf8'));
const caseNames = Object.keys(app.cases);
if (!caseNames.length) throw new Error('App 导出的 cases 是空的，先跑 export');

// Chrome 子进程不能继承代理：flutter_tester / DevTools 那条 localhost WebSocket
// 会被塞进代理，报 "Invalid WebSocket upgrade request"。这里显式剔掉。
const env = Object.fromEntries(Object.entries(process.env)
  .filter(([k]) => !['http_proxy', 'https_proxy', 'all_proxy'].includes(k.toLowerCase())));
env.NO_PROXY = env.no_proxy = 'localhost,127.0.0.1,::1';

const browser = spawn(CHROME, [
  '--headless', '--disable-gpu', '--no-first-run', '--remote-debugging-port=0',
  `--user-data-dir=D:/Ongeki/songquery-flutter/build/parity-cdp-${Date.now()}`,
  'about:blank',
], {env, stdio: ['ignore', 'ignore', 'pipe']});

const endpoint = await new Promise((ok, fail) => {
  const timer = setTimeout(() => fail(Error('Chrome 启动超时')), 20000);
  browser.stderr.on('data', b => {
    const m = b.toString().match(/DevTools listening on (ws:\/\/\S+)/);
    if (m) { clearTimeout(timer); ok(m[1]); }
  });
  browser.on('error', fail);
});

const ws = new WebSocket(endpoint);
await new Promise((ok, fail) => { ws.onopen = ok; ws.onerror = fail; });
let seq = 0;
const pending = new Map();
ws.onmessage = e => {
  const m = JSON.parse(e.data);
  const p = pending.get(m.id);
  if (!p) return;
  pending.delete(m.id);
  m.error ? p[1](Error(JSON.stringify(m.error))) : p[0](m.result);
};
const call = (method, params = {}, sessionId) => new Promise((ok, fail) => {
  const id = ++seq;
  pending.set(id, [ok, fail]);
  ws.send(JSON.stringify({id, method, params, sessionId}));
});

const target = (await call('Target.createTarget', {url: 'about:blank'})).targetId;
const session = (await call('Target.attachToTarget', {targetId: target, flatten: true})).sessionId;
const evaluate = async expression => {
  const r = await call('Runtime.evaluate', {expression, returnByValue: true, awaitPromise: true}, session);
  if (r.exceptionDetails) throw Error(JSON.stringify(r.exceptionDetails));
  return r.result.value;
};

let failures = 0;
try {
  await call('Emulation.setDeviceMetricsOverride',
    {width: 390, height: 844, deviceScaleFactor: 1, mobile: true}, session);
  await call('Page.navigate', {url: 'file:///' + HTML}, session);
  await new Promise(r => setTimeout(r, 900));
  await evaluate('document.fonts.ready');

  const ready = await evaluate('typeof SONGS === "object" && typeof filtered === "function" && typeof groupLabelOf === "function"');
  if (!ready) throw Error('页面没暴露 SONGS / filtered / groupLabelOf，网页结构变了');
  console.log(`网页曲目数 ${await evaluate('SONGS.length')}，App 曲目数 ${app.total}`);

  for (const name of caseNames) {
    const [group, sort] = name.split('/');
    const web = await evaluate(`(() => {
      state.q = '';
      state.genres = new Set(); state.chars = new Set(); state.releases = new Set();
      state.diffs = new Set(); state.levels = new Set();
      state.tabGroup = ${JSON.stringify(group)};
      state.tabSort = ${JSON.stringify(sort)};
      const list = filtered();
      const ids = list.map(x => x.i);
      const groups = [];
      for (const x of list) {
        const label = groupLabelOf(x);
        const last = groups[groups.length - 1];
        if (!last || last[0] !== label) groups.push([label, 1]);
        else last[1]++;
      }
      return {ids, groups, tabGroup: currentTabGroup(), tabSort: currentTabSort()};
    })()`);

    const want = app.cases[name];
    const problems = [];

    // 设置真的生效了没有：回退到默认项时整张表都是默认序，比对会「意外全对」。
    if (web.tabGroup !== group) problems.push(`分组没生效（页面停在 ${web.tabGroup}）`);
    if (web.tabSort !== sort) problems.push(`排序没生效（页面停在 ${web.tabSort}）`);

    if (web.ids.length !== want.ids.length) {
      problems.push(`曲目数 ${web.ids.length} ≠ ${want.ids.length}`);
    }
    const diffAt = [];
    const n = Math.min(web.ids.length, want.ids.length);
    for (let i = 0; i < n; i++) {
      if (web.ids[i] !== want.ids[i]) {
        diffAt.push({i, app: want.ids[i], web: web.ids[i]});
        if (diffAt.length >= 5) break;
      }
    }
    if (diffAt.length) problems.push(`所在位置不同 ${diffAt.length}+ 处，首处 #${diffAt[0].i}`);

    const wg = JSON.stringify(web.groups), ag = JSON.stringify(want.groups);
    if (wg !== ag) {
      const a = want.groups, w = web.groups;
      const firstBad = a.findIndex((x, i) => !w[i] || x[0] !== w[i][0] || x[1] !== w[i][1]);
      problems.push(`分段不同（段数 app=${a.length} web=${w.length}，首处 #${firstBad} ` +
        `app=${JSON.stringify(a[firstBad])} web=${JSON.stringify(w[firstBad])}）`);
    }

    if (problems.length) {
      failures++;
      console.error(`✗ ${name}  ${problems.join('；')}`);
      for (const d of diffAt) {
        console.error(`    #${d.i} app=${d.app} web=${d.web}`);
      }
    } else {
      console.log(`✓ ${name}  ${want.ids.length} 首 / ${want.groups.length} 段`);
    }
  }
} finally {
  try { browser.kill(); } catch {}
}

console.log(failures ? `\n${failures} 个组合有差异` : '\n全部组合 0 差异');
process.exit(failures ? 1 : 0);
