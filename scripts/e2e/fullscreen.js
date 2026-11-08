// Real Flutter release build + disposable local API. Insets below are explicitly
// simulated CSS values, not a claim to have tested an installed iPhone PWA.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const {chromium, webkit} = require(process.env.PLAYWRIGHT_MODULE || '/opt/node-tools/node_modules/playwright');
const origin = process.env.E2E_WEB_URL;
if (process.env.ERP_E2E_DISPOSABLE !== 'true' || !origin ||
    !['localhost', '127.0.0.1'].includes(new URL(origin).hostname)) {
  throw Error('Use a disposable localhost API with ERP_E2E_DISPOSABLE=true and E2E_WEB_URL.');
}
const output = process.env.E2E_OUTPUT_DIR || '/tmp/erp-fullscreen-browser';

async function pane(page) {
  return page.locator('flutter-view').evaluate(el => {
    const r=el.getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height};
  });
}
async function scrollPage(page, delta) {
  if(page.context().browser().browserType().name()!=='webkit') {
    await page.mouse.wheel(0,delta); return;
  }
  // Playwright mobile WebKit has no wheel API. Send a browser pointer-touch
  // gesture through Flutter's normal input binding, never invoke Dart handlers.
  await page.evaluate(async delta=>{
    const x=innerWidth/2;
    const start=delta>0?innerHeight*.75:innerHeight*.3;
    const distance=Math.min(Math.abs(delta),innerHeight*.5)*(delta>0?-1:1);
    const target=document.elementFromPoint(x,start)||document.body;
    const emit=(type,y,buttons)=>target.dispatchEvent(new PointerEvent(type,{
      bubbles:true,composed:true,cancelable:true,pointerId:71,pointerType:'touch',
      isPrimary:true,clientX:x,clientY:y,button:0,buttons,pressure:buttons?.5:0,
    }));
    emit('pointerdown',start,1);
    for(let i=1;i<=16;i++) {
      await new Promise(requestAnimationFrame);
      emit('pointermove',start+distance*i/16,1);
    }
    emit('pointerup',start+distance,0);
  },delta);
}
async function safeClick(page, locator) {
  const size=page.viewportSize();
  for(let attempt=0;attempt<12;attempt++) {
    const box=await locator.boundingBox().catch(()=>null);
    if(box && box.y>=0 && box.y+box.height/2<size.height-2) {
      await page.touchscreen.tap(box.x+box.width/2,box.y+box.height/2);
      return;
    }
    await page.mouse.move(size.width/2,size.height/2);
    await scrollPage(page,box&&box.y<0?-300:300);
    await page.waitForTimeout(120);
  }
  throw Error('Could not reach control: '+locator);
}
async function run() {
  await fs.mkdir(output,{recursive:true});
  const results=[];
  for (const engine of ['chromium','webkit']) {
    const browser=await (engine==='webkit'?webkit.launch({headless:true}):chromium.launch({headless:true,
      executablePath:process.env.CHROMIUM_PATH || '/opt/pw-browsers/chromium'}));
    try {
      for (const dark of [false,true]) {
        const name=`${engine}-${dark?'dark':'light'}`;
        const context=await browser.newContext({viewport:{width:393,height:852},deviceScaleFactor:3,
          isMobile:true,hasTouch:true,reducedMotion:'reduce'});
        const page=await context.newPage();
        const errors=[];
        page.on('pageerror',e=>errors.push(e.message));
        page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
        await page.addInitScript(({dark})=>{
          localStorage.setItem('flutter.theme.mode',JSON.stringify(dark?'dark':'light'));
          for(const id of ['dashboard','products','sales','inventory'])localStorage.setItem(`flutter.guide.${id}.done`,'true');
          document.addEventListener('DOMContentLoaded',()=>{
            const style=document.createElement('style');
            style.id='qa-simulated-insets';
            style.textContent='#erp-safe-area-probe {padding:59px 0px 34px 0px !important;}';
            document.head.appendChild(style);
            dispatchEvent(new Event('resize'));
          });
        },{dark});
        await page.goto(new URL('/fs/',origin).href);
        await page.waitForSelector('flt-semantics-placeholder',{state:'attached'});
        await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
        await page.waitForFunction(()=>window.erpSafeTop?.()===59);
        await page.getByRole('button',{name:'Войти',exact:true}).waitFor();
        assert.deepEqual(await pane(page),{x:0,y:0,width:393,height:852});
        assert.equal(await page.locator('meta[name="apple-mobile-web-app-status-bar-style"]').getAttribute('content'),'black-translucent');
        assert.equal(await page.locator('#erp-fs-diagnostic').evaluate(el=>getComputedStyle(el).pointerEvents),'none');
        await page.screenshot({path:path.join(output,`${name}-sign-in.png`)});
        await safeClick(page,page.getByRole('button',{name:'Войти',exact:true}));
        await safeClick(page,page.getByRole('button',{name:'Владелец',exact:true}));
        await page.getByRole('button',{name:'Товары',exact:true}).waitFor();
        await safeClick(page,page.getByRole('button',{name:'Обзор',exact:true}));
        await page.waitForFunction(()=>[...document.querySelectorAll('flt-semantics')].some(n=>
          ((n.getAttribute('aria-label')||n.textContent||'')).includes('Продажи за месяц')));
        const topBefore=await page.screenshot({clip:{x:0,y:0,width:393,height:59}});
        await page.mouse.move(200,400);
        await scrollPage(page,450);
        await page.waitForTimeout(250);
        const topAfter=await page.screenshot({clip:{x:0,y:0,width:393,height:59}});
        assert(!topBefore.equals(topAfter),'scrolling changes the rendered clock-area pixels');
        await fs.writeFile(path.join(output,`${name}-scroll-before.png`),topBefore);
        await fs.writeFile(path.join(output,`${name}-scroll-after.png`),topAfter);
        await safeClick(page,page.getByRole('button',{name:'Товары',exact:true}));
        await page.getByRole('textbox').first().waitFor();
        // Reproduce the engine replacing/altering viewport metadata; repair is
        // idempotent and keeps other viewport settings instead of shifting DOM.
        await page.evaluate(()=>document.querySelector('meta[name="viewport"]').content='width=device-width, initial-scale=1.0, viewport-fit=auto');
        await page.waitForFunction(()=>document.querySelector('meta[name="viewport"]').content.includes('viewport-fit=cover'));
        assert.deepEqual(await pane(page),{x:0,y:0,width:393,height:852});
        await safeClick(page,page.getByRole('button',{name:'Как это работает',exact:true}));
        await page.getByRole('button',{name:'Назад',exact:true}).waitFor();
        assert.deepEqual(await pane(page),{x:0,y:0,width:393,height:852});
        await safeClick(page,page.getByRole('button',{name:'Назад',exact:true}));
        await page.getByRole('textbox').first().waitFor();
        const navigation=page.getByRole('button',{name:'Ещё',exact:true}).last();
        await safeClick(page,navigation);
        await safeClick(page,page.getByRole('button',{name:'Настройки',exact:true}));
        await safeClick(page,page.getByRole('button',{name:dark?'Светлая':'Тёмная',exact:true}));
        await page.waitForFunction(expected=>getComputedStyle(document.documentElement).backgroundColor===expected,
          dark?'rgb(238, 241, 248)':'rgb(9, 12, 22)');
        assert.equal(await page.locator('meta[name="apple-mobile-web-app-status-bar-style"]').getAttribute('content'),'black-translucent');
        await page.waitForTimeout(500); // let the existing Material theme transition finish
        await page.screenshot({path:path.join(output,`${name}-switched.png`)});
        // Live orientation/inset updates without a new document/app restart.
        await page.setViewportSize({width:852,height:393});
        await page.evaluate(()=>{
          document.querySelector('#qa-simulated-insets').textContent='#erp-safe-area-probe {padding:0px 59px 21px 59px !important;}';
          dispatchEvent(new Event('orientationchange')); dispatchEvent(new Event('resize'));
        });
        await page.waitForFunction(()=>window.erpSafeTop()===0&&window.erpSafeLeft()===59&&window.erpSafeBottom()===21);
        await page.waitForFunction(()=>document.querySelector('flutter-view').getBoundingClientRect().width===852);
        assert.deepEqual(await pane(page),{x:0,y:0,width:852,height:393});
        assert.deepEqual(errors,[]);
        results.push({name,simulatedInsets:true,paneOrigin:[0,0],launchStyle:'black-translucent',themeSwitch:true,
          viewportRepair:true,scrollChangesTopPixels:true,topAndBottomTaps:true,orientationUpdate:true,errors});
        console.log(`PASS ${name}: full-size canvas, viewport repair, top/back/bottom taps, runtime theme and orientation`);
        await context.close();
      }
      const context=await browser.newContext({viewport:{width:393,height:852}});
      const page=await context.newPage();
      await page.goto(origin);
      await page.waitForSelector('flt-glass-pane',{state:'attached'});
      assert.equal(await page.evaluate(()=>window.erpFullScreen===true),false);
      assert.equal(await page.locator('#erp-fs-diagnostic').count(),0);
      results.push({name:`${engine}-normal`,fullScreen:false,diagnostic:false});
      await context.close();
    } finally {await browser.close();}
  }
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify(results,null,2));
}
run().catch(error=>{console.error(error);process.exitCode=1;});
