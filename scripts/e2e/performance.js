// Chromium Playwright CLI benchmark. Sign in to the local web app in Russian,
// at 390 x 844, then run `playwright-cli -s=<session> run-code
// --filename scripts/e2e/performance.js`. Warm the pages once before comparing.
// Reports timing and endpoint names only: no credentials, tokens or payloads.
async page => {
  await page.getByRole('button', { name: 'Обзор', exact: true }).click();
  await page.waitForTimeout(1400);
  const cdp = await page.context().newCDPSession(page);
  const requests = [];
  const listener = request => {
    if (request.url().includes('/api/v1/') && !request.url().includes('/auth/')) {
      requests.push({
        path: new URL(request.url()).pathname.split('/').slice(5).join('/')
          .replace(/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}/gi, ':id'),
        ms: Math.round(request.timing().responseEnd),
      });
    }
  };
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  page.on('requestfinished', listener);
  await page.evaluate(() => {
    window.erpFrames = [];
    window.erpTasks = [];
    let last = performance.now();
    const tick = time => {
      window.erpFrames.push(time - last);
      last = time;
      window.erpRafId = requestAnimationFrame(tick);
    };
    window.erpRafId = requestAnimationFrame(tick);
    window.erpObserver = new PerformanceObserver(list => {
      window.erpTasks.push(...list.getEntries().map(entry => entry.duration));
    });
    window.erpObserver.observe({ entryTypes: ['longtask'] });
  });
  const start = Date.now();
  try {
    for (const name of ['Товары', 'Продажи', 'Склад', 'Обзор', 'Товары']) {
      await page.getByRole('button', { name, exact: true }).click();
      await page.waitForTimeout(1300);
    }
    const metrics = await page.evaluate(() => {
      const frames = window.erpFrames.filter(value => value > 0).sort((a, b) => a - b);
      return {
        frames: frames.length,
        frameP95: Math.round(frames[Math.floor(frames.length * 0.95)]),
        framesOver33ms: frames.filter(value => value > 33).length,
        longTasks: window.erpTasks.length,
        longTaskMs: Math.round(window.erpTasks.reduce((a, b) => a + b, 0)),
        maxTaskMs: Math.round(Math.max(0, ...window.erpTasks)),
      };
    });
    return { ...metrics, elapsedMs: Date.now() - start, requests };
  } finally {
    await page.evaluate(() => {
      cancelAnimationFrame(window.erpRafId);
      window.erpObserver.disconnect();
    });
    page.off('requestfinished', listener);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 1 });
    await cdp.detach();
  }
}
