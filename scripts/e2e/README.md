# Real-stack browser run

One browser session that drives the **real** Flutter web build against the **real** Django API and PostgreSQL. It is not part of CI (it needs a browser, a database and both servers). It was run for Phases 1-4; the result is recorded in `HANDOFF.md`.

What it covers (44 checks): sign-in as owner, exchange rate, products priced in TMT and USD, supplier, purchase order (draft, submit), a partial receipt, a receipt whose **answer is dropped after the server committed**, a page reload standing in for a tablet restart (exactly one delivery, no duplicate, nothing left pending), stock value (FIFO), history, Russian to Turkmen and back after a reload, sign-out, and the warehouse user seeing no costs. It also checks `reconcile_stock` consistency through the database.

## Run it

1. Start PostgreSQL and write `backend/.env` (`bash scripts/claude_cloud_postgres.sh` on the Claude cloud VM), then `cd backend && uv run python manage.py migrate && uv run python manage.py createcachetable`.
2. `bash scripts/e2e/reset_db.sh` (**flushes the database**; local throwaway only).
3. Build the web app for the local API: `cd mobile && flutter build web --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:8000`.
4. Start the API with CORS for the web origin: `cd backend && DJANGO_CORS_ALLOWED_ORIGINS=http://127.0.0.1:8080 uv run python manage.py runserver 127.0.0.1:8000 --noreload`.
5. Serve the build: `cd mobile/build/web && python3 -m http.server 8080 --bind 127.0.0.1`.
6. `node scripts/e2e/real_stack.js`. Environment: `PLAYWRIGHT_MODULE` (path to the playwright package), `CHROMIUM_PATH`, `E2E_WEB_URL`, `E2E_OUT` (screenshots).

The Russian labels in the script follow `mobile/lib/l10n/app_ru.arb`; if a label changes, update the script.
