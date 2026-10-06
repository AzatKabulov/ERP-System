// Helpers for the real-stack browser run (see README.md in this folder).
// Flutter web draws to a canvas, so the run drives the accessibility tree: it enables
// semantics, finds nodes by their label, clicks their centre and types into the real
// <input> elements. Nothing here is part of the app.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/opt/node-tools/node_modules/playwright');
const URL = process.env.E2E_WEB_URL || 'http://127.0.0.1:8080/';
const IGNORE = [/software WebGL/i, /GPU stall due to ReadPixels/i];
const results = [];
function check(name, ok, extra = '') {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? '  ' + extra : ''}`);
}
async function enableSemantics(page) {
  await page.evaluate(() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); });
  await page.waitForTimeout(1500);
}
async function text(page) {
  return page.evaluate(() =>
    [...document.querySelectorAll('[aria-label], flt-semantics')]
      .map((n) => (n.getAttribute('aria-label') || n.textContent || '').trim())
      .filter(Boolean).join(' | '));
}
async function waitText(page, regex, ms = 8000) {
  const end = Date.now() + ms;
  let t = '';
  while (Date.now() < end) {
    t = await text(page);
    if (regex.test(t)) return { ok: true, t };
    await page.waitForTimeout(400);
  }
  return { ok: false, t };
}
async function expectText(page, name, regex, ms) {
  const r = await waitText(page, regex, ms);
  check(name, r.ok, r.ok ? '' : `(never matched ${regex}) ${r.t.slice(0, 400)}`);
  return r.ok;
}
async function expectNoText(page, name, regex) {
  await page.waitForTimeout(600);
  const t = await text(page);
  check(name, !regex.test(t), regex.test(t) ? `(found ${regex})` : '');
}
// click a semantics node whose label (aria-label or text) equals/matches
async function clickLabel(page, label, opts = {}) {
  const { which = 'first', exact = true, wait = 900, role = null } = opts;
  const box = await page.evaluate(([label, which, exact, role]) => {
    const re = exact ? null : new RegExp(label);
    const nodes = [...document.querySelectorAll('flt-semantics')].filter((n) => {
      if (role && n.getAttribute('role') !== role) return false;
      const t = ((n.getAttribute('aria-label') || '').trim() || n.textContent.trim());
      return exact ? t === label : re.test(t);
    });
    // among several matches (a group and the control inside it) the smallest is the control
    const area = (e) => { const r = e.getBoundingClientRect(); return r.width * r.height; };
    const sorted = exact ? nodes : [...nodes].sort((a, b) => area(a) - area(b));
    const n = which === 'last' ? sorted[sorted.length - 1] : sorted[0];
    if (!n) return null;
    const r = n.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, [label, which, exact, role]);
  if (!box) throw new Error(`no accessible element labelled "${label}"`);
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(wait);
}
// focus the text field whose label matches, replace its content (and check it took)
async function fill(page, labelRegex, value) {
  for (let attempt = 1; attempt <= 3; attempt++) {
    const box = await page.evaluate((src) => {
      const re = new RegExp(src);
      const el = [...document.querySelectorAll('input, textarea')].find((e) => re.test(e.getAttribute('aria-label') || ''));
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    }, labelRegex);
    if (!box) throw new Error(`no text field labelled /${labelRegex}/`);
    await page.mouse.click(box.x, box.y);
    await page.waitForTimeout(450);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(value, { delay: 25 });
    await page.waitForTimeout(350);
    const typed = await page.evaluate(() => (document.activeElement && 'value' in document.activeElement) ? document.activeElement.value : null);
    if (typed === value) return;
    if (attempt === 3) throw new Error(`typing into /${labelRegex}/ did not take (got ${JSON.stringify(typed)})`);
  }
}
async function boot(page) {
  await page.goto(URL, { waitUntil: 'load' });
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await page.waitForTimeout(3500);
  await enableSemantics(page);
}
async function newPage(browser, viewport = { width: 1440, height: 900 }) {
  const ctx = await browser.newContext({ viewport });
  const page = await ctx.newPage();
  const problems = [];
  page.on('console', (m) => {
    if (!['error', 'warning'].includes(m.type())) return;
    if (IGNORE.some((r) => r.test(m.text()))) return;
    problems.push(`console.${m.type()}: ${m.text()}`);
  });
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  return { ctx, page, problems };
}
async function launch() {
  return chromium.launch({ executablePath: process.env.CHROMIUM_PATH || '/opt/pw-browsers/chromium', headless: true, args: ['--no-sandbox'] });
}
module.exports = { URL, results, check, enableSemantics, text, waitText, expectText, expectNoText, clickLabel, fill, boot, newPage, launch };
