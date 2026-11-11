// Real release build + marked disposable shop. Never records credentials/payloads.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const L = require('../e2e/lib');
const origin = new URL(L.URL);
assert(process.env.ERP_E2E_DISPOSABLE === 'true');
assert(['localhost', '127.0.0.1'].includes(origin.hostname));
assert(fs.existsSync(path.join(process.env.PERF_SAMPLE_DATA || '', '.performance-sample')));
assert(process.env.PERF_OUT);
const ru = JSON.parse(fs.readFileSync(path.join(__dirname, '../../mobile/lib/l10n/app_ru.arb')));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
let active;
let stage = 'launch';
(async () => {
  const browser = await L.launch();
  const runs = [];
  try {
    for (const latency of [0, 600]) {
      for (let sample = 0; sample < Number(process.env.PERF_SAMPLES || 3); sample++) {
      const context = await browser.newContext({viewport:{width:390,height:844}, hasTouch:true,
        isMobile:true, userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1'});
      const page = await context.newPage();
      active = page;
      page.setDefaultTimeout(20000);
      const problems = [];
      page.on('pageerror', error => problems.push(error.message));
      await context.addInitScript(() => {
        for (const id of ['dashboard','products','sales','inventory'])
          localStorage.setItem(`flutter.guide.${id}.done`, 'true');
        localStorage.setItem('flutter.language', JSON.stringify('ru'));
        window.startupProbe = {firstFrame:null};
        addEventListener('flutter-first-frame', () => window.startupProbe.firstFrame = performance.now(), {once:true});
      });
      const requests = [];
      let recording = false;
      page.on('request', request => {
        const url = new URL(request.url());
        if (recording && url.pathname.startsWith('/api/v1/')) requests.push({
          path:url.pathname.replace(/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}/g, ':id'),
          startMs:Date.now(),request,
        });
      });
      page.on('requestfinished', request => {
        const record = requests.find(r => r.request === request);
        if (record) record.endMs = Date.now();
      });
      // No routing at zero latency: retain real HTTP-cache behavior. Playwright
      // routing disables HTTP cache in the injected-latency control; label it.
      if (latency) await page.route('**/api/v1/**', async route => {
        if (requests.some(r => r.request === route.request())) await sleep(latency);
        await route.continue();
      });
      // Empty browser cache/no session. Wait on actual sign-in semantics, not helper sleeps.
      const coldStart = Date.now();
      stage = 'cold sign-in';
      await page.goto(L.URL, {waitUntil:'domcontentloaded'});
      await page.waitForFunction(() => {
        document.querySelector('flt-semantics-placeholder')?.click();
        return [...document.querySelectorAll('flt-semantics')]
          .some(n => (n.getAttribute('aria-label') || n.textContent || '').trim() === 'Войти');
      });
      const cold = {firstFrameMs:await page.evaluate(() => window.startupProbe.firstFrame),
        signInObservedMs:Date.now()-coldStart};
      // The sample-only role chooser depends on the optional health probe. Its
      // setup and font/layout settling are outside both measured boundaries.
      await page.waitForFunction(notice => [...document.querySelectorAll('flt-semantics')]
        .some(n => (n.getAttribute('aria-label') || n.textContent || '').includes(notice)),ru.testLoginNotice);
      await page.waitForTimeout(300);
      await L.clickLabel(page, 'Войти', {which:'last',wait:300});
      await L.clickLabel(page, 'Владелец', {wait:1500});
      // Warm HTTP resources, persisted session; measure from reload, not helper waits.
      recording = true;
      stage = 'warm shell';
      const started = Date.now();
      await page.reload({waitUntil:'domcontentloaded'});
      await page.waitForFunction(() => {
        document.querySelector('flt-semantics-placeholder')?.click();
        return [...document.querySelectorAll('flt-semantics')]
          .some(n => (n.getAttribute('aria-label') || n.textContent || '').includes('Sample Owner'));
      });
      const firstHomeMs = Date.now()-started;
      stage = 'verified navigation';
      await page.waitForFunction(label => [...document.querySelectorAll('flt-semantics[role="button"]')]
        .some(n => (n.getAttribute('aria-label') || n.textContent || '').trim() === label),ru.products);
      const verifiedHomeMs = Date.now()-started;
      stage = 'home figures';
      await page.waitForFunction(() => [...document.querySelectorAll('flt-semantics')]
        .some(n => /0,00.*TMT/.test(n.getAttribute('aria-label') || n.textContent || '')));
      const dataMs = Date.now()-started;
      recording = false;
      const inputStarted = Date.now();
      stage = 'products interaction';
      await page.getByRole('button',{name:ru.products,exact:true}).first().click();
      await page.waitForFunction(() => location.hash.includes('/s') ||
        [...document.querySelectorAll('flt-semantics')].some(n =>
          (n.getAttribute('aria-label') || n.textContent || '').includes('Добавить товар')));
      const interactiveMs = Date.now()-started;
      const inputResponseMs = Date.now()-inputStarted;
      // Finish observing startup requests after the interaction boundary; this
      // does not add waiting to the screen/readiness measurements above.
      await Promise.all(requests.map(async record => {
        const response = await record.request.response();
        assert(response?.ok(), `Startup request failed: ${record.path}`);
        await response.finished();
      }));
      assert(requests.every(r => Number.isFinite(r.endMs)), 'Missing request-finished timing');
      await page.screenshot({path:`${process.env.PERF_OUT}.${latency}.${sample}.png`});
      runs.push({apiLatencyMs:latency,httpCache:latency?'disabled by latency routing':'enabled',
        sample,cold,firstHomeMs,verifiedHomeMs,homeDataMs:dataMs,
        interactiveProbeMs:interactiveMs,inputResponseMs,
        firstFrameMs:await page.evaluate(() => window.startupProbe.firstFrame),
        apiWallMs:Math.max(...requests.map(r=>r.endMs))-Math.min(...requests.map(r=>r.startMs)),
        summedApiMs:requests.reduce((sum,r)=>sum+r.endMs-r.startMs,0),
        requests:requests.map(r=>({path:r.path,startMs:r.startMs-started,endMs:r.endMs-started})),problems});
      console.log(JSON.stringify(runs.at(-1)));
      assert.deepEqual(problems, []);
      await context.close();
      }
    }
    const bytes = await (await fetch(new URL('/main.dart.js', L.URL))).arrayBuffer();
    fs.writeFileSync(process.env.PERF_OUT, JSON.stringify({browser:browser.version(),
      note:'Desktop browser with iPhone UA/viewport; added API latency only. Cold has empty resources/no session; warm reload uses the same context and secure session. HTTP cache enabled at 0ms; Playwright routing disables it in the 600ms control (static assets still use fast loopback). FirstHome may be a locked identity/skeleton shell. VerifiedHome requires server profile; HomeData requires money text. InteractiveProbe includes real product-tab click and destination semantics, not universal TTI. Not hardware FPS.',
      sha256:crypto.createHash('sha256').update(Buffer.from(bytes)).digest('hex'),runs}, null, 2)+'\n');
  } catch (error) {
    if (active && !active.isClosed()) {
      await active.screenshot({path:`${process.env.PERF_OUT}.failure.png`});
      fs.writeFileSync(`${process.env.PERF_OUT}.failure.txt`, await L.text(active));
    }
    throw error;
  } finally { await browser.close(); }
})().catch(error => {console.error(`${stage}: ${error.message}`);process.exitCode=1;});
