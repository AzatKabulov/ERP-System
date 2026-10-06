// End to end against the REAL stack: Flutter web build -> Django API -> PostgreSQL.
// Prerequisites and how to run: README.md in this folder. Needs a freshly reset sample
// business (reset_db.sh). Screenshots go to $E2E_OUT (default /tmp/erp-e2e).
const L = require('./lib.js');
const { check, expectText, expectNoText, clickLabel, fill, boot, text } = L;
const PASS = 'E2e-Sample-Passw0rd!';

const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const OUT = process.env.E2E_OUT || '/tmp/erp-e2e';
fs.mkdirSync(OUT, { recursive: true });
const BACKEND = path.resolve(__dirname, '../../backend');
function dbFacts() {
  const py = `
import json
from apps.purchasing.models import Delivery
from apps.inventory.models import StockBalance
from apps.inventory import services
from apps.purchasing import services as ps
d = services.reconcile() + ps.reconcile()
print('FACTS' + json.dumps({'deliveries': Delivery.objects.count(), 'balances': [{'q': str(b.quantity), 'c': b.condition} for b in StockBalance.objects.all()], 'reconcile': 'consistent' if not d else d}))
`;
  const out = execSync('cd ' + BACKEND + ' && export PATH="$HOME/.local/bin:$PATH" && uv run python manage.py shell', { input: py, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
  return JSON.parse(out.split('FACTS')[1]);
}


async function signIn(page, user) {
  await fill(page, '^Логин$', user);
  await fill(page, '^Пароль$', PASS);
  await clickLabel(page, 'Войти', { which: 'last', wait: 2500 });
}
async function nav(page, label) { await clickLabel(page, label, { wait: 1800 }); }
async function pickFromDropdown(page, fieldRegex, optionLabel) {
  // open the dropdown by clicking the field's semantics node, then choose the option
  await clickLabel(page, fieldRegex, { exact: false, wait: 700 });
  await clickLabel(page, optionLabel, { exact: false, wait: 700 });
}

let PAGE = null;
(async () => {
  const browser = await L.launch();
  const { page, problems } = await L.newPage(browser);
  PAGE = page;
  await boot(page);
  await expectText(page, 'a real build starts at sign-in and shows no demo data', /Войдите в рабочее пространство/);
  await expectNoText(page, 'no demonstration banner in the real build', /Демонстрационные данные/);

  // ---- owner signs in --------------------------------------------------------------
  await signIn(page, 'owner');
  await expectText(page, 'owner is signed in (welcome page)', /Здравствуйте, Sample/);
  await page.screenshot({ path: path.join(OUT, 'e2e-1-welcome.png') });

  // ---- exchange rate ---------------------------------------------------------------
  await nav(page, 'Настройки');
  await expectText(page, 'administration shows the exchange-rate section', /Курс ещё не задан/);
  await fill(page, 'Новый курс', '3,5');
  await clickLabel(page, 'Установить курс', { wait: 1500 });
  await expectText(page, 'the rate is saved and shown', /Текущий курс: 1 USD = 3,50 TMT/);

  // ---- catalog: a TMT product and a USD product -------------------------------------
  await nav(page, 'Товары');
  await expectText(page, 'empty catalog', /Товаров пока нет/);
  await clickLabel(page, 'Добавить товар', { wait: 1500 });
  await fill(page, 'Артикул \\(SKU\\)', 'BP-100');
  await fill(page, 'Название товара', 'Тормозные колодки');
  await pickFromDropdown(page, 'Единица измерения', 'Штука');
  await fill(page, '^Цена продажи', '120');
  await fill(page, 'Закупочная цена по умолчанию', '70');
  await page.screenshot({ path: path.join(OUT, 'e2e-2-product-form.png') });
  await clickLabel(page, 'Сохранить', { wait: 2000 });
  await expectText(page, 'product saved and listed with its TMT price', /BP-100/);
  await expectText(page, 'the TMT price is shown', /120,00/);

  await clickLabel(page, 'Добавить товар', { wait: 1500 });
  await fill(page, 'Артикул \\(SKU\\)', 'FLT-USD');
  await fill(page, 'Название товара', 'Масляный фильтр (импорт)');
  await pickFromDropdown(page, 'Единица измерения', 'Штука');
  await clickLabel(page, 'USD', { wait: 600 });
  await fill(page, '^Цена продажи', '10');
  await expectText(page, 'USD price previews the TMT value at the current rate', /≈ 35,00/);
  await clickLabel(page, 'Сохранить', { wait: 2000 });
  await expectText(page, 'USD product listed with TMT equivalent', /≈ 35,00/);

  // ---- supplier ----------------------------------------------------------------------
  await nav(page, 'Закупки');
  await expectText(page, 'no orders yet', /Заказов пока нет/);
  await clickLabel(page, 'Поставщики', { wait: 1500 });
  await clickLabel(page, 'Добавить поставщика', { role: 'button', wait: 1200 });
  await fill(page, 'Название поставщика', 'Ашхабад Запчасти');
  await clickLabel(page, 'Сохранить', { wait: 1800 });
  await expectText(page, 'supplier saved', /Ашхабад Запчасти/);
  await page.screenshot({ path: path.join(OUT, 'e2e-3-suppliers.png') });


  // ---- purchase order: create, submit -----------------------------------------------
  await clickLabel(page, 'Назад', { role: 'button', wait: 1500 });
  await clickLabel(page, 'Новый заказ поставщику', { role: 'button', wait: 1800 });
  await pickFromDropdown(page, '^Поставщик', 'Ашхабад Запчасти');
  await pickFromDropdown(page, 'Принять в точку', 'Warehouse');
  await clickLabel(page, 'Добавить товар', { role: 'button', wait: 1500 });
  await clickLabel(page, 'Тормозные колодки', { exact: false, wait: 1000 });
  await fill(page, '^Количество', '10');
  await fill(page, 'Себестоимость за единицу', '50');
  await page.screenshot({ path: path.join(OUT, 'e2e-4-order-form.png') });
  await clickLabel(page, 'Сохранить', { role: 'button', wait: 2500 });
  await expectText(page, 'the order is saved as draft PO-0001', /PO-0001/);
  await expectText(page, 'it is a draft', /Черновик/);
  await expectText(page, 'total is computed from the lines', /Итого: 500,00/);
  await clickLabel(page, 'Оформить заказ', { role: 'button', wait: 900 });
  await clickLabel(page, 'Подтвердить', { role: 'button', wait: 2000 });
  await expectText(page, 'order is submitted', /Оформлен/);
  let facts = dbFacts();
  check('submitting an order does not move stock', facts.balances.length === 0, JSON.stringify(facts.balances));

  // ---- receiving: partial, then lost answer, then restart -----------------------------
  await clickLabel(page, 'Принять товар', { role: 'button', wait: 1500 });
  await fill(page, 'Принять сейчас', '4');
  await clickLabel(page, 'Принять товар', { role: 'button', which: 'last', wait: 2500 });
  await expectText(page, 'a partial delivery is accepted', /Принят частично/);
  await expectText(page, 'progress shows 4 of 10', /принято 4 шт/);
  facts = dbFacts();
  check('stock rose by 4 at the warehouse', facts.balances.length === 1 && facts.balances[0].q === '4.000', JSON.stringify(facts.balances));
  check('one delivery recorded', facts.deliveries === 1);

  await page.route('**/deliveries/', async (route) => {
    if (route.request().method() !== 'POST') return route.continue();
    await route.fetch(); // the server really performs it ...
    await route.abort('failed'); // ... but the answer never reaches the app
  });
  await clickLabel(page, 'Принять товар', { role: 'button', wait: 1500 });
  await fill(page, 'Принять сейчас', '6');
  await clickLabel(page, 'Принять товар', { role: 'button', which: 'last', wait: 3500 });
  await expectText(page, 'the app says the outcome is unknown', /Ответ сервера не получен/);
  await expectText(page, 'the unconfirmed action is listed', /Ожидают подтверждения: 1/);
  facts = dbFacts();
  check('the server did commit the second delivery', facts.deliveries === 2 && facts.balances[0].q === '10.000', JSON.stringify(facts));
  await page.screenshot({ path: path.join(OUT, 'e2e-5-unknown.png') });
  await page.unroute('**/deliveries/');

  // "restart the tablet": reload the page; the saved key is checked against the server
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await page.waitForTimeout(4500);
  await L.enableSemantics(page);
  await expectText(page, 'still signed in after the restart', /Склад|Закупки/);
  await page.waitForTimeout(2000);
  const afterRestart = await text(page);
  check('the confirmed operation left the pending list by itself', !/Ожидают подтверждения/.test(afterRestart));
  facts = dbFacts();
  check('exactly two deliveries exist after the restart (no duplicate)', facts.deliveries === 2, JSON.stringify(facts));
  check('stock is exactly 10', facts.balances[0].q === '10.000');
  check('reconcile finds no difference', facts.reconcile === 'consistent', facts.reconcile);
  await nav(page, 'Закупки');
  await expectText(page, 'order list shows it fully received', /Принят полностью/);

  // ---- stock page and history ---------------------------------------------------------
  await nav(page, 'Склад');
  await expectText(page, 'stock shows 10 pieces', /10 шт/);
  await expectText(page, 'stock value is 10 x 50 = 500,00', /Стоимость: 500,00/);
  await clickLabel(page, 'История движений', { role: 'button', wait: 1800 });
  await expectText(page, 'history shows both receipts', /Поступление по заказу/);
  await expectText(page, 'history shows the quantities', /\+6 шт/);
  await page.screenshot({ path: path.join(OUT, 'e2e-6-history.png') });
  await clickLabel(page, 'Назад', { role: 'button', wait: 1200 });

  // ---- Turkmen, and it survives a reload ----------------------------------------------
  await clickLabel(page, 'Язык интерфейса', { exact: false, wait: 800 });
  await clickLabel(page, 'Türkmençe', { exact: false, wait: 1800 });
  await expectText(page, 'the interface switches to Turkmen', /Harytlar/);
  await expectText(page, 'stock page labels are Turkmen', /Hereketleriň taryhy/);
  await page.screenshot({ path: path.join(OUT, 'e2e-7-turkmen.png') });
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await page.waitForTimeout(4500);
  await L.enableSemantics(page);
  await expectText(page, 'after a reload the user is still signed in, in Turkmen', /Harytlar/);

  // ---- warehouse user sees no costs -----------------------------------------------------
  await clickLabel(page, 'Çykmak', { role: 'button', wait: 2000 });
  await expectText(page, 'signed out: the sign-in page', /Girmek/);
  await page.close();
  const w = await L.newPage(browser);
  await boot(w.page);
  await signIn(w.page, 'warehouse');
  await expectText(w.page, 'warehouse user is signed in', /Sample warehouse|Здравствуйте/);
  await nav(w.page, 'Закупки');
  await clickLabel(w.page, 'PO-0001', { exact: false, wait: 1800 });
  await expectText(w.page, 'warehouse sees the order quantities', /принято 10 шт/);
  const warehouseText = await text(w.page);
  check('warehouse sees no money on the order', !/TMT/.test(warehouseText), (warehouseText.match(/.{20}TMT.{10}/) || [''])[0]);
  await clickLabel(w.page, 'Назад', { role: 'button', wait: 1200 });
  await nav(w.page, 'Склад');
  await expectText(w.page, 'warehouse sees stock', /10 шт/);
  const stockText = await text(w.page);
  check('warehouse sees no stock value', !/Стоимость/.test(stockText) && !/TMT/.test(stockText));
  await w.page.screenshot({ path: path.join(OUT, 'e2e-8-warehouse.png') });
  problems.push(...w.problems);

  console.log('--- run finished; browser problems seen:', problems.length);
  const expectedAbort = /ERR_FAILED/; // the deliberately dropped answer in the lost-response step
  const unexpected = problems.filter((p) => !expectedAbort.test(p));
  check('no unexpected browser errors', unexpected.length === 0, unexpected.join(' | '));
  console.log(problems.join('\n'));
  const failed = L.results.filter((r) => !r.ok);
  console.log(`\n${L.results.length - failed.length}/${L.results.length} checks passed`);
  await browser.close();
  process.exit(failed.length ? 1 : 0);
})().catch(async (e) => {
  console.error('SCRIPT ERROR', e.message);
  if (PAGE) {
    await PAGE.screenshot({ path: path.join(OUT, 'e2e-error.png') }).catch(() => {});
    const dump = await PAGE.evaluate(() => [...document.querySelectorAll('input, textarea, flt-semantics')].map(n => `${n.tagName}|${n.getAttribute('role')||''}|${(n.getAttribute('aria-label')||n.textContent||'').slice(0,60).replace(/\n/g,' ')}`)).catch(() => []);
    console.error(dump.slice(0, 60).join('\n'));
  }
  process.exit(2);
});
