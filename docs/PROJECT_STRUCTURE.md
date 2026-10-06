# kumo HR — Project Structure

> An HR and attendance management app for a fictional Japanese IT staffing company, **Naniwa Systems**.
> Stack: **Next.js (App Router, TypeScript, shadcn/ui, Tailwind CSS)** frontend + **Django + Django REST Framework** backend + **PostgreSQL**, all run in **Docker** (Docker Compose for local development and deployment).

---

## About

kumo HR is a portfolio project: an HR and attendance app for a fictional IT staffing company, with features modelled on modern HR products. It covers employee records and skill sheets, monthly timesheets with approval, leave requests and balances, travel expense claims, work reports and analytics, and payslip distribution.

All data is fictional. The company, Naniwa Systems, and every person, client and project in the seed data are invented.

---

## 1. Repository root

```
kumo-hr/
├── backend/                         # Django + DRF: API, admin, business logic
├── frontend/                        # Next.js: employee- and HR-facing UI
├── docs/
│   ├── PROJECT_STRUCTURE.md         # this file
│   ├── BUSINESS_RULES.md            # hours, leave grants, accrual, security limits, email routing
│   ├── DATA_MODEL.md                # ERD of this project's own models
│   ├── API.md                       # endpoint summary
│   └── decisions/                   # short ADRs, one per major choice
│       ├── 0001-hybrid-django-nextjs.md
│       ├── 0002-session-auth-over-jwt.md
│       ├── 0003-normalized-skills-and-phases.md
│       ├── 0004-leave-independent-of-monthly-assignment.md
│       └── 0005-docker-compose-for-dev-and-deploy.md
├── scripts/
│   ├── check-private-terms.sh       # blocks committing configured private terms (names, secrets)
│   └── install-hooks.sh             # installs the pre-commit hook
├── .github/workflows/ci.yml         # builds images, runs lint + tests in containers, private-term check
├── docker/
│   └── nginx/
│       └── nginx.conf               # prod only: one origin — /api, /admin, /static → Django; rest → Next.js
├── compose.yaml                     # dev: db, backend, scheduler, frontend, mailpit (see §6)
├── compose.prod.yaml                # prod: db, backend (gunicorn), scheduler, frontend (standalone), nginx
├── .private-terms                   # LOCAL ONLY — listed in .gitignore and .dockerignore, never committed
├── .env.example                     # copied to .env; read by Compose and Django
├── .gitignore                       # includes .private-terms, PRIVATE_NOTES.md, .env, media/
├── Makefile                         # make up / down / logs / migrate / seed / types / test / check-terms
└── README.md                        # opens with the "About" paragraph above, then screenshots and quick start
```

---

## 2. Backend (`backend/`)

```
backend/
├── Dockerfile                       # multi-stage: dev (runserver) and prod (gunicorn); includes supercronic
├── .dockerignore                    # .venv, __pycache__, media/, .env, .private-terms
├── entrypoint.sh                    # waits for db, runs migrate + createcachetable, then exec "$@"
├── crontab                          # scheduled management commands, run by the scheduler service
├── manage.py
├── pyproject.toml                   # ruff / pytest config
├── requirements/
│   ├── base.txt
│   ├── dev.txt                      # -r base.txt + pytest, factory_boy, ruff
│   └── prod.txt                     # -r base.txt + gunicorn
├── pytest.ini
│
├── config/
│   ├── __init__.py
│   ├── settings/
│   │   ├── __init__.py
│   │   ├── base.py                  # INSTALLED_APPS, DRF, auth, i18n (ja/en), TIME_ZONE=Asia/Tokyo,
│   │   │                            # 30-min idle session, DatabaseCache, LOGGING → ErrorLog
│   │   ├── dev.py                   # DEBUG, CORS for localhost:3000
│   │   ├── test.py
│   │   └── prod.py                  # secure cookies, HSTS, private object storage
│   ├── urls.py                      # /admin/, /api/v1/, /api/schema/, /api/docs/
│   ├── api_router.py                # collects every app's DRF router
│   ├── asgi.py
│   └── wsgi.py
│
├── apps/
│   ├── core/                        # shared building blocks (no domain models)
│   │   ├── models.py                # TimeStampedModel (created_at, updated_at), SoftDeleteModel, ErrorLog
│   │   ├── managers.py              # ActiveManager (deleted_at IS NULL)
│   │   ├── permissions.py           # IsHRAdmin, IsSelfOrHR, ReadOnly
│   │   ├── pagination.py
│   │   ├── exceptions.py            # unified error response shape
│   │   ├── logging.py               # DatabaseErrorHandler → ErrorLog
│   │   ├── admin.py                 # ErrorLog, read-only
│   │   ├── utils/
│   │   │   ├── dates.py             # month_range(), claim_period(), timesheet_close_date(), business days
│   │   │   ├── money.py             # yen formatting
│   │   │   └── zip.py               # one ZIP builder for every bulk export
│   │   └── tests/
│   │
│   ├── accounts/                    # login, groups, password reset, lockout
│   │   ├── models.py                # User
│   │   ├── managers.py
│   │   ├── services.py              # record_failed_login(), is_locked(), issue_temporary_password()
│   │   ├── tokens.py                # WelcomeTokenGenerator (own salt, 72 h)
│   │   ├── permissions.py           # PasswordChangeNotRequired (default DRF permission)
│   │   ├── admin.py                 # "Issue temporary password" action
│   │   ├── serializers.py
│   │   ├── views.py                 # login, logout, me, csrf, password reset, set password, change password
│   │   ├── throttles.py             # PasswordResetThrottle (2 per address per JST day)
│   │   ├── urls.py
│   │   ├── fixtures/groups.json     # "HR Admin", "Employee"
│   │   ├── migrations/
│   │   └── tests/
│   │
│   ├── people/
│   │   ├── models/
│   │   │   ├── __init__.py
│   │   │   ├── choices.py           # Gender, EmploymentType, LanguageLevel, ProcessPhase
│   │   │   ├── department.py        # Department
│   │   │   ├── member.py            # Member, MemberSkill
│   │   │   └── career.py            # Project, ProjectPhase
│   │   ├── admin.py                 # MemberAdmin with Skill + Project inlines
│   │   ├── services.py              # create_member() (unusable password + welcome link), resend_welcome(),
│   │   │                            # soft_delete() safeguards
│   │   ├── exports.py               # skill sheet .xlsx; ZIP for HR
│   │   ├── serializers.py
│   │   ├── filters.py               # department, employment type, language level, active/resigned
│   │   ├── views.py                 # MemberViewSet, ProjectViewSet, DepartmentViewSet
│   │   ├── urls.py
│   │   ├── migrations/
│   │   └── tests/
│   │       ├── factories.py
│   │       ├── test_member_api.py
│   │       └── test_soft_delete.py
│   │
│   ├── transit/                     # rail companies, lines, stations (commute data)
│   │   ├── models.py                # RailCompany, RailLine, Station
│   │   ├── admin.py
│   │   ├── serializers.py
│   │   ├── views.py                 # read-only cascading lookups
│   │   ├── urls.py
│   │   ├── fixtures/                # sample Kansai-area companies, lines and stations
│   │   ├── migrations/
│   │   └── tests/
│   │
│   ├── calendar_master/
│   │   ├── models.py                # Holiday
│   │   ├── admin.py
│   │   ├── serializers.py
│   │   ├── views.py
│   │   ├── urls.py
│   │   ├── management/commands/
│   │   │   └── import_jp_holidays.py   # from the public Cabinet Office holiday CSV
│   │   ├── migrations/
│   │   └── tests/
│   │
│   ├── timesheets/
│   │   ├── models.py                # MonthlyAssignment, WorkDay
│   │   ├── services.py              # calc_hours(), submit(), approve() (+ monthly accrual), send_back()
│   │   ├── exports.py               # timesheet .xlsx per member-month; ZIP of a month for HR
│   │   ├── admin.py
│   │   ├── serializers.py
│   │   ├── views.py
│   │   ├── urls.py
│   │   ├── migrations/
│   │   └── tests/
│   │       ├── test_hours_calc.py
│   │       └── test_approval_flow.py
│   │
│   ├── leave/
│   │   ├── models.py                # LeaveType, LeaveCategory, LeaveRequest, LeaveBalance,
│   │   │                            # LeaveDeduction, LeaveAccrual
│   │   ├── services.py              # working_days(), statutory_grant_days(), renew(), accrue_monthly(),
│   │   │                            # available_days(), deduct_balance() (oldest first), five_day_status(),
│   │   │                            # approve(), decline(), cancel()
│   │   ├── management/commands/
│   │   │   └── renew_leave_balances.py  # daily 01:00, catches up missed days
│   │   ├── admin.py
│   │   ├── serializers.py
│   │   ├── views.py                 # requests, approve/decline/cancel, balance, team calendar
│   │   ├── urls.py
│   │   ├── migrations/
│   │   └── tests/
│   │       ├── test_statutory_grant.py      # full-time and part-time (proportional) tables
│   │       ├── test_balance_locking.py      # concurrent submit/approve cannot overspend
│   │       ├── test_carry_over.py
│   │       ├── test_hourly_cap.py
│   │       ├── test_five_day_duty.py
│   │       └── test_monthly_accrual.py
│   │
│   ├── travel/
│   │   ├── models.py                # TravelClaim (+ enums)
│   │   ├── services.py              # receipt-required rule, approve(), bulk_approve()
│   │   ├── management/commands/
│   │   │   └── expire_travel_attachments.py  # 02:00 on the 1st: delete files older than 2 months
│   │   ├── admin.py
│   │   ├── serializers.py
│   │   ├── views.py
│   │   ├── urls.py
│   │   ├── migrations/
│   │   └── tests/
│   │
│   ├── reports/
│   │   ├── models.py                # Report, MonthlyWorkSummary, ClientCase
│   │   ├── analytics.py             # overtime_by_department(), leave_usage(), submission_rate()
│   │   ├── exports/
│   │   │   ├── base.py              # Exporter interface
│   │   │   ├── xlsx.py              # openpyxl, one sheet per department + summary
│   │   │   └── csv.py               # UTF-8 with BOM
│   │   ├── admin.py
│   │   ├── serializers.py
│   │   ├── views.py                 # reports, submission grid, analytics, POST /export/
│   │   ├── urls.py
│   │   ├── migrations/
│   │   └── tests/
│   │
│   ├── payroll/
│   │   ├── models.py                # Payslip
│   │   ├── storage.py               # private storage + signed, expiring download URLs
│   │   ├── services.py              # bulk_upload() (match PDFs by employee_no), notify()
│   │   ├── admin.py
│   │   ├── serializers.py
│   │   ├── views.py                 # HR list/upload/notify; employee "my payslips"; download
│   │   ├── urls.py
│   │   ├── migrations/
│   │   └── tests/
│   │
│   └── notifications/
│       ├── models.py                # Notification (inbox), MailLog
│       ├── emails.py                # welcome, password reset, leave submitted/cancelled (manager, employee CC'd),
│       │                            # leave decision, timesheet sent back, payslip ready
│       ├── services.py              # send(recipients | broadcast), mark_read()
│       ├── templates/emails/
│       ├── admin.py                 # MailLog, read-only
│       ├── serializers.py
│       ├── views.py                 # my inbox, unread count, mark read; HR send
│       ├── urls.py
│       ├── migrations/
│       └── tests/
│
├── seed/                            # fictional demo data only
│   ├── README.md
│   └── management/commands/
│       └── seed_demo.py             # Naniwa Systems: 48 members, Sep–Oct 2026 data, sample PDFs
├── templates/admin/
├── static/
└── media/                           # dev only; prod uses object storage
```

---

## 3. Models (field level)

Every model inherits `created_at` / `updated_at` from `TimeStampedModel`. Dates are `DateField`, times are `TimeField`, and money is `IntegerField` in yen.

### accounts

```python
User(AbstractUser)
    email                  unique, USERNAME_FIELD
    groups                 "HR Admin" | "Employee"
    must_change_password   bool, default False (True only after HR issues a temporary password)
    failed_login_count     int, default 0
    locked_until           DateTimeField, null (5 failures → now + 30 min)
```

### core

```python
ErrorLog                   # no foreign keys: rows survive member deletion and pre-login errors
    occurred_at            DateTimeField, indexed
    user_id                int, null
    source                 "request" | command name
    path, method           null (requests only)
    error_class
    message                text
    traceback              text
```

### people

```python
Department
    code                   int, unique
    name

# choices.py — one enum per domain, so a gender value can never be stored as a skill level
Gender          MALE=1, FEMALE=2
EmploymentType  FULL_TIME=1, CONTRACT=2, PART_TIME=3
LanguageLevel   ADVANCED=1, INTERMEDIATE=2, BASIC=3
ProcessPhase   SURVEY_ANALYSIS=1, BASIC_DESIGN=2, DETAIL_DESIGN=3,
               DEVELOPMENT=4, IT_ST=5, OPERATIONS=6

Member(SoftDeleteModel)
    user                   OneToOne → User
    employee_no            unique (business ID shown in the UI)
    name
    name_kana              phonetic reading
    initials
    birth_date             (age is computed, never stored)
    gender                 Gender, null
    nationality
    address
    phone
    education
    hire_date
    department             FK → Department
    employment_type        EmploymentType, default FULL_TIME
    weekly_work_days       int 1–5, default 5 (scheduled days per week)
    weekly_work_hours      Decimal, default 40.0 (scheduled hours per week)
    jp_speaking_level      LanguageLevel, null
    jp_reading_level       LanguageLevel, null
    jp_writing_level       LanguageLevel, null
    english_level          short text (e.g. "TOEIC 780")
    commute_line           FK → transit.RailLine, null
    commute_station        FK → transit.Station, null
    notes
    deleted_at             DateField, null, indexed (resignation date)

MemberSkill                # child table instead of skill1…skill5 columns
    member                 FK → Member
    category               "skill" | "os" | "language" | "database" | "other"
    name
    acquired_year          int, null

Project                    # one row per client project in the member's career
    member                 FK → Member
    start_date
    end_date               null (ongoing)
    client_company
    location
    role
    team_size              int, null
    platforms
    languages
    databases
    notes

ProjectPhase               # which development phases the member worked on
    project                FK → Project
    phase                  ProcessPhase
    UniqueConstraint(project, phase)
```

### transit

```python
RailCompany   code (PK), name, name_kana, name_official, name_short, type, is_active, sort
RailLine      code (PK), company FK, name, name_kana, name_official, is_active, sort
Station       code (PK), line FK, name, is_active, sort
```

Used for commute fields on `Member` and `MonthlyAssignment`. Travel claims use free-text locations instead (see travel).

### calendar_master

```python
Holiday
    date                   DateField, PK
    name
```

### timesheets

```python
MonthlyAssignment
    member                 FK → Member
    month                  DateField (1st of month)
    work_site
    commute_from           FK → Station, null
    commute_to             FK → Station, null
    pass_price             int, null
    status                 draft | submitted | approved | sent_back
    submitted_at, approved_at, approved_by
    UniqueConstraint(member, month)

WorkDay
    assignment             FK → MonthlyAssignment
    date
    start_time             null
    end_time               null
    break_minutes          int, default 60
    overtime_hours         Decimal
    night_hours            Decimal
    holiday_hours          Decimal
    total_hours            Decimal
    work_content           text
    UniqueConstraint(assignment, date, name="unique_workday_per_assignment_date")
```

The member is reached through the assignment, so it is not stored on `WorkDay` a second time.

### leave

```python
LeaveType
    code                   int, unique
    name

LeaveCategory
    code                   int, unique
    leave_type             FK → LeaveType
    name
    day_count              Decimal (e.g. 1.0, 0.5)
    is_hourly              bool (start/end times required)
    deducts_from           PAID | SUBSTITUTE | NONE
    counter                LATE | EARLY_LEAVE | OUTING | UNPAID, null (only when deducts_from = NONE)

LeaveRequest
    member                 FK → Member
    category               FK → LeaveCategory
    start_date
    end_date
    start_time             null (hourly leave)
    end_time               null
    total_hours            Decimal, null
    reason
    notes
    status                 pending | approved | declined | cancelled
    decided_by             FK → Member, null
    decided_at             null
    cancelled_at           null

LeaveBalance               # one per grant; usable until expires_on
    member                 FK → Member
    period_start           grant date
    expires_on             period_start + 2 years
    granted_days           Decimal (statutory grant; drives the 5-day duty)
    total_days, used_days                  Decimal (total = granted + accruals)
    hourly_used_hours      Decimal (cap 40 per grant year)
    substitute_total, substitute_used      Decimal
    early_leave_count, late_count, outing_count, unpaid_count   Decimal
    is_active              bool (the current grant year)
    remaining_days         @property (total − used)
    UniqueConstraint(member, period_start)

LeaveDeduction             # where an approved request's days came from, so cancel can restore them
    request                FK → LeaveRequest
    balance                FK → LeaveBalance
    days                   Decimal

LeaveAccrual               # ledger of extra days granted on timesheet approval
    member                 FK → Member
    month                  DateField (1st of month)
    rule_code              e.g. "MONTHLY_140H_V1"
    days                   Decimal
    balance                FK → LeaveBalance
    UniqueConstraint(member, month, rule_code)
```

Grant, renewal and accrual rules are in `BUSINESS_RULES.md` §4.

`LeaveRequest` is linked to the member, not to a monthly assignment. A request can span two months (Oct 30 – Nov 2), and timesheets find leave by member and date. If leave ever has to be billed to a client project, add `assignment = ForeignKey(MonthlyAssignment, null=True, blank=True)`. See ADR 0004.

### travel

```python
class ExpenseCategory(IntegerChoices):  TRANSPORT=0, OTHER=1
class TransportMethod(IntegerChoices):  NONE=0, TRAIN=1, BUS=2, TAXI=3, SHINKANSEN=4
class TripType(IntegerChoices):         NONE=0, ONE_WAY=1, ROUND_TRIP=2
class AttachmentStatus(IntegerChoices): NONE=0, ATTACHED=1, EXPIRED=2
class ApprovalStatus(IntegerChoices):   PENDING=0, APPROVED=1

TravelClaim
    member                 FK → Member
    submitted_on
    used_on
    category               ExpenseCategory
    transport_method       TransportMethod
    departure              text
    arrival                text
    trip_type              TripType
    amount                 int (yen)
    purpose
    notes
    attachment             FileField, null
    attachment_status      AttachmentStatus
    approval_status        ApprovalStatus
    approved_on            null
```

Each choice field also gets a database `CheckConstraint`.

### reports

```python
class ReportType(IntegerChoices): DAILY=1, WEEKLY=2

Report
    author                 FK → Member (required)
    report_type            ReportType
    period_start
    period_end
    start_holiday, end_holiday   text
    holiday_count          int
    holiday_type           int
    contents               text
    comment                text
    has_notice             bool
    notice_contents        text

MonthlyWorkSummary
    assignment             OneToOne → MonthlyAssignment
    status_summary         text
    issues                 text
    response               text

ClientCase                 # "case" = a client project (案件) the member is placed on
    member                 FK → Member
    month                  DateField (1st of month)
    case_name
    customer
    planned_duration
    responsibilities       text
    UniqueConstraint(member, month)
```

### payroll

```python
Payslip
    member                 FK → Member
    period                 DateField (1st of month)
    pdf                    FileField (private storage)
    uploaded_by            FK → User
    uploaded_at
    updated_by             FK → User, null
    viewed_at              null
    deleted_at             null
    UniqueConstraint(member, period)
```

Pay amounts are not stored. The PDF is the record, and pay is calculated in an external payroll system.

### notifications

```python
Notification               # one-way HR → member; a broadcast creates one row per active member
    recipient              FK → Member
    sender                 FK → Member, null
    title
    body                   text
    read_at                DateTimeField, null
    Index(recipient, read_at)

MailLog
    from_address           EmailField (254)
    to_address, cc_address, bcc_address
    subject, body
    sent_at
    result                 sent | failed
```

---

## 4. API endpoints (`/api/v1/`)

| Area | Endpoint | Methods |
|---|---|---|
| Auth | `auth/login/`, `auth/logout/`, `auth/me/`, `auth/csrf/`, `auth/password-reset/`, `auth/password-reset/confirm/`, `auth/set-password/`, `auth/change-password/` | POST / GET |
| People | `members/`, `members/{id}/`, `members/{id}/resend-welcome/` (HR), `members/{id}/skills/`, `members/{id}/projects/`, `members/{id}/skill-sheet/` (.xlsx), `members/skill-sheets/?ids=` (.zip, HR), `departments/` | GET, POST, PATCH, DELETE |
| Transit | `transit/companies/`, `transit/lines/?company=`, `transit/stations/?line=` | GET |
| Calendar | `holidays/?year=2026` | GET |
| Timesheets | `timesheets/{member_id}/{yyyy-mm}/`, `.../submit/`, `.../approve/`, `.../send-back/`, `.../export/` (.xlsx), `timesheets/export/?month=` (.zip, HR) | GET, PUT, POST |
| Leave | `leave/requests/`, `leave/requests/{id}/approve/`, `leave/requests/{id}/decline/`, `leave/requests/{id}/cancel/`, `leave/balance/{member_id}/` (available days, carry-over, hourly hours left, 5-day status), `leave/five-day-duty/` (HR), `leave/calendar/?month=2026-10`, `leave/categories/` | GET, POST |
| Travel | `travel/claims/`, `travel/claims/{id}/approve/`, `travel/claims/bulk-approve/` | GET, POST, PATCH, DELETE |
| Reports | `reports/?type=weekly&week=`, `reports/monthly-summaries/`, `reports/client-cases/?month=`, `reports/analytics/?period=`, `reports/export/` | GET, POST |
| Payroll | `payslips/?period=`, `payslips/bulk-upload/`, `payslips/notify/`, `payslips/{id}/download/`, `me/payslips/` | GET, POST |
| Notifications | `notifications/` (mine; HR POST to send), `notifications/unread-count/`, `notifications/{id}/read/`, `notifications/read-all/` | GET, POST |

While `must_change_password` is set, every endpoint except `auth/me/`, `auth/logout/` and `auth/change-password/` returns 403 with code `password_change_required`.

---

## 5. Frontend (`frontend/`)

```
frontend/
├── Dockerfile                       # multi-stage: dev (next dev) and prod (standalone server)
├── .dockerignore                    # node_modules, .next, .env*, .private-terms
├── package.json
├── next.config.ts                   # output: 'standalone'; dev rewrites /api/* → ${API_INTERNAL_URL}
├── tsconfig.json
├── tailwind.config.ts
├── postcss.config.mjs
├── components.json                  # shadcn/ui config
├── eslint.config.mjs
├── .env.example
├── middleware.ts                    # no session cookie → redirect to /login
├── public/
└── src/
    ├── app/
    │   ├── layout.tsx               # fonts (Georgia headings, Source Sans 3 body), Providers
    │   ├── globals.css              # palette as shadcn CSS variables (§6)
    │   ├── providers.tsx            # QueryClientProvider, Toaster
    │   ├── not-found.tsx
    │   ├── (auth)/
    │   │   ├── layout.tsx
    │   │   ├── login/page.tsx
    │   │   ├── set-password/[token]/page.tsx  # from the welcome email
    │   │   ├── change-password/page.tsx    # forced after a temporary password (must_change_password)
    │   │   └── reset-password/
    │   │       ├── page.tsx
    │   │       └── [token]/page.tsx
    │   └── (app)/
    │       ├── layout.tsx           # TopBar + navy Sidebar + <main>
    │       ├── loading.tsx
    │       ├── error.tsx
    │       ├── dashboard/page.tsx
    │       ├── people/
    │       │   ├── page.tsx
    │       │   ├── new/page.tsx
    │       │   └── [memberId]/
    │       │       ├── page.tsx                # profile
    │       │       ├── skills/page.tsx         # skills + career (phases)
    │       │       ├── time-off/page.tsx
    │       │       └── payslips/page.tsx
    │       ├── time-tracking/
    │       │   ├── page.tsx
    │       │   └── [memberId]/[month]/page.tsx
    │       ├── time-off/
    │       │   ├── page.tsx
    │       │   └── calendar/page.tsx
    │       ├── travel/
    │       │   ├── page.tsx
    │       │   └── [claimId]/page.tsx
    │       ├── reports/page.tsx                # ?tab=work|analytics + export dialog
    │       ├── payslips/page.tsx               # HR admin
    │       ├── notifications/page.tsx          # inbox; HR also gets a "Send notification" dialog
    │       ├── me/
    │       │   ├── page.tsx
    │       │   ├── timesheet/page.tsx
    │       │   ├── reports/page.tsx            # write daily/weekly report
    │       │   └── payslips/page.tsx           # employee, mobile-first
    │       └── settings/
    │           ├── page.tsx
    │           ├── departments/page.tsx
    │           └── leave-categories/page.tsx
    │
    ├── components/
    │   ├── ui/                      # shadcn generated — do not edit by hand
    │   ├── layout/
    │   │   ├── sidebar.tsx
    │   │   ├── nav-config.ts
    │   │   ├── top-bar.tsx          # search, notification bell with unread badge, user menu
    │   │   └── page-header.tsx
    │   └── shared/
    │       ├── data-table.tsx       # TanStack Table wrapper
    │       ├── status-badge.tsx     # success / warning / danger / neutral / info
    │       ├── stat-tile.tsx
    │       ├── month-picker.tsx
    │       ├── station-picker.tsx   # company → line → station (commute fields)
    │       ├── pdf-viewer.tsx
    │       ├── empty-state.tsx
    │       ├── confirm-dialog.tsx
    │       └── yen.tsx
    │
    ├── features/
    │   ├── auth/            { api.ts, hooks.ts, components/login-form.tsx }
    │   ├── dashboard/       { api.ts, components/{todo-list,stats-grid,upcoming-holidays}.tsx }
    │   ├── people/
    │   │   ├── api.ts, hooks.ts, schemas.ts
    │   │   └── components/
    │   │       ├── people-table.tsx
    │   │       ├── people-filters.tsx
    │   │       ├── member-header.tsx
    │   │       ├── language-levels.tsx   # Advanced / Intermediate / Basic + English
    │   │       ├── skills-list.tsx
    │   │       ├── career-table.tsx      # phase checkmarks
    │   │       └── member-form.tsx
    │   ├── timesheets/
    │   │   ├── api.ts, hooks.ts, calc.ts
    │   │   └── components/{timesheet-table,timesheet-summary,approval-bar,commute-info}.tsx
    │   ├── leave/
    │   │   ├── api.ts, hooks.ts, schemas.ts
    │   │   └── components/{request-card,leave-request-form,balance-card,five-day-badge,team-calendar-grid}.tsx
    │   ├── travel/
    │   │   ├── api.ts, hooks.ts, schemas.ts
    │   │   └── components/{claims-table,claim-form}.tsx
    │   ├── reports/
    │   │   ├── api.ts, hooks.ts
    │   │   └── components/
    │   │       ├── submission-grid.tsx
    │   │       ├── client-cases.tsx
    │   │       ├── monthly-summary.tsx
    │   │       ├── analytics-kpis.tsx
    │   │       ├── overtime-bars.tsx
    │   │       ├── leave-usage-table.tsx
    │   │       └── export-dialog.tsx
    │   ├── payroll/
    │   │   ├── api.ts, hooks.ts
    │   │   └── components/{payslip-table,payslip-preview,bulk-upload-dialog,payslip-list-mobile}.tsx
    │   └── notifications/
    │       ├── api.ts, hooks.ts     # unread count polled every 60 s
    │       └── components/{notification-bell,notification-list,send-notification-dialog}.tsx
    │
    ├── lib/
    │   ├── api-client.ts            # credentials:'include', X-CSRFToken, error mapping;
    │   │                            # 403 password_change_required → /change-password
    │   ├── auth.ts                  # getSession(), requireRole()
    │   ├── query-keys.ts
    │   ├── enums.ts                 # labels for backend IntegerChoices (ja/en)
    │   ├── format.ts                # formatYen(), formatHours(), formatDate()
    │   └── utils.ts                 # cn()
    ├── types/
    │   ├── api.d.ts                 # GENERATED by openapi-typescript — never edit
    │   └── index.ts                 # aliases: Member, LeaveRequest, Payslip …
    └── tests/
```

### Packages

| Backend | Purpose | Frontend | Purpose |
|---|---|---|---|
| `djangorestframework` | API | `next`, `react`, `typescript` | framework |
| `drf-spectacular` | OpenAPI schema | `tailwindcss`, shadcn/ui | UI |
| `django-filter` | list filters | `@tanstack/react-query` | server state |
| `django-cors-headers` | dev CORS | `@tanstack/react-table` | tables |
| `django-simple-history` | audit trail (Member, LeaveRequest, MonthlyAssignment, TravelClaim, Payslip) | `react-hook-form`, `zod` | forms |
| `openpyxl` | spreadsheet export | `openapi-typescript` (dev) | type generation |
| `psycopg[binary]` | PostgreSQL | `date-fns` | dates |
| `django-storages` | private file storage | `vitest`, Testing Library | tests |
| `pytest-django`, `factory_boy`, `ruff` | tests, lint | | |
| `gunicorn` (prod) | WSGI server in the prod image | | |
| `supercronic` (binary) | runs `backend/crontab` in the scheduler container | | |
| `dj-database-url` | read `DATABASE_URL` from the environment | | |

---

## 6. Docker

Every service runs in a container, so the whole stack starts with one command and behaves the same on any machine.

### Services

| Service | Image | Dev | Prod |
|---|---|---|---|
| `db` | `postgres:16-alpine` | port 5432 exposed for DB tools; data in the `pgdata` volume | not exposed; same volume |
| `backend` | `backend/Dockerfile` | target `dev`: `runserver`, source bind-mounted, reloads on save | target `prod`: `gunicorn`, code baked into the image |
| `scheduler` | `backend/Dockerfile` | same image as `backend`; runs `supercronic /app/crontab` | same, target `prod` |
| `frontend` | `frontend/Dockerfile` | target `dev`: `next dev`, source bind-mounted | target `prod`: Next.js standalone `server.js` |
| `mailpit` | `axllent/mailpit` | catches every email the app sends; inbox at http://localhost:8025 | — |
| `nginx` | `nginx:alpine` | — | single public entry on port 80 |

### `compose.yaml` (development)

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

  scheduler:
    build: { context: ./backend, target: dev }
    env_file: .env
    command: supercronic /app/crontab
    volumes:
      - ./backend:/app
    depends_on: [backend]                      # backend's entrypoint runs the migrations first

  frontend:
    build: { context: ./frontend, target: dev }
    environment:
      API_INTERNAL_URL: http://backend:8000    # container-to-container address
      WATCHPACK_POLLING: "true"                # reliable hot reload on Windows/macOS mounts
    command: npm run dev -- -H 0.0.0.0
    volumes:
      - ./frontend:/app
      - /app/node_modules                      # keep the container's node_modules
      - /app/.next
    ports: ["3000:3000"]
    depends_on: [backend]

  mailpit:
    image: axllent/mailpit
    ports: ["8025:8025"]                       # web inbox; SMTP on mailpit:1025 inside the network

volumes:
  pgdata:
```

### `backend/Dockerfile`

```dockerfile
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
ARG SUPERCRONIC_VERSION=v0.2.33
ARG TARGETARCH
ADD https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${TARGETARCH} /usr/local/bin/supercronic
RUN chmod +x /usr/local/bin/supercronic
WORKDIR /app
COPY requirements/ requirements/

FROM base AS dev
RUN pip install -r requirements/dev.txt
COPY . .
ENTRYPOINT ["./entrypoint.sh"]

FROM base AS prod
RUN pip install -r requirements/prod.txt
COPY . .
RUN python manage.py collectstatic --noinput
RUN useradd --create-home app && chown -R app /app
USER app
ENTRYPOINT ["./entrypoint.sh"]
CMD ["gunicorn", "config.wsgi:application", "-b", "0.0.0.0:8000", "-w", "3"]
```

### `frontend/Dockerfile`

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

### `compose.prod.yaml` (deployment)

- `db`: same image and volume, no published port.
- `backend`: target `prod`, `DJANGO_SETTINGS_MODULE=config.settings.prod`; uploaded files in a `media` volume.
- `scheduler`: same `prod` image and environment as `backend`, `command: supercronic /app/crontab`, shares the `media` volume so it can delete expired attachments.
- `frontend`: target `prod`.
- `nginx`: the only service with a published port. It routes `/api/`, `/admin/` and `/static/` to `backend:8000` and everything else to `frontend:3000`, so the browser sees one origin, as in dev.
- Payslip PDFs and receipts are **never** served by nginx directly. They go through Django's signed, expiring download view, so permissions are always checked.

### `.env.example`

```bash
# Compose + Django
POSTGRES_DB=hr
POSTGRES_USER=hr
POSTGRES_PASSWORD=change-me
DATABASE_URL=postgres://hr:change-me@db:5432/hr   # host is "db" inside Compose; use localhost outside it
DJANGO_SETTINGS_MODULE=config.settings.dev
DJANGO_SECRET_KEY=change-me
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,backend
EMAIL_HOST=mailpit
EMAIL_PORT=1025
DEFAULT_FROM_EMAIL=hr@naniwa-systems.example
LEAVE_MANAGER_EMAIL=leave-manager@naniwa-systems.example   # receives leave requests; employee is CC'd
TIMESHEET_CLOSE_DAY=7                                      # approval deadline, day of the following month
```

### `backend/crontab`

```cron
CRON_TZ=Asia/Tokyo
0 1 * * *   python manage.py renew_leave_balances
0 2 1 * *   python manage.py expire_travel_attachments
```

Password-reset counts need no cleanup job: the throttle key includes the JST date (`BUSINESS_RULES.md` §6.3).

### Things that commonly go wrong

- **`localhost` inside a container is that container.** The frontend reaches Django at `http://backend:8000` (`API_INTERNAL_URL`), not `localhost:8000`. Server components that call the API must also forward the user's `sessionid` and `csrftoken` cookies.
- **`NEXT_PUBLIC_*` variables are baked in at build time.** The frontend always calls the relative path `/api/...`, so the same image works in every environment without a new build.
- **Bind mounts hide installed packages.** The anonymous `/app/node_modules` volume keeps the container's own `node_modules` from being replaced by the host folder.
- **Line endings on Windows.** Commit `entrypoint.sh` with LF endings (`.gitattributes`: `*.sh text eol=lf`), or the container fails with `exec format error` / `no such file or directory`.
- **Secrets stay out of images.** `.env`, `.private-terms` and `media/` are listed in both `.dockerignore` files.

### CI

`.github/workflows/ci.yml` builds both images with the `dev` target, then runs:

```bash
docker compose run --rm backend ruff check .
docker compose run --rm backend pytest
docker compose run --rm frontend npm run lint
docker compose run --rm frontend npm test
docker compose -f compose.prod.yaml build            # proves the prod images build
```

---

## 7. Theme tokens (`src/app/globals.css`)

| Role | Hex | shadcn variable |
|---|---|---|
| Main background | `#F8FAFC` | `--background` |
| Surface | `#FFFFFF` | `--card`, `--popover` |
| Sidebar | `#0F172A` | `--sidebar` |
| Sidebar secondary / active | `#1E293B` | `--sidebar-accent` |
| Primary action | `#2563EB` | `--primary` |
| Primary hover | `#1D4ED8` | `--primary-hover` |
| Heading text | `#0F172A` | `--foreground-strong` |
| Body text | `#334155` | `--foreground` |
| Muted text | `#64748B` | `--muted-foreground` |
| Border | `#E2E8F0` | `--border`, `--input` |
| Subtle divider / table header | `#F1F5F9` | `--muted` |

Radius `--radius: 6px` (badges 4px). Headings `Georgia, serif`; body `Source Sans 3`, fallback `Noto Sans JP`.

---

## 8. Design decisions

- **One enum per domain** for gender, employment type, language level and development phase, instead of a shared lookup table, so invalid combinations cannot be stored.
- **Soft delete only:** members and payslips are never hard-deleted, so employment records stay available for the statutory retention period (`BUSINESS_RULES.md` §6.5).
- **Child tables instead of repeating columns:** `MemberSkill` and `ProjectPhase` replace numbered columns such as skill1…skill5.
- **One member reference everywhere:** every table points to `Member` by foreign key. `employee_no` is a unique business field for display and file matching, never a join key.
- **Real types:** dates, times and money use proper column types, never text.
- **Single dates instead of split fields:** `WorkDay.date` replaces separate year/month/day columns, and `UNIQUE(assignment, date)` guarantees one row per day.
- **Leave is independent of monthly assignments** (ADR 0004).
- **Travel claim categories are enums** with check constraints, not lookup tables.
- **Payslips store the PDF only**, not pay amounts.
- **Approval workflows** for timesheets, leave and travel claims, with history via `django-simple-history`.
- **Business rules live in `BUSINESS_RULES.md`**, each mapped to the module that owns it, with worked examples that become unit tests.
- **Scheduled jobs are plain management commands** run by supercronic in a `scheduler` container. There is no Celery or Redis, and every command can be re-run safely.
- **Docker Compose for every environment** (ADR 0005): the same images run in development, CI and deployment, and nginx gives production the same single origin that Next.js rewrites give development.

---

## 9. Dev workflow

Requires only Docker Desktop (or Docker Engine with the Compose plugin) and Git.

```bash
# one-time: private-term pre-commit check
touch .private-terms                  # add terms locally, one per line; never commit
./scripts/install-hooks.sh

# start everything
cp .env.example .env
docker compose up -d --build          # db, backend, frontend, mailpit

# first-run setup (migrations run automatically from entrypoint.sh)
docker compose exec backend python manage.py loaddata groups rail_companies rail_lines stations
docker compose exec backend python manage.py import_jp_holidays --year 2026
docker compose exec backend python manage.py seed_demo          # fictional Naniwa Systems data
docker compose exec backend python manage.py createsuperuser

# generate frontend types from the running API
docker compose exec frontend npx openapi-typescript http://backend:8000/api/schema/ -o src/types/api.d.ts
```

| URL | What |
|---|---|
| http://localhost:3000 | Next.js app |
| http://localhost:8000/admin | Django admin |
| http://localhost:8000/api/docs | API docs (Swagger) |
| http://localhost:8025 | Mailpit inbox (all outgoing email) |

`Makefile` shortcuts:

| Command | Runs |
|---|---|
| `make up` / `make down` | `docker compose up -d --build` / `docker compose down` |
| `make logs` | `docker compose logs -f backend frontend` |
| `make migrate` | `docker compose exec backend python manage.py migrate` |
| `make seed` | the four first-run setup commands above |
| `make types` | regenerate `src/types/api.d.ts` |
| `make test` | backend `pytest` + frontend `npm test` in containers |
| `make reset-db` | `docker compose down -v` (deletes the `pgdata` volume), then `make up seed` |

Running without Docker still works for quick debugging: start only the database with `docker compose up -d db`, set `DATABASE_URL` to `localhost`, and run `manage.py runserver` and `npm run dev` on the host.

Auth uses a Django session cookie. In dev, `next.config.ts` rewrites `/api/*` to `API_INTERNAL_URL` (`http://backend:8000` inside Compose); in production nginx does the same routing, so the browser sees one origin and avoids CORS and SameSite problems. Send `X-CSRFToken` on every unsafe request.

### `scripts/check-private-terms.sh`

Keeps configured private terms (personal names, internal hostnames, secrets) out of the repository.

```bash
#!/usr/bin/env bash
# Fails if any term in .private-terms appears in a tracked file.
# Usage: scripts/check-private-terms.sh            (working tree)
#        scripts/check-private-terms.sh --history  (every commit)
set -euo pipefail
TERMS_FILE=".private-terms"
[ -s "$TERMS_FILE" ] || { echo "No $TERMS_FILE found; skipping."; exit 0; }

if [ "${1:-}" = "--history" ]; then
  if git log --all -p -i -G"$(paste -sd'|' "$TERMS_FILE")" --oneline | grep -q .; then
    echo "Private term found in git history."; exit 1
  fi
else
  if git grep -n -i -I -F -f "$TERMS_FILE" -- . ':!.private-terms'; then
    echo "Private term found (lines above). Remove it before committing."; exit 1
  fi
fi
echo "No private terms found."
```

In CI, the terms come from a repository secret (`PRIVATE_TERMS`) that the workflow writes to `.private-terms` before running the script, so the list never appears in the repository.

## 10. Suggested build order

0. Docker setup → `make up` brings up an empty Django project, a Next.js starter and PostgreSQL
1. `accounts` → login, `/auth/me/`, lockout, password reset, set password, forced password change; `ErrorLog` in `core`
2. `people` + `transit` → members in the Django admin, then API, then People pages; welcome email with set-password link; skill sheet export
3. `calendar_master` → holidays seeded
4. `timesheets` → monthly sheet + approval; `calc_hours()` tests from `BUSINESS_RULES.md` §2; Excel/ZIP export
5. `leave` → requests, cancel, balance, team calendar; statutory grant + `renew_leave_balances`; carry-over, hourly cap, 5-day duty; 140h accrual on approval; `scheduler` container
6. `travel` → claims + approval; `expire_travel_attachments`
7. `payroll` → payslips (HR + employee views)
8. `reports` → reports, monthly summaries, client cases, analytics, export
9. `notifications` → inbox + bell; emails wired into the flows above
10. `seed` → full fictional demo dataset for screenshots and the portfolio
