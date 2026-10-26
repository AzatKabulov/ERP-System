// Browser webcam smoke check against a disposable sample shop.
// E2E_CAMERA_VIDEO points to a Y4M video containing EAN-13 4006381333931.
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const L = require('./lib.js');
if (process.env.ERP_E2E_DISPOSABLE !== 'true' || !process.env.ERP_SAMPLE_PASSWORD || !process.env.E2E_CAMERA_VIDEO) {
  throw new Error('Use a disposable sample shop, ERP_SAMPLE_PASSWORD and E2E_CAMERA_VIDEO.');
}
(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH,
    headless: true,
    args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream',
      `--use-file-for-fake-video-capture=${process.env.E2E_CAMERA_VIDEO}`],
  });
  try {
    const { page, problems } = await L.newPage(browser);
    page.on('requestfailed', request => console.log('Request failed:', request.url(), request.failure()?.errorText));
    await L.boot(page);
    await L.fill(page, '^Логин$', 'owner');
    await L.fill(page, '^Пароль$', process.env.ERP_SAMPLE_PASSWORD);
    await L.clickLabel(page, 'Войти', { which: 'last', wait: 1800 });
    await L.clickLabel(page, 'Склад');
    await L.clickLabel(page, 'Приёмка сканированием');
    await L.clickLabel(page, 'Сканировать товар и указать количество');
    const decoded = await L.expectText(page, 'webcam decodes the EAN-13 and opens quantity entry', /4006381333931/, 60000);
    if (!decoded) {
      console.log('Browser problems:', problems);
      console.log('Camera state:', await page.evaluate(() => [...document.querySelectorAll('video')].map(v => ({width:v.videoWidth,height:v.videoHeight,paused:v.paused,ready:v.readyState,time:v.currentTime,tracks:v.srcObject?.getTracks().map(t => ({state:t.readyState,settings:t.getSettings()}))}))));
      await page.screenshot({path:'/tmp/erp-webcam-debug.png'});
    }
    assert.equal(decoded, true);
    assert.match(await L.text(page), /Количество/);
    await page.waitForFunction(() => [...document.querySelectorAll('video')].every(video =>
      !video.srcObject || video.srcObject.getTracks().every(track => track.readyState === 'ended')),
      null, {timeout: 5000});
    await L.clickLabel(page, 'Отмена');
    assert.match(await L.text(page), /4006381333931/);
    console.log('PASS: browser webcam decoding and return to the intake draft; no stock posted.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
