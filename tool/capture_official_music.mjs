import {spawn} from 'node:child_process';
import {mkdir, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';

// 使用本机已有 Chrome 和 Node WebSocket，不安装浏览器依赖。
const output = resolve('build/official-reference');
await mkdir(output, {recursive:true});
const browser = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless','--disable-gpu','--no-first-run','--remote-debugging-port=0',
  '--user-data-dir='+resolve('build/official-reference/chrome-profile'),'about:blank',
], {stdio:['ignore','ignore','pipe']});
const endpoint = await new Promise((ok,fail)=>{
  const timeout=setTimeout(()=>fail(new Error('Chrome 调试端口启动超时')),15000);
  browser.stderr.on('data', b=>{const m=b.toString().match(/DevTools listening on (ws:\/\/\S+)/); if(m){clearTimeout(timeout);ok(m[1]);}});
  browser.on('error',fail);
});
const ws = new WebSocket(endpoint);
await new Promise((ok,fail)=>{ws.onopen=ok;ws.onerror=fail;});
let next=0;
const pending=new Map();
ws.onmessage=event=>{const msg=JSON.parse(event.data);const cb=pending.get(msg.id);if(cb){pending.delete(msg.id);msg.error?cb[1](new Error(JSON.stringify(msg.error))):cb[0](msg.result);}};
const call=(method,params={},sessionId)=>new Promise((ok,fail)=>{const id=++next;pending.set(id,[ok,fail]);ws.send(JSON.stringify({id,method,params,sessionId}));});
try {
  const {targetId}=await call('Target.createTarget',{url:'about:blank'});
  const {sessionId}=await call('Target.attachToTarget',{targetId,flatten:true});
  for(const width of [390,320]){
    await call('Emulation.setDeviceMetricsOverride',{width,height:844,deviceScaleFactor:1,mobile:true},sessionId);
    await call('Page.navigate',{url:'https://ongeki.sega.jp/music/'},sessionId);
    await call('Runtime.evaluate',{expression:`new Promise(resolve=>{const end=Date.now()+25000;const tick=()=>{if(document.querySelector('.p-music__listChild')||Date.now()>end)resolve();else setTimeout(tick,200);};tick();})`,awaitPromise:true},sessionId);
    await call('Runtime.evaluate',{expression:`new Promise(resolve=>{const e=document.querySelector('select');if(e&&e.options.length>1){e.selectedIndex=1;e.dispatchEvent(new Event('change',{bubbles:true}));}setTimeout(resolve,2500);})`,awaitPromise:true},sessionId);
    await call('Runtime.evaluate',{expression:'document.fonts.ready',awaitPromise:true},sessionId);
    await call('Runtime.evaluate',{expression:'window.scrollTo(0,0)'},sessionId);
    const rules=await call('Runtime.evaluate',{expression:`JSON.stringify({viewport:innerWidth, rows:document.querySelectorAll('.p-music__listChild').length, styles:['.c-sectionTitle','.p-music__choice','.p-music__choiceWrapper','.p-music__choiceListChild','.p-music__listChildImg','.p-music__listFooter'].map(s=>{const e=document.querySelector(s);if(!e)return {selector:s,missing:true};const c=getComputedStyle(e);return {selector:s,width:c.width,height:c.height,padding:c.padding,margin:c.margin,fontSize:c.fontSize,rect:e.getBoundingClientRect().toJSON()};})})`,returnByValue:true},sessionId);
    await writeFile(resolve(output,`music-${width}-computed.json`),rules.result.value);
    const shot=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false},sessionId);
    await writeFile(resolve(output,`music-${width}.png`),Buffer.from(shot.data,'base64'));
    console.log('官网真实移动截图',resolve(output,`music-${width}.png`));
  }
} finally {await call('Browser.close').catch(()=>{});ws.close();}
