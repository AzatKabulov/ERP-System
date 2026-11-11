const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const L = require('../e2e/lib');
assert(process.env.ERP_E2E_DISPOSABLE === 'true');
assert(['localhost','127.0.0.1'].includes(new URL(L.URL).hostname));
assert(fs.existsSync(path.join(process.env.PERF_SAMPLE_DATA || '', '.performance-sample')));
assert(process.env.PERF_OUT);
const scheme = process.env.PERF_SCHEME || 'light';
assert(['light','dark'].includes(scheme));
(async () => {
  const browser = await L.launch();
  try {
    const context = await browser.newContext({viewport:{width:390,height:844},hasTouch:true,isMobile:true,
      userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1'});
    const page=await context.newPage();page.setDefaultTimeout(15000);
    await context.addInitScript(scheme => {
      for(const id of ['dashboard','products','sales','inventory']) localStorage.setItem(`flutter.guide.${id}.done`,'true');
      localStorage.setItem('flutter.language',JSON.stringify('ru'));
      localStorage.setItem('flutter.theme.mode',JSON.stringify(scheme));
    }, scheme);
    const login=await context.request.post(new URL('/api/v1/local-test-login/',L.URL).href,{data:{role:'owner'}});
    const {access}=await login.json();
    await context.request.patch(new URL('/api/v1/me/',L.URL).href,{headers:{Authorization:`Bearer ${access}`},data:{preferred_language:'ru'}});
    const errors=[];page.on('pageerror',error=>errors.push(error.message));
    await L.boot(page);await L.clickLabel(page,'Войти',{which:'last',wait:300});
    await L.clickLabel(page,'Владелец',{wait:1000});
    await L.clickLabel(page,'Товары',{role:'button',wait:800});
    const documents=[];const auth=[];
    page.on('request',request=>{
      const url=new URL(request.url());
      if(request.isNavigationRequest() && request.resourceType()==='document') documents.push(url.pathname);
      if(url.pathname.includes('/auth/') || url.pathname==='/api/v1/me/') auth.push(url.pathname);
    });
    const samples=[];
    for(let i=0;i<20;i++) {
      const historyBefore=await page.evaluate(()=>history.length);
      await page.getByRole('button',{name:/PERF-0000/}).first().click();
      await page.waitForFunction(()=>location.hash.includes('/s'));
      if(i===0) {
        await page.waitForTimeout(500);
        await page.screenshot({path:`${process.env.PERF_OUT}.detail.png`});
      }
      const historyOpen=await page.evaluate(()=>history.length);
      assert(historyOpen>=historyBefore,'History moved backwards on push');
      const start=Date.now();
      await page.goBack();
      await page.waitForFunction(()=> {
        const text=[...document.querySelectorAll('flt-semantics')].map(n=>n.getAttribute('aria-label')||n.textContent||'').join(' ');
        return !text.includes('Карточка товара') && text.includes('Товары');
      });
      samples.push({round:i,backObservedMs:Date.now()-start,historyBefore,historyOpen});
      await page.waitForTimeout(100);
    }
    // An in-app Back must replace its detail URL, not add a stale history entry.
    for(let i=0;i<5;i++) {
      await page.getByRole('button',{name:/PERF-0000/}).first().click();
      await page.waitForFunction(()=>location.hash.includes('/s'));
      const opened = await page.evaluate(()=>history.length);
      await page.getByRole('button',{name:/Назад|Back/}).first().click();
      await page.waitForFunction(()=>!location.hash.includes('/s'));
      assert.equal(await page.evaluate(()=>history.length),opened,'In-app Back added stale history');
      await page.goBack();
      await page.waitForTimeout(150);
      assert(!new URL(page.url()).hash.includes('/s'),'Back restored an unavailable detail URL');
    }
    assert.deepEqual(documents,[],'Back reloaded the application document');
    assert.deepEqual(auth,[],'Back recreated the authenticated root');
    assert.deepEqual(errors,[]);
    await page.screenshot({path:`${process.env.PERF_OUT}.catalog.png`});
    fs.writeFileSync(process.env.PERF_OUT,JSON.stringify({browser:browser.version(),scheme,
      note:'20 same-document browser-back and 5 mixed in-app/browser-back cycles, iPhone viewport/UA; not physical Safari edge gesture or GPU FPS.',
      samples,documentRequests:documents.length,authenticationRequests:auth.length,errors},null,2)+'\n');
    console.log(JSON.stringify({cycles:samples.length,documentRequests:documents.length,authenticationRequests:auth.length,
      medianBackObservedMs:[...samples].map(s=>s.backObservedMs).sort((a,b)=>a-b)[10]}));
    await context.close();
  } finally {await browser.close();}
})().catch(error=>{console.error(error.message);process.exitCode=1;});
