# kumo HR — Stage 0 Troubleshooting Log (Steps 5–6)

> What went wrong while working through Step 5 (`backend/entrypoint.sh`) and Step 6 (`frontend/next.config.ts`) of `STAGE0_WALKTHROUGH.md`, how each problem was found, and how it was fixed.
> Branch: `stage0/docker`. Date: 2026-10-07.

**Outcome:** `docker compose up --build -d` brings up all four containers. `db` and `mailpit` report healthy, the backend runs its migrations and serves on `:8000`, the frontend serves on `:3000`, and `/api/...` on the frontend is proxied to Django.

---

## Summary

| # | File | Problem | Effect | Status |
|---|------|---------|--------|--------|
| 1 | `backend/entrypoint.sh` | `2>/dev/null` on its own line | Database wait loop exited immediately | Fixed |
| 2 | `backend/entrypoint.sh` | `[ -d local ]` instead of `[ -d locale ]` | `compilemessages` would never run | Fixed |
| 3 | `.env` | `POSTGRE_DB` instead of `POSTGRES_DB` | `db` healthcheck failed, so the backend never started | Fixed |
| 4 | `.env` | `DJANGO_ALLOWED_HOOSTS` instead of `DJANGO_ALLOWED_HOSTS` | Setting would be ignored once 0.2 reads it | Fixed |
| 5 | `.env` | Spaces after commas in `DJANGO_ALLOWED_HOSTS` | Hosts would not match after `.split(",")` in 0.2 | Fixed |
| 6 | `frontend/next.config.ts` | Five typos (see below) | Proxy rules ignored; nothing reached Django | Fixed |
| 7 | `backend/config/settings.py` | `ALLOWED_HOSTS = []` | `/api/` returns `400 DisallowedHost` | Expected until Stage 0.2 |
| 8 | git | `backend/db.sqlite3` committed and pushed | Stray file in the repo | **Open** |

---

## Step 5 — `backend/entrypoint.sh`

### 1. The database wait loop never waited

**Symptom.** No visible error at first. `docker stats` showed no running containers.

**Cause.** The redirect had wrapped onto its own line:

```bash
until python -c "import os, psycopg; ...close()"
2>/dev/null
do
```

Bash reads `2>/dev/null` as a second command inside the `until` condition. The loop checks only the exit status of the *last* command in the condition, and a bare redirect always succeeds. So the loop ended on the first pass, whether Postgres was ready or not, and `migrate` could run against a database that wasn't up yet. Because of `set -e`, that failure would kill the container.

**Fix.** Keep the redirect on the same line as the command:

```bash
until python -c "import os, psycopg; psycopg.connect(os.environ['DATABASE_URL'], connect_timeout=2).close()" 2>/dev/null
do
    sleep 1
done
```

### 2. `local` instead of `locale`

**Cause.** `if [ -d local ]` checks for a folder that will never exist. `LOCALE_PATHS` in 0.2 points to `BASE_DIR / "locale"`.

**Fix.** `if [ -d locale ]; then`.

### Checked and fine

- **Line endings.** `file backend/entrypoint.sh` reports plain ASCII (LF), and `.gitattributes` enforces `*.sh text eol=lf`.
- **Shebang.** The file uses `#!/bin/bash` while the guide uses `#!/bin/sh`. Both work because `python:3.12-slim` includes bash.

---

## Running the stack — `.env` problems

### 3. `db` unhealthy: `POSTGRE_DB`

**Symptom.**

```text
✘ Container kumo_hr-db-1       Error dependency db failed to start
dependency failed to start: container kumo_hr-db-1 is unhealthy
```

and Compose warned:

```text
The "POSTGRES_DB" variable is not set. Defaulting to a blank string.
```

**Investigation.**

1. `docker compose logs db` showed that Postgres initialised and logged `database system is ready to accept connections`. So the server was fine and the healthcheck was the problem.
2. `docker inspect kumo_hr-db-1 --format '{{json .State.Health.Log}}'` showed the healthcheck output:

   ```text
   pg_isready: option requires an argument: d
   ```

   The healthcheck `pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}` was running with an empty `POSTGRES_DB`.
3. `docker inspect ... --format '{{json .Config.Env}}'` confirmed `POSTGRES_USER` and `POSTGRES_PASSWORD` were set but `POSTGRES_DB=` was blank.
4. Listing the variable **names** in `.env` (without printing values) showed the typo:

   ```bash
   cut -d= -f1 .env
   ```

   ```text
   POSTGRE_DB
   ```

**Fix.** Rename the key to `POSTGRES_DB`, then `docker compose up -d`. Compose recreated `db`, it became healthy, and the backend started and applied migrations.

**Volume.** There was no need to delete `pgdata`. When `POSTGRES_DB` is blank, the Postgres image names the database after `POSTGRES_USER` (`hr`), which already matches `DATABASE_URL`.

### 4. `DJANGO_ALLOWED_HOOSTS`

The same name check turned up a second typo. It had no effect yet because `settings.py` doesn't read the variable until 0.2, but Django would have ignored it then. Renamed to `DJANGO_ALLOWED_HOSTS`.

### 5. Spaces in `DJANGO_ALLOWED_HOSTS`

The value was `localhost, 127.0.0.1, backend`. In 0.2, `settings.py` does:

```python
ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost").split(",")
```

which would produce `" 127.0.0.1"` and `" backend"` with leading spaces, so neither host would match. Changed to `localhost,127.0.0.1,backend`, matching `.env.example`.

### Left as is

- The first comment line reads `#Compose + Django` (no space after `#`). It's a comment, so it's harmless, and it's the only line that differs from `.env.example` in the name check below.
- `.env` mixes CRLF and LF line endings. Compose reads both correctly.

---

## Step 6 — `frontend/next.config.ts`

### 6. Five typos

| Line | Had | Should be | Effect |
|------|-----|-----------|--------|
| 1 | `NextConifg` | `NextConfig` | Type import fails; `nextConfig` loses its type |
| 3 | `https://localhost:8000` | `http://localhost:8000` | Django's dev server doesn't speak HTTPS |
| 9 | `async rewrite()` | `async rewrites()` | Next.js only reads `rewrites`; **the proxy was silently ignored** |
| 12 | `source: "api/:path*/"` | `source: "/api/:path*"` | Missing leading `/`, and the trailing `/` made it a copy of rule 1 |
| 12 | `destination: …/api/:path*/` | `destination: …/api/:path*` | Paths without a trailing slash should be forwarded as they are |

The `rewrite` typo was the serious one: nothing errors, the rules just never apply. The two rules are meant to cover both URL forms, one for paths ending in `/` and one for paths without it.

**Fix.** Replaced the file with the version from Step 6 of the walkthrough.

**Verification.**

```bash
docker compose restart frontend
docker compose logs frontend --tail 15     # "✓ Running next.config.ts" with no errors
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/api/
```

The `curl` returned a Django error page, which shows the request now goes through Next.js to the backend container.

### 7. `400 DisallowedHost` (expected for now)

Django reported:

```text
Invalid HTTP_HOST header: 'backend:8000'. You may need to add 'backend' to ALLOWED_HOSTS.
```

The backend container already has `DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,backend`, but `backend/config/settings.py` still has Django's default `ALLOWED_HOSTS = []` and doesn't read the variable. Stage 0.2 replaces the settings with the version that reads the variable from the environment, and that resolves this error. No action needed before then.

---

## Open items

1. **Remove `backend/db.sqlite3` from git.** Commit `17863d1` added it and it has been pushed. It's an empty SQLite file Django created before Postgres was configured.

   ```bash
   git rm --cached backend/db.sqlite3
   echo "*.sqlite3" >> .gitignore
   git commit -m "Stop tracking db.sqlite3"
   ```

2. **Commit the `next.config.ts` fix.** It's still uncommitted on `stage0/docker`.
3. **`frontend/.gitignore`** has an uncommitted, unfinished `# local env files` heading with no patterns under it. The root `.gitignore` already ignores `.env` and `.env.*`, so you can finish or drop it.

---

## Lessons

- **Silent failures are the dangerous ones.** The stray `2>/dev/null` line and the `rewrite` method name both ran without errors and just did nothing. When copying from the walkthrough, diff your file against it instead of relying on "it started".
- **"Unhealthy" doesn't mean "not running."** Read `docker compose logs <service>` first, then the healthcheck output with `docker inspect <container> --format '{{json .State.Health.Log}}'`.
- **Compose warnings about unset variables point straight at `.env` typos.** Compare key names against `.env.example`:

  ```bash
  diff <(cut -d= -f1 .env.example | sort) <(cut -d= -f1 .env | tr -d '\r' | sort)
  ```

  This compares only the names, so no secret values are printed.

- **Comma-separated env values must not contain spaces** when the code uses a plain `.split(",")`.
