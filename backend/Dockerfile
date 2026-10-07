# syntax=docker/dockerfile:1
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

COPY --from=ghcr.io/astral-sh/uv:0.11 /uv /usr/local/bin/uv

WORKDIR /app
# Dependencies first so this layer is cached until uv.lock changes.
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen --no-dev --no-install-project

COPY . .
# Receipt photos and other uploads live here, outside the code and outside any static path.
# Mount a persistent volume on it (infra/docker-compose.yml does) and back it up with the database.
RUN useradd --system --create-home --uid 10001 app && chown -R app /app \
    && mkdir -p /var/lib/erp/private_files && chown app /var/lib/erp/private_files
USER app
ENV PATH="/app/.venv/bin:$PATH" \
    DJANGO_ENV=production \
    DJANGO_DEBUG=false \
    PRIVATE_FILES_ROOT=/var/lib/erp/private_files

# collectstatic needs a key but never uses it at runtime; real secrets come from the environment.
RUN DJANGO_SECRET_KEY=build-time-only python manage.py collectstatic --noinput

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/v1/health/', timeout=4)"

# Migrations are a separate, reviewed step (see infra/README.md), not run on every start.
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3", "--timeout", "60", "--access-logfile", "-"]
