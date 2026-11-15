// Explicit, on-device OCR; images never leave this device. No runtime CDN.
(() => {
  const base = new URL('ocr/', document.currentScript.src);
  let loading;
  let busy = false;
  function load() {
    if (window.Tesseract) return Promise.resolve(window.Tesseract);
    if (loading) return loading;
    loading = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      const timer = setTimeout(() => fail(), 15000);
      function fail() { clearTimeout(timer); script.remove(); loading = null; reject(Error('OCR unavailable')); }
      script.onload = () => { clearTimeout(timer); if (window.Tesseract) resolve(window.Tesseract); else fail(); };
      script.onerror = fail;
      script.src = new URL('tesseract.min.js', base).href;
      document.head.appendChild(script);
    });
    return loading;
  }
  window.erpReadLabelText = async bytes => {
    if (busy || !bytes.length || bytes.length > 12 * 1024 * 1024) throw Error('Invalid OCR request');
    busy = true;
    let worker;
    let timer;
    let expired = false;
    let objectUrl;
    try {
      const engine = await load();
      objectUrl = URL.createObjectURL(new Blob([bytes]));
      const image = new Image();
      image.src = objectUrl;
      await image.decode();
      if (!image.width || image.width * image.height > 16000000) throw Error('Image too large');
      const work = (async () => {
        worker = await engine.createWorker('eng', 1, {
          workerPath: new URL('worker.min.js', base).href,
          corePath: base.href, langPath: base.href,
          workerBlobURL: false, cacheMethod: 'none',
        });
        if (expired) { await worker.terminate(); throw Error('OCR expired'); }
        await worker.setParameters({ tessedit_pageseg_mode: '11' });
        const result = await worker.recognize(image);
        return (result.data.text || '').slice(0, 20000);
      })();
      const timeout = new Promise((_, reject) => {
        timer = setTimeout(() => { expired = true; reject(Error('OCR timeout')); }, 45000);
      });
      return await Promise.race([work, timeout]);
    } finally {
      clearTimeout(timer);
      expired = true;
      if (worker) await worker.terminate().catch(() => {});
      if (objectUrl) URL.revokeObjectURL(objectUrl);
      busy = false;
    }
  };
})();
