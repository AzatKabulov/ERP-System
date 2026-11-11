// Failure controls use only the marked loopback sample shop; no real tokens are recorded.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const L = require('../e2e/lib');
assert(process.env.ERP_E2E_DISPOSABLE === 'true');
assert(['localhost', '127.0.0.1'].includes(new URL(L.URL).hostname));
assert(fs.existsSync(path.join(process.env.PERF_SAMPLE_DATA || '', '.performance-sample')));
assert(process.env.PERF_OUT);
const ru = JSON.parse(fs.readFileSync(path.join(__dirname, '../../mobile/lib/l10n/app_ru.arb')));
(async () => {
  const browser = await L.launch();
  try {
    const context = await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
    await context.addInitScript(() => {
      for (const id of ['dashboard','products','sales','inventory'])
        localStorage.setItem(`flutter.guide.${id}.done`, 'true');
      localStorage.setItem('flutter.language', JSON.stringify('ru'));
    });
    const page = await context.newPage();
    page.setDefaultTimeout(20000);
    let mode = 'online';
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/api/v1/**', async route => {
      if (mode === 'offline') return route.abort('internetdisconnected');
      if (mode === 'revoked') return route.fulfill({status:401,contentType:'application/json',
        body:JSON.stringify({error:{code:'token_not_valid',message:'Synthetic revoked session'}})});
      return route.continue();
    });
    const login = await context.request.post(new URL('/api/v1/local-test-login/',L.URL).href,{data:{role:'owner'}});
    const {access} = await login.json();
    await context.request.patch(new URL('/api/v1/me/',L.URL).href,
      {headers:{Authorization:`Bearer ${access}`},data:{preferred_language:'ru'}});
    await L.boot(page);
    await L.clickLabel(page,'Войти',{which:'last',wait:300});
    await L.clickLabel(page,'Владелец',{wait:1200});
    const money = () => page.waitForFunction(() => [...document.querySelectorAll('flt-semantics')]
      .some(n => /0,00.*TMT/.test(n.getAttribute('aria-label') || n.textContent || '')));
    await money();
    mode = 'offline';
    await page.reload({waitUntil:'domcontentloaded'});
    await page.waitForFunction(() => {
      document.querySelector('flt-semantics-placeholder')?.click();
      return [...document.querySelectorAll('flt-semantics')].some(n =>
        (n.getAttribute('aria-label') || n.textContent || '').includes('Нет связи с сервером'));
    });
    assert.match(await L.text(page), /Sample Owner/);
    assert.doesNotMatch(await L.text(page), /0,00.*TMT/);
    await page.getByRole('button',{name:ru.retry,exact:true}).waitFor({state:'visible'});
    await page.screenshot({path:`${process.env.PERF_OUT}.offline.png`});
    mode = 'online';
    await page.getByRole('button',{name:ru.retry,exact:true}).click();
    await money();
    mode = 'revoked';
    await page.reload({waitUntil:'domcontentloaded'});
    await page.waitForFunction(() => {
      document.querySelector('flt-semantics-placeholder')?.click();
      return [...document.querySelectorAll('flt-semantics')].some(n =>
        (n.getAttribute('aria-label') || n.textContent || '').trim() === 'Войти');
    });
    assert.doesNotMatch(await L.text(page), /0,00.*TMT/);
    // Revocation removes the persisted snapshot too: a second offline launch has no old identity.
    mode = 'offline';
    await page.reload({waitUntil:'domcontentloaded'});
    await page.waitForFunction(() => {
      document.querySelector('flt-semantics-placeholder')?.click();
      return [...document.querySelectorAll('flt-semantics')].some(n =>
        (n.getAttribute('aria-label') || n.textContent || '').trim() === 'Войти');
    });
    assert.doesNotMatch(await L.text(page), /Sample Owner/);
    assert.deepEqual(errors, []);
    fs.writeFileSync(process.env.PERF_OUT, JSON.stringify({browser:browser.version(),
      offlineApi:'locked shell, no private figures',reconnect:'passed',revocation:'signed out and cache removed',errors,
      note:'API offline with runtime assets available; not first-ever offline PWA installation or physical-device acceptance.'},null,2)+'\n');
    console.log('PASS offline API, reconnect, revoked session and cleared-cache relaunch');
    await context.close();
  } finally {await browser.close();}
})().catch(error => {console.error(error.stack);process.exitCode=1;});
