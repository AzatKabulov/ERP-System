// Browser receiving after a scanned/typed code; real disposable stock API, synthetic enrichment.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const L = require('./lib');
if (process.env.ERP_E2E_DISPOSABLE !== 'true') throw Error('Disposable shop required');
if (process.env.E2E_SCANNER_ONLY !== 'true') execFileSync(process.execPath, [path.join(__dirname, 'store_day.js')], {stdio:'inherit',env:process.env});
const ru = JSON.parse(fs.readFileSync(path.join(__dirname,'../../mobile/lib/l10n/app_ru.arb')));
const out = process.env.E2E_OUT || '/tmp/erp-scanner-browser';
const delay = ms => new Promise(r=>setTimeout(r,ms));
const gtin = n => {
  const body = String(n).padStart(12,'0');
  const sum = [...body].reverse().reduce((sum,c,i)=>sum+Number(c)*(i%2?1:3),0);
  return body + String((10-sum%10)%10);
};
(async()=>{
  const login=await fetch(new URL('/api/v1/local-test-login/',L.URL),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({role:'owner'})});
  assert.equal(login.status,200);
  const {access}=await login.json();
  const api=async (route, options={})=>{
    const r=await fetch(new URL(route,L.URL),{...options,headers:{Authorization:`Bearer ${access}`,'Content-Type':'application/json'}});
    assert.ok(r.ok,`API ${r.status} ${route}`);return r.json();
  };
  const me=await api('/api/v1/me/');
  await api('/api/v1/me/',{method:'PATCH',body:JSON.stringify({preferred_language:'ru'})});
  const base=`/api/v1/businesses/${me.memberships[0].business.id}`;
  const store=(await api(`${base}/locations/`)).results.find(l=>l.kind==='store').id;
  const codes=[gtin(981234560001),gtin(981234560002),gtin(981234560003)];
  const states=new Map([[codes[0],'found'],[codes[1],'miss'],[codes[2],'down']]);
  const browser=await L.launch();let active;
  try {
    const {ctx,page,problems}=await L.newPage(browser,{width:390,height:844});active=page;
    const expectedCatalogMisses=[];
    page.on('response', response=>{
      const url=new URL(response.url());
      if(response.status()===404 && url.pathname.endsWith('/barcodes/lookup/') && codes.includes(url.searchParams.get('code'))) expectedCatalogMisses.push(url.searchParams.get('code'));
    });
    await ctx.addInitScript(({user,business,store})=>{
      for(const id of ['dashboard','inventory','intake'])localStorage.setItem(`flutter.guide.${id}.done`,'true');
      localStorage.setItem('flutter.language',JSON.stringify('ru'));
      localStorage.setItem(`flutter.session.${user}.business`,JSON.stringify(business));
      localStorage.setItem(`flutter.session.${user}.location`,JSON.stringify(store));
    },{user:me.user.id,business:me.memberships[0].business.id,store});
    await page.route('**/barcodes/info/?**',async route=>{
      const code=new URL(route.request().url()).searchParams.get('code');
      const state=states.get(code);if(!state)return route.continue();
      await delay(1600);
      await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({code,found:state==='found',unavailable:state==='down',name:state==='found'?'QA Oil filter':'',brand:state==='found'?'QA Maker':'',category:'',quantity:'',source:'Synthetic browser fixture'})});
    });
    await L.boot(page);
    await L.clickLabel(page,ru.signInAction,{which:'last',wait:300});
    await L.clickLabel(page,'Владелец',{wait:1100});
    await L.clickLabel(page,ru.inventory,{role:'button',wait:500});
    await L.clickLabel(page,ru.intakeScanShort,{role:'button',wait:500});
    const scan=async code=>{
      if (!(await L.text(page)).includes(ru.intakeTitle)) await L.clickLabel(page,ru.intakeScanShort,{role:'button',wait:500});
      await L.fill(page,'^Код товара$',code);
      await page.keyboard.press('Enter');await delay(300);
      assert.match(await L.text(page),/Ищем товар по штрихкоду/);
      await page.screenshot({path:path.join(out,`scanner-${states.get(code)}-loading.png`)});
      await delay(1900);
    };
    const product=async code=>(await api(`${base}/products/?q=${code}`)).results.find(p=>p.sku===code);
    const receive=async()=>{
      await L.clickLabel(page,ru.intakeSubmit,{role:'button',wait:400,bottomInset:140});
      await L.clickLabel(page,ru.confirm,{role:'button',wait:800});
    };
    const value = async pattern => {
      // Flutter paints unfocused values on canvas; focus the real editor before reading it.
      for (let attempt=0;attempt<10;attempt++) {
        const box=await page.evaluate(pattern=>{
          const el=[...document.querySelectorAll('input,textarea')].find(el=>new RegExp(pattern).test(el.getAttribute('aria-label')||''));
          if(!el)return null;const r=el.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};
        },pattern);
        assert.ok(box,`No field ${pattern}`);
        if(box.y<60 || box.y>704){await page.mouse.move(195,420);await page.mouse.wheel(0,box.y<60?-300:300);await delay(300);continue;}
        await page.mouse.click(box.x,box.y);await delay(350);
        return page.evaluate(()=>document.activeElement?.value);
      }
      throw Error(`Could not focus ${pattern}`);
    };
    await scan(codes[0]);
    assert.equal(await value('^Название товара$'),'QA Maker QA Oil filter');
    await L.fill(page,'^Количество$','50');
    await page.screenshot({path:path.join(out,'scanner-found-form.png')});
    await L.clickLabel(page,ru.save,{role:'button',wait:700,bottomInset:12});
    const found=await product(codes[0]);assert.ok(found);
    assert.match((await api(`${base}/products/${found.id}/?location=${store}`)).stock.on_hand,/^0(?:\.0+)?$/);
    await receive();
    assert.equal((await api(`${base}/products/${found.id}/?location=${store}`)).stock.on_hand,'50.000');
    await scan(codes[1]);
    assert.match(await L.text(page),/Товар не найден/);
    await L.fill(page,'^Название товара$','QA Unknown filter');
    await L.clickLabel(page,ru.save,{role:'button',wait:700,bottomInset:12});
    const manualCode=await product(codes[1]);assert.ok(manualCode);
    const manualCodeDetail=await api(`${base}/products/${manualCode.id}/`);
    assert.ok(manualCodeDetail.barcodes.includes(codes[1]));
    await receive();
    assert.equal((await api(`${base}/products/${manualCode.id}/?location=${store}`)).stock.on_hand,'1.000');
    await scan(codes[2]);
    assert.match(await L.text(page),/Не удалось проверить интернет/);
    await L.fill(page,'^Название товара$','QA Preserve typed name');
    states.set(codes[2],'found');
    await L.clickLabel(page,ru.retry,{role:'button',wait:2100,bottomInset:12});
    assert.equal(await value('^Название товара$'),'QA Preserve typed name');
    assert.equal(await product(codes[2]),undefined,'enrichment never saves by itself');
    await L.clickLabel(page,ru.cancel,{role:'button',wait:400,bottomInset:12});
    const normal404='console.error: Failed to load resource: the server responded with a status of 404 (Not Found)';
    assert.equal(expectedCatalogMisses.length,3,'the three unknown local barcodes produce the expected API misses');
    assert.equal(problems.filter(p=>p===normal404).length,expectedCatalogMisses.length,'no unexplained missing resources');
    const unexpected=problems.filter(p=>p!==normal404 && !p.includes('WebGL: non-portable extension enabled: WEBGL_polygon_mode'));
    assert.deepEqual(unexpected,[]);
    fs.writeFileSync(path.join(out,'scanner-results.json'),JSON.stringify({viewport:[390,844],camera:'not exercised; decoded code entered through existing input',enrichment:'synthetic HTTP replies',loading:true,foundPrefill:true,quantity50:true,unknownCodeRetained:true,unavailableRetryPreservesName:true,automaticStockWrite:false},null,2)+'\n');
    console.log('PASS browser receiving: loading, exact code, prefilled form, quantity 50, unknown manual entry, unavailable/retry without data loss');
    await ctx.close();
  } catch(error){if(active&&!active.isClosed()){await active.screenshot({path:path.join(out,'scanner-failure.png')});fs.writeFileSync(path.join(out,'scanner-failure.txt'),await L.text(active));}throw error;}
  finally{await browser.close();}
})().catch(e=>{console.error(e.stack);process.exitCode=1;});
