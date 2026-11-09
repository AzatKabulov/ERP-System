// Release-build phone-layout control. Callback gaps are NOT presented-frame FPS.
// Runs only against a disposable synthetic shop; never saves tokens or payloads.
const fs = require('node:fs');
const crypto = require('node:crypto');
const L = require('../e2e/lib');
if (process.env.ERP_E2E_DISPOSABLE !== 'true' || !process.env.PERF_OUT) {
  throw Error('Set ERP_E2E_DISPOSABLE=true, E2E_WEB_URL and PERF_OUT.');
}
(async () => {
  const browser = await L.launch();
  try {
    const viewport = {width:Number(process.env.PERF_WIDTH || 390), height:Number(process.env.PERF_HEIGHT || 844)};
    if (!Number.isInteger(viewport.width) || !Number.isInteger(viewport.height) ||
        viewport.width < 320 || viewport.height < 320) throw Error('Use viewport dimensions of at least 320 pixels.');
    const {page, problems} = await L.newPage(browser, viewport);
    await L.boot(page);
    await L.clickLabel(page, 'Войти', {which:'last',wait:300});
    await L.clickLabel(page, 'Владелец', {wait:1200});
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('Emulation.setCPUThrottlingRate', {rate:4});
    await cdp.send('Performance.enable');
    const cpu = async () => Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m=>[m.name,m.value]));
    const route = ['Товары', 'Продажи', 'Склад', 'Обзор', 'Товары'];
    // Warm routes, fonts and engine caches before the identical measured workload.
    for (const label of route) await L.clickLabel(page, label, {wait:900,role:'button'});
    const samples = [];
    for (let round=0;round<3;round++) {
      await L.clickLabel(page, 'Обзор', {wait:900,role:'button'});
      const visits = [];
      for (const label of route) {
        const before = await cpu();
        await page.evaluate(() => {
          window.phonePerf = {tasks:[],gaps:[],last:null};
          const tick = t => {
            const p = window.phonePerf;
            if (p.last !== null) p.gaps.push(t-p.last);
            p.last=t; p.raf=requestAnimationFrame(tick);
          };
          window.phonePerf.raf=requestAnimationFrame(tick);
          window.phonePerf.observer=new PerformanceObserver(list =>
            window.phonePerf.tasks.push(...list.getEntries().map(e=>e.duration)));
          window.phonePerf.observer.observe({type:'longtask'});
        });
        await L.clickLabel(page, label, {wait:1200,role:'button'});
        const metrics = await page.evaluate(() => {
          const p=window.phonePerf;
          cancelAnimationFrame(p.raf);p.observer.disconnect();
          const gaps=p.gaps.sort((a,b)=>a-b);
          return {longTasks:p.tasks.length,longTaskMs:p.tasks.reduce((a,b)=>a+b,0),
            maxTaskMs:Math.max(0,...p.tasks),callbackGapP95Ms:gaps[Math.floor(gaps.length*.95)]||0,
            callbacksOver33Ms:gaps.filter(g=>g>33.4).length};
        });
        const after = await cpu();
        visits.push({label,...metrics,taskWorkMs:(after.TaskDuration-before.TaskDuration)*1000,
          layoutWorkMs:(after.LayoutDuration-before.LayoutDuration)*1000,
          scriptWorkMs:(after.ScriptDuration-before.ScriptDuration)*1000});
      }
      samples.push({round,visits});
      console.log(JSON.stringify({round,taskWorkMs:visits.reduce((a,v)=>a+v.taskWorkMs,0),longTaskMs:visits.reduce((a,v)=>a+v.longTaskMs,0),longTasks:visits.reduce((a,v)=>a+v.longTasks,0)}));
    }
    const bundle = await (await page.request.get(new URL('/main.dart.js',L.URL).href)).body();
    const result={browser:browser.version(),viewport,cpuRate:4,
      scenario:'Warm responsive navigation: Products, Sales, Stock, Overview, Products; 300 synthetic products; 1200ms per visit; semantics enabled',
      bundleSha256:crypto.createHash('sha256').update(bundle).digest('hex'),samples,problems};
    fs.writeFileSync(process.env.PERF_OUT,JSON.stringify(result,null,2));
    if (problems.length) throw Error(problems.join('\n'));
  } finally {await browser.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
