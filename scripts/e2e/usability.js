// Real store-day checks plus a read-only platform-owner visual review.
// The runner must create a disposable PostgreSQL cluster and local operator.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const L = require('./lib');
if (process.env.ERP_E2E_DISPOSABLE !== 'true') throw Error('Disposable shop required');
execFileSync(process.execPath, [path.join(__dirname, 'store_day.js')], {stdio:'inherit',env:process.env});
const out = process.env.E2E_OUT || '/tmp/erp-usability-browser';
(async () => {
  const browser = await L.launch();
  const results = [];
  try {
    for (const width of [390, 820, 1440]) {
      for (const dark of [false, true]) {
        const {ctx,page,problems} = await L.newPage(browser, {width,height:1000});
        await ctx.addInitScript(dark => {
          localStorage.setItem('flutter.theme.mode', JSON.stringify(dark ? 'dark' : 'light'));
        }, dark);
        await L.boot(page);
        await L.clickLabel(page, 'Войти', {which:'last',wait:350});
        await L.clickLabel(page, 'Владелец платформы', {wait:1200});
        assert.match(await L.text(page), /Пробный период и заканчивающиеся подписки/);
        assert.match(await L.text(page), /Всего клиентов/);
        await page.screenshot({path:path.join(out, `platform-${width}-${dark?'dark':'light'}.png`),fullPage:true});
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
        const unexpected = problems.filter(p => !p.includes('WebGL: non-portable extension enabled: WEBGL_polygon_mode'));
        assert.deepEqual(unexpected, []);
        results.push({width,dark,overview:'passed',documentFits:true});
        await ctx.close();
      }
    }
    fs.writeFileSync(path.join(out,'platform-results.json'),JSON.stringify(results,null,2)+'\n');
  } finally { await browser.close(); }
})().catch(error => {console.error(error.stack);process.exitCode=1;});
