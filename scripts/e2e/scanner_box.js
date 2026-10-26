// Focused real-API smoke test. Run only against a disposable sample shop; see README.
// The browser exercises keyboard/manual input; widget tests exercise the camera callback.
const assert = require('node:assert/strict');
const L = require('./lib.js');
const API = process.env.E2E_WEB_URL;
const password = process.env.ERP_SAMPLE_PASSWORD;
const barcode = process.env.E2E_BARCODE || 'BOX-SMOKE-50';
if (!API || !password || process.env.ERP_E2E_DISPOSABLE !== 'true') {
  throw new Error('Set E2E_WEB_URL, ERP_SAMPLE_PASSWORD and ERP_E2E_DISPOSABLE=true for a disposable sample shop.');
}
(async () => {
  const browser = await L.launch();
  let activePage;
  try {
    const { page } = await L.newPage(browser);
    activePage = page;
    await L.boot(page);
    await L.fill(page, '^Логин$', 'owner');
    await L.fill(page, '^Пароль$', password);
    await L.clickLabel(page, 'Войти', { which: 'last', wait: 1800 });
    await L.clickLabel(page, 'Склад');
    await L.clickLabel(page, 'Приёмка сканированием');
    await L.fill(page, '^Код товара$', barcode);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(1200);
    if (process.env.E2E_EXPECT_PREFILL === 'true') {
      // Flutter synchronizes a semantics input's DOM value when it gains focus.
      const fieldValue = async label => {
        const selector = `input[aria-label="${label}"]`;
        for (let i = 0; i < 12; i++) {
          const box = await page.locator(selector).boundingBox();
          assert.ok(box);
          if (box.y > 60 && box.y + box.height < page.viewportSize().height - 40) {
            await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
            await page.waitForTimeout(450);
            return page.evaluate(() => document.activeElement.value);
          }
          await page.mouse.move(page.viewportSize().width / 2, page.viewportSize().height / 2);
          await page.mouse.wheel(0, box.y < 60 ? -350 : 350);
          await page.waitForTimeout(500);
        }
        throw new Error(`could not focus ${label}`);
      };
      assert.equal(await fieldValue('Название товара'), 'Parts maker Brake pad 1 pc');
      assert.equal(await fieldValue('Бренд'), 'Parts maker');
      assert.equal(await fieldValue('Категория'), 'Brake pads');
      assert.equal(await fieldValue('Цена продажи, TMT (необязательно)'), '');
      assert.equal(await fieldValue('Себестоимость за единицу, TMT (необязательно)'), '');
      await page.screenshot({path: '/tmp/erp-receiving-form.png'});
    }
    await L.fill(page, '^Количество$', '50');
    await L.fill(page, '^Себестоимость', '60,25');
    await L.fill(page, '^Бренд$', 'Parts maker');
    await L.fill(page, '^Категория$', 'Brake pads');
    await L.fill(page, '^Название товара$', 'Подшипник ÄŇŞ smoke');
    await L.fill(page, '^Цена продажи, TMT', '125,50');
    await L.clickLabel(page, 'Сохранить', { wait: 1500 });
    await L.clickLabel(page, 'Принять на склад');
    await L.clickLabel(page, 'Подтвердить', { wait: 1800 });
    await L.clickLabel(page, 'Продажи');
    await L.fill(page, 'Поиск', barcode);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(1000);
    assert.match(await L.text(page), /Подшипник ÄŇŞ smoke/);
    assert.match(await L.text(page), /Корзина пуста/);
    const login = await fetch(new URL('/api/v1/auth/login/', API), {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({username: 'owner', password}),
    });
    assert.equal(login.status, 200);
    const { access } = await login.json();
    const get = async path => {
      const response = await fetch(new URL(path, API), {headers: {Authorization: `Bearer ${access}`}});
      assert.equal(response.status, 200);
      return response.json();
    };
    const me = await get('/api/v1/me/');
    const business = me.memberships[0].business.id;
    const base = `/api/v1/businesses/${business}`;
    const product = await get(`${base}/barcodes/lookup/?code=${encodeURIComponent(barcode)}`);
    assert.equal(product.name, 'Подшипник ÄŇŞ smoke');
    assert.equal(product.price.amount, '125.50');
    assert.equal(product.brand.name, 'Parts maker');
    assert.equal(product.category.name, 'Brake pads');
    const stock = await get(`${base}/stock/?product=${product.id}`);
    assert.equal(stock.results.find(row => row.product.id === product.id).quantity, '50.000');
    const movements = await get(`${base}/stock/movements/?product=${product.id}`);
    assert.equal(movements.results.find(row => row.product.id === product.id).unit_cost, '60.25');
    const sales = await get(`${base}/sales/`);
    assert.equal(sales.count, 0);
    console.log('PASS: real browser/API/PostgreSQL: barcode, name, brand, category, manual prices, 50 received; sales search creates no sale.');
  } catch (error) {
    if (activePage) {
      await activePage.screenshot({path:'/tmp/erp-receiving-form-error.png'});
      console.error((await L.text(activePage)).slice(0, 6000));
    }
    throw error;
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
