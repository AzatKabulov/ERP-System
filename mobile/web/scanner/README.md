# Bundled web barcode fallback

`mobile_scanner` 7.4.2 auto-selects the browser's BarcodeDetector or zxing-wasm
3.1.3. Keep that selection; serve its fallback from this application so phones do
not wait for jsDelivr or fail when the CDN is unavailable. These assets load only
when the camera needs the fallback, not during application startup.

Source: https://registry.npmjs.org/zxing-wasm/-/zxing-wasm-3.1.3.tgz

Published npm SHA-512 integrity (verified before extraction):
`sha512-3lC9BJk4fR5ZJxcGjb0hVnDFOW7KpLXHIebiBmVd4FDRQZVeObztoTKxRUPxlWwSgxrMRONK0u50hBD1aTYEKg==`

`reader.js` is `package/dist/iife/reader/index.js` followed by the clearly marked
ERP footer configuring `locateFile` to the same directory. The upstream code is
unchanged. `zxing_reader.wasm` is `package/dist/reader/zxing_reader.wasm` unchanged.
`SHA256SUMS` covers the files as shipped. Retain the MIT license and the Apache
license of zxing-cpp (upstream commit a17fd9dc65d6aa0dd2f660fdfca7a6a6613d938f).

When upgrading mobile_scanner, check its pinned web decoder version and public
configuration API, refresh these files and checksums, and run the real-browser
camera lifecycle check with third-party requests blocked. Never silently fetch
the newest decoder during a build. Camera access still requires trusted HTTPS
on a phone; this does not bypass browser permissions.
