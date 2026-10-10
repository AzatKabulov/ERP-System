// Phases 7 and 8 of the real-stack browser run (called from real_stack.js, after Phase 6, with the
// owner signed in): customer returns, supplier return, minimum stock and the reorder list,
// an expense with a receipt photo, a warranty claim closed with a replacement, CSV import and
// export. State on entry (end of Phase 6): BP-100 has 2 sellable at the Warehouse and 1 at the
// Main store; S-000001 (3 x 100, cash) and S-000002 (2 x 120, card) were sold from the Warehouse.
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// A 1x1 PNG: a real image, small enough to be a "receipt" for the run.
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');

module.exports = async function phase78(page, ctx) {
  const { L, dbFacts, stockAt, nav, pickFromDropdown, OUT, PASS, API } = ctx;
  const { check, expectText, expectNoText, clickLabel, fill, text } = L;

  const restart = async () => { // "restart the tablet": the page reloads, the session and saved keys stay
    await page.reload({ waitUntil: 'load' });
    await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
    await page.waitForTimeout(4500);
    await L.enableSemantics(page);
    await page.waitForTimeout(2500);
  };
  // Clicks a control that opens the file dialog and answers the dialog with [file].
  const chooseFile = async (file, label, opts = {}) => {
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser', { timeout: 15000 }),
      clickLabel(page, label, { wait: 2500, ...opts }),
    ]);
    await chooser.setFiles(file);
    await page.waitForTimeout(2500);
  };
  const openSale = async (number) => {
    await nav(page, 'Продажи');
    await clickLabel(page, 'История продаж', { role: 'button', wait: 1800 });
    await clickLabel(page, number, { exact: false, wait: 1800 });
  };
  const returnForm = async ({ quantity, damaged = false, reason }) => {
    await clickLabel(page, 'Вернуть товар', { role: 'button', wait: 1800 });
    await fill(page, '^Вернуть', quantity);
    if (damaged) await clickLabel(page, 'Повреждённый', { exact: false, wait: 500 });
    await fill(page, 'Причина возврата', reason);
  };

  // ---- Phase 7: a customer brings back part of S-000001 (sold: 3 x 100, cash) -----------------
  await openSale('S-000001');
  await expectText(page, 'the sale shows until when its goods can be returned (30 days from the sale)', /Вернуть можно до/);
  await returnForm({ quantity: '1', reason: 'Не подошли по размеру' });
  await expectText(page, 'the form says how much of the line can still be returned', /Можно вернуть: 3 шт/);
  await expectText(page, 'the refund is the price charged, not the catalog price: 1 x 100,00', /К возврату покупателю: 100,00/);
  await page.screenshot({ path: path.join(OUT, 'e2e-15-return-form.png') });
  await clickLabel(page, 'Вернуть товар', { role: 'button', which: 'last', wait: 1500 });
  await expectText(page, 'the person is asked to confirm, with what comes back and what is refunded', /Принять обратно: Тормозные колодки 1 шт\. Вернуть покупателю: 100,00/);
  await clickLabel(page, 'Подтвердить', { role: 'button', wait: 2500 });
  await expectText(page, 'the return is confirmed by the server', /Возврат оформлен/);
  let facts = dbFacts();
  check('one return R-0001: 1 piece sellable, refund 100.00 paid back as cash', facts.returns.length === 1 && facts.returns[0].refund === '100.00' && facts.returns[0].method === 'cash' && facts.returns[0].lines[0].q === '1.000' && facts.returns[0].lines[0].c === 'sellable', JSON.stringify(facts.returns));
  check('the piece is back at the Warehouse (sellable 2 -> 3)', stockAt(facts, 'Warehouse') === '3.000', JSON.stringify(facts.balances));
  check('reconcile is consistent after the first return', facts.reconcile === 'consistent', facts.reconcile);
  await expectText(page, 'the sale lists its return and what was returned so far', /R-0001[\s\S]*Уже возвращено: 1 шт/);

  // the rest of the line comes back damaged: the last piece takes the remainder (200,00)
  await returnForm({ quantity: '2', damaged: true, reason: 'Брак: не держат' });
  await expectText(page, 'the second refund is the rest of the line: 2 x 100,00', /К возврату покупателю: 200,00/);
  await clickLabel(page, 'Вернуть товар', { role: 'button', which: 'last', wait: 1500 });
  await clickLabel(page, 'Подтвердить', { role: 'button', wait: 2500 });
  await expectText(page, 'the second return is recorded', /R-0002/);
  facts = dbFacts();
  check('R-0002 refunds 200.00 and the two pieces wait as damaged', facts.returns.length === 2 && facts.returns[1].refund === '200.00' && facts.returns[1].lines[0].c === 'damaged' && stockAt(facts, 'Warehouse', 'damaged') === '2.000' && stockAt(facts, 'Warehouse') === '3.000', JSON.stringify(facts.returns) + JSON.stringify(facts.balances));
  check('the two refunds add up to the sale: 300.00, no cents lost', parseFloat(facts.returns[0].refund) + parseFloat(facts.returns[1].refund) === parseFloat(facts.sales[0].total), JSON.stringify(facts.returns));
  await expectNoText(page, 'nothing is left to return, so the button is gone', /Вернуть товар/);
  await page.screenshot({ path: path.join(OUT, 'e2e-16-sale-returned.png') });

  // S-000002 (card): a return whose answer is lost after the server committed, then a restart
  await clickLabel(page, 'Назад', { role: 'button', wait: 1200 });
  await clickLabel(page, 'S-000002', { exact: false, wait: 1800 });
  await returnForm({ quantity: '1', reason: 'Передумал' });
  await page.route('**/returns/', async (route) => {
    if (route.request().method() !== 'POST') return route.continue();
    await route.fetch(); // the server really takes the piece back ...
    await route.abort('failed'); // ... but the answer never reaches the tablet
  });
  await clickLabel(page, 'Вернуть товар', { role: 'button', which: 'last', wait: 1500 });
  await clickLabel(page, 'Подтвердить', { role: 'button', wait: 3500 });
  await expectText(page, 'the app does not claim the return: outcome unknown', /Ответ сервера не получен/);
  await expectText(page, 'the unconfirmed return is listed', /Ожидают подтверждения: 1/);
  facts = dbFacts();
  check('the server did record the third return: 120.00, paid back by card', facts.returns.length === 3 && facts.returns[2].refund === '120.00' && facts.returns[2].method === 'card' && stockAt(facts, 'Warehouse') === '4.000', JSON.stringify(facts.returns));
  await page.unroute('**/returns/');
  await restart();
  check('the confirmed return left the pending list by itself', !/Ожидают подтверждения/.test(await text(page)));
  facts = dbFacts();
  check('exactly three returns after the restart (no duplicate), stock exactly 4 sellable', facts.returns.length === 3 && facts.returns.map((r) => r.n).join() === '1,2,3' && stockAt(facts, 'Warehouse') === '4.000', JSON.stringify(facts.returns));
  check('reconcile finds no difference after the restart', facts.reconcile === 'consistent', facts.reconcile);
  await nav(page, 'Продажи');
  await clickLabel(page, 'Возвраты', { role: 'button', wait: 1800 });
  await expectText(page, 'the returns list shows all three', /R-0003[\s\S]*R-0002[\s\S]*R-0001/);
  await page.screenshot({ path: path.join(OUT, 'e2e-17-returns.png') });
  await clickLabel(page, 'Назад', { role: 'button', wait: 1200 });

  // ---- Phase 7: one damaged piece goes back to the supplier ------------------------------------
  await nav(page, 'Закупки');
  await clickLabel(page, 'PO-0001', { exact: false, wait: 1800 });
  await clickLabel(page, 'Вернуть поставщику', { role: 'button', wait: 1800 });
  await fill(page, '^Вернуть', '1');
  await clickLabel(page, 'Повреждённый', { exact: false, wait: 500 });
  await fill(page, 'Причина возврата', 'Заводской брак');
  await clickLabel(page, 'Вернуть поставщику', { role: 'button', which: 'last', wait: 2500 });
  await expectText(page, 'the supplier return is recorded', /Возврат поставщику оформлен/);
  facts = dbFacts();
  check('SR-0001 credits the delivery price (50.00) and the damaged stock falls 2 -> 1', facts.supplier_returns.length === 1 && facts.supplier_returns[0].credit === '50.00' && facts.supplier_returns[0].lines[0].c === 'damaged' && stockAt(facts, 'Warehouse', 'damaged') === '1.000', JSON.stringify(facts.supplier_returns) + JSON.stringify(facts.balances));
  check('reconcile is consistent after the supplier return', facts.reconcile === 'consistent', facts.reconcile);
  await clickLabel(page, 'Назад', { role: 'button', wait: 1500 });
  await clickLabel(page, 'Возвраты поставщикам', { role: 'button', wait: 1800 });
  await expectText(page, 'the supplier returns list shows SR-0001', /SR-0001/);
  await clickLabel(page, 'Назад', { role: 'button', wait: 1200 });

  // ---- Phase 7: minimum stock at the shop -> reorder list -> a draft order --------------------------
  await nav(page, 'Товары');
  await clickLabel(page, 'BP-100', { exact: false, wait: 1800 });
  await expectText(page, 'the product shows its return window', /Возврат в течение 30 дн\./);
  await clickLabel(page, 'Изменить', { role: 'button', wait: 1800 });
  await fill(page, '^Минимум', '5'); // the first place in the list, the Main store
  await fill(page, '^Цель', '20');
  await clickLabel(page, 'Сохранить', { role: 'button', wait: 2500 });
  await expectText(page, 'the levels are saved and shown', /Main store: минимум 5 шт, цель 20 шт/);
  await clickLabel(page, 'Назад', { role: 'button', wait: 1500 });
  await nav(page, 'Закупки');
  await clickLabel(page, 'Пополнение запаса', { role: 'button', wait: 2000 });
  await expectText(page, 'the shop holds 1, below its minimum of 5: suggest ordering up to the target', /Есть: 1 шт · в заказах: 0 шт · минимум: 5 шт[\s\S]*Предлагается заказать: 19 шт/);
  await page.screenshot({ path: path.join(OUT, 'e2e-18-reorder.png') });
  await clickLabel(page, 'Тормозные колодки', { exact: false, wait: 800 });
  await clickLabel(page, 'Создать заказ', { role: 'button', wait: 2000 });
  await expectText(page, 'the order form opens with the suggested quantity', /Тормозные колодки/);
  await pickFromDropdown(page, '^Поставщик', 'Ашхабад Запчасти');
  await clickLabel(page, 'Сохранить', { role: 'button', wait: 2500 });
  await expectText(page, 'the draft order PO-0002 is created', /PO-0002/);
  facts = dbFacts();
  check('PO-0002 is a draft for 19 pieces; nothing was ordered on its own', facts.orders.length === 2 && facts.orders[1].status === 'draft' && facts.orders[1].lines.join() === '19.000', JSON.stringify(facts.orders));
  await clickLabel(page, 'Назад', { role: 'button', wait: 1500 }); // from the order to the purchasing page

  // ---- Phase 8: an expense with a photo of the receipt ----------------------------------------------
  const receipt = path.join(OUT, 'receipt.png');
  fs.writeFileSync(receipt, PNG);
  await nav(page, 'Расходы');
  await expectText(page, 'no expenses yet', /Расходов за этот период нет/);
  await clickLabel(page, 'Добавить расход', { role: 'button', wait: 1800 });
  await pickFromDropdown(page, '^Категория', 'Аренда');
  await fill(page, 'Сумма, TMT', '150');
  await fill(page, 'Описание', 'Аренда за октябрь');
  await chooseFile(receipt, 'Выбрать фото или файл', { role: 'button' });
  await expectText(page, 'the receipt photo is uploaded and attached', /Чек приложен: receipt\.png/);
  await page.screenshot({ path: path.join(OUT, 'e2e-19-expense-form.png') });
  await clickLabel(page, 'Сохранить', { role: 'button', wait: 2500 });
  await expectText(page, 'the expense is listed with its amount', /Аренда за октябрь/);
  await expectText(page, 'the period total is shown', /Всего за период: 150,00/);
  facts = dbFacts();
  check('one expense: rent 150.00 with its receipt file', facts.expenses.length === 1 && facts.expenses[0].amount === '150.00' && facts.expenses[0].category === 'Аренда' && facts.expenses[0].file && !facts.expenses[0].voided, JSON.stringify(facts.expenses));

  // the receipt file is private: the API serves it to a signed-in member only, byte for byte
  const login = await (await fetch(API + '/api/v1/auth/login/', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username: 'owner', password: PASS }) })).json();
  const url = `${API}/api/v1/businesses/${facts.business}/attachments/${facts.expenses[0].file_id}/`;
  const anonymous = await fetch(url);
  const served = await fetch(url, { headers: { Authorization: 'Bearer ' + login.access } });
  const bytes = Buffer.from(await served.arrayBuffer());
  check('the receipt is refused without a sign-in', anonymous.status === 401 || anonymous.status === 403, String(anonymous.status));
  check('a signed-in member gets exactly the uploaded bytes, not sniffable', served.status === 200 && bytes.equals(PNG) && served.headers.get('x-content-type-options') === 'nosniff', `${served.status} ${bytes.length} ${served.headers.get('x-content-type-options')}`);

  // open the expense and fetch the receipt through the app (it is handed over like a download)
  await clickLabel(page, 'Аренда за октябрь', { exact: false, wait: 1800 });
  const [download] = await Promise.all([
    page.waitForEvent('download', { timeout: 15000 }),
    clickLabel(page, 'Открыть или отправить чек', { exact: false, wait: 2500 }),
  ]);
  const savedReceipt = path.join(OUT, 'receipt-downloaded.png');
  await download.saveAs(savedReceipt);
  check('the app fetches the receipt for sharing: same name, same bytes', download.suggestedFilename() === 'receipt.png' && fs.readFileSync(savedReceipt).equals(PNG), download.suggestedFilename());
  await clickLabel(page, 'Аннулировать', { role: 'button', wait: 1500 });
  await fill(page, 'Причина аннулирования', 'Внесено по ошибке');
  await clickLabel(page, 'Подтвердить', { role: 'button', wait: 2500 });
  await expectText(page, 'the expense is voided, not deleted', /Расход аннулирован/);
  facts = dbFacts();
  check('the expense still exists, marked voided', facts.expenses.length === 1 && facts.expenses[0].voided, JSON.stringify(facts.expenses));
  await clickLabel(page, 'Назад', { role: 'button', wait: 1500 });
  await expectText(page, 'a voided expense is not in the total', /Всего за период: 0,00/);

  // ---- Phase 8: a warranty claim from S-000002, closed with a replacement ----------------------------
  await openSale('S-000002');
  await expectText(page, 'the line shows its warranty', /Гарантия: 12 мес\./);
  await clickLabel(page, 'Гарантийное обращение', { role: 'button', wait: 1800 });
  await clickLabel(page, 'Тормозные колодки', { exact: false, wait: 1200 });
  await expectText(page, 'the server worked out the warranty end date from the sale', /Гарантия до \d{4}-\d{2}-\d{2}|Гарантия до \d{2}\.\d{2}\.\d{4}/);
  await fill(page, '^Количество', '1');
  await fill(page, 'Что случилось', 'Скрипят при торможении');
  await clickLabel(page, 'Открыть обращение', { role: 'button', wait: 2500 });
  await expectText(page, 'the claim is opened with its number', /Обращение W-0001 открыто/);
  facts = dbFacts();
  check('W-0001 is open, in warranty', facts.claims.length === 1 && facts.claims[0].status === 'open' && !facts.claims[0].out && facts.claims[0].q === '1.000', JSON.stringify(facts.claims));
  await clickLabel(page, 'Назад', { role: 'button', wait: 1200 }); // sale -> history
  await clickLabel(page, 'Назад', { role: 'button', wait: 1200 }); // history -> sales page
  await nav(page, 'Гарантии');
  await clickLabel(page, 'W-0001', { exact: false, wait: 1800 });
  await expectText(page, 'the claim shows its problem and history', /Скрипят при торможении[\s\S]*История/);
  await clickLabel(page, 'Замена', { role: 'checkbox', wait: 600 }).catch(() => clickLabel(page, 'Замена', { exact: false, wait: 600 }));
  await page.screenshot({ path: path.join(OUT, 'e2e-20-warranty.png') });
  await clickLabel(page, 'Закрыть обращение', { role: 'button', wait: 1500 });
  await clickLabel(page, 'Подтвердить', { role: 'button', wait: 2500 });
  await expectText(page, 'the claim is closed', /Обращение закрыто/);
  facts = dbFacts();
  check('W-0001 is closed as a replacement', facts.claims[0].status === 'closed' && facts.claims[0].outcome === 'replacement', JSON.stringify(facts.claims));
  check('a replacement gives one sellable piece away and takes one damaged back (3 / 2)', stockAt(facts, 'Warehouse') === '3.000' && stockAt(facts, 'Warehouse', 'damaged') === '2.000', JSON.stringify(facts.balances));
  check('reconcile is consistent after the warranty claim', facts.reconcile === 'consistent', facts.reconcile);
  await clickLabel(page, 'Назад', { role: 'button', wait: 1200 }); // the claim -> the Warranties page

  // ---- Phase 8: CSV import (a file with errors changes nothing), then a fixed file, then export ----
  const header = 'sku;name;unit;category;brand;price;currency';
  const bad = path.join(OUT, 'import-bad.csv');
  fs.writeFileSync(bad, ['﻿' + header, 'IMP-1;Свеча зажигания;Штука;Запчасти;;45,50;TMT', 'BP-100;Повтор;Штука;;;10;TMT', 'IMP-3;Бочка масла;Бочка;;;20;TMT'].join('\r\n'));
  const fixed = path.join(OUT, 'import-fixed.csv');
  fs.writeFileSync(fixed, ['﻿' + header, 'IMP-1;Свеча зажигания;Штука;Запчасти;;45,50;TMT', 'IMP-2;Масляный фильтр;Штука;Запчасти;;80;TMT', 'IMP-3;Çyralyk ýagy (täze);Штука;Запчасти;;12,5;TMT'].join('\r\n'));
  const before = dbFacts().products.length;
  await nav(page, 'Товары');
  await clickLabel(page, 'Импорт CSV', { role: 'button', wait: 1800 });
  await chooseFile(bad, 'Выбрать файл', { role: 'button' });
  await expectText(page, 'the file is checked as a whole and the summary says 1 of 3 rows is fine', /Строк: 3, без ошибок: 1/);
  await expectText(page, 'the row with an existing SKU is named', /Такой артикул уже есть в каталоге/);
  await expectText(page, 'the row with an unknown unit is named', /Неизвестная единица измерения/);
  await page.screenshot({ path: path.join(OUT, 'e2e-21-import-errors.png') });
  facts = dbFacts();
  check('the catalog did not change (not even the good first row)', facts.products.length === before, JSON.stringify(facts.products));
  await chooseFile(fixed, 'Выбрать файл', { role: 'button' });
  await expectText(page, 'the fixed file has no errors', /Ошибок нет\. Можно добавлять товары/);
  await clickLabel(page, 'Добавить товары', { role: 'button', wait: 3500 });
  await expectText(page, 'three products are added', /Добавлено товаров: 3/);
  facts = dbFacts();
  check('the three products exist now (Turkmen letters intact) and no stock was created for them', facts.products.join() === 'BP-100,FLT-USD,IMP-1,IMP-2,IMP-3' && facts.product_names['IMP-3'] === 'Çyralyk ýagy (täze)' && !facts.balances.some((b) => /^IMP/.test(b.sku)), JSON.stringify(facts.products) + JSON.stringify(facts.product_names));
  check('reconcile is consistent after the import', facts.reconcile === 'consistent', facts.reconcile);
  await clickLabel(page, 'Назад', { role: 'button', wait: 1800 });
  await expectText(page, 'the new products are in the catalog list', /IMP-2/);
  const [csv] = await Promise.all([
    page.waitForEvent('download', { timeout: 15000 }),
    clickLabel(page, 'Экспорт CSV', { role: 'button', wait: 3000 }),
  ]);
  const exported = path.join(OUT, 'products-exported.csv');
  await csv.saveAs(exported);
  const raw = fs.readFileSync(exported);
  const csvText = raw.toString('utf8');
  check('the export is products.csv, UTF-8 with a BOM, ";"-separated, with every product', csv.suggestedFilename() === 'products.csv' && raw[0] === 0xEF && raw[1] === 0xBB && raw[2] === 0xBF && /sku;name/.test(csvText) && /BP-100;/.test(csvText) && /Çyralyk ýagy \(täze\)/.test(csvText) && /IMP-2;/.test(csvText), csvText.slice(0, 160));
};
