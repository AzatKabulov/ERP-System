// Receiving goods by scanning, in the real-stack browser run (called from real_stack.js after
// Phase 9, owner signed in). The web build has no camera, so the items are "scanned" the way a
// hand scanner does it: the code is typed into the field and Enter is pressed. The same list and
// the same posting are used by the camera.
//
// State on entry (end of Phase 9): product BP-100 (stock 3 + 2 damaged at the Warehouse, 1 at the
// Main store), the CSV products, one voided expense, ledger consistent.
const path = require('path');

module.exports = async function phaseIntake(page, ctx) {
  const { L, dbFacts, stockAt, nav, pickFromDropdown, OUT } = ctx;
  const { check, expectText, expectNoText, clickLabel, fill, text } = L;
  const scan = async (code) => {
    await fill(page, '^Код товара', code);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(1200);
  };

  let facts = dbFacts();
  const before = stockAt(facts, 'Main store');
  check('before: the ledger is consistent and there is no intake yet', facts.reconcile === 'consistent' && facts.intakes.length === 0, facts.reconcile);

  await nav(page, 'Склад');
  await clickLabel(page, 'Приёмка сканированием', { role: 'button', wait: 1800 });
  await expectText(page, 'the intake screen explains what to do', /Откройте коробку и отсканируйте каждый товар/);
  await pickFromDropdown(page, 'Куда принимаем', 'Main store');

  // three pieces of a product the catalog knows (by its article number), written in two letter cases
  await scan('BP-100');
  await scan('bp-100');
  await scan('BP-100');
  await expectText(page, 'the known product is found and counted: 3 pieces on one line', /Тормозные колодки[\s\S]*3 шт/);
  // an item the catalog has never seen, twice
  await scan('MH044089');
  await scan('MH044089');
  await expectText(page, 'an unknown code says so and offers to add the product', /Этого товара нет в каталоге/);
  await page.screenshot({ path: path.join(OUT, 'e2e-24-intake-unknown.png') });
  await clickLabel(page, 'Добавить товар', { role: 'button', wait: 1500 });
  await expectText(page, 'the new product form shows the scanned code', /Код: MH044089/);
  await fill(page, '^Название товара', 'Подшипник КПП Fuso');
  await clickLabel(page, 'Добавить и учесть', { role: 'button', wait: 2500 });
  await expectText(page, 'the product is added and the two scans are on its line', /Подшипник КПП Fuso[\s\S]*2 шт/);
  await expectText(page, 'the totals say 2 lines and 5 pieces', /Позиций: 2, всего: 5/);
  await page.screenshot({ path: path.join(OUT, 'e2e-25-intake-list.png') });
  facts = dbFacts();
  check('nothing is on the shelf yet: the list only lives on the device', stockAt(facts, 'Main store') === before && facts.intakes.length === 0, JSON.stringify(facts.intakes));
  check('the new product exists with its code as article and barcode and no price', facts.products.includes('MH044089') && JSON.stringify(facts.barcodes['MH044089']) === '["MH044089"]' && facts.prices['MH044089'] === '0.00', JSON.stringify([facts.barcodes['MH044089'], facts.prices['MH044089']]));

  // the tablet is closed and opened again in the middle of the box: the list is still there
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await page.waitForTimeout(4500);
  await L.enableSemantics(page);
  await nav(page, 'Склад');
  await clickLabel(page, 'Приёмка сканированием', { role: 'button', wait: 2500 });
  await expectText(page, 'after the restart the unfinished list is offered again', /Продолжаем незавершённую приёмку: 2 поз\./);
  await expectText(page, 'with both lines and their counts', /Тормозные колодки[\s\S]*3 шт[\s\S]*Подшипник КПП Fuso[\s\S]*2 шт|Подшипник КПП Fuso[\s\S]*2 шт[\s\S]*Тормозные колодки[\s\S]*3 шт/);
  await scan('MH044089'); // one more of the new one, now found by itself
  await expectText(page, 'a code added a moment ago is found by itself and counted', /Подшипник КПП Fuso[\s\S]*3 шт/);

  // put the box on the shelf, with the answer lost after the server committed
  await page.route('**/intakes/', async (route) => {
    if (route.request().method() !== 'POST') return route.continue();
    await route.fetch(); // the server really performs it ...
    await route.abort('failed'); // ... but the answer never reaches the app
  });
  await clickLabel(page, 'Принять на склад', { role: 'button', wait: 1500 });
  await expectText(page, 'a confirmation names the place and the totals', /Main store: 2 поз\., всего 6/);
  await clickLabel(page, 'Подтвердить', { role: 'button', wait: 3500 });
  await expectText(page, 'the app says the outcome is unknown', /Ответ сервера не получен/);
  await page.unroute('**/intakes/');
  facts = dbFacts();
  check('the server did commit the intake (one document, two lines)', facts.intakes.length === 1 && facts.intakes[0].lines.length === 2, JSON.stringify(facts.intakes));
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await page.waitForTimeout(4500);
  await L.enableSemantics(page);
  await page.waitForTimeout(2000);
  check('the confirmed receipt left the pending list by itself', !/Ожидают подтверждения/.test(await text(page)));
  facts = dbFacts();
  const line = (sku) => (facts.intakes[0] ? facts.intakes[0].lines.find((l) => l.sku === sku) : null) || {};
  check('exactly one intake exists after the restart (IN-0001 at the Main store)', facts.intakes.length === 1 && facts.intakes[0].n === 1 && facts.intakes[0].place === 'Main store', JSON.stringify(facts.intakes));
  check('BP-100 came in by 3 and the new product by 3', line('BP-100').q === '3.000' && line('MH044089').q === '3.000', JSON.stringify(facts.intakes));
  check('no cost was typed: BP-100 takes its default cost (70.00), the new product costs zero, and both are marked as not known', line('BP-100').cost === '70.00' && line('BP-100').known === false && line('MH044089').cost === '0.00' && line('MH044089').known === false, JSON.stringify(facts.intakes));
  check('the shop holds 3 more BP-100 and the new product, and the ledger is consistent', stockAt(facts, 'Main store') === (parseFloat(before) + 3).toFixed(3) && stockAt(facts, 'Main store', 'sellable', 'MH044089') === '3.000' && facts.reconcile === 'consistent', JSON.stringify(facts.balances) + facts.reconcile);

  // the list is empty again, the stock page shows the new product
  await nav(page, 'Склад');
  await clickLabel(page, 'Приёмка сканированием', { role: 'button', wait: 2500 });
  await expectText(page, 'a new intake starts from an empty list', /Откройте коробку и отсканируйте каждый товар/);
  await expectNoText(page, 'and no old list is offered', /Продолжаем незавершённую приёмку/);
  await clickLabel(page, 'Назад', { role: 'button', wait: 1500 });
  await expectText(page, 'the stock page lists the new product with its count', /Подшипник КПП Fuso[\s\S]*3 шт/);
  await page.screenshot({ path: path.join(OUT, 'e2e-26-intake-done.png') });

};
