// Raw CDP trace and operational navigation boundaries; authentication is outside capture.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const os = require('node:os');
const zlib = require('node:zlib');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const L = require('../e2e/lib');
const out = process.env.PERF_OUT;
if (!out || !process.env.ERP_SAMPLE_PASSWORD || process.env.ERP_E2E_DISPOSABLE !== 'true') throw Error('Use PERF_OUT and credentials for a disposable sample server.');
fs.mkdirSync(out, { recursive: true });
const iterations = Number(process.env.PERF_ITERATIONS || 10);
const rate = Number(process.env.PERF_CPU_RATE || 4);
const traceEnabled = process.env.PERF_TRACE !== 'false';
async function traceEnd(cdp, filename) {
  const done = new Promise(resolve => cdp.once('Tracing.tracingComplete', resolve));
  await cdp.send('Tracing.end');
  const { stream } = await done;
  const chunks = [];
  for (;;) {
    const r = await cdp.send('IO.read', { handle: stream });
    chunks.push(Buffer.from(r.data, r.base64Encoded ? 'base64' : 'utf8'));
    if (r.eof) break;
  }
  await cdp.send('IO.close', { handle: stream });
  fs.writeFileSync(filename, zlib.gzipSync(Buffer.concat(chunks)));
}
(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH, headless: true });
  const summary = { version: browser.version(), platform: os.platform(), arch: os.arch(), cpus: os.cpus()[0].model,
    viewport: { width: 820, height: 1000 }, cpuRate: rate, tracing: traceEnabled,
    scenario: 'Overview to Products, 300 products, 30 per page, no photos; accessibility enabled', samples: [] };
  try {
    const { page } = await L.newPage(browser, summary.viewport);
    await L.boot(page);
    await L.fill(page, '^Логин$', 'owner');
    await L.fill(page, '^Пароль$', process.env.ERP_SAMPLE_PASSWORD);
    await L.clickLabel(page, 'Войти', { which: 'last', wait: 1500 });
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate });
    for (let i = 0; i < iterations; i++) {
      if (i > 0) { await L.clickLabel(page, 'Обзор'); await page.waitForTimeout(800); }
      const box = await page.evaluate(() => {
        const elements = [...document.querySelectorAll('flt-semantics')].filter(n =>
          n.getAttribute('role') === 'button' && (n.getAttribute('aria-label') || n.textContent).trim() === 'Товары');
        const r = elements[0]?.getBoundingClientRect();
        if (!r) throw Error('No Products navigation control');
        return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
      });
      const requests = [];
      const listener = request => {
        const u = new URL(request.url());
        if (u.pathname.includes('/api/v1/') && !u.pathname.includes('/auth/')) {
          const t = request.timing();
          requests.push({ endpoint: u.pathname.split('/').slice(5).join('/'), startMs: t.startTime, endMs: t.responseEnd });
        }
      };
      page.on('requestfinished', listener);
      if (traceEnabled) await cdp.send('Tracing.start', { categories: 'devtools.timeline,blink.user_timing,v8,disabled-by-default-v8.cpu_profiler', transferMode: 'ReturnAsStream' });
      await page.evaluate(() => {
        const state = window.erpPerf = { start: performance.now(), timeOrigin: performance.timeOrigin, feedbackMs: null, usefulMs: null, readyMs: null, tasks: [] };
        performance.mark('erp.navigation.input');
        const check = () => {
          const now = performance.now();
          if (state.feedbackMs === null && document.querySelector('input[aria-label^="Поиск по названию"]')) {
            state.feedbackMs = now - state.start; performance.mark('erp.navigation.feedback');
          }
          if (state.usefulMs === null && (document.querySelector('[aria-label*="PERF-0000"]') || document.body.textContent.includes('PERF-0000'))) {
            state.usefulMs = now - state.start; performance.mark('erp.navigation.useful');

          }
        };
        state.domObserver = new MutationObserver(check);
        state.domObserver.observe(document.body, {subtree:true,childList:true,attributes:true,attributeFilter:['aria-label']});
        state.observer = new PerformanceObserver(list => state.tasks.push(...list.getEntries().map(e => ({startMs:e.startTime-state.start,durationMs:e.duration}))));
        state.observer.observe({type:'longtask'});
      });
      await cdp.send('Input.dispatchMouseEvent', { type: 'mousePressed', button: 'left', clickCount: 1, ...box });
      await cdp.send('Input.dispatchMouseEvent', { type: 'mouseReleased', button: 'left', clickCount: 1, ...box });
      await page.waitForFunction(() => window.erpPerf.usefulMs !== null);
      const search = await page.locator('input[aria-label^="Поиск по названию"]').boundingBox();
      if (!search) throw Error('No destination search field');
      await page.evaluate(() => performance.mark('erp.navigation.focusProbe'));
      const focusPoint = {x:search.x + search.width/2,y:search.y + search.height/2};
      await cdp.send('Input.dispatchMouseEvent', {type:'mousePressed',button:'left',clickCount:1,...focusPoint});
      await cdp.send('Input.dispatchMouseEvent', {type:'mouseReleased',button:'left',clickCount:1,...focusPoint});
      await page.waitForFunction(() => document.activeElement?.getAttribute('aria-label')?.startsWith('Поиск по названию'));
      await page.evaluate(() => { window.erpPerf.readyMs=performance.now()-window.erpPerf.start; performance.mark('erp.navigation.ready'); });
      // Fixed observation window; its elapsed duration is never called navigation latency.
      await page.waitForTimeout(2000);
      const sample = await page.evaluate(() => {
        const s = window.erpPerf; s.domObserver.disconnect(); s.observer.disconnect();
        const { observer, domObserver, ...result } = s; return result;
      });
      page.off('requestfinished', listener);
      if (traceEnabled) await traceEnd(cdp, path.join(out, `sample-${i}.trace.json.gz`));
      if (sample.usefulMs === null || sample.readyMs === null) throw Error('Destination content never appeared');
      summary.samples.push({ i, cache: i === 0 ? 'first-route' : 'warm', ...sample, requests });
      fs.writeFileSync(path.join(out, 'samples.json'), JSON.stringify(summary, null, 2));
      console.log(JSON.stringify({sample:i, feedbackMs:sample.feedbackMs, usefulMs:sample.usefulMs, readyMs:sample.readyMs, longTaskMs:sample.tasks.reduce((sum,t)=>sum+t.durationMs,0)}));
    }
    await page.screenshot({path:path.join(out,'destination.png')});
    summary.bundleSha256 = crypto.createHash('sha256').update(await (await page.request.get(new URL('/main.dart.js',process.env.E2E_WEB_URL).toString())).body()).digest('hex');
    fs.writeFileSync(path.join(out,'samples.json'),JSON.stringify(summary,null,2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
