// Current UI, real API/PostgreSQL, disposable shop only. No legacy Purchasing screens.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const L = require('./lib');
if (process.env.ERP_E2E_DISPOSABLE !== 'true' || !process.env.E2E_WEB_URL) {
  throw Error('Use a disposable shop and set ERP_E2E_DISPOSABLE=true and E2E_WEB_URL.');
}
const out = process.env.E2E_OUT || '/tmp/erp-readiness-browser';
fs.mkdirSync(out, {recursive:true});
const ru = JSON.parse(fs.readFileSync(path.join(__dirname, '../../mobile/lib/l10n/app_ru.arb')));
const tk = JSON.parse(fs.readFileSync(path.join(__dirname, '../../mobile/lib/l10n/app_tk.arb')));
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const viewports = process.env.E2E_VIEWPORTS ? JSON.parse(process.env.E2E_VIEWPORTS)
  : [[390,844], [768,1024], [1024,768], [1440,900]];
(async () => {
  const login = await fetch(new URL('/api/v1/local-test-login/', L.URL), {
    method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({role:'owner'}),
  });
  assert.equal(login.status, 200);
  const {access} = await login.json();
  const api = async (route, body) => {
    const response = await fetch(new URL(route, L.URL), {
      method:body ? 'POST' : 'GET', headers:{Authorization:`Bearer ${access}`,
        'Content-Type':'application/json', 'Idempotency-Key':crypto.randomUUID()},
      body:body ? JSON.stringify(body) : undefined,
    });
    assert.ok(response.ok, `${route}: ${response.status}`);
    return response.json();
  };
  const me = await api('/api/v1/me/');
  const base = `/api/v1/businesses/${me.memberships[0].business.id}`;
  const store = (await api(`${base}/locations/`)).results.find(l => l.name === 'Main store').id;
  const unit = (await api(`${base}/units/`)).results.find(u => u.symbol === 'шт').id;
  const browser = await L.launch();
  const results = [];
  let active;
  try {
    for (const [width,height] of viewports) {
      console.log(`START ${width}x${height}`);
      const sku = `BROWSER-${width}-${Date.now()}`;
      const product = await api(`${base}/products/`, {sku,
        name:`${sku} Тормозные колодки ÄŇŞ — длинное название запчасти`, unit,
        price_amount:'125.50', price_currency:'TMT', barcodes:[], warranty_months:12});
      await api(`${base}/intakes/`, {location:store,
        lines:[{product:product.id, quantity:'50', unit_cost:'60.25'}]});
      const {ctx,page,problems} = await L.newPage(browser, {width,height});
      active = page;
      page.setDefaultTimeout(15000);
      let failSearch = false;
      await page.route('**/api/v1/businesses/*/products/?**', async route => {
        if (failSearch) await route.fulfill({status:503, contentType:'application/json',
          body:JSON.stringify({error:{code:'server_unavailable',message:'Synthetic failure'}})});
        else await route.continue();
      });
      await L.boot(page);
      await L.clickLabel(page, ru.signInAction || 'Войти', {which:'last', wait:350});
      await L.clickLabel(page, 'Владелец', {wait:1200});
      // The previous viewport saved Turkmen on the user's real profile.
      await L.clickLabel(page, 'RU', {role:'button',wait:500});
      const nav = async label => {
        // Less frequent phone modules live in the drawer.
        if (width < 768 && ![ru.dashboard,ru.products,ru.sales,ru.inventory].includes(label)) {
          await L.clickLabel(page, ru.menu, {role:'button',wait:400});
        }
        await L.clickLabel(page, label, {role:'button',wait:700});
      };
      await nav(ru.sales);
      await L.fill(page, '^Поиск', sku);
      await delay(600);
      assert.match(await L.text(page), /В наличии здесь: 50 шт/);
      const result = page.getByRole('button', {name:new RegExp(sku)});
      await result.first().click();
      await delay(700);
      await L.fill(page, '^Количество$', '2');
      await L.fill(page, '^Цена за единицу', '123,45');
      await L.clickLabel(page, ru.toPayment, {role:'button',wait:700});
      assert.match(await L.text(page), /246,90/);
      const before = (await api(`${base}/sales/`)).count;
      await L.clickLabel(page, ru.completeSale, {role:'button',wait:1100});
      assert.match(await L.text(page), /Продажа S-\d+ оформлена/);
      assert.equal((await api(`${base}/sales/`)).count, before + 1);
      assert.equal((await api(`${base}/products/${product.id}/?location=${store}`)).stock.on_hand, '48.000');
      await page.screenshot({path:path.join(out, `${width}-sale.png`)});
      // A failed read must show an error/retry, then recover with the same search.
      await nav(ru.products);
      failSearch = true;
      await L.fill(page, '^Поиск', sku);
      await delay(800);
      assert.match(await L.text(page), new RegExp(ru.retry));
      failSearch = false;
      await L.clickLabel(page, ru.retry, {role:'button',wait:800});
      assert.match(await L.text(page), /Остаток: 48 шт/);
      for (const label of [ru.inventory,ru.expenses,ru.warranties,ru.reports,ru.administration,ru.dashboard]) {
        await nav(label);
        assert.doesNotMatch(await L.text(page), /RenderFlex|Exception|Internal server error/);
      }
      // Every sale in this fresh fixture is today in the shop. A device on tomorrow's
      // date must not compare today's total to that same day as "yesterday".
      assert.doesNotMatch(await L.text(page), /ко вчера/);
      // Switch language with the real selector and visit primary routes in Turkmen.
      await L.clickLabel(page, 'TM', {role:'button',wait:650});
      for (const label of [tk.products,tk.sales,tk.inventory,tk.dashboard]) {
        await L.clickLabel(page, label, {role:'button',wait:700});
      }
      await page.screenshot({path:path.join(out, `${width}-tk.png`)});
      const documentFits = await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth);
      assert.ok(documentFits, `horizontal document overflow at ${width}`);
      const engineWarnings = problems.filter(p => p ===
        'console.warning: WebGL: non-portable extension enabled: WEBGL_polygon_mode');
      const unexpected = problems.filter(p => !p.includes('503 (Service Unavailable)') && !engineWarnings.includes(p));
      assert.deepEqual(unexpected, [], `browser errors at ${width}`);
      results.push({width,height,browser:browser.version(),language:['ru','tk'],sale:'passed',readRecovery:'passed',modules:'passed',engineWarnings});
      if (engineWarnings.length) console.log(`INFO ${engineWarnings.length} recorded WebKit polygon-mode extension warnings`);
      console.log(`PASS ${width}x${height}: sale, stock, read failure/retry, current modules, Russian/Turkmen`);
      await ctx.close();
    }
    fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify(results,null,2)+'\n');
  } catch (error) {
    if (active && !active.isClosed()) {
      await active.screenshot({path:path.join(out, 'failure.png')});
      fs.writeFileSync(path.join(out, 'failure-text.txt'), await L.text(active));
    }
    throw error;
  } finally {await browser.close();}
})().catch(e => {console.error(e.stack); process.exitCode=1;});
