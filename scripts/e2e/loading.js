// Real web build + API + disposable PostgreSQL. Delays hold actual responses;
// they are test instrumentation, never a product timer or a fabricated response.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium, webkit } = require(process.env.PLAYWRIGHT_MODULE || '/opt/node-tools/node_modules/playwright');
const address = process.env.E2E_WEB_URL;
if (process.env.ERP_E2E_DISPOSABLE !== 'true' || !address ||
    !['localhost', '127.0.0.1'].includes(new URL(address).hostname)) {
  throw Error('Set ERP_E2E_DISPOSABLE=true and E2E_WEB_URL to a disposable localhost shop.');
}
const output = process.env.E2E_OUTPUT_DIR || '/tmp/erp-skeleton-browser';

async function run() {
  await fs.mkdir(output, { recursive: true });
  // Seed one synthetic product through the real API, only in the disposable shop.
  const login = await fetch(new URL('/api/v1/local-test-login/', address), {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ role: 'owner' }),
  });
  assert.equal(login.status, 200);
  const { access } = await login.json();
  const headers = { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' };
  const me = await (await fetch(new URL('/api/v1/me/', address), { headers })).json();
  const base = `/api/v1/businesses/${me.memberships[0].business.id}`;
  const existing = await (await fetch(new URL(`${base}/products/?q=SKELETON-QA`, address), { headers })).json();
  if (!existing.count) {
    const units = await (await fetch(new URL(`${base}/units/`, address), { headers })).json();
    const response = await fetch(new URL(`${base}/products/`, address), {
      method: 'POST', headers, body: JSON.stringify({ sku: 'SKELETON-QA', name: 'Фильтр Skeleton QA ÄŇŞ',
        unit: units.results[0].id, price_amount: '100.00', price_currency: 'TMT', warranty_months: 12 }),
    });
    assert.equal(response.status, 201, await response.text());
  }
  const results = [];
  const viewports = [[390, 844], [800, 1100], [1280, 900], [1920, 1080]];
  for (const engine of (process.env.E2E_WEBKIT === 'true' ? ['chromium', 'webkit'] : ['chromium'])) {
    const browser = await (engine === 'webkit' ? webkit.launch({ headless: true }) : chromium.launch({
      headless: true, executablePath: process.env.CHROMIUM_PATH || '/opt/pw-browsers/chromium',
    }));
    try {
      for (const [width, height] of viewports) {
        for (const dark of [false, true]) {
          const name = `${engine}-${width}-${dark ? 'dark' : 'light'}`;
          const animated = engine === 'chromium' && width === 1280 && !dark;
          const context = await browser.newContext({ viewport: { width, height }, reducedMotion: animated ? 'no-preference' : 'reduce' });
          const page = await context.newPage();
          const errors = [];
          page.on('pageerror', error => errors.push(error.message));
          page.on('console', message => {
            if (message.type() === 'error') errors.push(message.text());
          });
          await page.addInitScript(({ dark }) => {
            localStorage.setItem('flutter.theme.mode', JSON.stringify(dark ? 'dark' : 'light'));
            for (const id of ['dashboard', 'products', 'sales', 'inventory']) {
              localStorage.setItem(`flutter.guide.${id}.done`, 'true');
            }
          }, { dark });
          await page.goto(address);
          await page.waitForSelector('flt-semantics-placeholder', { state: 'attached' });
          await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
          await page.getByRole('button', { name: 'Войти', exact: true }).click();
          await page.getByRole('button', { name: 'Владелец', exact: true }).click();
          await page.getByRole('button', { name: 'Товары', exact: true }).waitFor();

          let release;
          const gate = new Promise(resolve => { release = resolve; });
          await page.route(`**${base}/products/?*`, async route => {
            const response = await route.fetch();
            await gate;
            await route.fulfill({ response });
          });
          await page.getByRole('button', { name: 'Товары', exact: true }).click();
          const status = page.getByRole('status', { name: 'Загрузка…', exact: true });
          await status.waitFor();
          assert.equal(await status.count(), 1, 'one status for the gallery, no per-bone announcements');
          let frameP95Ms = null;
          if (animated) {
            frameP95Ms = await page.evaluate(() => new Promise(resolve => {
              const intervals = [];
              let previous;
              function sample(now) {
                if (previous !== undefined) intervals.push(now - previous);
                previous = now;
                if (intervals.length < 60) requestAnimationFrame(sample);
                else { intervals.sort((a, b) => a - b); resolve(intervals[56]); }
              }
              requestAnimationFrame(sample);
            }));
          }
          const search = page.getByRole('textbox').first();
          const searchBefore = await search.boundingBox();
          const shellBefore = await page.getByRole('button', { name: 'Товары', exact: true }).boundingBox();
          await page.screenshot({ path: path.join(output, `${name}-loading.png`) });
          release();
          await status.waitFor({ state: 'detached' });
          await page.unroute(`**${base}/products/?*`);
          await page.screenshot({ path: path.join(output, `${name}-loaded.png`) });
          await page.getByRole('button', { name: /Фильтр Skeleton QA ÄŇŞ/ }).waitFor();
          const searchAfter = await search.boundingBox();
          const shellAfter = await page.getByRole('button', { name: 'Товары', exact: true }).boundingBox();
          assert.deepEqual(searchAfter, searchBefore, 'search toolbar does not shift');
          assert.deepEqual(shellAfter, shellBefore, 'navigation does not shift');
          assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
          await page.screenshot({ path: path.join(output, `${name}-loaded.png`) });
          assert.deepEqual(errors, [], 'browser errors');
          results.push({ name, loading: true, loaded: true, statusCount: 1, shellShift: 0, toolbarShift: 0, animated, frameP95Ms, errors });
          console.log(`PASS ${name}: real slow read, status, reserved shell/toolbar, loaded content, no overflow/errors`);
          await context.close();
        }
      }
    } finally {
      await browser.close();
    }
  }
  await fs.writeFile(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
}

run().catch(error => { console.error(error); process.exitCode = 1; });
