// Same-origin, local-only photo fallback for browsers without a live camera origin.
(() => {
  const base = new URL('.', document.currentScript.src);
  let loading;
  function decoder() {
    if (window.ZXingWASM) return Promise.resolve(window.ZXingWASM);
    if (loading) return loading;
    loading = new Promise((resolve, reject) => {
      const id = 'mobile-scanner-zxing-wasm';
      let script = document.getElementById(id);
      const owned = !script;
      script ||= document.createElement('script');
      const timer = setTimeout(() => fail(), 15000);
      function finish() {
        clearTimeout(timer);
        script.removeEventListener('load', success);
        script.removeEventListener('error', fail);
      }
      function success() {
        finish();
        if (window.ZXingWASM) resolve(window.ZXingWASM);
        else { loading = null; reject(Error('Decoder missing')); }
      }
      function fail() {
        finish();
        if (owned) script.remove();
        loading = null;
        reject(Error('Decoder unavailable'));
      }
      script.addEventListener('load', success);
      script.addEventListener('error', fail);
      if (owned) {
        script.id = id;
        script.src = new URL('zxing-wasm-3.1.3/reader.js', base).href;
        document.head.appendChild(script);
      }
    });
    return loading;
  }
  window.erpReadBarcodePhoto = async bytes => {
    if (!bytes.length || bytes.length > 12 * 1024 * 1024) throw Error('Invalid image size');
    const reader = await decoder();
    try {
      const results = await reader.readBarcodesFromImageFile(new Blob([bytes]), {
        formats: ['EAN13', 'EAN8', 'UPCA', 'UPCE', 'Code128', 'Code39', 'ITF', 'ITF14', 'QRCode'],
        tryHarder: true, maxNumberOfSymbols: 8,
      });
      return [...new Set(results.filter(r => r.isValid && r.text?.trim()).map(r => r.text.trim()))];
    } catch (error) {
      reader.purgeZXingModule();
      throw error;
    }
  };
})();
