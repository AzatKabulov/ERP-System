# Deploy runbook (live test server)

Who this is for: a developer who has been given access to the live server by the owner.
Read [AGENTS.md](../AGENTS.md) first. Nothing here contains a password or key: those come from the owner through a private channel and are never committed.

## What you need from the owner (private channel, never in git or chat)

- `<SERVER_IP>`: the server's address.
- `<KEY_FILE>`: the SSH private key file (for example `C:\Users\<you>\.ssh\erp-server.key`). Keep it out of the repository. Set its permissions so only you can read it.
- The server user name (`ubuntu`) and the domain (`erp.kemalysh.dev`).

Do not paste the key, the operator password, the authenticator key or any `.env` values into chat, tickets or commits.

## 1. Check out the code

```
git fetch origin
git checkout feature/premium-design        # or main once it is the release branch
git pull --ff-only
```

Run the checks before deploying:

```
cd backend && uv sync && uv run python manage.py test --noinput      # needs a local PostgreSQL, see docs/LOCAL_TEST.md
cd ../mobile && flutter analyze && flutter test
```

## 2. Build the web app

```
cd mobile
flutter build web --release --no-web-resources-cdn
```

The output is `mobile/build/web`. Optional full-screen test copy (served at `/fs/`):

```
cd .. && python3 scripts/build_fullscreen_preview.py    # writes mobile/build/web-fs
```

## 3. Back up the server (always first)

```
ssh -i <KEY_FILE> ubuntu@<SERVER_IP> "cd ERP-System && bash scripts/deploy/backup.sh"
```

The backup pauses the API briefly so the database and uploaded files are saved together, then restarts it. Backups stay in `infra/backups/` on the server. A backup is kept only after it reads back correctly.

## 4. Upload the code and the web app

Create the archives on your machine:

```
git archive --format=tar.gz -o srcN.tgz HEAD backend infra scripts/deploy
(cd mobile/build/web && tar -czf ../../../webN.tgz .)
(cd mobile/build/web-fs && tar -czf ../../../fsN.tgz .)     # only if you deploy /fs/
```

Upload them:

```
scp -i <KEY_FILE> srcN.tgz webN.tgz fsN.tgz ubuntu@<SERVER_IP>:/home/ubuntu/
```

On the server, unpack them. Keep a copy of the current web files first so you can roll back:

```
ssh -i <KEY_FILE> ubuntu@<SERVER_IP>
cd ~/ERP-System
tar -czf ~/web-before.tgz -C infra/public --exclude=./downloads --exclude=./fs .
tar -xzf ~/srcN.tgz
find infra/public -mindepth 1 -maxdepth 1 ! -name downloads ! -name fs ! -name .gitkeep -exec rm -rf {} +
tar -xzf ~/webN.tgz -C infra/public
rm -rf infra/public/fs && mkdir infra/public/fs && tar -xzf ~/fsN.tgz -C infra/public/fs   # only if deploying /fs/
rm ~/srcN.tgz ~/webN.tgz ~/fsN.tgz
```

## 5. Rebuild the server containers

```
cd ~/ERP-System/infra
nohup docker compose up -d --build > ~/deploy.log 2>&1 &
```

Migrations run automatically on start. The build can take 10 minutes or more on the small server: wait, do not start a second build.

## 6. Check that it is live

```
curl -s https://erp.kemalysh.dev/api/v1/health/        # {"status":"ok",...}
curl -s -o /dev/null -w "%{http_code}\n" https://erp.kemalysh.dev/
curl -s -o /dev/null -w "%{http_code}\n" https://erp.kemalysh.dev/api/v1/platform/overview/   # 401 = new API is up
curl -s https://erp.kemalysh.dev/index.html | grep -c erpSafeTop    # the /fs/ build is current
```

Look at the logs if anything is wrong: `cd ~/ERP-System/infra && docker compose logs --tail 80 api`.

## Rollback

The previous web files are in `~/web-before.tgz` on the server. Unpack them into `infra/public` the same way as step 4. For the API, check out the previous commit, upload its archive and run step 5 again. Database changes are not reversed automatically: restore from the backup with `scripts/deploy/restore.sh` if a migration must be undone, and tell the owner first.

## Things that are easy to get wrong

- The web app is not built on the server. You must run `flutter build web` on your machine and upload the result (step 4).
- `scripts/deploy/update.sh` pulls from git on the server but does not build the web app; use the steps above for a full release.
- Turn the test-login switch off before real customers: remove `ERP_PUBLIC_TEST_LOGIN` from `infra/.env` and restart the API.
- A new shop created through "Новый клиент" waits for its owner's first-sign-in answers. That is expected.
- Never run `docker compose down -v`: it deletes the database volume.

## Who to ask

The owner (Azat) gives access and keys. Do not share the server with anyone not on the team.
