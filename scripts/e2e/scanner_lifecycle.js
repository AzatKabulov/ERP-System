// Keep references to ALL getUserMedia streams, even after their video DOM is removed.
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const L = require('./lib');
if (process.env.ERP_E2E_DISPOSABLE !== 'true' || !process.env.E2E_CAMERA_VIDEO) {
  throw Error('Use a disposable local sample shop and an EAN-13 Y4M fixture.');
}
(async () => {
  const browser = await chromium.launch({executablePath:process.env.CHROMIUM_PATH,headless:true,
    args:['--use-fake-device-for-media-stream','--use-fake-ui-for-media-stream',
      `--use-file-for-fake-video-capture=${process.env.E2E_CAMERA_VIDEO}`]});
  try {
    const {page} = await L.newPage(browser, process.env.E2E_PHONE === 'true'
      ? {width:390,height:844} : {width:1440,height:900});
    // A successful scan must not rely on jsDelivr, unpkg or any other origin.
    const foreignRequests = [];
    await page.route('**/*', route => {
      if (new URL(route.request().url()).origin !== new URL(L.URL).origin) {
        foreignRequests.push(route.request().url()); return route.abort();
      }
      return route.continue();
    });
    await page.addInitScript(() => {
      window.scannerStreams = [];
      window.scannerStartDelay = 0;
      window.scannerDenyNext = false;
      // Exercise the same WASM fallback used by browsers without BarcodeDetector.
      delete window.BarcodeDetector;
      const original = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
      navigator.mediaDevices.getUserMedia = async (...args) => {
        if (window.scannerDenyNext) {
          window.scannerDenyNext = false;
          throw new DOMException('Denied for the synthetic test','NotAllowedError');
        }
        if (window.scannerStartDelay) await new Promise(resolve => setTimeout(resolve, window.scannerStartDelay));
        const stream = await original(...args); window.scannerStreams.push(stream); return stream;
      };
    });
    await L.boot(page);
    await L.clickLabel(page, 'Войти', {which:'last',wait:400});
    await L.clickLabel(page, 'Владелец', {wait:1300});
    await L.clickLabel(page, 'Склад');
    await L.clickLabel(page, 'Приёмка сканированием');
    await L.clickLabel(page, 'Сканировать товар и указать количество', {wait:100});
    assert.equal((await L.waitText(page, /4006381333931/, 60000)).ok, true);
    await page.waitForFunction(() => window.scannerStreams.length > 0 &&
      window.scannerStreams.every(s => s.getTracks().every(t => t.readyState === 'ended')));
    console.log('PASS: decoded scanner releases all tracks.');
    await L.clickLabel(page, 'Отмена');
    await page.evaluate(() => { window.scannerStartDelay = 500; });
    // Exit before asynchronous camera/decoder startup completes, then open again.
    for (let i=0; i<2; i++) {
      const expected = await page.evaluate(() => window.scannerStreams.length + 1);
      await L.clickLabel(page, 'Сканировать товар и указать количество', {wait:0});
      await page.waitForTimeout(60);
      await L.clickLabel(page, 'Назад', {wait:0});
      await page.waitForFunction(expected => window.scannerStreams.length >= expected &&
        window.scannerStreams.every(s => s.getTracks().every(t => t.readyState === 'ended')), expected, {timeout:15000});
    }
    await page.waitForFunction(() => window.scannerStreams.every(s =>
      s.getTracks().every(t => t.readyState === 'ended')), null, {timeout:15000});
    console.log('PASS: decoded scan and early exits stop all captured camera tracks, including detached video streams.');

    // The same camera must find catalog and sales results; scanning never adds
    // to a cart or posts a sale. Seed only this explicitly disposable shop.
    const login = await page.request.post(new URL('/api/v1/local-test-login/',L.URL).href,
      {data:{role:'owner'}});
    assert.equal(login.status(),200);
    const {access} = await login.json();
    const headers = {Authorization:`Bearer ${access}`};
    const me = await (await page.request.get(new URL('/api/v1/me/',L.URL).href,{headers})).json();
    const base = `/api/v1/businesses/${me.memberships[0].business.id}`;
    const url = suffix => new URL(base+suffix,L.URL).href;
    const lookup = await page.request.get(url('/barcodes/lookup/?code=4006381333931'),{headers});
    let product;
    if (lookup.status()===200) product=await lookup.json();
    else {
      assert.equal(lookup.status(),404);
      const units=await (await page.request.get(url('/units/'),{headers})).json();
      const created=await page.request.post(url('/products/'),{headers,data:{
        sku:`CAMERA-${Date.now()}`,name:'Колодка камера ÄŇŞ',unit:units.results[0].id,
        price_amount:'125.50',price_currency:'TMT',barcodes:['4006381333931']}});
      assert.equal(created.status(),201);product=await created.json();
    }
    await page.evaluate(() => {window.scannerStartDelay=0;});
    await L.clickLabel(page,'Назад');
    for (const destination of ['Товары','Продажи']) {
      await L.clickLabel(page,destination,{role:'button'});
      await L.clickLabel(page,'Сканировать камерой',{wait:100,role:'button'});
      assert.equal((await L.waitText(page,new RegExp(product.name),15000)).ok,true);
      await page.waitForFunction(() => window.scannerStreams.every(s =>
        s.getTracks().every(t=>t.readyState==='ended')));
      if (destination==='Продажи') assert.match(await L.text(page),/Корзина пуста/);
    }
    const sales=await (await page.request.get(url('/sales/'),{headers})).json();
    assert.equal(sales.count,0);
    console.log('PASS: camera finds catalog and sales results; cart stays empty and no sale is created.');
    if (process.env.E2E_PHOTO_FIXTURE) {
      await page.evaluate(()=>{window.scannerDenyNext=true;});
      await L.clickLabel(page,'Сканировать камерой',{role:'button'});
      assert.equal((await L.waitText(page,/Нет доступа к камере/,15000)).ok,true);
      await L.clickLabel(page,'Выбрать фото штрихкода');
      const [chooser]=await Promise.all([
        page.waitForEvent('filechooser'),
        L.clickLabel(page,'Выбрать фото штрихкода',{wait:0}),
      ]);
      await chooser.setFiles(process.env.E2E_PHOTO_FIXTURE);
      assert.equal((await L.waitText(page,new RegExp(product.name),15000)).ok,true);
      assert.match(await L.text(page),/Корзина пуста/);
      await page.waitForFunction(()=>window.scannerStreams.every(s=>
        s.getTracks().every(t=>t.readyState==='ended')));
      console.log('PASS: denied live camera offers local photo decoding; no stale camera tracks or cart additions.');
    }
    assert.deepEqual(foreignRequests, [], 'scanner tried to fetch a third-party resource');
    console.log('PASS: camera decoder works with all third-party resources blocked.');
  } finally { await browser.close(); }
})().catch(e => {console.error(e.message); process.exitCode=1;});
