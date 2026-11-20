// Real browser/API sign-in against an explicitly disposable shop only.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const L = require('./lib');
if (process.env.ERP_E2E_DISPOSABLE !== 'true' || !process.env.ERP_QA_OPERATOR_PASSWORD) {
  throw Error('Disposable QA accounts required.');
}
(async () => {
  const browser = await L.launch();
  try {
    for (const language of ['ru', 'tk']) {
      const l = JSON.parse(fs.readFileSync(path.join(__dirname, `../../mobile/lib/l10n/app_${language}.arb`)));
      for (const operator of [true, false]) {
        const username = operator ? 'qa-platform-operator' : 'owner';
        const password = operator ? process.env.ERP_QA_OPERATOR_PASSWORD : process.env.ERP_SAMPLE_PASSWORD;
        const {ctx, page} = await L.newPage(browser);
        await L.boot(page);
        if ((await L.text(page)).includes('Войти по логину и паролю')) {
          await L.clickLabel(page, 'Войти по логину и паролю');
        }
        if (language === 'tk') await L.clickLabel(page, 'TM');
        await L.fill(page, `^${l.username}$`, username);
        await L.fill(page, `^${l.password}$`, password);
        const profile = page.waitForResponse(r => new URL(r.url()).pathname === '/api/v1/me/' && r.status() === 200);
        await L.clickLabel(page, l.signInAction, {which: 'last', wait: 1500});
        const me = await (await profile).json();
        assert.equal(me.user.username, username);
        assert.equal(me.user.is_platform_operator, operator);
        assert.equal(await page.locator(`input[aria-label="${l.signInCodeLabel}"]`).count(), 0);
        assert.equal(await page.locator(`input[aria-label="${l.password}"]`).count(), 0);
        const login = await page.request.post(new URL('/api/v1/auth/login/', L.URL).href, {data: {username, password}});
        assert.equal(login.status(), 200);
        const {access} = await login.json();
        const permissions = await page.request.get(new URL('/api/v1/platform/overview/', L.URL).href,
          {headers: {Authorization: `Bearer ${access}`}});
        assert.equal(permissions.status(), operator ? 200 : 403);
        console.log(`PASS password-only ${operator ? 'operator' : 'shop'} sign-in and role isolation (${language})`);
        await ctx.close();
      }
    }
  } finally { await browser.close(); }
})().catch(e => {console.error(e.message); process.exitCode = 1;});
