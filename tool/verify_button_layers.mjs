import {spawn} from 'node:child_process';
import {writeFile,readFile} from 'node:fs/promises';
const out=process.env.SONGQUERY_VERIFY_OUT||`C:/Users/Tsumugi/Desktop/a/card-alpha-${Date.now()}`;
const file=process.env.SONGQUERY_VERIFY_HTML||'D:/WorkBuddy space/outputs/songquery-webapp/index.html';
const env=Object.fromEntries(Object.entries(process.env).filter(([k])=>!['http_proxy','https_proxy','all_proxy'].includes(k.toLowerCase())));env.NO_PROXY=env.no_proxy='localhost,127.0.0.1';
const browser=spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',['--headless','--disable-gpu','--no-first-run','--remote-debugging-port=0',`--user-data-dir=D:/Ongeki/songquery-flutter/build/button-cdp-${Date.now()}`,'about:blank'],{env,stdio:['ignore','ignore','pipe']});
const endpoint=await new Promise((ok,fail)=>{const t=setTimeout(()=>fail(Error('Chrome 超时')),15000);browser.stderr.on('data',b=>{const m=b.toString().match(/DevTools listening on (ws:\/\/\S+)/);if(m){clearTimeout(t);ok(m[1]);}});browser.on('error',fail);});
const ws=new WebSocket(endpoint);await new Promise((ok,fail)=>{ws.onopen=ok;ws.onerror=fail;});let id=0;const pending=new Map();ws.onmessage=e=>{const m=JSON.parse(e.data),p=pending.get(m.id);if(p){pending.delete(m.id);m.error?p[1](Error(JSON.stringify(m.error))):p[0](m.result);}};
const call=(method,params={},sessionId)=>new Promise((ok,fail)=>{const i=++id;pending.set(i,[ok,fail]);ws.send(JSON.stringify({id:i,method,params,sessionId}));});
const target=(await call('Target.createTarget',{url:'about:blank'})).targetId;const session=(await call('Target.attachToTarget',{targetId:target,flatten:true})).sessionId;
const evaluate=async expression=>{const r=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},session);if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
const settle=()=>evaluate('new Promise(r=>setTimeout(r,650))');
const checks=[];const check=(name,ok,data)=>{checks.push({name,ok:!!ok,data});if(!ok)console.error('失败',name,JSON.stringify(data));};
const click=async selector=>{const p=await evaluate(`(()=>{const n=document.querySelector(${JSON.stringify(selector)});n.scrollIntoView({block:'center'});const r=n.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()`);await call('Input.dispatchMouseEvent',{type:'mousePressed',...p,button:'left',clickCount:1},session);await call('Input.dispatchMouseEvent',{type:'mouseReleased',...p,button:'left',clickCount:1},session);await settle();};
const shot=async name=>{const r=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false},session);await writeFile(`${out}-${name}.png`,Buffer.from(r.data,'base64'));};
try{
await call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true},session);
await call('Page.navigate',{url:'file:///'+file},session);await evaluate('document.fonts.ready');await settle();
for(const theme of ['light','dark']){
await evaluate(`setThemeMode('${theme}');state.stack=['home'];show('home')`);await settle();
await click('#btnMenu');check(`${theme} 菜单仅返回与设置关于`,await evaluate("document.querySelector('.screen:not(.hidden)').id==='s-menu'&&[...document.querySelectorAll('.controls')].every(n=>!n.getBoundingClientRect().width)&&document.querySelectorAll('#s-menu button').length===3"));
await click('#menuSettings');await evaluate(`$('themeMode').value='${theme==='light'?'dark':'light'}';$('themeMode').dispatchEvent(new Event('change'))`);await settle();check(`${theme} 原位主题切换`,await evaluate(`document.documentElement.dataset.theme==='${theme==='light'?'dark':'light'}'`));await evaluate(`$('themeMode').value='${theme}';$('themeMode').dispatchEvent(new Event('change'))`);await settle();
for(const page of ['settings','menu','search','about','license','home','detail']){
await evaluate(page==='detail'?"openDetail(SONGS[0])":`show('${page}')`);await settle();
const result=await evaluate(`(()=>{const screen=document.querySelector('.screen:not(.hidden)');const buttons=[...screen.querySelectorAll('button')].filter(n=>{const r=n.getBoundingClientRect();return r.width&&r.height;});const css=getComputedStyle(document.documentElement);return {active:screen.id,isolated:[...document.querySelectorAll('.screen')].every(n=>n===screen?!n.inert:n.inert),buttons:buttons.map(n=>{const c=getComputedStyle(n),s=n.querySelector('svg:not(.chamfer-outline)'),r=n.getBoundingClientRect(),o=n.querySelector('.chamfer-outline');return {id:n.id,cls:n.className,color:c.color,bg:c.backgroundColor,disabled:n.disabled,icon:s?getComputedStyle(s).fill:null,outline:o?{w:o.getBoundingClientRect().width,h:o.getBoundingClientRect().height,pointer:getComputedStyle(o).pointerEvents}:null,w:r.width,h:r.height};}),circuit:css.getPropertyValue('--card-circuit-opacity').trim()};})()`);
const surfaces=await evaluate(`(()=>{const s=document.querySelector('.screen:not(.hidden)');return [...s.querySelectorAll('.card,.menu-card,.meta,.chart,.infolist,.linklist,.panel,.statuscard,.field')].filter(n=>n.style.background!=='transparent').map(n=>{const c=getComputedStyle(n);return {bg:c.backgroundColor,opacity:c.opacity,content:[...n.querySelectorAll('.title,.artist,.ring span,.character,.val,.tt,.ds,.lead,.name,img')].map(t=>{let p=t;while(p&&p!==s){if(getComputedStyle(p).opacity!=='1')return false;p=p.parentElement;}return true;})};});})()`);
check(`${theme} ${page} 卡片背景 alpha 204/255 且字图不透明`,surfaces.every(c=>c.bg===(theme==='dark'?'rgba(34, 34, 34, 0.8)':'rgba(255, 255, 255, 0.8)')&&c.opacity==='1'&&c.content.every(Boolean)),surfaces);
check(`${theme} ${page} 页面隔离`,result.isolated,result.active);
check(`${theme} ${page} 电路透明度`,Number(result.circuit)===(theme==='dark'?.16:.05));
for(const b of result.buttons){if(b.icon)check(`${theme} ${page} ${b.id||b.cls} 图标继承`,b.icon===b.color,b);if(b.outline)check(`${theme} ${page} 返回完整包边且不可点`,Math.abs(b.outline.w-b.w)<1&&Math.abs(b.outline.h-b.h)<1&&b.outline.pointer==='none',b);if(/iconbtn|fabback|circle/.test(b.cls))check(`${theme} ${page} 中性按钮跟随主题`,b.color===(theme==='dark'?'rgb(255, 255, 255)':'rgb(17, 17, 17)')&&b.bg===(theme==='dark'?'rgba(34, 34, 34, 0.867)':'rgb(255, 255, 255)'),b);if(b.disabled)check(`${theme} ${page} 禁用态`,b.color===(theme==='dark'?'rgb(170, 170, 170)':'rgb(102, 102, 102)'),b);}
if(['home','search','settings','detail','menu'].includes(page))await shot(`${theme}-${page}`);
}
await evaluate("state.stack=['home'];show('home')");await click('#btnSearch');check(`${theme} 搜索隐藏主页底钮`,await evaluate("document.querySelector('.screen:not(.hidden)').id==='s-search'&&[...document.querySelectorAll('.controls')].every(n=>!n.getBoundingClientRect().width)"));await click('#q');await call('Input.insertText',{text:'test'},session);await click('#qClear');check(`${theme} 清除关键词`,await evaluate("$('q').value===''&&state.q===' ' .trim()"));await click('#applyFiltersBtn');check(`${theme} 应用返回恢复主页`,await evaluate("document.querySelector('.screen:not(.hidden)').id==='s-home'&&$('btnSearch').getBoundingClientRect().width===43"));
await click('#btnMenu');await click('#menuAbout');await click('#viewLicenseBtn');await click('#s-license [data-back]');check(`${theme} 许可返回关于`,await evaluate("document.querySelector('.screen:not(.hidden)').id==='s-about'"));await click('#s-about [data-back]');await click('#s-menu [data-back]');check(`${theme} 往返恢复两个圈`,await evaluate("[...document.querySelectorAll('#s-home .circle')].every(n=>n.getBoundingClientRect().width===43)"));
// 详情页刻意没有底部控件（左下角不该出现菜单钮），App 侧 DetailScreen 的
// 注释里写得很清楚。这里曾经点 #btnDetailMenu 验「详情能进菜单」——按钮在
// 11-21 撤掉后这条只剩一个 null 选择器，脚本整段抛异常中断，后面那 6 条检查
// 其实一直没跑，报告里却只写「1 项失败」。现在改成正向断言「详情页确实没有
// 底部控件」，撤掉的东西再长回来才会红。
await evaluate("openDetail(SONGS[0])");await settle();
check(`${theme} 详情页打开`,await evaluate("document.querySelector('.screen:not(.hidden)').id==='s-detail'"));
check(`${theme} 详情页没有底部控件`,await evaluate("[...document.querySelectorAll('#s-detail .controls')].every(n=>!n.getBoundingClientRect().width)"));
check(`${theme} 详情返回钮浮在上层`,await evaluate("(()=>{const b=document.querySelector('#s-detail [data-back]');if(!b)return false;const r=b.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(b).visibility!=='hidden';})()"));
await call('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27},session);await settle();check(`${theme} Escape 返回主页`,await evaluate("document.querySelector('.screen:not(.hidden)').id==='s-home'"));
}
await call('Emulation.setDeviceMetricsOverride',{width:1100,height:1000,deviceScaleFactor:1,mobile:false},session);await settle();check('收起控制台不可聚焦',await evaluate("$('toolbar').inert"));await click('#devToggle');check('控制台打开可交互',await evaluate("!$('toolbar').inert"));await click('#devToggle');check('控制台关闭移出焦点序列',await evaluate("$('toolbar').inert"));
// 正式 HTML 当前没有自定义弹窗；原生 select 使用浏览器顶层弹出面板。
// 三栏是 tabGroupSel / tabSortSel / rivalSel（原来的单一 sortSel 已拆成三栏，
// 这条检查一度还指着旧 id，取到 null 直接把后面整段跑挂）。
await evaluate("show('search')");await settle();
check('排序区是三栏下拉',await evaluate("['tabGroupSel','tabSortSel','rivalSel'].every(id=>{const n=document.getElementById(id);return n&&n.tagName==='SELECT';})"));
check('缺数据的项是灰项',await evaluate("[...document.querySelectorAll('#tabGroupSel option,#tabSortSel option,#rivalSel option')].filter(o=>o.disabled).length>0"));
await click('#tabSortSel');await call('Input.dispatchKeyEvent',{type:'keyDown',key:'ArrowDown',code:'ArrowDown',windowsVirtualKeyCode:40},session);await call('Input.dispatchKeyEvent',{type:'keyDown',key:'Enter',code:'Enter',windowsVirtualKeyCode:13},session);await settle();check('真实原生下拉可选择关闭',await evaluate("$('tabSortSel').value!=='recommended'"));
}catch(e){check('运行器异常',false,String(e.stack));}finally{await writeFile(out+'-checks.json',JSON.stringify({passed:checks.filter(x=>x.ok).length,failed:checks.filter(x=>!x.ok).length,checks},null,2));console.log(JSON.stringify({passed:checks.filter(x=>x.ok).length,failed:checks.filter(x=>!x.ok).length,report:out+'-checks.json'}));await call('Browser.close').catch(()=>{});ws.close();}
process.exitCode=checks.some(x=>!x.ok)?1:0;
