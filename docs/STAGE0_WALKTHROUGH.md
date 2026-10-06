# kumo HR — Stage 0 Walkthrough

> Step-by-step guide for Stage 0 of `ROADMAP.md`: an empty but working stack that starts with `make up`, plus green CI.
> File contents referenced as "§n" come from `PROJECT_STRUCTURE.md`.

**Done when** a fresh clone → `cp .env.example .env && make up` shows the empty themed app with a working language switcher, `make test` passes, and CI is green.

---

## Before you start

- **Requirements:** Docker Desktop (or Docker Engine with the Compose plugin) and Git. You don't need Node or Python on your machine; every scaffolding command below runs inside a container.
- **Branching:** one branch and one pull request per phase, e.g. `git switch -c stage0/docker`.
- **One-time setup:**

  ```bash
  touch .private-terms          # add your real name, internal hostnames etc., one per line
  ./scripts/install-hooks.sh    # pre-commit private-term check
  ```

---

## 0.1 Repo and Docker

The Dockerfiles copy `requirements/` and `package.json`, so both projects must exist before the first build.

1. **Scaffold Django** inside a throwaway Python container:

   ```bash
   mkdir -p backend/requirements
   docker run --rm -v "$PWD/backend":/app -w /app python:3.12-slim \
     sh -c "pip install -q django && django-admin startproject config ."
   ```

2. **Add the requirements files** (package list in §5). Pin major versions.
   - `backend/requirements/base.txt`: django, djangorestframework, drf-spectacular, django-filter, django-cors-headers, django-simple-history, django-storages, openpyxl, psycopg[binary], dj-database-url
   - `backend/requirements/dev.txt`: `-r base.txt` + pytest, pytest-django, factory_boy, ruff
   - `backend/requirements/prod.txt`: `-r base.txt` + gunicorn

3. **Scaffold Next.js:**

   ```bash
   docker run --rm -it -v "$PWD":/w -w /w node:22-alpine \
     npx create-next-app@latest frontend --ts --eslint --tailwind --app --src-dir --import-alias "@/*" --use-npm
   ```

4. **Write the container files**, copied from the spec:
   - `backend/Dockerfile` (§6)
   - `frontend/Dockerfile` (§6)
   - `compose.yaml` (§6)
   - `.env.example` (§6)
   - `backend/.dockerignore` (§2) and `frontend/.dockerignore` (§5)

5. **Write `backend/entrypoint.sh`.** It waits for the database, runs `migrate`, then `createcachetable` (needed later for the password-reset limit, `BUSINESS_RULES.md` §6.3), then `exec "$@"`. Mark it executable in git too, or the container fails on Windows and macOS checkouts:

   ```bash
   chmod +x backend/entrypoint.sh && git update-index --chmod=+x backend/entrypoint.sh
   ```

6. **Add the API proxy.** In `frontend/next.config.ts`, set `output: 'standalone'` and add a rewrite from `/api/:path*` to `${API_INTERNAL_URL}/api/:path*`.

7. **Add the `Makefile`** with `up`, `down`, `logs`, `migrate`, `test` and `reset-db` (§9). `seed` and `types` come later.

8. **Verify:**

   ```bash
   cp .env.example .env && make up
   ```

   These should all respond:
   - http://localhost:8000/admin — Django admin
   - http://localhost:3000 — Next.js starter
   - http://localhost:8025 — mailpit

**Pitfalls**
- The `ADD … supercronic-linux-${TARGETARCH}` line needs BuildKit. Compose uses it by default.
- If hot reload doesn't fire on macOS or Windows, check that `WATCHPACK_POLLING` is set.
- `localhost` inside a container is that container. The frontend reaches Django at `http://backend:8000`.

---

## 0.2 Backend skeleton

1. **Split the settings.** Turn `config/settings.py` into a `config/settings/` package with `base`, `dev`, `test` and `prod` modules. In `base.py`:
   - `TIME_ZONE = "Asia/Tokyo"`, `USE_TZ = True`
   - `LANGUAGES = [("ja", …), ("en", …)]`
   - `DATABASES` read from `DATABASE_URL` with `dj-database-url`
   - `CACHES` using `DatabaseCache`
   - `SESSION_COOKIE_AGE = 1800`, `SESSION_SAVE_EVERY_REQUEST = True`
   - DRF defaults: session authentication, pagination, the custom exception handler

2. **Create the `accounts` app with a custom `User` now, before the first real migration.** The roadmap puts accounts in phase 1.2, but `AUTH_USER_MODEL` is very hard to change once migrations exist. For now the model only needs `email` as the login field; phase 1.2 adds the lockout fields. Then wipe the database once:

   ```bash
   make reset-db
   ```

3. **Create `apps/core`:**
   - `models.py`: `TimeStampedModel`, `SoftDeleteModel`, `ErrorLog`
   - `managers.py`: `ActiveManager`
   - `permissions.py`: `IsHRAdmin`, `IsSelfOrHR`
   - `exceptions.py`: the unified error format
   - `logging.py`: `DatabaseErrorHandler`, connected in `LOGGING`
   - `admin.py`: a read-only `ErrorLog` admin

4. **Write `core/utils/dates.py` test-first.** Test cases:
   - `claim_period(2026-10)` → 2026-09-16 to 2026-10-15
   - `timesheet_close_date(2026-09)` → 2026-10-07
   - `month_range` gets the last day of February right, including leap years

5. **Wire up the routes** in `config/urls.py`: `/admin/`, `/api/v1/`, `/api/schema/`, `/api/docs/`.

6. **Configure the tools.** Ruff settings in `pyproject.toml`; `pytest.ini` with `DJANGO_SETTINGS_MODULE=config.settings.test`.

7. **Verify:**

   ```bash
   docker compose run --rm backend pytest
   docker compose run --rm backend ruff check .
   ```

   Then open http://localhost:8000/api/docs/.

---

## 0.3 Frontend skeleton

1. **Set up shadcn/ui:**

   ```bash
   docker compose exec frontend npx shadcn@latest init
   ```

   Add the starter components: button, card, input, dropdown-menu, badge, table, dialog, sonner.

2. **Put the theme tokens in `globals.css`** as shadcn CSS variables (§7), with `--radius: 6px`.
   Note: newer create-next-app versions set up Tailwind v4, which has no `tailwind.config.ts` (its config lives in CSS). That's fine; the spec lists the file only out of habit.

3. **Set up fonts in `layout.tsx`:** Georgia for headings; Source Sans 3 with Noto Sans JP as fallback for body text, loaded through `next/font`.

4. **Set up `providers.tsx`** with a `QueryClientProvider` and the `Toaster`.

5. **Build the app layout** in `(app)/layout.tsx`: the navy sidebar driven by `components/layout/nav-config.ts`, plus the top bar. Add an empty placeholder page for each route in §5.

6. **Write `lib/api-client.ts`:**
   - Always call relative `/api/...` paths with `credentials: 'include'`.
   - Read the `csrftoken` cookie and send it as the `X-CSRFToken` header.
   - Map error responses to the backend's error format.

7. **Add the type generator:**

   ```bash
   docker compose exec frontend npm i -D openapi-typescript
   ```

   Then add the `make types` target (§9).

8. **Set up Vitest and Testing Library** with one smoke test for the layout.

9. **Verify:**

   ```bash
   docker compose exec frontend npm run lint
   docker compose exec frontend npm test
   ```

   Compare the placeholder pages with the layout in the Dashboard mockup.

---

## 0.4 ja/en setup

1. **Install next-intl** with the **cookie-based locale** setup rather than a locale in the URL. That suits an app behind a login, and the routes in the spec stay as they are.

2. **Create `messages/en.json` and `messages/ja.json`.** Add a language switcher to the top-bar user menu that sets the `NEXT_LOCALE` cookie.

3. **Add labels and formatting:**
   - `lib/enums.ts` turns backend enum values into labels through the message files.
   - `lib/format.ts` formats dates and hours for the current locale.

4. **Set up Django i18n:** add `LocaleMiddleware`, set `LOCALE_PATHS`, and run `makemessages -l ja` once to prove the email-translation pipeline works.

5. **Rule from here on:** no hard-coded UI strings. ESLint's `react/jsx-no-literals` rule can enforce this if you want.

6. **Verify:** switching the language changes the sidebar labels and the date format.

---

## 0.5 CI

1. **Create `.github/workflows/ci.yml`.** Run it on pull requests and on pushes to `main`. Steps:
   - Check out the repo, then `cp .env.example .env`.
   - Write the `PRIVATE_TERMS` repository secret to `.private-terms`, then run `scripts/check-private-terms.sh`.
   - `docker compose build`
   - Run the four checks from §6 CI:

     ```bash
     docker compose run --rm backend ruff check .
     docker compose run --rm backend pytest
     docker compose run --rm frontend npm run lint
     docker compose run --rm frontend npm test
     ```

   - `docker compose -f compose.prod.yaml build`

2. **Add a placeholder `compose.prod.yaml`.** The full version comes in Stage 4, but the prod build must work now. For now it needs only `db`, `backend` (prod target) and `frontend` (prod target).

3. **Add the `PRIVATE_TERMS` secret** under GitHub → Settings → Secrets and variables → Actions.

4. **Verify:** open the pull request and confirm all checks are green. Then tick the Stage 0 boxes in `ROADMAP.md`.
