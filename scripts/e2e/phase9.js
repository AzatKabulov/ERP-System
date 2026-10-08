// Phase 9 of the real-stack browser run (called from real_stack.js after Phases 7-8, owner signed
// in): the dashboard and the reports are read back against the figures the database itself
// holds, then the activity history. Expected figures are computed here from the database facts
// (sales, returns, expenses), not copied from the screens.
//
// State on entry (end of Phase 8): two sales from the Warehouse (S-000001 3 x 100 cash, S-000002
// 2 x 120 card, both bought at 50 per piece), three returns (100 + 200 + 120), one supplier
// return (credit 50), PO-0001 received (10 x 50) and PO-0002 a draft, one voided expense, six
// pieces in stock (Warehouse 3 sellable + 2 damaged, Main store 1) all at the cost of 50.
const fs = require('fs');
const path = require('path');

const money = (n) => n.toFixed(2).replace('.', ',');
// "300,00 TMT" on the screen has a non-breaking space; \s matches it.
const shown = (n) => new RegExp(money(n).replace(',', ',') + '\\s?TMT');

module.exports = async function phase9(page, ctx) {
  const { L, dbFacts, nav, OUT } = ctx;
  const { check, expectText, expectNoText, clickLabel, fill, text } = L;
  const pick = async (current, option) => { // a dropdown shows its current value as its label
    await clickLabel(page, current, { exact: false, wait: 700 });
    await clickLabel(page, option, { exact: false, wait: 900 });
  };

  // a plain expense (no photo), so the expenses figures are not zero: the first one was voided
  await nav(page, 'Расходы');
  await clickLabel(page, 'Добавить расход', { role: 'button', wait: 1800 });
  await pick('^Категория', 'Транспорт');
  await fill(page, 'Сумма, TMT', '40');
  await fill(page, 'Описание', 'Такси до склада');
  await clickLabel(page, 'Сохранить', { role: 'button', wait: 2500 });
  await expectText(page, 'the second expense is listed', /Такси до склада/);

  // ---- what the database holds, worked out independently ---------------------------------------
  const facts = dbFacts();
  const num = (x) => parseFloat(x);
  const revenue = facts.sales.reduce((a, s) => a + num(s.total), 0);
  const refunds = facts.returns.reduce((a, r) => a + num(r.refund), 0);
  const net = revenue - refunds;
  const cogs = facts.sales.reduce((a, s) => a + num(s.cost), 0) - facts.returns.reduce((a, r) => a + num(r.cost), 0);
  const profit = net - cogs;
  const expenses = facts.expenses.filter((e) => !e.voided).reduce((a, e) => a + num(e.amount), 0);
  const result = profit - expenses;
  const pieces = facts.balances.filter((b) => b.sku === 'BP-100').reduce((a, b) => a + num(b.q), 0);
  const stockValue = pieces * 50; // every layer cost 50
  check('the expected figures from the database are what the scenario says (540 / 420 / 120 / 50 / 70 / 40 / 30 / 300)',
    revenue === 540 && refunds === 420 && net === 120 && cogs === 50 && profit === 70 && expenses === 40 && result === 30 && stockValue === 300,
    JSON.stringify({ revenue, refunds, net, cogs, profit, expenses, result, stockValue }));
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Ashgabat' }); // the business's day

  // ---- dashboard ---------------------------------------------------------------------------------------
  await nav(page, 'Обзор');
  await expectText(page, 'the dashboard shows today\'s sales with their count', new RegExp('Продажи сегодня \\(2\\)[\\s\\S]*' + money(revenue) + '\\s?TMT'));
  await expectText(page, 'and the month, the gross profit net of returns, the expenses', new RegExp('Продажи за месяц \\(2\\)[\\s\\S]*Валовая прибыль за месяц[\\s\\S]*' + money(profit) + '\\s?TMT[\\s\\S]*Расходы за месяц[\\s\\S]*' + money(expenses) + '\\s?TMT'));
  await expectText(page, 'the stock value at cost and what is below the minimum', new RegExp('Стоимость склада[\\s\\S]*' + money(stockValue) + '\\s?TMT[\\s\\S]*Ниже минимума[\\s\\S]*\\| 1'));
  await expectText(page, 'recent activity is listed', /Недавние действия/);
  await page.screenshot({ path: path.join(OUT, 'e2e-22-dashboard.png') });

  // ---- reports: summary ------------------------------------------------------------------------------
  await clickLabel(page, 'Открыть отчёты', { role: 'button', wait: 2500 });
  await expectText(page, 'the summary shows the revenue', new RegExp('Выручка[\\s\\S]*' + money(revenue) + '\\s?TMT'));
  const summary = await text(page);
  check('refunds, net sales, cost of goods, gross profit, expenses and the result are separate figures that match the database',
    shown(refunds).test(summary) && shown(net).test(summary) && shown(cogs).test(summary) && shown(profit).test(summary) && shown(expenses).test(summary) && shown(result).test(summary) && shown(stockValue).test(summary),
    summary.slice(0, 400));
  check('the result says it is not an accounting profit', /не бухгалтерская прибыль/.test(summary));
  check('the counts line names 2 sales and 3 returns', /Продаж: 2 · Возвратов: 3/.test(summary));
  await page.screenshot({ path: path.join(OUT, 'e2e-23-report-summary.png') });

  // ---- sales ---------------------------------------------------------------------------------------------
  await clickLabel(page, 'Продажи', { role: 'checkbox', wait: 1800 }).catch(() => clickLabel(page, 'Продажи', { exact: true, which: 'last', wait: 1800 }));
  await expectText(page, 'sales: revenue, refunds and net sales of the period', new RegExp('Выручка: ' + money(revenue) + '\\s?TMT[\\s\\S]*Возвраты денег: ' + money(refunds) + '\\s?TMT[\\s\\S]*Чистые продажи: ' + money(net) + '\\s?TMT'));
  await expectText(page, 'sales: how they paid (cash and card)', new RegExp('Наличные: 1 · 300,00\\s?TMT[\\s\\S]*Карта: 1 · 240,00\\s?TMT'));
  await expectText(page, 'sales: the day of the sales, with the refunds of the day', new RegExp(today + ': 2 · выручка 540,00\\s?TMT · возвраты 420,00\\s?TMT'));
  await expectText(page, 'sales: the best product', /Тормозные колодки · BP-100/);

  // one place at a time: all sales were made at the Warehouse
  await pick('Все точки', 'Main store');
  await expectText(page, 'filtered to the Main store: nothing was sold there', /Выручка: 0,00\s?TMT/);
  await pick('Main store', 'Warehouse');
  await expectText(page, 'filtered to the Warehouse: everything was sold there', new RegExp('Выручка: ' + money(revenue) + '\\s?TMT'));
  await pick('Warehouse', 'Все точки');

  // the CSV of the same figures
  const [csv] = await Promise.all([
    page.waitForEvent('download', { timeout: 15000 }),
    clickLabel(page, 'Экспорт CSV', { role: 'button', wait: 3000 }),
  ]);
  const file = path.join(OUT, 'report-sales.csv');
  await csv.saveAs(file);
  const raw = fs.readFileSync(file);
  const csvText = raw.toString('utf8');
  check('the sales export is a UTF-8 CSV with a BOM and ";", named for the period, with the day and its revenue',
    /^sales-\d{4}-\d{2}-\d{2}-\d{4}-\d{2}-\d{2}\.csv$/.test(csv.suggestedFilename()) && raw[0] === 0xEF && raw[1] === 0xBB && raw[2] === 0xBF && csvText.includes(';') && csvText.includes(today) && csvText.includes('540.00'),
    csv.suggestedFilename() + ' ' + csvText.slice(0, 200));

  // ---- stock ------------------------------------------------------------------------------------------------
  await clickLabel(page, 'Склад', { role: 'checkbox', wait: 1800 }).catch(() => clickLabel(page, 'Склад', { exact: true, which: 'last', wait: 1800 }));
  await expectText(page, 'stock: the shop holds 1, below its minimum of 5', /Main store: есть 1 шт, минимум 5 шт/);
  await expectText(page, 'stock: the value at cost is the six pieces x 50', new RegExp('Стоимость склада: ' + money(stockValue) + '\\s?TMT'));
  await expectText(page, 'stock: every movement kind has its own name (sale, return, supplier return, warranty)', /Продажа: \d+ · приход 0 · расход 5[\s\S]*Возврат от покупателя/);
  await page.screenshot({ path: path.join(OUT, 'e2e-24-report-stock.png') });

  // ---- purchasing ---------------------------------------------------------------------------------------
  await clickLabel(page, 'Закупки', { role: 'checkbox', wait: 1800 }).catch(() => clickLabel(page, 'Закупки', { exact: true, which: 'last', wait: 1800 }));
  await expectText(page, 'purchasing: two orders were made, the draft is not counted as money ordered', /Заказов создано: 2[\s\S]*Сумма заказов: 500,00\s?TMT/);
  await expectText(page, 'purchasing: what was received and the supplier return credit', /Принято на сумму: 500,00\s?TMT[\s\S]*Возвраты поставщикам: 1, зачёт 50,00\s?TMT/);

  // ---- returns -----------------------------------------------------------------------------------------------
  await clickLabel(page, 'Возвраты', { role: 'checkbox', wait: 1800 }).catch(() => clickLabel(page, 'Возвраты', { exact: true, which: 'last', wait: 1800 }));
  await expectText(page, 'returns: refunded to customers', new RegExp('Возвращено покупателям: ' + money(refunds) + '\\s?TMT'));
  await expectText(page, 'returns: by the condition of the goods', /Годный к продаже: 2 · 220,00\s?TMT[\s\S]*Повреждённый: 2 · 200,00\s?TMT/);
  await expectText(page, 'returns: the reasons the customers gave', /Не подошли по размеру: 1 · 100,00\s?TMT/);

  // ---- expenses ----------------------------------------------------------------------------------------------
  await clickLabel(page, 'Расходы', { role: 'checkbox', wait: 1800 }).catch(() => clickLabel(page, 'Расходы', { exact: true, which: 'last', wait: 1800 }));
  await expectText(page, 'expenses: the voided one is not counted, only the 40', /Всего: 40,00\s?TMT/);
  await expectText(page, 'expenses: by category', /Транспорт: 40,00\s?TMT \(1\)/);

  // ---- activity history ------------------------------------------------------------------------------------
  await clickLabel(page, 'История действий', { role: 'checkbox', wait: 2500 }).catch(() => clickLabel(page, 'История действий', { exact: true, which: 'last', wait: 2500 }));
  await expectText(page, 'activity: sales and returns are recorded with the person', /Оформлена продажа[\s\S]*Sample Owner/);
  await expectText(page, 'activity: the other actions are named in Russian, not by their codes', /Возврат от покупателя/);
  check('no raw action code is shown', !/\b(sale|expense|product|count|transfer)\.[a-z_]+\b/.test(await text(page)));
  await pick('Все действия', 'Оформлена продажа');
  await page.waitForTimeout(1500);
  const filtered = await text(page);
  check('narrowed to one action: sales are listed, returns are not', /Оформлена продажа/.test(filtered) && !/Возврат от покупателя/.test(filtered));
  await page.screenshot({ path: path.join(OUT, 'e2e-25-activity.png') });

  const after = dbFacts();
  check('reconcile is still consistent: reports only read', after.reconcile === 'consistent', after.reconcile);
};
