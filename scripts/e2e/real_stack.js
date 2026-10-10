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
from apps.purchasing.models import Delivery, PurchaseOrder, SupplierReturn
from apps.inventory.models import StockBalance
from apps.inventory import services
from apps.purchasing import services as ps
from apps.sales import services as ss
from apps.sales.models import Sale, SaleReturn
from apps.stockops import services as xs
from apps.stockops.models import StockCount, Transfer
from apps.warranties import services as ws
from apps.warranties.models import WarrantyClaim
from apps.expenses.models import Expense
from apps.catalog.models import Product
from apps.businesses.models import Business
d = services.reconcile() + ps.reconcile() + ss.reconcile() + xs.reconcile() + ws.reconcile()
sales = [{'id': str(x.pk), 'number': x.number, 'total': str(x.total), 'method': x.payment_method, 'prices': [str(l.unit_price) for l in x.lines.all()], 'cost': str(sum(l.cost_total for l in x.lines.all()))} for x in Sale.objects.order_by('created_at')]
returns = [{'n': r.number, 'sale': r.sale.number, 'refund': str(r.refund_total), 'method': r.payment_method, 'claim': r.warranty_claim_id is not None, 'cost': str(sum(l.cost_total for l in r.lines.all())), 'lines': [{'q': str(l.quantity), 'c': l.condition, 'refund': str(l.refund_amount)} for l in r.lines.all()]} for r in SaleReturn.objects.order_by('number')]
supplier_returns = [{'n': r.number, 'credit': str(r.credit_total), 'lines': [{'q': str(l.quantity), 'c': l.condition} for l in r.lines.all()]} for r in SupplierReturn.objects.order_by('number')]
orders = [{'n': o.number, 'status': o.status, 'lines': [str(l.quantity) for l in o.lines.all()]} for o in PurchaseOrder.objects.order_by('number')]
expenses = [{'amount': str(e.amount), 'category': e.category.name, 'voided': e.voided_at is not None, 'file': e.attachment_id is not None, 'file_id': str(e.attachment_id), 'place': e.location.name} for e in Expense.objects.order_by('created_at')]
claims = [{'n': c.number, 'status': c.status, 'outcome': c.outcome, 'out': c.out_of_warranty, 'q': str(c.quantity), 'events': c.events.count()} for c in WarrantyClaim.objects.order_by('number')]
print('FACTS' + json.dumps({'business': str(Business.objects.first().pk), 'deliveries': Delivery.objects.count(), 'sales': sales, 'balances': [{'q': str(b.quantity), 'c': b.condition, 'at': b.location.name, 'sku': b.product.sku} for b in StockBalance.objects.select_related('location', 'product').all()], 'transfers': [{'n': t.number, 'status': t.status} for t in Transfer.objects.order_by('number')], 'counts': [{'n': c.number, 'status': c.status} for c in StockCount.objects.order_by('number')], 'returns': returns, 'supplier_returns': supplier_returns, 'orders': orders, 'expenses': expenses, 'claims': claims, 'products': [p.sku for p in Product.objects.order_by('sku')], 'product_names': {p.sku: p.name for p in Product.objects.all()}, 'reconcile': 'consistent' if not d else d}))
`;
  const out = execSync('cd ' + BACKEND + ' && export PATH="$HOME/.local/bin:$PATH" && uv run python manage.py shell', { input: py, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
  return JSON.parse(out.split('FACTS')[1]);
}


// Quantity of the product at a place in a condition, from the database facts.
function stockAt(facts, place, condition = 'sellable', sku = 'BP-100') {
  const row = facts.balances.find((b) => b.at === place && b.c === condition && b.sku === sku);
  return row ? row.q : '0.000';
}

const API = process.env.E2E_API_URL || 'http://127.0.0.1:8000';
// Fetches a document straight from the API (a real HTTP request) and returns its type and its text,
// extracted with pypdf from the PDF the server produced.
async function documentText(businessId, saleId, query) {
  const login = await (await fetch(API + '/api/v1/auth/login/', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'owner', password: PASS }),
  })).json();
  const res = await fetch(`${API}/api/v1/businesses/${businessId}/sales/${saleId}/document/?${query}`, {
    headers: { Authorization: 'Bearer ' + login.access, Accept: 'application/pdf' },
  });
  const bytes = Buffer.from(await res.arrayBuffer());
  const file = path.join(OUT, 'document.pdf');
  fs.writeFileSync(file, bytes);
  const out = execSync('cd ' + BACKEND + ' && export PATH="$HOME/.local/bin:$PATH" && uv run python ' + path.join(__dirname, 'pdf_text.py') + ' ' + file, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
  return { status: res.status, type: res.headers.get('content-type'), text: out.split('TEXT')[1] || '' };
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

  // Development aid: E2E_RESUME=phase78 (or phase9) skips the earlier phases and continues from a database snapshot taken with
  // E2E_STOP_AFTER=phase6 (or phase78) (see README.md); the owner still signs in above.
  let facts;
  if (!process.env.E2E_RESUME) {
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
  await fill(page, 'Гарантия, месяцев', '12'); // the warranty claim in Phase 8 needs one
  await fill(page, 'Срок возврата, дней', '30'); // the return window of Phase 7: 30 days from the sale
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
  facts = dbFacts();
  check('submitting an order does not move stock', facts.balances.length === 0, JSON.stringify(facts.balances));

  // ---- receiving: partial, then lost answer, then restart -----------------------------
  await clickLabel(page, 'Принять товар', { role: 'button', wait: 1500 });
  await fill(page, 'Принять сейчас', '4');
  await clickLabel(page, 'Принять товар', { role: 'button', which: 'last', wait: 2500 });
  await expectText(page, 'a partial delivery is accepted', /Принят частично/);
  await expectText(page, 'progress shows 4 of 10', /принято 4 шт/);
  facts = dbFacts();
  check('stock rose by 4 at the warehouse', stockAt(facts, 'Warehouse') === '4.000', JSON.stringify(facts.balances));
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
  check('the server did commit the second delivery', facts.deliveries === 2 && stockAt(facts, 'Warehouse') === '10.000', JSON.stringify(facts));
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
  check('stock is exactly 10', stockAt(facts, 'Warehouse') === '10.000');
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

  // ---- selling (Phase 5): from the Warehouse, where the 10 pieces are ---------------------
  await nav(page, 'Продажи');
  await clickLabel(page, '^Местоположение', { exact: false, role: 'button', wait: 900 });
  await clickLabel(page, 'Warehouse', { exact: false, wait: 1500 });
  await expectNoText(page, 'the real sales page shows no demonstration sale', /Завершить демо-продажу/);
  await fill(page, 'Название, артикул или штрихкод', 'колодки');
  await page.waitForTimeout(1500);
  await clickLabel(page, 'BP-100', { exact: false, wait: 1500 });
  await expectText(page, 'the product is in the cart with its availability', /В наличии здесь: 10 шт/);
  await expectText(page, 'the price box starts with the catalog price', /В каталоге: 120,00/);
  await fill(page, '^Количество', '3');
  await fill(page, 'Цена за единицу, TMT', '100'); // prices are not fixed: the seller charges 100, not 120
  await expectText(page, 'total = 3 x 100 = 300,00', /Итого: 300,00/);
  await page.screenshot({ path: path.join(OUT, 'e2e-9-cart.png') });
  await clickLabel(page, 'К оплате', { role: 'button', wait: 1500 });
  await expectText(page, 'the last step opens and offers cash and card', /Оплата/);
  await expectNoText(page, 'no change to work out, no amounts to type', /Сдача|Осталось оплатить|Сумма, TMT/);
  await page.screenshot({ path: path.join(OUT, 'e2e-10-payment.png') });
  await clickLabel(page, 'Завершить продажу', { role: 'button', wait: 2500 });
  await expectText(page, 'the sale is confirmed with its number', /Продажа S-000001 оформлена/);
  await page.screenshot({ path: path.join(OUT, 'e2e-11-sale-done.png') });
  facts = dbFacts();
  check('one sale at the seller price, paid in cash, with the FIFO cost', facts.sales.length === 1 && facts.sales[0].total === '300.00' && facts.sales[0].method === 'cash' && facts.sales[0].prices[0] === '100.00' && parseFloat(facts.sales[0].cost) === 150, JSON.stringify(facts.sales));
  check('stock fell from 10 to 7', stockAt(facts, 'Warehouse') === '7.000', JSON.stringify(facts.balances));
  check('reconcile is consistent after the sale', facts.reconcile === 'consistent', facts.reconcile);

  // the receipt button asks the server for the PDF
  const receiptReply = page.waitForResponse((r) => /\/document\//.test(r.url()), { timeout: 15000 }).catch(() => null);
  await clickLabel(page, 'Чек · Печать', { role: 'button', wait: 1500 });
  const reply = await receiptReply;
  check('the Receipt button downloads a PDF from the server', !!reply && reply.status() === 200 && /application\/pdf/.test(reply.headers()['content-type'] || ''), reply ? String(reply.status()) : 'no request seen');

  // a sale whose answer is lost after the server committed, then a "restart"
  await clickLabel(page, 'Новая продажа', { exact: false, role: 'button', wait: 1200 });
  await fill(page, 'Название, артикул или штрихкод', 'колодки');
  await page.waitForTimeout(1500);
  await clickLabel(page, 'BP-100', { exact: false, wait: 1500 });
  await fill(page, '^Количество', '2');
  await clickLabel(page, 'К оплате', { role: 'button', wait: 1500 });
  await clickLabel(page, 'Карта', { role: 'checkbox', wait: 600 }); // this customer paid by card
  await page.route('**/sales/', async (route) => {
    if (route.request().method() !== 'POST') return route.continue();
    await route.fetch(); // the server really sells ...
    await route.abort('failed'); // ... but the answer never reaches the tablet
  });
  await clickLabel(page, 'Завершить продажу', { role: 'button', wait: 3500 });
  await expectText(page, 'the app does not claim the sale: outcome unknown', /Ответ сервера не получен/);
  await expectText(page, 'the unconfirmed sale is listed', /Ожидают подтверждения: 1/);
  facts = dbFacts();
  check('the server did record the second sale (card, catalog price 120)', facts.sales.length === 2 && stockAt(facts, 'Warehouse') === '5.000' && facts.sales[1].method === 'card' && facts.sales[1].total === '240.00', JSON.stringify(facts.sales));
  await page.unroute('**/sales/');
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await page.waitForTimeout(4500);
  await L.enableSemantics(page);
  await page.waitForTimeout(2500);
  const afterSaleRestart = await text(page);
  check('the confirmed sale left the pending list by itself', !/Ожидают подтверждения/.test(afterSaleRestart));
  facts = dbFacts();
  check('exactly two sales exist after the restart (no duplicate)', facts.sales.length === 2 && facts.sales[1].number !== facts.sales[0].number, JSON.stringify(facts.sales));
  check('stock is exactly 5 (10 - 3 - 2)', stockAt(facts, 'Warehouse') === '5.000', JSON.stringify(facts.balances));
  check('receipt numbers run without a gap', facts.sales.map((x) => x.number).join() === '1,2', facts.sales.map((x) => x.number).join());
  check('reconcile finds no difference after the restart', facts.reconcile === 'consistent', facts.reconcile);
  await nav(page, 'Продажи');
  await clickLabel(page, 'История продаж', { role: 'button', wait: 1800 });
  await expectText(page, 'the history lists both sales', /S-000002/);
  await expectText(page, 'and the first one', /S-000001/);
  await page.screenshot({ path: path.join(OUT, 'e2e-12-sales-history.png') });
  await clickLabel(page, 'Назад', { role: 'button', wait: 1200 });

  // the receipt: a real PDF from the real API, text read back with pypdf
  const ru = await documentText(facts.business, facts.sales[0].id, 'lang=ru');
  check('the receipt is a PDF', ru.status === 200 && /application\/pdf/.test(ru.type || ''), ru.type);
  check('the Russian receipt names the product and the number', /Тормозные колодки/.test(ru.text) && /S-000001/.test(ru.text), ru.text.slice(0, 200));
  check('it shows the price charged (100,00 not 120,00), the total and how it was paid', /100,00/.test(ru.text) && /300,00/.test(ru.text) && /Наличные/.test(ru.text) && !/120,00/.test(ru.text), ru.text.slice(0, 300));
  check('no cost, profit, change, discount or invoice wording on a receipt', !/Себестоимость|Прибыль|150,00|Сдача|Скидка|Накладная/.test(ru.text));
  const tk = await documentText(facts.business, facts.sales[1].id, 'lang=tk');
  check('the Turkmen receipt uses Turkmen labels and says card', /Çek/.test(tk.text) && /Jemi/.test(tk.text) && /Kart/.test(tk.text), tk.text.slice(0, 200));

  // ---- Phase 6: a transfer (short on arrival, answer lost) and a stock count --------------------
  await nav(page, 'Склад');
  await clickLabel(page, 'Перемещения', { role: 'button', wait: 1800 });
  await expectText(page, 'no transfers yet', /Перемещений пока нет/);
  await clickLabel(page, 'Новое перемещение', { role: 'button', wait: 1500 });
  await pickFromDropdown(page, '^Откуда', 'Warehouse');
  await pickFromDropdown(page, '^Куда', 'Main store');
  await clickLabel(page, 'Добавить товар', { role: 'button', wait: 1500 });
  await clickLabel(page, 'Тормозные колодки', { exact: false, role: 'button', wait: 1000 });
  await page.mouse.move(700, 850); // an idle page draws no frame: until the pointer moves, the accessibility tree still shows the form without the new line
  await page.waitForTimeout(500);
  await fill(page, '^Количество', '2');
  await page.screenshot({ path: path.join(OUT, 'e2e-13-transfer-form.png') });
  await clickLabel(page, 'Отправить', { role: 'button', wait: 2500 });
  await expectText(page, 'the transfer is listed as in transit', /T-0001/);
  await expectText(page, 'with its status', /В пути/);
  facts = dbFacts();
  check('goods left the warehouse and wait in transit at the shop', stockAt(facts, 'Warehouse') === '3.000' && stockAt(facts, 'Main store', 'in_transit') === '2.000' && stockAt(facts, 'Main store') === '0.000', JSON.stringify(facts.balances));
  check('one transfer exists and the ledger agrees', facts.transfers.length === 1 && facts.transfers[0].status === 'dispatched' && facts.reconcile === 'consistent', JSON.stringify(facts.transfers) + facts.reconcile);

  // the shop receives only 1 of 2, and the answer is lost after the server committed
  await clickLabel(page, 'T-0001', { exact: false, wait: 1800 });
  await expectText(page, 'goods in transit say they cannot be sold yet', /пока не доступен для продажи/);
  await clickLabel(page, 'Принять', { role: 'button', wait: 1500 });
  await fill(page, '^Пришло', '1');
  await fill(page, 'Причина недостачи', 'Коробка повреждена');
  await page.route('**/receive/', async (route) => {
    if (route.request().method() !== 'POST') return route.continue();
    await route.fetch(); // the server really receives it ...
    await route.abort('failed'); // ... but the answer never reaches the tablet
  });
  await clickLabel(page, 'Принять', { role: 'button', which: 'last', wait: 3500 });
  await expectText(page, 'the app says the outcome is unknown', /Ответ сервера не получен/);
  await expectText(page, 'the unconfirmed receipt is listed', /Ожидают подтверждения: 1/);
  facts = dbFacts();
  check('the server did record the short receipt', facts.transfers[0].status === 'partially_received' && stockAt(facts, 'Main store') === '1.000' && stockAt(facts, 'Main store', 'in_transit') === '0.000', JSON.stringify(facts.transfers) + JSON.stringify(facts.balances));
  await page.unroute('**/receive/');
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await page.waitForTimeout(4500);
  await L.enableSemantics(page);
  await page.waitForTimeout(2500);
  check('the confirmed receipt left the pending list by itself', !/Ожидают подтверждения/.test(await text(page)));
  facts = dbFacts();
  check('still exactly one transfer, one piece at the shop, one written off, ledger consistent', facts.transfers.length === 1 && stockAt(facts, 'Main store') === '1.000' && facts.reconcile === 'consistent', JSON.stringify(facts.balances) + facts.reconcile);

  // a count at the warehouse: 3 in the system, 2 on the shelf
  await nav(page, 'Склад');
  await clickLabel(page, 'Инвентаризация', { role: 'button', wait: 1800 });
  await clickLabel(page, 'Начать инвентаризацию', { role: 'button', wait: 1500 });
  await pickFromDropdown(page, '^Точка', 'Warehouse');
  await clickLabel(page, 'Начать инвентаризацию', { role: 'button', which: 'last', wait: 2500 });
  await expectText(page, 'the count opens with what the system shows', /В системе: 3 шт/);
  await fill(page, '^Посчитано', '2');
  await expectText(page, 'the difference shows at once', /Разница: −1 шт/);
  await page.screenshot({ path: path.join(OUT, 'e2e-14-count.png') });
  await clickLabel(page, 'Отправить на утверждение', { role: 'button', wait: 2500 });
  await expectText(page, 'the count waits for approval', /Ждёт утверждения/);
  await fill(page, 'Объяснение расхождений', 'Одна коробка оказалась пустой');
  await clickLabel(page, 'Утвердить', { role: 'button', wait: 2500 });
  await expectText(page, 'the count is approved', /Утверждена/);
  facts = dbFacts();
  check('the warehouse now holds what was counted and the ledger agrees', stockAt(facts, 'Warehouse') === '2.000' && facts.counts.length === 1 && facts.counts[0].status === 'approved' && facts.reconcile === 'consistent', JSON.stringify(facts.balances) + JSON.stringify(facts.counts));
  await clickLabel(page, 'Назад', { role: 'button', wait: 1200 });
  await clickLabel(page, 'Назад', { role: 'button', wait: 1200 });
  await nav(page, 'Продажи'); // the Turkmen check below looks at the sales page

  } // end of Phases 1-6 (skipped when resuming)

  // ---- Phases 7 and 8: returns, reorder, expenses, warranty, CSV (phase78.js) ----------------------
  if (process.env.E2E_STOP_AFTER === 'phase6') { // development aid: stop here to take a database snapshot
    console.log('stopping after Phase 6 (E2E_STOP_AFTER)');
    await browser.close();
    process.exit(0);
  }
  const shared = { L, dbFacts, stockAt, nav, pickFromDropdown, OUT, PASS, API, BACKEND };
  if (process.env.E2E_RESUME !== 'phase9') await require('./phase78.js')(page, shared);
  if (process.env.E2E_STOP_AFTER === 'phase78') { // development aid: stop here to take a database snapshot
    console.log('stopping after Phases 7-8 (E2E_STOP_AFTER)');
    await browser.close();
    process.exit(0);
  }
  await require('./phase9.js')(page, shared); // Phase 9: the dashboard, the reports and the activity history
  await nav(page, 'Продажи'); // the Turkmen check below looks at the sales page

  // ---- Turkmen, and it survives a reload ----------------------------------------------
  await clickLabel(page, 'Язык интерфейса', { exact: false, wait: 800 });
  await clickLabel(page, 'Türkmençe', { exact: false, wait: 1800 });
  await expectText(page, 'the interface switches to Turkmen', /Harytlar/);
  await expectText(page, 'the sales page is in Turkmen too (cart title)', /Sebet/);
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
  await clickLabel(w.page, 'Возвраты поставщикам', { role: 'button', wait: 1800 });
  await expectText(w.page, 'warehouse sees the supplier return it may make', /SR-0001/);
  check('and no credit amount on it', !/Зачёт|TMT/.test(await text(w.page)));
  await clickLabel(w.page, 'Назад', { role: 'button', wait: 1200 });
  await nav(w.page, 'Склад');
  await expectText(w.page, 'warehouse sees stock (3 sellable after the returns and the warranty swap)', /3 шт/);
  const stockText = await text(w.page);
  check('warehouse sees no stock value', !/Стоимость/.test(stockText) && !/TMT/.test(stockText));
  check('the warehouse role has no Sales page and no Customers', !/Продажи/.test(await text(w.page)));
  await w.page.screenshot({ path: path.join(OUT, 'e2e-8-warehouse.png') });
  await nav(w.page, 'Обзор');
  await expectText(w.page, 'the warehouse dashboard shows what is below the minimum and the open orders', /Ниже минимума[\s\S]*Открытые заказы/);
  const keeperDash = await text(w.page);
  check('the warehouse dashboard has no money, no sales and no Reports page', !/TMT/.test(keeperDash) && !/Продажи сегодня/.test(keeperDash) && !/Отчёты/.test(keeperDash), keeperDash.slice(0, 200));
  problems.push(...w.problems);
  await w.page.close();

  // a manager sees the same reports as the owner; a seller sees sales only (no costs, no reports)
  const mg = await L.newPage(browser);
  await boot(mg.page);
  await signIn(mg.page, 'manager');
  await expectText(mg.page, 'the manager dashboard shows the gross profit', /Валовая прибыль за месяц[\s\S]*70,00\s?TMT/);
  await nav(mg.page, 'Отчёты');
  await expectText(mg.page, 'the manager sees the report summary with the result', /Результат[\s\S]*30,00\s?TMT/);
  check('the manager also has the activity history tab', /История действий/.test(await text(mg.page)));
  problems.push(...mg.problems);
  await mg.page.close();
  const sl = await L.newPage(browser);
  await boot(sl.page);
  await signIn(sl.page, 'sales');
  await expectText(sl.page, 'the seller dashboard shows sales', /Продажи сегодня/);
  const sellerDash = await text(sl.page);
  check('the seller dashboard has no profit, no stock value, no expenses and no Reports page', !/Валовая прибыль/.test(sellerDash) && !/Стоимость склада/.test(sellerDash) && !/Расходы за месяц/.test(sellerDash) && !/Отчёты/.test(sellerDash), sellerDash.slice(0, 240));
  problems.push(...sl.problems);

  console.log('--- run finished; browser problems seen:', problems.length);
  const expectedAbort = /ERR_FAILED/; // the deliberately dropped answers in the lost-response steps
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
