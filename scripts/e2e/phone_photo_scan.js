// Real HTTP private-IP origin: do not use localhost or bypass browser security.
const assert = require('node:assert/strict');
const L = require('./lib');
if (process.env.ERP_E2E_DISPOSABLE !== 'true' || !process.env.E2E_PHOTO_FIXTURE ||
    !process.env.E2E_BLANK_PHOTO_FIXTURE || !process.env.E2E_WEB_URL) {
  throw Error('Use a disposable shop, a private HTTP URL and synthetic photo fixtures.');
}
(async () => {
  const browser = await L.launch();
  let activePage;
  try {
    const {page,problems} = await L.newPage(browser,{width:390,height:844});
    activePage=page;
    const foreign = [], photosUploaded = [];
    await page.route('**/*', route => {
      const url = new URL(route.request().url());
      if (url.origin !== new URL(L.URL).origin && url.protocol !== 'data:') {
        foreign.push(url.origin);return route.abort();
      }
      if (route.request().method()==='POST' && /\/photo\//.test(url.pathname)) photosUploaded.push(url.pathname);
      return route.continue();
    });
    const login=await page.request.post(new URL('/api/v1/local-test-login/',L.URL).href,{data:{role:'owner'}});
    assert.equal(login.status(),200);
    const {access}=await login.json();const headers={Authorization:`Bearer ${access}`};
    const me=await (await page.request.get(new URL('/api/v1/me/',L.URL).href,{headers})).json();
    const base=`/api/v1/businesses/${me.memberships[0].business.id}`;
    const url=suffix=>new URL(base+suffix,L.URL).href;
    const lookup=await page.request.get(url('/barcodes/lookup/?code=4006381333931'),{headers});
    if (lookup.status()!==200) {
      assert.equal(lookup.status(),404);
      const units=await (await page.request.get(url('/units/'),{headers})).json();
      const created=await page.request.post(url('/products/'),{headers,data:{
        sku:`PHOTO-${Date.now()}`,name:'Колодка фото ÄŇŞ',unit:units.results[0].id,
        price_amount:'125.50',price_currency:'TMT',barcodes:['4006381333931']}});
      assert.equal(created.status(),201);
    } else assert.equal((await lookup.json()).name,'Колодка фото ÄŇŞ');
    await L.boot(page);
    assert.equal(await page.evaluate(()=>window.isSecureContext),false);
    await L.clickLabel(page,'Войти',{which:'last',wait:300});
    await L.clickLabel(page,'Владелец',{wait:1200});
    const photo=async (fixture, camera=true) => {
      const [chooser]=await Promise.all([
        page.waitForEvent('filechooser'),
        L.clickLabel(page,camera?'Сфотографировать штрихкод':'Выбрать фото штрихкода',{wait:0}),
      ]);
      const capture=await chooser.element().getAttribute('capture');
      assert.equal(capture,camera?'environment':null);
      await chooser.setFiles(fixture);
    };
    await L.clickLabel(page,'Товары',{role:'button'});
    await L.clickLabel(page,'Сканировать камерой',{role:'button'});
    await photo(process.env.E2E_BLANK_PHOTO_FIXTURE);
    assert.equal((await L.waitText(page,/Штрихкод не найден/,20000)).ok,true);
    await photo(process.env.E2E_PHOTO_FIXTURE,false);
    assert.equal((await L.waitText(page,/Колодка фото ÄŇŞ/,20000)).ok,true);
    await L.clickLabel(page,'Продажи',{role:'button'});
    await L.clickLabel(page,'Сканировать камерой',{role:'button'});
    await photo(process.env.E2E_PHOTO_FIXTURE);
    assert.equal((await L.waitText(page,/Колодка фото ÄŇŞ/,20000)).ok,true);
    assert.match(await L.text(page),/Корзина пуста/);
    await L.clickLabel(page,'Склад',{role:'button'});
    await L.clickLabel(page,'Приёмка сканированием');
    await L.clickLabel(page,'Сканировать товар и указать количество');
    await photo(process.env.E2E_PHOTO_FIXTURE);
    await page.locator('input[aria-label="Количество"]').waitFor({state:'attached'});
    await L.fill(page,'^Количество$','50');
    await L.clickLabel(page,'Отмена');
    const sales=await (await page.request.get(url('/sales/'),{headers})).json();
    const stock=await (await page.request.get(url('/stock/'),{headers})).json();
    assert.equal(sales.count,0);assert.equal(stock.count,0);
    assert.deepEqual(foreign,[]);assert.deepEqual(photosUploaded,[]);
    // The local Django server sends its normal COOP header. Chromium explicitly
    // ignores that header on this deliberately insecure origin; keep that known
    // browser diagnostic visible, while still rejecting application errors.
    const policyWarning='console.error: The Cross-Origin-Opener-Policy header has been ignored, because the URL\'s origin was untrustworthy.';
    const expectedWarnings=problems.filter(p=>p.startsWith(policyWarning));
    assert.deepEqual(problems.filter(p=>!p.startsWith(policyWarning)),[]);
    if (expectedWarnings.length) console.log(`Expected insecure-origin COOP warnings: ${expectedWarnings.length}`);
    console.log('PASS: real insecure HTTP phone origin shows scanning; rear-photo capture, gallery, unreadable-photo retry, catalog/sales lookup and intake quantity form work with local WASM. No photo upload, sale, stock posting or third-party request.');
    await page.screenshot({path:'/tmp/erp-phone-photo-scanning.png'});
  } catch (error) {
    if (activePage) {
      await activePage.screenshot({path:'/tmp/erp-phone-photo-error.png'});
      console.error((await L.text(activePage)).slice(0,3000));
    }
    throw error;
  } finally {await browser.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
