# kumo HR — Roadmap

> How the project gets built, stage by stage. What to build is in `PROJECT_STRUCTURE.md`, `BUSINESS_RULES.md` and `DATA_MODEL.md`; this file only orders it.
> Tick a box when its exit check passes and the pull request is merged.

## Ground rules

- **MVP first.** Stage 1 is a demo-able core (auth, people, timesheets, leave). Everything else follows.
- **Vertical slices.** Each phase delivers one module end to end: model → services + tests → API → pages matching the mockups.
- **Bilingual from day one.** Every page ships in English and Japanese; no hard-coded UI strings.
- **One phase = one pull request** with green CI.
- **Deployment is optional** and decided later (Stage 4).

---

## Stage 0 — Foundation

Goal: `make up` starts an empty but working stack, and CI is green.

- [ ] **0.1 Repo and Docker** — `compose.yaml`, `backend/Dockerfile`, `frontend/Dockerfile`, `entrypoint.sh`, `.env.example`, `Makefile`, `.dockerignore` files, mailpit.
  Exit: `make up` serves the Django admin, the Next.js starter and PostgreSQL.
- [ ] **0.2 Backend skeleton** — settings split (`base` / `dev` / `test` / `prod`), `core` app (`TimeStampedModel`, `SoftDeleteModel`, `ActiveManager`, `ErrorLog`, `DatabaseErrorHandler`, unified error shape, permissions), `core/utils/dates.py`, drf-spectacular, pytest, ruff.
  Exit: `month_range()`, `claim_period()`, `timesheet_close_date()` unit-tested; `/api/docs/` loads.
- [ ] **0.3 Frontend skeleton** — shadcn/ui, theme tokens (`PROJECT_STRUCTURE.md` §7), fonts, `(app)` layout with sidebar and top bar, `api-client.ts` with CSRF, TanStack Query, `make types`, Vitest.
  Exit: placeholder pages render in the theme; lint and tests pass.
- [ ] **0.4 ja/en setup** — next-intl (or equivalent), language switcher, message files, enum and date label helpers; Django i18n for email templates.
  Exit: one page switches between English and Japanese.
- [ ] **0.5 CI** — `.github/workflows/ci.yml`: build dev images, ruff, pytest, frontend lint and tests, prod image build, private-term check.
  Exit: CI green on a pull request.

## Stage 1 — MVP: auth, people, timesheets, leave

Goal: an employee logs in, fills in a timesheet and requests leave; HR approves both.

- [ ] **1.1 Email basics** — `MailLog`, `notifications/emails.py` sender, template layout, mailpit wiring. *(Moved earlier than the spec's step 9: 1.2 and 1.4 need email.)*
  Exit: a test email arrives in mailpit and is logged.
- [ ] **1.2 Accounts** — custom `User`, login/logout, `auth/me/`, `auth/csrf/`, lockout (5 failures → 30 min), 30-min idle session, password reset + throttle, `WelcomeTokenGenerator`, set-password, forced password change, groups fixture.
  Exit: tests cover `BUSINESS_RULES.md` §6.1–6.4a; login, reset and change-password pages work.
- [ ] **1.3 Calendar and transit** — `Holiday` + `import_jp_holidays`; `RailCompany` / `RailLine` / `Station` + Kansai fixtures; cascading lookup API.
  Exit: 2026 holidays and station fixtures load.
- [ ] **1.4 People** — `Department`, `Member`, `MemberSkill`, `Project`, `ProjectPhase`; `create_member()` + welcome email + resend; soft delete safeguards; ownership filtering (404); People list, member detail, skills & career, new member form; skill sheet `.xlsx` / `.zip`.
  Exit: matches the People list and Employee detail mockups.
- [ ] **1.5 Timesheets** — `MonthlyAssignment`, `WorkDay`; `calc_hours()` with all 8 worked examples from §2 as tests; submit / approve / send back (+ email); `.xlsx` / `.zip` export. `approve()` calls a stub `accrue_monthly()` until 1.6.
  Exit: matches the Monthly timesheet mockup; approval flow tests pass.
- [ ] **1.6 Leave** — leave models; statutory grant (both tables), `renew_leave_balances`, carry-over and oldest-first deduction, hourly cap, five-day duty, balance locking, 140h accrual wired into timesheet approval; requests, approve / decline / cancel, balance card, team calendar; `scheduler` container + `backend/crontab`.
  Exit: every test file listed in `leave/tests/` passes; matches both Time off mockups.
- [ ] **1.7 MVP dashboard** — HR "Things to do" (pending approvals, timesheet close countdown, five-day duty warnings), stat tiles.
  Exit: **MVP demo** — full employee and HR flow works end to end.

## Stage 2 — Remaining features

- [ ] **2.1 Travel claims** — `TravelClaim` + validation, receipt-required rule, single and bulk approve, `expire_travel_attachments`; Travel expenses page.
- [ ] **2.2 Payslips** — private storage, 15-minute signed URLs, bulk upload matched by `employee_no`, HR desktop and employee mobile views, "payslip ready" email.
- [ ] **2.3 Notifications** — inbox, unread bell, HR send / broadcast; remaining leave emails (submitted, cancelled, approved, declined).
- [ ] **2.4 Reports** — daily / weekly reports, monthly summaries, client cases, analytics, `.xlsx` / `.csv` export; Reports page tabs.
- [ ] **2.5 Full dashboard** — add travel, payslip and report data.

## Stage 3 — Portfolio polish

- [ ] **3.1 Demo data** — `seed_demo`: 48 fictional members, Sep–Oct 2026 data, sample PDFs.
- [ ] **3.2 Docs** — `docs/API.md` and ADRs 0001–0005 referenced by `PROJECT_STRUCTURE.md`.
- [ ] **3.3 Hardening** — security review, `check-private-terms.sh --history`, accessibility and mobile checks.
- [ ] **3.4 Screenshots and README** — retake all screenshots (EN + JA) from the real app; quick-start guide.

## Stage 4 — Deployment (optional, host not chosen)

- [ ] **4.1 Choose a host** — a small VPS is the simplest fit for `compose.prod.yaml`.
- [ ] **4.2 Production setup** — `compose.prod.yaml`, nginx, HTTPS, media storage, database backups, scheduler.
- [ ] **4.3 Deploy pipeline** — CI deploy step; public demo with periodically reset seed data.
