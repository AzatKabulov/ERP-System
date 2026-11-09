// Catalog photo-download control on a marked, disposable local sample shop.
// Run after sample_server.py --photos; authentication stays outside measurement.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const L = require('../e2e/lib');

const origin = new URL(L.URL);
if (process.env.ERP_E2E_DISPOSABLE !== 'true' ||
    !['127.0.0.1', 'localhost'].includes(origin.hostname) ||
    !process.env.PERF_OUT || !process.env.PERF_SAMPLE_DATA ||
    !fs.existsSync(path.join(process.env.PERF_SAMPLE_DATA, '.performance-sample'))) {
  throw Error('Requires a loopback URL, ERP_E2E_DISPOSABLE=true, PERF_SAMPLE_DATA and PERF_OUT.');
}
const language = process.env.PERF_LANGUAGE || 'ru';
const scheme = process.env.PERF_SCHEME || 'light';
const view = process.env.PERF_VIEW || 'list';
const viewport = {
  width: Number(process.env.PERF_WIDTH || 1440),
  height: Number(process.env.PERF_HEIGHT || 1000),
};
const sampleCount = Number(process.env.PERF_SAMPLES || 3);
assert(Number.isInteger(sampleCount) && sampleCount > 0, 'PERF_SAMPLES must be positive');
assert(Object.values(viewport).every(n => Number.isInteger(n) && n > 0), 'Invalid viewport');
assert(['ru', 'tk'].includes(language));
assert(['light', 'dark'].includes(scheme));
assert(['list', 'gallery'].includes(view));
const labels = JSON.parse(fs.readFileSync(
  path.join(__dirname, `../../mobile/lib/l10n/app_${language}.arb`), 'utf8'));

(async () => {
  const browser = await L.launch();
  const samples = [];
  try {
    for (let round = 0; round < sampleCount; round++) {
      const {ctx, page, problems} = await L.newPage(browser, viewport);
      page.setDefaultTimeout(10000);
      try {
        // Profile language takes precedence at sign-in. Set only the marked
        // sample owner's preference; keep tokens in memory and outside output.
        const login = await ctx.request.post(new URL('/api/v1/local-test-login/', L.URL).href,
          {data: {role: 'owner'}});
        assert.equal(login.status(), 200);
        const {access} = await login.json();
        const profile = await ctx.request.patch(new URL('/api/v1/me/', L.URL).href,
          {headers: {Authorization: `Bearer ${access}`}, data: {preferred_language: language}});
        assert.equal(profile.status(), 200);
        await ctx.addInitScript(({language, scheme, view}) => {
          for (const [key, value] of Object.entries({
            language, 'theme.mode': scheme, catalog_view: view,
            'guide.dashboard.done': true, 'guide.products.done': true,
          })) localStorage.setItem(`flutter.${key}`, JSON.stringify(value));
        }, {language, scheme, view});
        await L.boot(page);
        await L.clickLabel(page, labels.signInAction, {which: 'last', wait: 300});
        await L.clickLabel(page, labels.roleOwner, {wait: 1200});
        const cdp = await ctx.newCDPSession(page);
        await cdp.send('Emulation.setCPUThrottlingRate', {rate: 4});
        await cdp.send('Performance.enable');
        const cpu = async () => Object.fromEntries(
          (await cdp.send('Performance.getMetrics')).metrics.map(m => [m.name, m.value]));
        const downloads = new Set();
        page.on('request', request => {
          if (new URL(request.url()).pathname.endsWith('/photo/')) downloads.add(request.url());
        });
        const before = await cpu();
        await L.clickLabel(page, labels.products, {wait: 1800, role: 'button'});
        assert((await L.text(page)).includes('PERF-0000'), 'First catalog product missing');
        const after = await cpu();
        const initialPhotoRequests = downloads.size;
        assert(initialPhotoRequests > 0, 'Start sample_server.py with --photos');
        if (process.env.PERF_ASSERT_LAZY === 'true') {
          assert(initialPhotoRequests < 30, 'Offscreen product photos downloaded eagerly');
        }
        if (round === 0) await page.screenshot({path: `${process.env.PERF_OUT}.png`});
        await page.mouse.move(viewport.width * 0.7, viewport.height * 0.6);
        for (let step = 0; step < 12; step++) {
          const more = page.getByRole('button', {name: labels.loadMore, exact: true});
          const box = await more.count() ? await more.boundingBox() : null;
          if (box && box.y > 100 && box.y + box.height < viewport.height - 80) break;
          await page.mouse.wheel(0, 500);
          await page.waitForTimeout(300);
        }
        const nextPage = page.waitForResponse(response => {
          const url = new URL(response.url());
          return url.pathname.endsWith('/products/') && url.searchParams.get('offset') === '30';
        }, {timeout: 10000});
        await L.clickLabel(page, labels.loadMore, {wait: 1200, role: 'button'});
        if (round === 0) await page.screenshot({path: `${process.env.PERF_OUT}.paging.png`});
        assert.equal((await nextPage).status(), 200);
        await page.mouse.wheel(0, 500);
        await page.waitForTimeout(700);
        assert(downloads.size > initialPhotoRequests, 'Later rows did not load photos');
        assert.deepEqual(problems, [], 'Browser reported an error');
        samples.push({round, initialPhotoRequests, afterPagingPhotoRequests: downloads.size,
          taskWorkMs: (after.TaskDuration - before.TaskDuration) * 1000});
        console.log(JSON.stringify(samples.at(-1)));
      } finally {
        await ctx.close();
      }
    }
    const bundle = await (await fetch(new URL('/main.dart.js', L.URL))).arrayBuffer();
    fs.writeFileSync(process.env.PERF_OUT, JSON.stringify({
      browser: browser.version(), viewport, language, scheme, view, cpuRate: 4,
      scenario: 'Fresh catalog visit, first 30 of 300 synthetic products with photos; then scroll and load next page',
      bundleSha256: crypto.createHash('sha256').update(Buffer.from(bundle)).digest('hex'),
      samples,
    }, null, 2) + '\n');
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error.message); process.exitCode = 1;});
