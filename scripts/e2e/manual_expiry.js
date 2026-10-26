// Synthetic sample shop only. Real browser -> API -> PostgreSQL, without passwords.
const assert = require('node:assert/strict');
const L = require('./lib');
if (process.env.ERP_E2E_DISPOSABLE !== 'true' || !process.env.E2E_WEB_URL) {
  throw Error('Use ERP_E2E_DISPOSABLE=true and E2E_WEB_URL for a disposable local shop.');
}
(async () => {
  const browser = await L.launch();
  try {
    const { page } = await L.newPage(browser, process.env.E2E_PHONE === 'true'
      ? {width:390,height:844} : { width: 820, height: 1000 });
    await L.boot(page);
    await L.clickLabel(page, 'Войти', { which: 'last', wait: 400 });
    await L.clickLabel(page, 'Владелец', { wait: 1300 });
    await L.clickLabel(page, 'Склад');
    await L.clickLabel(page, 'Приёмка сканированием');
    await L.clickLabel(page, 'Добавить вручную', { wait: 800 });
    const name = `Фильтр ÄŇŞ без кода ${Date.now()}`;
    const date = new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10);
    await L.fill(page, '^Название товара$', name);
    await L.fill(page, '^Количество$', '50');
    await L.fill(page, '^Себестоимость', '60,25');
    await L.fill(page, '^Цена продажи', '125,50');
    await L.fill(page, '^Гарантия, месяцев', '12');
    await L.fill(page, '^Срок годности партии', date.split('-').reverse().join('.'));
    await L.clickLabel(page, 'Сохранить', { wait: 1000 });
    await L.clickLabel(page, 'Принять на склад');
    await L.clickLabel(page, 'Подтвердить', { wait: 1200 });
    const login = await fetch(new URL('/api/v1/local-test-login/', L.URL), {
      method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({role:'owner'}),
    });
    assert.equal(login.status, 200);
    const { access } = await login.json();
    const get = async path => {
      const r = await fetch(new URL(path, L.URL), {headers:{Authorization:`Bearer ${access}`}});
      assert.equal(r.status, 200); return r.json();
    };
    const me = await get('/api/v1/me/');
    const base = `/api/v1/businesses/${me.memberships[0].business.id}`;
    const products = await get(`${base}/products/?q=${encodeURIComponent(name)}`);
    assert.equal(products.count, 1);
    const p = products.results[0];
    assert.deepEqual(p.barcodes, []);
    assert.equal(p.warranty_months, 12);
    assert.equal(p.stock.on_hand, '50.000');
    assert.equal(p.expiry.date, date);
    assert.equal(p.expiry.quantity, '50.000');
    assert.equal(p.expiry.status, 'soon');
    await L.clickLabel(page, 'Товары');
    await L.fill(page, '^Поиск', name);
    await page.waitForTimeout(800);
    assert.match(await L.text(page), /Остаток: 50 шт/);
    await L.clickLabel(page, 'Истекают за 30 дней');
    assert.match(await L.text(page), /Остаток: 50 шт/);
    await page.screenshot({path:'/tmp/erp-manual-expiry-tablet.png'});
    await page.setViewportSize({width:390,height:844});
    await page.waitForTimeout(800);
    assert.match(await L.text(page), /Остаток: 50 шт/);
    await page.screenshot({path:'/tmp/erp-manual-expiry-phone.png'});
    assert.equal((await get(`${base}/sales/`)).count, 0);
    console.log('PASS: empty-field role login, name-only product, no barcode, warranty 12, batch expiry, 50 units, tablet/phone catalog and soon filter; no sale.');
  } finally { await browser.close(); }
})().catch(e => { console.error(e.message); process.exitCode = 1; });
