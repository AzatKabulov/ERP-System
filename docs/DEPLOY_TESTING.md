# A free test server for the pilot

Status: written 2026-10-09. **Nothing here has been run on a real server yet**: the pieces were checked one by one (the proxy configuration against the real Caddy program, the API in production mode behind it, the web app signing in through it, the scripts with shellcheck, the container build and compose files in CI), but no Docker daemon and no cloud account were available while writing it. Expect to fix small things the first time, and tell us what broke.

Goal: a server that costs nothing, that you can give to testers today, and that you can later copy to a paid server of your own or of a client without changing the app.

## What you get

One machine runs everything:

- the API and the database (PostgreSQL), with receipt photos kept on its disk;
- the **web app** at `https://your-address/` (opens in any browser);
- an **install page** at `https://your-address/install/` to send to testers (Russian and Turkmen), with the Android app to download at `/downloads/erp.apk`;
- automatic HTTPS (a free certificate, renewed by itself);
- a **nightly backup** of the database and the files (kept 14 days).

Each **client later gets their own copy of the same thing** on their own hosting. The Android app is one file for all of them: on the sign-in screen the person types the address of their server ("Server" > "Change"), and the app remembers it.

## Choosing where it runs

| Option | Cost | Good for | Catch |
| --- | --- | --- | --- |
| **A. A free Oracle Cloud virtual machine** (Always Free) | 0 | Testers for weeks: always on, keeps its data | Signing up asks for a bank card to verify who you are (you are not charged while you stay inside the free resources). Oracle reduced the free ARM allowance in 2026 to about 2 CPUs and 12 GB, which is still plenty. Not tried from Turkmenistan: test it first. |
| **B. Your own computer, always on, with a free tunnel** | 0 | A first look today, no card, no domain | The computer must stay on and online, and the temporary address changes whenever the tunnel restarts (testers type the new address). |
| **C. Any cheap VPS** (a few dollars a month) | small | The same script works unchanged | This is also how a client's own server will be set up later. |

Not recommended for this system: the free plans of Render, Koyeb, Fly.io or Railway. They put the service to sleep when idle, delete the free database after weeks, or have no persistent disk for the receipt photos (checked 2026-10-09; the sources disagree and change often, so look at their pricing pages yourself before relying on them).

## Option A, step by step (Oracle Cloud Always Free)

1. **Create the account** at oracle.com/cloud/free. Choose a home region you can live with (it cannot be changed later); a region in Europe is a reasonable guess for Turkmenistan, but only a test from your own phone will tell.
2. **Create the machine**: Menu > Compute > Instances > Create instance. Image: **Ubuntu 24.04**. Shape: **Ampere (VM.Standard.A1.Flex)**, 2 OCPU and 12 GB memory at most (that is the free limit). Add your SSH public key (or let it generate one and download it). Keep "Assign a public IPv4 address" on. If it says "out of capacity", try another availability domain or try again in some hours.
3. **Open the web ports in Oracle's network**: Networking > Virtual cloud networks > your network > the subnet > Security List > Add ingress rules: source `0.0.0.0/0`, TCP, destination ports `80` and again `443`. (The script opens the machine's own firewall; Oracle's network firewall is separate and only you can open it.)
4. **Get a free address name**. At duckdns.org sign in and create a name such as `myshop`; set its IP to the machine's public IP. You now have `myshop.duckdns.org`. (Any domain you own works the same way: point an `A` record at the IP.)
5. **Connect and install**:

   ```bash
   ssh ubuntu@<the machine's public IP>
   sudo apt-get update && sudo apt-get install -y git
   git clone https://github.com/AzatKabulov/ERP-System.git     # a private repository asks for a token: use a fine-grained read-only one
   cd ERP-System
   git checkout claude/laughing-faraday-3dkwcb                    # or main once the branch is merged
   bash scripts/deploy/bootstrap_vm.sh
   ```

   It asks for the domain name, the business name and the owner's login and email; installs Docker; writes the settings with fresh random secrets; starts everything; waits until the server answers over HTTPS; creates the business and the owner; and prints **the owner's password once**. Write it down.
6. **Check it**: open `https://myshop.duckdns.org/api/v1/health/` on your phone using the mobile network, not your home Wi-Fi. It must show `{"status":"ok"}`. If it is slow or does not open from where the shop is, tell us before going further.
7. **Put the apps on the server**: see "The Android app" below.

## Option B, your own computer

You need Docker (Docker Desktop on Windows or Mac, or Docker on Linux) and the repository.

```bash
git clone https://github.com/AzatKabulov/ERP-System.git && cd ERP-System
MODE=tunnel bash scripts/deploy/bootstrap_vm.sh      # Linux or Mac with a shell; on Windows use WSL
```

At the end it prints a temporary `https://....trycloudflare.com` address. The tunnel needs no account. It changes whenever the tunnel restarts; read it again with `cd infra && docker compose logs cloudflared | grep trycloudflare`. Testers re-enter the address in the app (sign-in screen > Server > Change).

## The Android app (direct install) and the web app

The files are built by GitHub for you, signed with **your own key** (one-time setup: `docs/ANDROID_RELEASE.md`). Then:

1. GitHub > Actions > **Release APK** > Run workflow. Wait about 15 minutes. Download the `erp-system-release` files from the finished run (a `.apk`, a `-web.zip` and a checksum list).
2. Copy the two files to the server and install them:

   ```bash
   scp erp-system-*.apk erp-system-*-web.zip ubuntu@<server>:~/
   ssh ubuntu@<server>
   cd ERP-System && bash scripts/deploy/install_release.sh ~/erp-system-*-web.zip ~/erp-system-*.apk
   ```

3. Send testers **`https://your-address/install/`**. They download the app, allow the installation, type the server address once and sign in. Without installing anything they can also open `https://your-address/` in a browser.

## Giving people access

- Sign in as the owner and open **Settings > Staff**: add each tester with a **role** (owner, manager, seller, keeper), the **locations** they may use, and an **initial password** (set it yourself: no email service is needed for that). Passwords can be changed by the person in the app. Password recovery by emailed code only works once an email service is configured (decision D16, `infra/.env`).
- Fill the shop with realistic data so testing means something: Catalog > **Import CSV** with `docs/samples/products_sample.csv` (a few car parts with prices, warranty and return days), then Stock > opening stock and a first purchase order.
- A tester's walk-through with things to try is in `docs/USER_GUIDE_ru.md` (Turkmen draft: `docs/USER_GUIDE_tk.md`).

## Looking after it

| What | How |
| --- | --- |
| Update to the newest code | `bash scripts/deploy/update.sh` (it takes a backup first, then rebuilds and restarts) |
| Backup now | `bash scripts/deploy/backup.sh`. Files go to `infra/backups/`, the nightly job does it by itself. **Copy them off the machine now and then** (a backup on the same disk does not survive losing the machine). |
| Restore, or move to another server | `bash scripts/deploy/restore.sh infra/backups/db-....sql.gz infra/backups/files-....tar.gz` (it asks you to type `restore`) |
| See what is running or why it stopped | `cd infra && docker compose ps` and `docker compose logs --tail 80 api` |
| Stop / start | `cd infra && docker compose stop` / `docker compose up -d` |
| Free machines can disappear | Oracle may reclaim an idle free machine or change the free allowance: keep your off-machine backups. |

## Moving a client to their own hosting later

1. Buy a small VPS for the client (the same Ubuntu steps), point their domain at it, run `bootstrap_vm.sh` there.
2. To bring over existing data: `backup.sh` on the old server, copy the two files, `restore.sh` on the new one.
3. Tell the client's people the new address; they type it once in the app (sign-in screen > Server > Change). No new app is needed.
4. One server can hold several businesses (the software keeps them apart), but giving each paying client **their own server and database** is the simplest to explain, to back up, to move and to switch off.

## What is not covered

- Email for password recovery (`EMAIL_*` in `infra/.env`; any SMTP service).
- Monitoring and alerts: nothing tells you when the server is down. A free uptime check on the health address (for example UptimeRobot) is a good first step.
- A load or security test of the public address; before real clients, follow `PLAN.md` steps 10.1 to 10.3.
- Whether the free address works well from the shop's own internet connection in Turkmenistan: test it from there.
