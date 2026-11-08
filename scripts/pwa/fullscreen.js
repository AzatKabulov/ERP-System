/* Opt-in /fs/ host bridge. No layout transforms, touch interception or color sampling. */
(function () {
  'use strict';
  if (window.erpFullScreen !== true) return;
  var listeners = new Set();
  var safe = { top: 0, right: 0, bottom: 0, left: 0 };
  var probe;
  var queued = false;
  var repairResize = false;
  var lastTouch = '-';
  var diagnostic;

  function measure() {
    if (!probe) {
      probe = document.createElement('div');
      probe.id = 'erp-safe-area-probe';
      probe.setAttribute('aria-hidden', 'true');
      probe.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;width:0;height:0;' +
        'padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) ' +
        'env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px);';
      document.documentElement.appendChild(probe);
    }
    var style = getComputedStyle(probe);
    var changed = false;
    ['top', 'right', 'bottom', 'left'].forEach(function (side) {
      var value = parseFloat(style.getPropertyValue('padding-' + side)) || 0;
      value = Number.isFinite(value) ? Math.max(0, value) : 0;
      if (safe[side] !== value) { safe[side] = value; changed = true; }
    });
    if (changed) listeners.forEach(function (listener) { listener(); });
  }

  function updateDiagnostic() {
    if (!diagnostic) return;
    // In this engine glass-pane is only a platform-view host and can be 0x0.
    // The actual Flutter viewport is its parent flutter-view.
    var pane = document.querySelector('flt-glass-pane');
    var view = document.querySelector('flutter-view');
    var rect = view && view.getBoundingClientRect();
    var paneRect = pane && pane.getBoundingClientRect();
    var visual = window.visualViewport;
    diagnostic.textContent =
      'inner ' + innerWidth + 'x' + innerHeight + ' screen ' + screen.width + 'x' + screen.height +
      '\nvv ' + (visual ? Math.round(visual.width) + 'x' + Math.round(visual.height) +
        ' top ' + Math.round(visual.offsetTop) + ' scale ' + visual.scale.toFixed(2) : '-') +
      ' scrollY ' + Math.round(scrollY) +
      '\nsafe T/R/B/L ' + [safe.top, safe.right, safe.bottom, safe.left].join('/') +
      ' view ' + (rect ? [rect.x, rect.y, rect.width, rect.height].map(Math.round).join(',') : '-') +
      ' pane ' + (paneRect ? [paneRect.width, paneRect.height].map(Math.round).join('x') : '-') +
      '\ntouch ' + lastTouch + ' ' + (navigator.standalone || matchMedia('(display-mode: standalone)').matches ? 'standalone' : 'browser');
  }

  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () {
      queued = false;
      measure();
      updateDiagnostic();
      if (repairResize) {
        repairResize = false;
        // Flutter may have measured before the repaired viewport was laid out.
        // One coalesced notification; never resize/translate the drawing surface.
        dispatchEvent(new Event('resize'));
        requestAnimationFrame(function () { measure(); updateDiagnostic(); });
      }
    });
  }

  function coverViewport() {
    document.querySelectorAll('meta[name="viewport"]').forEach(function (meta) {
      var old = meta.content || '';
      var next = /viewport-fit\s*=/i.test(old)
        ? old.replace(/viewport-fit\s*=\s*[^,;\s]+/ig, 'viewport-fit=cover')
        : old + ', viewport-fit=cover';
      if (next !== old) { meta.content = next; repairResize = true; }
    });
    schedule();
  }

  window.erpSafeTop = function () { return safe.top; };
  window.erpSafeRight = function () { return safe.right; };
  window.erpSafeBottom = function () { return safe.bottom; };
  window.erpSafeLeft = function () { return safe.left; };
  window.erpObserveViewport = function (listener) { listeners.add(listener); };
  window.erpUnobserveViewport = function (listener) { listeners.delete(listener); };

  new MutationObserver(coverViewport).observe(document.head, {
    childList: true, subtree: true, attributes: true, attributeFilter: ['content', 'name']
  });
  coverViewport();
  measure();
  ['resize', 'orientationchange', 'pageshow'].forEach(function (event) {
    addEventListener(event, schedule, { passive: true });
  });
  document.addEventListener('visibilitychange', schedule);
  if (window.visualViewport) {
    visualViewport.addEventListener('resize', schedule, { passive: true });
    visualViewport.addEventListener('scroll', schedule, { passive: true });
  }

  function ready() {
    // Deliberately visible only in the test copy; it never intercepts a tap.
    diagnostic = document.createElement('div');
    diagnostic.id = 'erp-fs-diagnostic';
    diagnostic.setAttribute('aria-hidden', 'true');
    diagnostic.style.cssText = 'position:fixed;left:4px;bottom:4px;z-index:99999;' +
      'font:10px monospace;color:#0f0;background:rgba(0,0,0,.7);padding:3px 5px;' +
      'pointer-events:none;white-space:pre;max-width:calc(100vw - 8px);overflow:hidden;';
    document.body.appendChild(diagnostic);
    schedule();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready, { once: true });
  else ready();
  addEventListener('flutter-first-frame', schedule, { once: true });
  addEventListener('pointerdown', function (event) {
    lastTouch = Math.round(event.clientX) + ',' + Math.round(event.clientY);
    updateDiagnostic();
  }, { passive: true, capture: true });
}());
