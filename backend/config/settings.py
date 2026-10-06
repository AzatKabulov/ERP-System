"""Django settings. Every deployment-specific value comes from the environment."""

import warnings
from datetime import timedelta
from pathlib import Path

from . import env

BASE_DIR = Path(__file__).resolve().parent.parent
env.load_dotenv(BASE_DIR / ".env")

# WhiteNoise warns when collectstatic has not run; expected in development and tests.
warnings.filterwarnings("ignore", message="No directory at", category=UserWarning)

DJANGO_ENV = env.get("DJANGO_ENV", "production")  # "development" | "production"
DEBUG = env.get_bool("DJANGO_DEBUG", False)
SECRET_KEY = env.required("DJANGO_SECRET_KEY")
ALLOWED_HOSTS = env.get_list("DJANGO_ALLOWED_HOSTS", ("127.0.0.1", "localhost"))

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "rest_framework_simplejwt.token_blacklist",
    "drf_spectacular",
    "corsheaders",
    "apps.common",
    "apps.accounts",
    "apps.businesses",
    "apps.audit",
]

CORS_ALLOWED_ORIGINS = env.get_list("DJANGO_CORS_ALLOWED_ORIGINS")  # empty = CORS disabled
CORS_EXPOSE_HEADERS = ["X-Request-ID", "Idempotent-Replay"]

MIDDLEWARE = [
    "apps.common.middleware.RequestIDMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    *(["corsheaders.middleware.CorsMiddleware"] if CORS_ALLOWED_ORIGINS else []),
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]
if CORS_ALLOWED_ORIGINS:
    from corsheaders.defaults import default_headers

    CORS_ALLOW_HEADERS = [*default_headers, "idempotency-key", "x-request-id"]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ]
        },
    }
]

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": env.get("POSTGRES_DB", "erp"),
        "USER": env.get("POSTGRES_USER", "erp"),
        "PASSWORD": env.get("POSTGRES_PASSWORD", ""),
        "HOST": env.get("POSTGRES_HOST", "127.0.0.1"),
        "PORT": env.get("POSTGRES_PORT", "5432"),
        "CONN_MAX_AGE": env.get_int("POSTGRES_CONN_MAX_AGE", 60),
        "CONN_HEALTH_CHECKS": True,
        # Transactions are explicit (apps/*/services.py): a failing business rule must
        # roll back exactly the work it belongs to, never half of an HTTP request.
        "ATOMIC_REQUESTS": False,
    }
}
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# Shared across gunicorn workers without Redis; run `manage.py createcachetable` once.
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.db.DatabaseCache",
        "LOCATION": "django_cache",
    }
}

AUTH_USER_MODEL = "accounts.User"
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
        "OPTIONS": {"min_length": 10},
    },
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"  # Server messages are error codes; the app translates them.
TIME_ZONE = "UTC"
USE_I18N = False
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {
        "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"
        if DEBUG
        else "whitenoise.storage.CompressedManifestStaticFilesStorage"
    },
}

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": ["apps.accounts.authentication.ERPJWTAuthentication"],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": ["rest_framework.parsers.JSONParser"],
    "DEFAULT_PAGINATION_CLASS": "apps.common.pagination.StandardPagination",
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "EXCEPTION_HANDLER": "apps.common.errors.exception_handler",
    # Trust X-Forwarded-For only for as many proxies as are really in front of the app.
    # 0 = use the socket address, so a client cannot dodge IP throttles with a fake header.
    "NUM_PROXIES": env.get_int("DJANGO_NUM_PROXIES", 0),
    "DEFAULT_THROTTLE_RATES": {
        "login_identity": "5/min",
        "login_ip": "30/min",
        "reset_request_ip": "10/hour",
        "reset_request_identity": "3/hour",
        "reset_confirm_ip": "20/hour",
    },
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=env.get_int("JWT_ACCESS_MINUTES", 15)),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=env.get_int("JWT_REFRESH_DAYS", 14)),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "UPDATE_LAST_LOGIN": True,
    "AUTH_HEADER_TYPES": ("Bearer",),
}

SPECTACULAR_SETTINGS = {
    "TITLE": "Inventory ERP API",
    "DESCRIPTION": "Business-scoped inventory, purchasing and sales API.",
    "VERSION": "0.1.0",
    "SERVE_INCLUDE_SCHEMA": False,
}
EXPOSE_API_SCHEMA = DEBUG or env.get_bool("DJANGO_EXPOSE_SCHEMA", False)

# Password-recovery codes are sent through any SMTP service (D16). Console in development.
EMAIL_BACKEND = env.get(
    "DJANGO_EMAIL_BACKEND",
    "django.core.mail.backends.console.EmailBackend"
    if DEBUG
    else "django.core.mail.backends.smtp.EmailBackend",
)
EMAIL_HOST = env.get("EMAIL_HOST", "localhost")
EMAIL_PORT = env.get_int("EMAIL_PORT", 587)
EMAIL_HOST_USER = env.get("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = env.get("EMAIL_HOST_PASSWORD", "")
EMAIL_USE_TLS = env.get_bool("EMAIL_USE_TLS", True)
DEFAULT_FROM_EMAIL = env.get("DEFAULT_FROM_EMAIL", "ERP System <no-reply@localhost>")

if not DEBUG:
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = env.get_int("DJANGO_HSTS_SECONDS", 0)  # raise once HTTPS is verified
    SECURE_CONTENT_TYPE_NOSNIFF = True
    SECURE_SSL_REDIRECT = env.get_bool("DJANGO_SSL_REDIRECT", False)  # a proxy usually does this

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "filters": {"request_id": {"()": "apps.common.middleware.RequestIDLogFilter"}},
    "formatters": {
        "plain": {"format": "%(asctime)s %(levelname)s [%(request_id)s] %(name)s: %(message)s"}
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "filters": ["request_id"],
            "formatter": "plain",
        }
    },
    "root": {"handlers": ["console"], "level": env.get("DJANGO_LOG_LEVEL", "INFO")},
}
