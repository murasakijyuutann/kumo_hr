# kumo HR — Stage 0 Walkthrough

> Step-by-step guide for Stage 0 of `ROADMAP.md`: an empty but working stack that starts with `make up`, plus green CI.
> Every file you need to write is given in full below. "§n" refers to a section of `PROJECT_STRUCTURE.md`.
> Commands are written for **Git Bash on Windows** and also work on macOS and Linux.

**Done when** a fresh clone → `cp .env.example .env && make up` shows the empty themed app with a working language switcher, `make test` passes, and CI is green.

---

## Before you start

### Requirements

- **Docker Desktop**, running. Check with `docker info`; if it says `cannot find the file specified`, open Docker Desktop and wait for "Engine running".
- **Git** and **Git Bash**.
- **make.** Git Bash doesn't include it. Install it once from PowerShell, then reopen the terminal:

  ```powershell
  winget install ezwinports.make
  ```

  If you'd rather not install it, every `make` target is a one-line `docker compose` command you can run directly; see the `Makefile` in 0.1.

You don't need Node or Python on your machine. Every scaffolding command runs inside a container.

### One-time setup (already done in this repo)

```bash
touch .private-terms          # one private term per line; never committed
./scripts/install-hooks.sh    # pre-commit private-term check
```

Only repeat these in a fresh clone on another machine.

### Two Windows rules for the whole walkthrough

1. **Prefix `docker run` with `MSYS_NO_PATHCONV=1`.** Otherwise Git Bash rewrites container paths such as `/app` into `C:/Program Files/Git/app`.
2. **Save `.sh` files with LF line endings.** In Cursor, click `CRLF` in the status bar and pick `LF` before saving. A CRLF `entrypoint.sh` makes the container fail with `no such file or directory`.

### Branch and pull request per phase

Each phase (0.1, 0.2 …) is one branch and one pull request:

```bash
git switch main && git pull
git switch -c stage0/docker          # 0.1; then stage0/backend, stage0/frontend, stage0/i18n, stage0/ci
# ... do the phase ...
git add -A && git commit -m "Stage 0.1: Docker setup"
git push -u origin stage0/docker     # then open the pull request on GitHub and merge it
```

---

## 0.1 Repo and Docker

**Goal:** `make up` serves the Django admin, the Next.js starter, PostgreSQL and Mailpit.

### Step 1 — Scaffold Django

```bash
mkdir -p backend/requirements
MSYS_NO_PATHCONV=1 docker run --rm -v "$PWD/backend":/app -w /app python:3.12-slim \
  sh -c "pip install -q django && django-admin startproject config ."
```

You now have `backend/manage.py` and `backend/config/`.

### Step 2 — Requirements files

`backend/requirements/base.txt`

```text
Django>=5.2,<6.0
djangorestframework>=3.16,<4
drf-spectacular>=0.28,<1
django-filter>=25.1,<26
django-cors-headers>=4.7,<5
django-simple-history>=3.8,<4
django-storages>=1.14,<2
openpyxl>=3.1,<4
psycopg[binary]>=3.2,<4
dj-database-url>=2.3,<4
```

`backend/requirements/dev.txt`

```text
-r base.txt
pytest>=8.3,<9
pytest-django>=4.9,<5
factory_boy>=3.3,<4
ruff>=0.12,<1
```

`backend/requirements/prod.txt`

```text
-r base.txt
gunicorn>=23,<24
```

Django 5.2 is the long-term-support release, so every library above supports it.

### Step 3 — Scaffold Next.js

```bash
MSYS_NO_PATHCONV=1 docker run --rm -it -v "$PWD":/w -w /w node:22-alpine \
  npx create-next-app@latest frontend --ts --eslint --tailwind --app --src-dir \
  --import-alias "@/*" --use-npm --yes
```

- If it says `the input device is not a TTY`, run it in Cursor's built-in terminal instead of the separate Git Bash window.
- It creates `frontend/node_modules` on your disk. That copy is never used by the containers; you can delete it whenever you like.
- If a `frontend/.git` folder appears, delete it. The project has one repository, at the root.

### Step 4 — Container files

`backend/Dockerfile` (§6, plus `gettext` for translations in 0.4 and a build-time environment for `collectstatic`)

```dockerfile
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
RUN apt-get update \
 && apt-get install -y --no-install-recommends gettext \
 && rm -rf /var/lib/apt/lists/*
ARG SUPERCRONIC_VERSION=v0.2.33
ARG TARGETARCH
ADD https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${TARGETARCH} /usr/local/bin/supercronic
RUN chmod +x /usr/local/bin/supercronic
WORKDIR /app
COPY requirements/ requirements/

FROM base AS dev
RUN pip install -r requirements/dev.txt
COPY . .
RUN chmod +x entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]

FROM base AS prod
RUN pip install -r requirements/prod.txt
COPY . .
# collectstatic loads the settings, which need these variables; the real values come from .env at runtime.
RUN chmod +x entrypoint.sh \
 && DJANGO_SETTINGS_MODULE=config.settings.prod \
    DJANGO_SECRET_KEY=build-only \
    DATABASE_URL=sqlite:////tmp/build.db \
    python manage.py collectstatic --noinput
RUN useradd --create-home app && chown -R app /app
USER app
ENTRYPOINT ["./entrypoint.sh"]
CMD ["gunicorn", "config.wsgi:application", "-b", "0.0.0.0:8000", "-w", "3"]
```

The `prod` target isn't built until 0.5, after the settings split in 0.2 creates `config.settings.prod`.

`frontend/Dockerfile` (§6)

```dockerfile
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM deps AS dev
CMD ["npm", "run", "dev"]

FROM deps AS build
COPY . .
RUN npm run build

FROM node:22-alpine AS prod
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static
COPY --from=build /app/public ./public
USER node
CMD ["node", "server.js"]
```

`compose.yaml` (repo root; §6 without the `scheduler` service, which arrives with the first scheduled job in phase 1.6)

```yaml
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports: ["5432:5432"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      retries: 10

  backend:
    build: { context: ./backend, target: dev }
    env_file: .env
    command: python manage.py runserver 0.0.0.0:8000
    volumes:
      - ./backend:/app
    ports: ["8000:8000"]
    depends_on:
      db: { condition: service_healthy }

  frontend:
    build: { context: ./frontend, target: dev }
    environment:
      API_INTERNAL_URL: http://backend:8000
      WATCHPACK_POLLING: "true"
    command: npm run dev -- -H 0.0.0.0
    volumes:
      - ./frontend:/app
      - /app/node_modules
      - /app/.next
    ports: ["3000:3000"]
    depends_on: [backend]

  mailpit:
    image: axllent/mailpit
    ports: ["8025:8025"]

volumes:
  pgdata:
```

`.env.example` (repo root)

```bash
# Compose + Django
POSTGRES_DB=hr
POSTGRES_USER=hr
POSTGRES_PASSWORD=change-me
DATABASE_URL=postgres://hr:change-me@db:5432/hr
DJANGO_SETTINGS_MODULE=config.settings
DJANGO_SECRET_KEY=change-me
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,backend
EMAIL_HOST=mailpit
EMAIL_PORT=1025
DEFAULT_FROM_EMAIL=hr@naniwa-systems.example
LEAVE_MANAGER_EMAIL=leave-manager@naniwa-systems.example
TIMESHEET_CLOSE_DAY=7
```

`DJANGO_SETTINGS_MODULE` changes to `config.settings.dev` in 0.2, when the settings become a package.

`backend/.dockerignore`

```text
.venv
__pycache__
*.pyc
media/
staticfiles/
db.sqlite3
.env
.private-terms
```

`frontend/.dockerignore`

```text
node_modules
.next
.env*
.private-terms
```

### Step 5 — `backend/entrypoint.sh`

Save with **LF** line endings.

```sh
#!/bin/sh
set -e

echo "Waiting for the database..."
until python -c "import os, psycopg; psycopg.connect(os.environ['DATABASE_URL'], connect_timeout=2).close()" 2>/dev/null
do
  sleep 1
done

if [ -d locale ]; then
  python manage.py compilemessages
fi
python manage.py migrate --noinput
python manage.py createcachetable

exec "$@"
```

Then mark it executable in git:

```bash
git add backend/entrypoint.sh
git update-index --chmod=+x backend/entrypoint.sh
```

### Step 6 — API proxy in `frontend/next.config.ts`

Replace the generated file:

```ts
import type { NextConfig } from "next";

const apiUrl = process.env.API_INTERNAL_URL ?? "http://localhost:8000";

const nextConfig: NextConfig = {
  output: "standalone",
  // Django URLs end in "/"; without this Next.js redirects them to the slash-less form.
  skipTrailingSlashRedirect: true,
  async rewrites() {
    return [
      { source: "/api/:path*/", destination: `${apiUrl}/api/:path*/` },
      { source: "/api/:path*", destination: `${apiUrl}/api/:path*` },
    ];
  },
};

export default nextConfig;
```

### Step 7 — `Makefile` (repo root)

Recipe lines must start with a **tab**, not spaces.

```make
.PHONY: up down logs migrate test reset-db

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f backend frontend

migrate:
	docker compose exec backend python manage.py migrate

test:
	docker compose exec backend pytest
	docker compose exec frontend npm test

reset-db:
	docker compose down -v
	$(MAKE) up
```

`make test` starts working in 0.2 (pytest) and 0.3 (Vitest). `seed` and `types` are added later.

Add these lines to the root `.gitignore`:

```text
db.sqlite3
*.mo
```

### Step 8 — Verify

```bash
cp .env.example .env
make up
docker compose ps        # db, backend, frontend and mailpit should be "running"
```

These should all respond:

- http://localhost:8000/admin — Django admin login page
- http://localhost:3000 — Next.js starter page
- http://localhost:8025 — Mailpit inbox

If the backend keeps restarting, run `docker compose logs backend`. `no such file or directory` on `entrypoint.sh` means CRLF line endings (see "Two Windows rules").

**Commit, push and merge** `stage0/docker`.

---

## 0.2 Backend skeleton

**Goal:** settings split, `core` and `accounts` apps, date helpers with tests, `/api/docs/` loads.

```bash
git switch main && git pull && git switch -c stage0/backend
make up
```

### Step 1 — Create the apps

```bash
docker compose exec backend sh -c "mkdir -p apps/core apps/accounts && \
  touch apps/__init__.py && \
  python manage.py startapp core apps/core && \
  python manage.py startapp accounts apps/accounts && \
  rm apps/core/tests.py apps/accounts/tests.py && \
  mkdir -p apps/core/utils apps/core/tests && \
  touch apps/core/utils/__init__.py apps/core/tests/__init__.py"
```

`backend/apps/core/apps.py`

```python
from django.apps import AppConfig
from django.utils.translation import gettext_lazy as _


class CoreConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.core"
    verbose_name = _("Core")
```

`backend/apps/accounts/apps.py`

```python
from django.apps import AppConfig
from django.utils.translation import gettext_lazy as _


class AccountsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.accounts"
    verbose_name = _("Accounts")
```

### Step 2 — Custom `User` (before the first real migration)

`AUTH_USER_MODEL` is very hard to change once migrations exist, so the model is created now with `email` as the login field. Phase 1.2 adds the lockout and password-change fields.

`backend/apps/accounts/managers.py`

```python
from django.contrib.auth.base_user import BaseUserManager


class UserManager(BaseUserManager):
    use_in_migrations = True

    def _create_user(self, email, password, **extra_fields):
        if not email:
            raise ValueError("An email address is required.")
        email = self.normalize_email(email).lower()
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", False)
        extra_fields.setdefault("is_superuser", False)
        return self._create_user(email, password, **extra_fields)

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        if not extra_fields["is_staff"] or not extra_fields["is_superuser"]:
            raise ValueError("A superuser needs is_staff=True and is_superuser=True.")
        return self._create_user(email, password, **extra_fields)
```

`backend/apps/accounts/models.py`

```python
from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils.translation import gettext_lazy as _

from .managers import UserManager


class User(AbstractUser):
    username = None
    email = models.EmailField(_("email address"), unique=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []

    objects = UserManager()
```

`backend/apps/accounts/admin.py`

```python
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.forms import UserChangeForm as BaseUserChangeForm
from django.contrib.auth.forms import UserCreationForm as BaseUserCreationForm

from .models import User


class UserCreationForm(BaseUserCreationForm):
    class Meta:
        model = User
        fields = ("email",)


class UserChangeForm(BaseUserChangeForm):
    class Meta:
        model = User
        fields = ("email",)


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    add_form = UserCreationForm
    form = UserChangeForm
    ordering = ["email"]
    list_display = ["email", "is_staff", "is_active", "last_login"]
    search_fields = ["email"]
    fieldsets = (
        (None, {"fields": ("email", "password")}),
        ("Permissions", {"fields": ("is_active", "is_staff", "is_superuser", "groups")}),
        ("Dates", {"fields": ("last_login", "date_joined")}),
    )
    add_fieldsets = (
        (None, {"classes": ("wide",), "fields": ("email", "password1", "password2")}),
    )
```

The custom forms are needed because Django's default user forms expect a `username` field.

### Step 3 — `core` building blocks

`backend/apps/core/managers.py`

```python
from django.db import models


class ActiveManager(models.Manager):
    """Hides soft-deleted rows."""

    def get_queryset(self):
        return super().get_queryset().filter(deleted_at__isnull=True)
```

`backend/apps/core/models.py`

```python
from django.db import models
from django.utils import timezone

from .managers import ActiveManager


class TimeStampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class SoftDeleteModel(models.Model):
    deleted_at = models.DateField(null=True, blank=True, db_index=True)

    objects = ActiveManager()
    all_objects = models.Manager()

    class Meta:
        abstract = True

    def soft_delete(self, on=None):
        self.deleted_at = on or timezone.localdate()
        self.save(update_fields=["deleted_at"])


class ErrorLog(models.Model):
    """No foreign keys, so rows survive member deletion and record pre-login errors."""

    occurred_at = models.DateTimeField(default=timezone.now, db_index=True)
    user_id = models.IntegerField(null=True, blank=True)
    source = models.CharField(max_length=100)
    path = models.CharField(max_length=500, blank=True, default="")
    method = models.CharField(max_length=10, blank=True, default="")
    error_class = models.CharField(max_length=200)
    message = models.TextField()
    traceback = models.TextField(blank=True, default="")

    class Meta:
        ordering = ["-occurred_at"]

    def __str__(self):
        return f"{self.occurred_at:%Y-%m-%d %H:%M} {self.error_class}"
```

`path` and `method` are empty strings rather than `NULL` for non-request errors; Django's convention (and ruff rule `DJ001`) is to avoid nullable text columns.

`backend/apps/core/logging.py`

```python
import logging
import traceback


class DatabaseErrorHandler(logging.Handler):
    """Writes ERROR records to ErrorLog. Configured in settings.LOGGING."""

    def emit(self, record):
        try:
            from apps.core.models import ErrorLog

            request = getattr(record, "request", None)
            user = getattr(request, "user", None)
            error_class, trace = record.levelname, ""
            if record.exc_info and record.exc_info[0]:
                error_class = record.exc_info[0].__name__
                trace = "".join(traceback.format_exception(*record.exc_info))

            ErrorLog.objects.create(
                user_id=user.pk if user is not None and user.is_authenticated else None,
                source="request" if request is not None else record.name,
                path=request.path[:500] if request is not None else "",
                method=request.method if request is not None else "",
                error_class=error_class[:200],
                message=record.getMessage(),
                traceback=trace,
            )
        except Exception:
            self.handleError(record)
```

The model is imported inside `emit()` because the logging config loads before Django's apps are ready.

`backend/apps/core/exceptions.py`

```python
from django.core.exceptions import PermissionDenied as DjangoPermissionDenied
from django.http import Http404
from rest_framework import exceptions
from rest_framework.views import exception_handler


def api_exception_handler(exc, context):
    """Every API error becomes {"error": {"code", "message", "details"}}."""
    if isinstance(exc, Http404):
        exc = exceptions.NotFound()
    elif isinstance(exc, DjangoPermissionDenied):
        exc = exceptions.PermissionDenied()

    response = exception_handler(exc, context)
    if response is None:
        return None

    code = exc.default_code if isinstance(exc, exceptions.APIException) else "error"
    codes = exc.get_codes() if isinstance(exc, exceptions.APIException) else None
    if isinstance(codes, str):
        code = codes

    data = response.data
    if isinstance(data, dict) and set(data) == {"detail"}:
        message, details = str(data["detail"]), None
    else:
        message, details = "Invalid input.", data

    response.data = {"error": {"code": code, "message": message, "details": details}}
    return response
```

`backend/apps/core/pagination.py`

```python
from rest_framework.pagination import PageNumberPagination


class StandardPagination(PageNumberPagination):
    page_size = 50
    page_size_query_param = "page_size"
    max_page_size = 200
```

`backend/apps/core/permissions.py`

```python
from rest_framework.permissions import SAFE_METHODS, BasePermission

HR_ADMIN_GROUP = "HR Admin"


def is_hr_admin(user):
    return user.is_authenticated and user.groups.filter(name=HR_ADMIN_GROUP).exists()


class IsHRAdmin(BasePermission):
    def has_permission(self, request, view):
        return is_hr_admin(request.user)


class IsSelfOrHR(BasePermission):
    """Object access for HR, or for the user who owns the object (obj.user or obj.member.user)."""

    def has_object_permission(self, request, view, obj):
        if is_hr_admin(request.user):
            return True
        owner = getattr(obj, "user", None)
        if owner is None and hasattr(obj, "member"):
            owner = obj.member.user
        return owner == request.user


class ReadOnly(BasePermission):
    def has_permission(self, request, view):
        return request.method in SAFE_METHODS
```

`backend/apps/core/admin.py`

```python
from django.contrib import admin

from .models import ErrorLog


@admin.register(ErrorLog)
class ErrorLogAdmin(admin.ModelAdmin):
    list_display = ["occurred_at", "source", "error_class", "method", "path", "user_id"]
    list_filter = ["source", "error_class"]
    search_fields = ["message", "path"]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
```

### Step 4 — Date helpers, test first

Write the test, run it and watch it fail, then write the code.

`backend/apps/core/tests/test_dates.py`

```python
from datetime import date

import pytest

from apps.core.utils.dates import claim_period, month_range, timesheet_close_date


@pytest.mark.parametrize(
    ("day", "expected"),
    [
        (date(2026, 10, 1), (date(2026, 10, 1), date(2026, 10, 31))),
        (date(2026, 10, 17), (date(2026, 10, 1), date(2026, 10, 31))),
        (date(2026, 2, 14), (date(2026, 2, 1), date(2026, 2, 28))),
        (date(2028, 2, 1), (date(2028, 2, 1), date(2028, 2, 29))),
        (date(2100, 2, 1), (date(2100, 2, 1), date(2100, 2, 28))),
    ],
)
def test_month_range(day, expected):
    assert month_range(day) == expected


def test_claim_period_october_2026():
    assert claim_period(date(2026, 10, 1)) == (date(2026, 9, 16), date(2026, 10, 15))


def test_claim_period_crosses_new_year():
    assert claim_period(date(2027, 1, 1)) == (date(2026, 12, 16), date(2027, 1, 15))


def test_timesheet_close_date_september_2026():
    assert timesheet_close_date(date(2026, 9, 1)) == date(2026, 10, 7)


def test_timesheet_close_date_december_rolls_into_next_year():
    assert timesheet_close_date(date(2026, 12, 1)) == date(2027, 1, 7)


def test_timesheet_close_day_comes_from_settings(settings):
    settings.TIMESHEET_CLOSE_DAY = 10
    assert timesheet_close_date(date(2026, 9, 1)) == date(2026, 10, 10)
```

`backend/apps/core/utils/dates.py`

```python
import calendar
from datetime import date, timedelta

from django.conf import settings


def month_range(day: date) -> tuple[date, date]:
    """First and last day of the calendar month containing `day`."""
    first = day.replace(day=1)
    last = first.replace(day=calendar.monthrange(first.year, first.month)[1])
    return first, last


def claim_period(month: date) -> tuple[date, date]:
    """Travel claim period for `month`: the 16th of the previous month to the 15th."""
    first = month.replace(day=1)
    previous_month = first - timedelta(days=1)
    return previous_month.replace(day=16), first.replace(day=15)


def timesheet_close_date(month: date) -> date:
    """Approval deadline for `month`'s timesheet: TIMESHEET_CLOSE_DAY of the next month."""
    _, last = month_range(month)
    return (last + timedelta(days=1)).replace(day=settings.TIMESHEET_CLOSE_DAY)
```

Business-day helpers need the `Holiday` model and arrive with phase 1.3.

### Step 5 — Split the settings

Delete `backend/config/settings.py` and `backend/db.sqlite3`, then create the package `backend/config/settings/` with these five files.

`backend/config/settings/__init__.py` — empty file.

`backend/config/settings/base.py`

```python
"""Settings shared by every environment."""

import os
from pathlib import Path

import dj_database_url
from django.utils.translation import gettext_lazy as _

BASE_DIR = Path(__file__).resolve().parent.parent.parent

SECRET_KEY = os.environ["DJANGO_SECRET_KEY"]
DEBUG = False
ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost").split(",")

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "drf_spectacular",
    "django_filters",
    "simple_history",
    "apps.core",
    "apps.accounts",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.locale.LocaleMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "simple_history.middleware.HistoryRequestMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

DATABASES = {"default": dj_database_url.parse(os.environ["DATABASE_URL"], conn_max_age=60)}
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

AUTH_USER_MODEL = "accounts.User"
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

# i18n: Django reads the same cookie the Next.js language switcher sets (0.4).
LANGUAGE_CODE = "ja"
LANGUAGES = [("ja", _("Japanese")), ("en", _("English"))]
LANGUAGE_COOKIE_NAME = "NEXT_LOCALE"
LOCALE_PATHS = [BASE_DIR / "locale"]
TIME_ZONE = "Asia/Tokyo"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "media/"
MEDIA_ROOT = BASE_DIR / "media"

CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.db.DatabaseCache",
        "LOCATION": "django_cache",
    }
}

SESSION_COOKIE_AGE = 1800
SESSION_SAVE_EVERY_REQUEST = True
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
CSRF_COOKIE_SAMESITE = "Lax"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework.authentication.SessionAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
    "DEFAULT_PAGINATION_CLASS": "apps.core.pagination.StandardPagination",
    "PAGE_SIZE": 50,
    "DEFAULT_FILTER_BACKENDS": ["django_filters.rest_framework.DjangoFilterBackend"],
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "EXCEPTION_HANDLER": "apps.core.exceptions.api_exception_handler",
}

SPECTACULAR_SETTINGS = {
    "TITLE": "kumo HR API",
    "VERSION": "1.0.0",
    "SERVE_INCLUDE_SCHEMA": False,
}

EMAIL_HOST = os.environ.get("EMAIL_HOST", "localhost")
EMAIL_PORT = int(os.environ.get("EMAIL_PORT", "25"))
DEFAULT_FROM_EMAIL = os.environ.get("DEFAULT_FROM_EMAIL", "hr@naniwa-systems.example")
LEAVE_MANAGER_EMAIL = os.environ.get("LEAVE_MANAGER_EMAIL", "")
TIMESHEET_CLOSE_DAY = int(os.environ.get("TIMESHEET_CLOSE_DAY", "7"))

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {
        "console": {"class": "logging.StreamHandler"},
        "database": {"level": "ERROR", "class": "apps.core.logging.DatabaseErrorHandler"},
    },
    "loggers": {
        "django.request": {"handlers": ["console", "database"], "level": "ERROR", "propagate": False},
        "apps": {"handlers": ["console", "database"], "level": "INFO", "propagate": False},
    },
    "root": {"handlers": ["console"], "level": "WARNING"},
}
```

`backend/config/settings/dev.py`

```python
from .base import *

DEBUG = True

INSTALLED_APPS += ["corsheaders"]
MIDDLEWARE.insert(0, "corsheaders.middleware.CorsMiddleware")
CORS_ALLOWED_ORIGINS = ["http://localhost:3000"]
CORS_ALLOW_CREDENTIALS = True
CSRF_TRUSTED_ORIGINS = ["http://localhost:3000"]
```

`backend/config/settings/test.py`

```python
from .base import *

PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
```

`backend/config/settings/prod.py`

```python
from .base import *

DEBUG = False

SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_HSTS_SECONDS = 3600
SECURE_CONTENT_TYPE_NOSNIFF = True
```

HSTS starts at one hour; raise it once HTTPS is confirmed working in Stage 4. Private object storage is added with payslips in phase 2.2.

Point the entry files at the new modules:

- `backend/manage.py`: change `"config.settings"` to `"config.settings.dev"`.
- `backend/config/wsgi.py` and `backend/config/asgi.py`: change `"config.settings"` to `"config.settings.prod"`.
- `.env.example` **and** your `.env`: `DJANGO_SETTINGS_MODULE=config.settings.dev`.

### Step 6 — Routes

`backend/config/api_router.py`

```python
from rest_framework.routers import DefaultRouter

router = DefaultRouter()
# Each app registers its viewsets here, e.g. router.register("members", MemberViewSet)

urlpatterns = router.urls
```

`backend/config/urls.py` (replace the generated file)

```python
from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include("config.api_router")),
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs/", SpectacularSwaggerView.as_view(url_name="schema"), name="docs"),
]
```

### Step 7 — Tool config

`backend/pytest.ini`

```ini
[pytest]
addopts = -q --ds=config.settings.test
python_files = test_*.py
```

`--ds` is used instead of `DJANGO_SETTINGS_MODULE =` because the `.env` value (`config.settings.dev`) would otherwise take priority.

`backend/pyproject.toml`

```toml
[tool.ruff]
line-length = 100
target-version = "py312"
extend-exclude = ["*/migrations/*"]

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP", "DJ"]

[tool.ruff.lint.per-file-ignores]
"config/settings/*" = ["F403", "F405"]
```

### Step 8 — First migrations and a clean database

The entrypoint runs `migrate` on start, so create the migrations with the entrypoint switched off, then wipe the old database:

```bash
docker compose run --rm --entrypoint "" backend python manage.py makemigrations accounts core
make reset-db
docker compose exec backend python manage.py createsuperuser
```

### Step 9 — Verify

```bash
docker compose exec backend pytest
docker compose exec backend ruff check .
```

- If ruff reports import-order or style issues in generated files, run `docker compose exec backend ruff check . --fix`.
- http://localhost:8000/admin — log in with your superuser; you should see **Users** and **Error logs**.
- http://localhost:8000/api/docs/ — Swagger UI loads (no endpoints yet).
- http://localhost:3000/api/schema/ — returns the OpenAPI YAML through the Next.js proxy.

**Commit, push and merge** `stage0/backend`.

---

## 0.3 Frontend skeleton

**Goal:** placeholder pages render in the kumo theme with the sidebar and top bar; lint and tests pass.

```bash
git switch main && git pull && git switch -c stage0/frontend
make up
```

> **Installing packages:** always install inside the container (`docker compose exec frontend npm i …`). If someone else's pull adds packages, refresh the container's `node_modules` with `docker compose up -d --build -V`.

### Step 1 — shadcn/ui and packages

```bash
docker compose exec frontend npx shadcn@latest init
docker compose exec frontend npx shadcn@latest add button card input dropdown-menu badge table dialog sonner
docker compose exec frontend npm i @tanstack/react-query
```

Pick **Neutral** as the base colour when asked; the next step replaces the colours anyway.

### Step 2 — Theme tokens in `frontend/src/app/globals.css`

shadcn generated a `:root { … }` block and an `@theme inline { … }` block.

1. In `:root`, set these values (keep any other variables shadcn added, such as `--chart-*`):

   ```css
   :root {
     --radius: 6px;
     --background: #F8FAFC;
     --foreground: #334155;
     --foreground-strong: #0F172A;
     --card: #FFFFFF;
     --card-foreground: #334155;
     --popover: #FFFFFF;
     --popover-foreground: #334155;
     --primary: #2563EB;
     --primary-foreground: #FFFFFF;
     --primary-hover: #1D4ED8;
     --secondary: #F1F5F9;
     --secondary-foreground: #0F172A;
     --muted: #F1F5F9;
     --muted-foreground: #64748B;
     --accent: #F1F5F9;
     --accent-foreground: #0F172A;
     --destructive: #DC2626;
     --border: #E2E8F0;
     --input: #E2E8F0;
     --ring: #2563EB;
     --sidebar: #0F172A;
     --sidebar-foreground: #CBD5E1;
     --sidebar-accent: #1E293B;
     --sidebar-accent-foreground: #FFFFFF;
     --sidebar-border: #1E293B;
   }
   ```

2. Delete the `.dark { … }` block; the app has one theme.

3. In `@theme inline`, replace the `--font-sans` / `--font-mono` lines and make sure these lines exist (add any that are missing):

   ```css
   --font-sans: var(--font-source-sans), var(--font-noto-sans-jp), system-ui, sans-serif;
   --color-foreground-strong: var(--foreground-strong);
   --color-primary-hover: var(--primary-hover);
   --color-sidebar: var(--sidebar);
   --color-sidebar-foreground: var(--sidebar-foreground);
   --color-sidebar-accent: var(--sidebar-accent);
   --color-sidebar-accent-foreground: var(--sidebar-accent-foreground);
   --color-sidebar-border: var(--sidebar-border);
   ```

4. At the end of the file add the heading font:

   ```css
   @layer base {
     h1, h2, h3 {
       font-family: Georgia, serif;
       color: var(--foreground-strong);
     }
   }
   ```

Tailwind v4 keeps its config in CSS, so there is no `tailwind.config.ts`; the spec lists one only out of habit.

### Step 3 — Message file (English for now)

UI text lives in message files from the start, so 0.4 only has to add Japanese.

`frontend/messages/en.json`

```json
{
  "nav": {
    "dashboard": "Dashboard",
    "people": "People",
    "timeTracking": "Time tracking",
    "timeOff": "Time off",
    "travel": "Travel expenses",
    "reports": "Reports",
    "payslips": "Payslips",
    "settings": "Company settings",
    "help": "Help"
  },
  "topBar": {
    "searchPeople": "Search people",
    "notifications": "Notifications"
  },
  "userMenu": {
    "placeholderName": "Hana Mori",
    "placeholderRole": "HR Admin · Naniwa Systems",
    "language": "Language",
    "languages": { "en": "English", "ja": "日本語" }
  },
  "dashboard": {
    "title": "Dashboard"
  },
  "enums": {
    "gender": { "1": "Male", "2": "Female" },
    "employmentType": { "1": "Full-time", "2": "Contract", "3": "Part-time" },
    "languageLevel": { "1": "Advanced", "2": "Intermediate", "3": "Basic" }
  }
}
```

### Step 4 — Root layout, fonts and providers

`frontend/src/app/providers.tsx`

```tsx
"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";

import { Toaster } from "@/components/ui/sonner";

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(
    () => new QueryClient({ defaultOptions: { queries: { staleTime: 30_000, retry: 1 } } }),
  );

  return (
    <QueryClientProvider client={queryClient}>
      {children}
      <Toaster richColors position="top-right" />
    </QueryClientProvider>
  );
}
```

`frontend/src/app/layout.tsx` (replace the generated file; 0.4 adds the locale)

```tsx
import type { Metadata } from "next";
import { Noto_Sans_JP, Source_Sans_3 } from "next/font/google";

import { Providers } from "./providers";
import "./globals.css";

const sourceSans = Source_Sans_3({
  subsets: ["latin"],
  variable: "--font-source-sans",
  display: "swap",
});

const notoSansJp = Noto_Sans_JP({
  variable: "--font-noto-sans-jp",
  display: "swap",
  preload: false,
});

export const metadata: Metadata = {
  title: "kumo HR",
  description: "HR and attendance for Naniwa Systems",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${sourceSans.variable} ${notoSansJp.variable}`}>
      <body className="bg-background font-sans text-foreground antialiased">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
```

`frontend/src/app/page.tsx` (replace the starter page)

```tsx
import { redirect } from "next/navigation";

export default function Home() {
  redirect("/dashboard");
}
```

### Step 5 — App shell: sidebar, top bar, page header

`frontend/src/components/layout/nav-config.ts`

```ts
import type en from "../../../messages/en.json";

export type NavKey = keyof (typeof en)["nav"];

export type NavItem = { href: string; labelKey: NavKey };

// Each inner array is one group in the sidebar, separated by a divider.
export const navSections: NavItem[][] = [
  [
    { href: "/dashboard", labelKey: "dashboard" },
    { href: "/people", labelKey: "people" },
  ],
  [
    { href: "/time-tracking", labelKey: "timeTracking" },
    { href: "/time-off", labelKey: "timeOff" },
    { href: "/travel", labelKey: "travel" },
    { href: "/reports", labelKey: "reports" },
  ],
  [
    { href: "/payslips", labelKey: "payslips" },
    { href: "/settings", labelKey: "settings" },
    { href: "/help", labelKey: "help" },
  ],
];
```

Role-based hiding (HR-only items) is added in phase 1.2, once there is a logged-in user.

`frontend/src/components/layout/sidebar.tsx`

```tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { cn } from "@/lib/utils";

import en from "../../../messages/en.json";
import { navSections } from "./nav-config";

export function Sidebar() {
  const pathname = usePathname();

  return (
    <nav className="w-40 shrink-0 bg-sidebar px-3 py-5 text-sm text-sidebar-foreground">
      {navSections.map((section, index) => (
        <ul key={index} className="mb-3 space-y-1 border-b border-sidebar-border pb-3">
          {section.map((item) => {
            const active = pathname === item.href || pathname.startsWith(`${item.href}/`);
            return (
              <li key={item.href}>
                <Link
                  href={item.href}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "block rounded-md px-3 py-2 hover:bg-sidebar-accent",
                    active && "bg-sidebar-accent font-semibold text-sidebar-accent-foreground",
                  )}
                >
                  {en.nav[item.labelKey]}
                </Link>
              </li>
            );
          })}
        </ul>
      ))}
    </nav>
  );
}
```

`frontend/src/components/layout/top-bar.tsx`

```tsx
import { Bell, Search } from "lucide-react";

import { Input } from "@/components/ui/input";

import en from "../../../messages/en.json";

export function TopBar() {
  return (
    <header className="flex h-14 items-center justify-between border-b border-border bg-card px-5">
      <span className="text-xl font-bold text-foreground-strong">kumo</span>
      <div className="flex items-center gap-5">
        <div className="relative w-52">
          <Search className="absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
          <Input placeholder={en.topBar.searchPeople} className="pl-8" />
        </div>
        <button type="button" aria-label={en.topBar.notifications} className="text-foreground">
          <Bell className="size-5" />
        </button>
        <div className="border-l border-border pl-4 text-sm">
          <span className="block font-semibold text-foreground-strong">
            {en.userMenu.placeholderName}
          </span>
          <span className="block text-xs text-muted-foreground">{en.userMenu.placeholderRole}</span>
        </div>
      </div>
    </header>
  );
}
```

`frontend/src/components/layout/page-header.tsx`

```tsx
export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: string;
  actions?: React.ReactNode;
}) {
  return (
    <div className="mb-6 flex items-start justify-between gap-4">
      <div>
        <h1 className="text-3xl font-bold">{title}</h1>
        {description && <p className="mt-1 text-sm text-muted-foreground">{description}</p>}
      </div>
      {actions}
    </div>
  );
}
```

`frontend/src/app/(app)/layout.tsx`

```tsx
import { Sidebar } from "@/components/layout/sidebar";
import { TopBar } from "@/components/layout/top-bar";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col">
      <TopBar />
      <div className="flex flex-1">
        <Sidebar />
        <main className="flex-1 px-10 py-8">{children}</main>
      </div>
    </div>
  );
}
```

### Step 6 — Placeholder pages

Run this from the repo root. It creates one placeholder `page.tsx` per route in §5; each phase later replaces its own pages.

```bash
cd frontend/src/app
while IFS='|' read -r route title; do
  mkdir -p "$route"
  cat > "$route/page.tsx" <<EOF
import { PageHeader } from "@/components/layout/page-header";

export default function Page() {
  return <PageHeader title="$title" />;
}
EOF
done <<'ROUTES'
(app)/dashboard|Dashboard
(app)/people|People
(app)/people/new|New member
(app)/people/[memberId]|Member profile
(app)/people/[memberId]/skills|Skills and career
(app)/people/[memberId]/time-off|Member time off
(app)/people/[memberId]/payslips|Member payslips
(app)/time-tracking|Time tracking
(app)/time-tracking/[memberId]/[month]|Monthly timesheet
(app)/time-off|Time off
(app)/time-off/calendar|Team calendar
(app)/travel|Travel expenses
(app)/travel/[claimId]|Travel claim
(app)/reports|Reports
(app)/payslips|Payslips
(app)/notifications|Notifications
(app)/me|My page
(app)/me/timesheet|My timesheet
(app)/me/reports|My reports
(app)/me/payslips|My payslips
(app)/settings|Company settings
(app)/settings/departments|Departments
(app)/settings/leave-categories|Leave categories
(app)/help|Help
(auth)/login|Log in
(auth)/set-password/[token]|Set password
(auth)/change-password|Change password
(auth)/reset-password|Reset password
(auth)/reset-password/[token]|Choose a new password
ROUTES
cd -
```

The English titles here are temporary. 0.4 converts the dashboard to message files, and each phase does the same for its own pages.

### Step 7 — `frontend/src/lib/api-client.ts`

```ts
export type ApiErrorBody = {
  error: { code: string; message: string; details?: unknown };
};

export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
    public details?: unknown,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

const UNSAFE_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);

function getCookie(name: string): string | undefined {
  if (typeof document === "undefined") return undefined;
  const row = document.cookie.split("; ").find((item) => item.startsWith(`${name}=`));
  return row ? decodeURIComponent(row.split("=")[1]) : undefined;
}

/** Browser-side fetch to the Django API. Paths are relative to /api/v1, e.g. "/members/". */
export async function apiFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const method = (init.method ?? "GET").toUpperCase();
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body && !(init.body instanceof FormData) && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  if (UNSAFE_METHODS.has(method)) {
    const csrfToken = getCookie("csrftoken");
    if (csrfToken) headers.set("X-CSRFToken", csrfToken);
  }

  const response = await fetch(`/api/v1${path}`, {
    ...init,
    method,
    headers,
    credentials: "include",
  });

  if (response.status === 204) return undefined as T;
  const body: unknown = await response.json().catch(() => null);

  if (!response.ok) {
    const error = (body as ApiErrorBody | null)?.error;
    if (response.status === 403 && error?.code === "password_change_required") {
      window.location.assign("/change-password");
    }
    throw new ApiError(
      response.status,
      error?.code ?? "unknown_error",
      error?.message ?? response.statusText,
      error?.details,
    );
  }
  return body as T;
}

function jsonBody(data: unknown): BodyInit {
  return data instanceof FormData ? data : JSON.stringify(data ?? {});
}

export const api = {
  get: <T>(path: string) => apiFetch<T>(path),
  post: <T>(path: string, data?: unknown) =>
    apiFetch<T>(path, { method: "POST", body: jsonBody(data) }),
  put: <T>(path: string, data?: unknown) =>
    apiFetch<T>(path, { method: "PUT", body: jsonBody(data) }),
  patch: <T>(path: string, data?: unknown) =>
    apiFetch<T>(path, { method: "PATCH", body: jsonBody(data) }),
  delete: <T>(path: string) => apiFetch<T>(path, { method: "DELETE" }),
};
```

This client is for client components. Server components that call the API come later and must forward the user's cookies (§6 "Things that commonly go wrong").

### Step 8 — Type generator

```bash
docker compose exec frontend npm i -D openapi-typescript
mkdir -p frontend/src/types
```

Add to the `Makefile` (and add `types` to the `.PHONY` line):

```make
types:
	docker compose exec frontend npx openapi-typescript http://backend:8000/api/schema/ -o src/types/api.d.ts
```

Run `make types` once; it creates `frontend/src/types/api.d.ts`. Commit the generated file and never edit it by hand.

### Step 9 — Vitest and Testing Library

```bash
docker compose exec frontend npm i -D vitest @vitejs/plugin-react jsdom vite-tsconfig-paths \
  @testing-library/react @testing-library/dom @testing-library/jest-dom
docker compose exec frontend npm pkg set scripts.test="vitest run"
```

`frontend/vitest.config.mts`

```ts
import react from "@vitejs/plugin-react";
import tsconfigPaths from "vite-tsconfig-paths";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [tsconfigPaths(), react()],
  test: {
    environment: "jsdom",
    setupFiles: ["./src/tests/setup.ts"],
  },
});
```

`frontend/src/tests/setup.ts`

```ts
import "@testing-library/jest-dom/vitest";

import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

afterEach(() => cleanup());
```

`frontend/src/tests/sidebar.test.tsx`

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { Sidebar } from "@/components/layout/sidebar";

vi.mock("next/navigation", () => ({ usePathname: () => "/time-off/calendar" }));

describe("Sidebar", () => {
  it("marks the section containing the current page as active", () => {
    render(<Sidebar />);
    expect(screen.getByRole("link", { name: "Time off" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("link", { name: "Dashboard" })).not.toHaveAttribute("aria-current");
  });
});
```

### Step 10 — Verify

```bash
docker compose exec frontend npm run lint
docker compose exec frontend npm test
make test
```

Open http://localhost:3000. It should redirect to `/dashboard` and look like the frame of `docs/screenshots/Dashboard (HR admin).png`: white top bar with "kumo", navy sidebar with three groups, light grey page with a Georgia "Dashboard" heading. Click through every sidebar link.

**Commit, push and merge** `stage0/frontend`.

---

## 0.4 ja/en setup

**Goal:** the language switcher in the user menu flips the app between English and Japanese, including date formats.

```bash
git switch main && git pull && git switch -c stage0/i18n
make up
docker compose exec frontend npm i next-intl@^4
```

The locale is stored in a `NEXT_LOCALE` cookie rather than in the URL. That suits an app behind a login, and the routes stay as they are. Django reads the same cookie (`LANGUAGE_COOKIE_NAME` in 0.2), so emails and API messages follow the same choice.

### Step 1 — next-intl config

`frontend/src/i18n/config.ts`

```ts
export const locales = ["ja", "en"] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = "ja";
export const LOCALE_COOKIE = "NEXT_LOCALE";

export function isLocale(value: string | undefined): value is Locale {
  return locales.includes(value as Locale);
}
```

`frontend/src/i18n/request.ts`

```ts
import { cookies } from "next/headers";
import { getRequestConfig } from "next-intl/server";

import { defaultLocale, isLocale, LOCALE_COOKIE } from "./config";

export default getRequestConfig(async () => {
  const cookieLocale = (await cookies()).get(LOCALE_COOKIE)?.value;
  const locale = isLocale(cookieLocale) ? cookieLocale : defaultLocale;

  return {
    locale,
    timeZone: "Asia/Tokyo",
    messages: (await import(`../../messages/${locale}.json`)).default,
  };
});
```

`frontend/next.config.ts` — wrap the config from 0.1 with the next-intl plugin:

```ts
import type { NextConfig } from "next";
import createNextIntlPlugin from "next-intl/plugin";

const withNextIntl = createNextIntlPlugin();

const apiUrl = process.env.API_INTERNAL_URL ?? "http://localhost:8000";

const nextConfig: NextConfig = {
  output: "standalone",
  // Django URLs end in "/"; without this Next.js redirects them to the slash-less form.
  skipTrailingSlashRedirect: true,
  async rewrites() {
    return [
      { source: "/api/:path*/", destination: `${apiUrl}/api/:path*/` },
      { source: "/api/:path*", destination: `${apiUrl}/api/:path*` },
    ];
  },
};

export default withNextIntl(nextConfig);
```

`frontend/src/app/layout.tsx` — make it locale-aware:

```tsx
import type { Metadata } from "next";
import { Noto_Sans_JP, Source_Sans_3 } from "next/font/google";
import { NextIntlClientProvider } from "next-intl";
import { getLocale } from "next-intl/server";

import { Providers } from "./providers";
import "./globals.css";

const sourceSans = Source_Sans_3({
  subsets: ["latin"],
  variable: "--font-source-sans",
  display: "swap",
});

const notoSansJp = Noto_Sans_JP({
  variable: "--font-noto-sans-jp",
  display: "swap",
  preload: false,
});

export const metadata: Metadata = {
  title: "kumo HR",
  description: "HR and attendance for Naniwa Systems",
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const locale = await getLocale();

  return (
    <html lang={locale} className={`${sourceSans.variable} ${notoSansJp.variable}`}>
      <body className="bg-background font-sans text-foreground antialiased">
        <NextIntlClientProvider>
          <Providers>{children}</Providers>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
```

`NextIntlClientProvider` with no props passes the server's locale and messages to client components (next-intl 4).

### Step 2 — Japanese messages

`frontend/messages/ja.json` (labels match `docs/screenshots/[JA] Dashboard (HR admin).png`)

```json
{
  "nav": {
    "dashboard": "ダッシュボード",
    "people": "社員",
    "timeTracking": "勤怠",
    "timeOff": "休暇",
    "travel": "交通費精算",
    "reports": "レポート",
    "payslips": "給与明細",
    "settings": "会社設定",
    "help": "ヘルプ"
  },
  "topBar": {
    "searchPeople": "社員を検索",
    "notifications": "お知らせ"
  },
  "userMenu": {
    "placeholderName": "森 花",
    "placeholderRole": "人事管理者・なにわシステムズ",
    "language": "言語",
    "languages": { "en": "English", "ja": "日本語" }
  },
  "dashboard": {
    "title": "ダッシュボード"
  },
  "enums": {
    "gender": { "1": "男性", "2": "女性" },
    "employmentType": { "1": "正社員", "2": "契約社員", "3": "パート" },
    "languageLevel": { "1": "上級", "2": "中級", "3": "初級" }
  }
}
```

Both files must always have the same keys. Add a key to both in the same commit.

### Step 3 — Use translations in the shell

`frontend/src/components/layout/sidebar.tsx` — replace the `en` import with `useTranslations`:

```tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";

import { cn } from "@/lib/utils";

import { navSections } from "./nav-config";

export function Sidebar() {
  const pathname = usePathname();
  const t = useTranslations("nav");

  return (
    <nav className="w-40 shrink-0 bg-sidebar px-3 py-5 text-sm text-sidebar-foreground">
      {navSections.map((section, index) => (
        <ul key={index} className="mb-3 space-y-1 border-b border-sidebar-border pb-3">
          {section.map((item) => {
            const active = pathname === item.href || pathname.startsWith(`${item.href}/`);
            return (
              <li key={item.href}>
                <Link
                  href={item.href}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "block rounded-md px-3 py-2 hover:bg-sidebar-accent",
                    active && "bg-sidebar-accent font-semibold text-sidebar-accent-foreground",
                  )}
                >
                  {t(item.labelKey)}
                </Link>
              </li>
            );
          })}
        </ul>
      ))}
    </nav>
  );
}
```

`frontend/src/components/layout/user-menu.tsx` — new, with the language switcher:

```tsx
"use client";

import { Check, ChevronDown } from "lucide-react";
import { useRouter } from "next/navigation";
import { useLocale, useTranslations } from "next-intl";
import { useTransition } from "react";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { type Locale, LOCALE_COOKIE, locales } from "@/i18n/config";

export function UserMenu() {
  const t = useTranslations("userMenu");
  const locale = useLocale();
  const router = useRouter();
  const [isPending, startTransition] = useTransition();

  function switchLocale(next: Locale) {
    document.cookie = `${LOCALE_COOKIE}=${next}; path=/; max-age=31536000; samesite=lax`;
    startTransition(() => router.refresh());
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        disabled={isPending}
        className="flex items-center gap-2 border-l border-border pl-4 text-left text-sm"
      >
        <span>
          <span className="block font-semibold text-foreground-strong">{t("placeholderName")}</span>
          <span className="block text-xs text-muted-foreground">{t("placeholderRole")}</span>
        </span>
        <ChevronDown className="size-4 text-muted-foreground" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuLabel>{t("language")}</DropdownMenuLabel>
        {locales.map((option) => (
          <DropdownMenuItem key={option} onSelect={() => switchLocale(option)}>
            {t(`languages.${option}`)}
            {option === locale && <Check className="ml-auto size-4" />}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
```

The name and role are placeholders until phase 1.2 provides the logged-in user; the logout item is added then too.

`frontend/src/components/layout/top-bar.tsx` — use translations and the new menu:

```tsx
import { Bell, Search } from "lucide-react";
import { useTranslations } from "next-intl";

import { Input } from "@/components/ui/input";

import { UserMenu } from "./user-menu";

export function TopBar() {
  const t = useTranslations("topBar");

  return (
    <header className="flex h-14 items-center justify-between border-b border-border bg-card px-5">
      <span className="text-xl font-bold text-foreground-strong">kumo</span>
      <div className="flex items-center gap-5">
        <div className="relative w-52">
          <Search className="absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
          <Input placeholder={t("searchPeople")} className="pl-8" />
        </div>
        <button type="button" aria-label={t("notifications")} className="text-foreground">
          <Bell className="size-5" />
        </button>
        <UserMenu />
      </div>
    </header>
  );
}
```

### Step 4 — Label and format helpers

`frontend/src/lib/format.ts`

```ts
const TIME_ZONE = "Asia/Tokyo";

export function formatDate(
  value: Date | string,
  locale: string,
  options: Intl.DateTimeFormatOptions = { dateStyle: "medium" },
): string {
  const date = typeof value === "string" ? new Date(value) : value;
  return new Intl.DateTimeFormat(locale, { timeZone: TIME_ZONE, ...options }).format(date);
}

export function formatYen(amount: number, locale: string): string {
  return new Intl.NumberFormat(locale, { style: "currency", currency: "JPY" }).format(amount);
}

/** 9.5 → "9:30" */
export function formatHours(hours: number | string): string {
  const totalMinutes = Math.round(Number(hours) * 60);
  const h = Math.floor(totalMinutes / 60);
  const m = totalMinutes % 60;
  return `${h}:${String(m).padStart(2, "0")}`;
}
```

`frontend/src/lib/enums.ts`

```ts
import { useTranslations } from "next-intl";

// Values match the backend IntegerChoices (PROJECT_STRUCTURE.md §3).
export const Gender = { MALE: 1, FEMALE: 2 } as const;
export const EmploymentType = { FULL_TIME: 1, CONTRACT: 2, PART_TIME: 3 } as const;
export const LanguageLevel = { ADVANCED: 1, INTERMEDIATE: 2, BASIC: 3 } as const;

export type EnumName = "gender" | "employmentType" | "languageLevel";

/** const label = useEnumLabel("languageLevel"); label(1) → "Advanced" / "上級" */
export function useEnumLabel(name: EnumName) {
  const t = useTranslations(`enums.${name}`);
  return (value: number) => t(String(value));
}
```

### Step 5 — Convert the dashboard page

`frontend/src/app/(app)/dashboard/page.tsx`

```tsx
import { useLocale, useTranslations } from "next-intl";

import { PageHeader } from "@/components/layout/page-header";
import { formatDate } from "@/lib/format";

export default function DashboardPage() {
  const t = useTranslations("dashboard");
  const locale = useLocale();

  return (
    <PageHeader title={t("title")} description={formatDate(new Date(), locale, { dateStyle: "full" })} />
  );
}
```

### Step 6 — Update the sidebar test

The sidebar now needs the translation provider. Replace `frontend/src/tests/sidebar.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import { Sidebar } from "@/components/layout/sidebar";

import en from "../../messages/en.json";
import ja from "../../messages/ja.json";

vi.mock("next/navigation", () => ({ usePathname: () => "/time-off/calendar" }));

function renderSidebar(locale: "en" | "ja") {
  return render(
    <NextIntlClientProvider locale={locale} messages={locale === "en" ? en : ja}>
      <Sidebar />
    </NextIntlClientProvider>,
  );
}

describe("Sidebar", () => {
  it("marks the section containing the current page as active", () => {
    renderSidebar("en");
    expect(screen.getByRole("link", { name: "Time off" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("link", { name: "Dashboard" })).not.toHaveAttribute("aria-current");
  });

  it("shows Japanese labels", () => {
    renderSidebar("ja");
    expect(screen.getByRole("link", { name: "休暇" })).toBeInTheDocument();
  });
});

describe("message files", () => {
  it("have the same keys in English and Japanese", () => {
    const keys = (obj: object, prefix = ""): string[] =>
      Object.entries(obj).flatMap(([key, value]) =>
        typeof value === "object" && value !== null
          ? keys(value, `${prefix}${key}.`)
          : [`${prefix}${key}`],
      );
    expect(keys(ja).sort()).toEqual(keys(en).sort());
  });
});
```

### Step 7 — Django translation pipeline

The settings from 0.2 already include `LocaleMiddleware`, `LANGUAGES` and `LOCALE_PATHS`, and the image has `gettext`. Prove the pipeline once with the app names:

```bash
docker compose exec backend sh -c "mkdir -p locale && python manage.py makemessages -l ja"
```

Open `backend/locale/ja/LC_MESSAGES/django.po` and fill in these `msgstr` values:

```text
msgid "Core"
msgstr "共通"

msgid "Accounts"
msgstr "アカウント"

msgid "Japanese"
msgstr "日本語"

msgid "English"
msgstr "英語"
```

Then compile (the entrypoint also does this on every start; `.mo` files are git-ignored):

```bash
docker compose exec backend python manage.py compilemessages
```

`backend/apps/core/tests/test_i18n.py`

```python
from django.apps import apps
from django.utils import translation


def test_japanese_translations_are_compiled():
    with translation.override("ja"):
        assert str(apps.get_app_config("core").verbose_name) == "共通"


def test_english_is_the_source_language():
    with translation.override("en"):
        assert str(apps.get_app_config("core").verbose_name) == "Core"
```

### Step 8 — Rule from here on

No hard-coded UI strings: every label goes into both message files. To have ESLint enforce it, add `"react/jsx-no-literals": "warn"` to the rules in `frontend/eslint.config.mjs`. Expect warnings on the placeholder pages until their phases replace them.

### Step 9 — Verify

```bash
make test
docker compose exec frontend npm run lint
docker compose exec backend ruff check .
```

At http://localhost:3000, open the user menu and switch language. The sidebar, the search placeholder and the dashboard heading change, and the date under the heading switches between `2026年10月6日火曜日` and `Tuesday, October 6, 2026`. Reload the page; the choice is kept. With Japanese selected, the Django admin shows "共通" as the section name.

**Commit, push and merge** `stage0/i18n`.

---

## 0.5 CI

**Goal:** every pull request runs the private-term check, lint, tests and the production image build.

```bash
git switch main && git pull && git switch -c stage0/ci
```

### Step 1 — Placeholder `compose.prod.yaml`

The full version (scheduler, nginx, media volume) comes in Stage 4, but the production images must build from now on.

```yaml
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data

  backend:
    build: { context: ./backend, target: prod }
    env_file: .env
    environment:
      DJANGO_SETTINGS_MODULE: config.settings.prod
    depends_on: [db]

  frontend:
    build: { context: ./frontend, target: prod }
    environment:
      API_INTERNAL_URL: http://backend:8000
    depends_on: [backend]

volumes:
  pgdata:
```

Check it builds locally before pushing:

```bash
docker compose -f compose.prod.yaml build
```

### Step 2 — `.github/workflows/ci.yml`

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Private-term check
        env:
          PRIVATE_TERMS: ${{ secrets.PRIVATE_TERMS }}
        run: |
          if [ -z "$PRIVATE_TERMS" ]; then
            echo "PRIVATE_TERMS secret is not set"; exit 1
          fi
          printf '%s\n' "$PRIVATE_TERMS" | sed '/^[[:space:]]*$/d' > .private-terms
          bash scripts/check-private-terms.sh
          rm .private-terms

      - name: Environment file
        run: cp .env.example .env

      - name: Build dev images
        run: docker compose build

      - name: Backend lint
        run: docker compose run --rm backend ruff check .

      - name: Backend tests
        run: docker compose run --rm backend pytest

      - name: Frontend lint
        run: docker compose run --rm frontend npm run lint

      - name: Frontend tests
        run: docker compose run --rm frontend npm test

      - name: Build prod images
        run: docker compose -f compose.prod.yaml build
```

Blank lines are stripped from the secret because an empty pattern would match every line of every file.

### Step 3 — `PRIVATE_TERMS` secret

On GitHub: **Settings → Secrets and variables → Actions → New repository secret**.

- Name: `PRIVATE_TERMS`
- Value: the contents of your local `.private-terms`, one term per line.

### Step 4 — Verify

Push the branch and open the pull request. The **CI** check should go green; click it to see each step. If a step fails, the log shows the same output you'd get running that command locally.

Merge it, then tick the five Stage 0 boxes in `docs/ROADMAP.md` in a small follow-up commit.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `docker: error during connect … dockerDesktopLinuxEngine` | Docker Desktop isn't running. Start it. |
| `C:/Program Files/Git/app: no such file` | Git Bash path conversion. Prefix the command with `MSYS_NO_PATHCONV=1`. |
| Backend exits with `entrypoint.sh: no such file or directory` | CRLF line endings. Switch the file to LF in Cursor and save. |
| `make: command not found` | Install make (`winget install ezwinports.make`) and reopen the terminal, or run the `docker compose` line from the `Makefile` directly. |
| `Dependency on app with no migrations: accounts` | Run `makemigrations` with `--entrypoint ""` as in 0.2 step 8, then `make reset-db`. |
| Frontend can't find a package you just installed | It was installed on the host instead of the container. Use `docker compose exec frontend npm i …`, or run `docker compose up -d --build -V`. |
| Hot reload doesn't fire | Check `WATCHPACK_POLLING: "true"` on the frontend service. |
| A POST to `/api/...` returns 403 CSRF | The request must send `X-CSRFToken`; use `api-client.ts`, which reads the `csrftoken` cookie. |
