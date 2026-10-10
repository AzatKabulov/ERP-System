#!/bin/bash
# Reset the LOCAL development database to a fresh sample business (users: owner, manager,
# sales, warehouse). Destructive: it flushes every table of the database in backend/.env,
# so only ever point it at a throwaway local database.
set -e
cd "$(dirname "${BASH_SOURCE[0]}")/../../backend"
export PATH="$HOME/.local/bin:$PATH" ERP_SAMPLE_PASSWORD='E2e-Sample-Passw0rd!'
uv run python manage.py flush --no-input
uv run python manage.py create_sample_business
