# Deployment files (staging runbook)

These files describe how to run the API; they do **not** deploy anything by themselves. Choosing the host (PLAN.md D2) and operating it are owner steps.

## Run the stack

```bash
cd infra
cp .env.example .env        # then fill in the secrets; .env is git-ignored
docker compose build
docker compose up -d        # starts the database, applies migrations once, then the API
curl http://127.0.0.1:8000/api/v1/health/     # {"status":"ok"}
```

Put a reverse proxy with HTTPS in front of port 8000 and set `DJANGO_NUM_PROXIES=1` and `DJANGO_ALLOWED_HOSTS` to the real host name. Raise `DJANGO_HSTS_SECONDS` only after HTTPS works everywhere.

## Uploaded files and backups

Receipt photos and PDFs are stored in the `privatefiles` volume (mounted at `/var/lib/erp/private_files`, `PRIVATE_FILES_ROOT`). They are not served as static files: the API sends them only to signed-in members of the right business. **Back this volume up together with the database** (a database backup alone loses the files) and include it in the restore drill (PLAN.md D11, step 10.2). Set a request-size limit of about 6 MB in the reverse proxy; the app already stops files above 5 MB. Gunicorn's timeout is 60 s so that a catalog import of 2000 rows (about 16 s on a developer machine) finishes.

## First business and owner

```bash
docker compose run --rm api sh -c 'ERP_OWNER_PASSWORD=... python manage.py create_business \
  --name "Shop name" --owner-username owner --owner-email owner@example.test --location "Main store"'
```

Prefer typing the password at the prompt (omit `ERP_OWNER_PASSWORD`, add `-it`). Sample data for testing only: `python manage.py create_sample_business` (refuses to run when `DJANGO_ENV=production`).

## Updating

1. Review new migrations (`backend/apps/*/migrations`) and back up the database first.
2. `docker compose build && docker compose run --rm migrate && docker compose up -d api`.
3. Check `/api/v1/health/`. Rolling back code does not roll back migrations; keep schema changes backward compatible.

## Test from the shop (PLAN.md step 2.1)

Open `https://<your-host>/api/v1/health/` on the pilot tablet or phone over the shop's own internet connection and note whether it answers quickly. If it is slow or blocked, revisit the hosting decision (D2) now.
