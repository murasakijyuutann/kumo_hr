# kumo HR — Business Rules

> Every rule the code must implement exactly, with the Django module that owns it.
> If code and this file disagree, this file wins until it is changed on purpose.
> All dates and times are **Asia/Tokyo**. Hours are stored as `Decimal` with two places.

---

## 1. Periods

| Rule | Value | Owner |
|---|---|---|
| Timesheet month | Calendar month, 1st → last day | `core/utils/dates.py: month_range()` |
| Travel claim period | 16th of the previous month → 15th of the current month, by `used_on` | `core/utils/dates.py: claim_period()` |
| Timesheet close | Approval deadline for the previous month: the **7th** of the next month (`TIMESHEET_CLOSE_DAY = 7`). The dashboard banner counts down to it | `core/utils/dates.py: timesheet_close_date()` |

Example: the **October 2026** claim period is 2026-09-16 → 2026-10-15.

---

## 2. Working hours (`timesheets/services.py: calc_hours()`)

Inputs per `WorkDay`: `start_time`, `end_time`, `break_minutes`, and the day type.

### Day type

| Type | When |
|---|---|
| Weekday | Mon–Fri and no `Holiday` row for the date |
| Day off | Saturday, Sunday, or any date in `Holiday` |

### Calculation

1. **Break.** When a time is entered, `break_minutes` defaults to the overlap of the shift with **12:00–13:00** (60 if the shift spans lunch, less if it only partly overlaps, 0 otherwise). The employee may overwrite it.
2. **Worked** (`total_hours`) = `end − start − break`.
3. **Overtime** (`overtime_hours`) = `max(0, worked − 8h)` on a weekday. There is **no grace window**: the first minute past 8 hours is overtime.
4. **Night** (`night_hours`) = overlap of the shift with **22:00–24:00** and **00:00–05:00**. Night hours are counted in addition to overtime, because the premiums stack.
5. **Day off** (`holiday_hours`) = `worked` on a day off; `overtime_hours` is then 0 so the same hours are not paid twice.

### Input rules

- `start < end`. A shift cannot cross midnight; `24:00` is the latest end.
- `TimeField` cannot hold `24:00`, so an end of `00:00` with a later start means `24:00`. The UI shows it as `24:00`.
- Both times blank = no work that day; all hour fields are 0.

### Worked examples (must be unit tests in `timesheets/tests/test_hours_calc.py`)

| Day | Start–End | Break | Worked | Overtime | Night | Day off |
|---|---|---|---|---|---|---|
| Weekday | 09:00–18:00 | 1:00 | 8:00 | 0 | 0 | 0 |
| Weekday | 09:00–19:30 | 1:00 | 9:30 | 1:30 | 0 | 0 |
| Weekday | 09:00–20:00 | 1:00 | 10:00 | 2:00 | 0 | 0 |
| Weekday | 13:00–17:00 | 0:00 | 4:00 | 0 | 0 | 0 |
| Weekday | 12:30–18:00 | 0:30 | 5:00 | 0 | 0 | 0 |
| Weekday | 09:00–24:00 | 1:00 | 14:00 | 6:00 | 2:00 | 0 |
| Weekday | 04:00–13:00 | 1:00 | 8:00 | 0 | 1:00 | 0 |
| Saturday | 10:00–15:00 | 1:00 | 4:00 | 0 | 0 | 4:00 |

### Monthly totals

- **Days worked** = days with `total_hours > 0`.
- Totals are sums of the daily fields. They are recalculated on every save, never edited by hand.

---

## 3. Timesheet approval (`timesheets/services.py`)

```
draft ──submit()──▶ submitted ──approve()──▶ approved
                        │
                        └──send_back(reason)──▶ sent_back ──submit()──▶ submitted
```

- Only the owner submits; only HR approves or sends back.
- An `approved` sheet is read-only. A `sent_back` sheet is editable again and emails the employee the reason.
- `approve()` runs the monthly accrual check below in the same transaction.

---

## 4. Paid leave

### 4.1 Annual statutory grant (`leave/services.py: statutory_grant_days()`)

Based on the Labour Standards Act, Art. 39. Which table applies depends on the member's scheduled working pattern (`Member.weekly_work_days`, `Member.weekly_work_hours`), not on `employment_type`: a contract employee working full weeks gets the full table.

**Standard table:** members with `weekly_work_hours ≥ 30`, or `weekly_work_days = 5`.

| Service at grant date | 0.5y | 1.5y | 2.5y | 3.5y | 4.5y | 5.5y | 6.5y+ |
|---|---|---|---|---|---|---|---|
| Days granted | 10 | 11 | 12 | 14 | 16 | 18 | 20 |

**Proportional table:** members with `weekly_work_hours < 30` and `weekly_work_days ≤ 4`.

| Weekly days | 0.5y | 1.5y | 2.5y | 3.5y | 4.5y | 5.5y | 6.5y+ |
|---|---|---|---|---|---|---|---|
| 4 | 7 | 8 | 9 | 10 | 12 | 13 | 15 |
| 3 | 5 | 6 | 6 | 8 | 9 | 10 | 11 |
| 2 | 3 | 4 | 4 | 5 | 6 | 6 | 7 |
| 1 | 1 | 2 | 2 | 2 | 3 | 3 | 3 |

- The working pattern on the grant date decides the table. Changing it mid-year does not change a grant already made.
- Worked examples in `leave/tests/test_statutory_grant.py`: full-time at 0.5y → 10; full-time at 7y → 20; 4 days/week, 24 h at 3.5y → 10 (so the 5-day duty in §4.5 applies); 3 days/week, 18 h at 0.5y → 5; 4 days/week but 32 h → standard table.

- The first grant is on `hire_date + 6 months`. Each later grant is one year after the previous `period_start`.
- A grant creates a new `LeaveBalance` with `period_start` = grant date, `granted_days` = the table value, `expires_on = period_start + 2 years`, and `is_active = True`. The previous balance is set to `is_active = False` but stays usable until it expires.

### 4.1a Carry-over and expiry (`leave/services.py: available_days()`)

- Each grant is valid for **2 years**, so unused days carry over into the next grant year once and then expire.
- **Available days** = sum of `remaining_days` over the member's balances with `expires_on > today` (at most two: the current grant and the previous one).
- Deductions take from the **oldest unexpired balance first**, then the current one. Each approved request records where its days came from in `LeaveDeduction(request, balance, days)`, so cancelling restores the same balances.
- Expired balances are kept for history. Their remaining days are simply no longer counted.

### 4.2 Renewal job (`leave/management/commands/renew_leave_balances.py`)

- Runs **daily at 01:00**.
- Selects active members whose next grant date is **on or before today** (`<=`, not `==`), so a missed run catches up the next day.
- `UniqueConstraint(member, period_start)` on `LeaveBalance` makes a second run a no-op; a duplicate insert is caught and skipped.
- One transaction per member. A failure is written to `ErrorLog` and the job moves on to the next member.

### 4.3 Monthly accrual (`timesheets/services.py: approve()` → `leave/services.py: accrue_monthly()`)

- When HR approves a month with `total_hours ≥ 140.0`, add **+1.0 day** to the member's active `LeaveBalance.total_days`. `granted_days` is unchanged, so the 5-day check (§4.5) uses only the statutory grant.
- Recorded in `LeaveAccrual(member, month, rule_code="MONTHLY_140H_V1", days)`, with `UniqueConstraint(member, month, rule_code)`, so a month can never accrue twice (for example after send-back and re-approval).
- Rows are locked with `select_for_update()` during the check.

Example: the September 2026 mockup sheet totals 146.5h, so approving it grants +1 day.

### 4.4 Requests (`leave/services.py`)

```
pending ──approve()──▶ approved ──cancel()──▶ cancelled
   │
   ├──decline()──▶ declined
   └──cancel()───▶ cancelled
```

Each `LeaveCategory` says what it does to the balance:

| `deducts_from` | `counter` | Examples |
|---|---|---|
| `PAID` | — | full day, half day, hourly paid leave |
| `SUBSTITUTE` | — | substitute holiday |
| `NONE` | `LATE` / `EARLY_LEAVE` / `OUTING` / `UNPAID` | late arrival, early leave, outing, unpaid absence |
| `NONE` | — | special leave (bereavement, etc.) |

- **Days requested** = `LeaveCategory.day_count` × working days in the range. Working days exclude weekends and `Holiday` dates (`working_days()`).
- **Hourly paid leave** (`is_hourly`, `deducts_from = PAID`) requires `start_time` and `end_time` on a single date. Days = `total_hours / 8`. At most **40 hours (5 days) per grant year**, tracked in the current balance's `hourly_used_hours`.
- **Balance pre-check** at submission: requested days must not exceed `available_days() − days in the member's other pending requests`. Hourly requests also check the 40-hour cap.
- **Deduction** happens on `approve()`, following §4.1a. Cancelling an approved request reverses its `LeaveDeduction` rows.
- `SUBSTITUTE` categories use `substitute_total` / `substitute_used`. `counter` categories increment their counter on the current balance and deduct nothing.
- The employee can cancel their own request while it is `pending` or `approved` and the start date is in the future. HR can cancel any request.
- **Concurrency.** `submit()`, `approve()` and `cancel()` each run in one transaction and first lock all of the member's unexpired `LeaveBalance` rows with `select_for_update()`, ordered by `period_start` so two transactions always lock in the same order. The balance pre-check and the 40-hour check are recalculated **after** the lock is taken, so two requests sent at the same moment cannot both spend the same days. Covered by `leave/tests/test_balance_locking.py`.

### 4.5 Five-day annual leave duty (`leave/services.py: five_day_status()`)

Employers must make sure every employee granted **10 or more days** takes at least **5 days** within the year after the grant.

- Applies to the current balance when `granted_days ≥ 10`.
- **Days taken** = approved full-day and half-day `PAID` leave with a date inside `period_start` → `period_start + 1 year`, whichever balance it was deducted from. Hourly leave does not count.
- Status:
  - `ok`: 5 or more days taken.
  - `at_risk`: fewer than 5 days taken and fewer than **3 months** left in the year.
  - `overdue`: the year has ended with fewer than 5 days taken.
  - `on_track`: otherwise.
- Shown on the member's leave balance card. The HR dashboard adds a "Things to do" item when any member is `at_risk` or `overdue`.

---

## 5. Travel claims (`travel/services.py`)

- An employee creates, edits and deletes their own claims while `PENDING`. An `APPROVED` claim is read-only.
- HR approves claims one at a time or in bulk.
- `category = TRANSPORT` requires `transport_method`, `departure` and `arrival`; `trip_type` is required for `TRAIN`, `BUS` and `SHINKANSEN`.
- `amount` is a positive integer in yen.
- **Receipt required** for `TAXI`, `SHINKANSEN` and every `category = OTHER` claim. Submitting one without an attachment is rejected; HR cannot approve it either. Other claims may attach a receipt optionally.
- **Attachment expiry** (`travel/management/commands/expire_travel_attachments.py`, **02:00 on the 1st**): for claims with `used_on` more than **2 months** ago that still have a file, delete the file from storage, clear `attachment`, set `attachment_status = EXPIRED`.

---

## 6. Accounts and security (`accounts/`)

### 6.1 Login lockout (`accounts/services.py`)

- **5 consecutive failed logins → locked for 30 minutes** (`User.failed_login_count`, `User.locked_until`).
- A successful login resets the counter.
- A locked account returns the same error as a wrong password, so the response does not reveal whether the email exists.

### 6.2 Session

- Django session cookie: `HttpOnly`, `Secure` in prod, `SameSite=Lax`.
- **30-minute idle timeout**: `SESSION_COOKIE_AGE = 1800`, `SESSION_SAVE_EVERY_REQUEST = True`.
- The session key is rotated on login (Django default) to prevent session fixation.

### 6.3 Password reset

- At most **2 requests per email address per day**: `PasswordResetThrottle`, keyed by the lowercased address and the JST date. Because the key includes the date, no cleanup job is needed.
- The throttle uses `DatabaseCache` so the count is shared across gunicorn workers.
- Tokens come from Django's `PasswordResetTokenGenerator`: HMAC-signed, single use (invalidated by the password change), and valid for **1 hour** (`PASSWORD_RESET_TIMEOUT = 3600`).
- The endpoint always returns the same success response, whether or not the address exists.

### 6.4 New accounts (`accounts/services.py`, `people/services.py: create_member()`)

- HR creates a member; the system generates `employee_no` and creates the `User` with an **unusable password**, so no password ever exists in an email.
- The **welcome email** (§8) contains a one-time **set-password link valid for 72 hours**. Its token comes from `WelcomeTokenGenerator`, a subclass of `PasswordResetTokenGenerator` with its own salt and expiry, so a reset link can't be used as a welcome link or the other way round.
- The link opens `/set-password/[token]`. Setting a password logs the member in.
- If the link expires, HR clicks **Resend welcome email** on the member page, or the member uses "Forgot password" (§6.3).

### 6.4a Forced password change

- `User.must_change_password` is `False` for normal accounts. It is set to `True` only when HR issues a **temporary password** (the Django admin action for someone who can't receive email) and on the bootstrap superuser.
- While it is set, every API call except `auth/me/`, `auth/logout/` and `auth/change-password/` returns **403** with code `password_change_required`, and the frontend redirects to `/change-password`.
- Changing the password requires the current password and clears the flag.

### 6.5 Member deletion and record retention (`people/services.py`)

- Deletion is a soft delete (`deleted_at` = resignation date). The member's `User` is deactivated (`is_active = False`) so they can no longer log in.
- HR cannot delete their own account.
- The last active member in the "HR Admin" group cannot be deleted.
- **No hard delete.** There is no endpoint or admin action that removes a member's rows. The Labour Standards Act (Art. 109) requires employers to keep employee registers, wage records and attendance records for 5 years (3 years under the current transitional rule), so timesheets, leave, payslips and the member record are all kept after resignation.
- **Erasure is deferred.** Anonymising a resigned member's personal fields (name, address, phone, birth date) after the retention period is a possible later feature. It is not built until there is a concrete requirement, because an untested erasure path is riskier than not having one.
- Travel receipt files are the exception: they are deleted after 2 months (§5), but the claim rows themselves are kept.

### 6.6 Ownership

- Employees can read and change only their own timesheets, leave, claims, reports, payslips and notifications.
- Querysets are filtered by owner, so another member's object returns **404**, not 403.

---

## 7. Payslips (`payroll/`)

- One PDF per member per month (`UniqueConstraint(member, period)`). Re-uploading replaces the file and sets `updated_by`.
- Bulk upload matches each PDF to a member by `employee_no` in the file name; unmatched files are reported back, not guessed.
- Downloads go through a signed URL valid for **15 minutes**. The first employee download sets `viewed_at`.

---

## 8. Email (`notifications/emails.py`)

Every outgoing email is written to `MailLog` with its result. Addresses come from settings, never from code.

| Email | To | CC |
|---|---|---|
| Welcome (employee number, 72-hour set-password link) | new member | — |
| Password reset link | requester | — |
| Leave request submitted / cancelled | `LEAVE_MANAGER_EMAIL` | employee |
| Leave approved / declined | employee | — |
| Timesheet sent back (with reason) | employee | — |
| Payslip ready | employee | — |

Settings: `DEFAULT_FROM_EMAIL`, `LEAVE_MANAGER_EMAIL`.

---

## 9. Notifications inbox (`notifications/`)

- HR sends a one-way notification to selected members or to everyone. A broadcast creates one `Notification` row per active member.
- Members see only their own notifications. Opening one sets `read_at`.
- The top-bar bell shows the unread count.

---

## 10. Error log (`core/logging.py`)

- `DatabaseErrorHandler` writes every `ERROR` from `django.request` and from the scheduled commands to `ErrorLog`.
- `ErrorLog` has no foreign keys, so rows survive member deletion and can record errors that happen before login.
- HR reads `ErrorLog` and `MailLog` in the Django admin (read-only).

---

## 11. Exports

| Export | Who | Format | Owner |
|---|---|---|---|
| Timesheet, one member-month | owner or HR | `.xlsx` | `timesheets/exports.py` |
| Timesheets, all active members for a month | HR | `.zip` of `.xlsx` | `timesheets/exports.py` |
| Skill sheet, one member | owner or HR | `.xlsx` | `people/exports.py` |
| Skill sheets, selected members | HR | `.zip` of `.xlsx` | `people/exports.py` |
| Reports and analytics | HR | `.xlsx` / `.csv` (UTF-8 with BOM) | `reports/exports/` |

ZIP files are built by one shared helper, `core/utils/zip.py`. File names use `employee_no`, never the member's name.

---

## 12. Scheduled jobs

Run by the `scheduler` container (see `PROJECT_STRUCTURE.md` §6) from `backend/crontab`, with `CRON_TZ=Asia/Tokyo`.

| Time | Command | Rule |
|---|---|---|
| Daily 01:00 | `renew_leave_balances` | §4.2 |
| 1st of month 02:00 | `expire_travel_attachments` | §5 |

Each command logs its start and end, and writes failures to `ErrorLog` (§10). Every command can be re-run safely.

---

## 13. Decision log

| Date | Decision | Section |
|---|---|---|
| 2026-10-06 | Overtime = worked time past 8 hours a day; no 18:00–18:30 grace window (matches the timesheet mockup) | §2 |
| 2026-10-06 | Annual grants follow the statutory table (10 → 20 days) | §4.1 |
| 2026-10-06 | Unused days carry over once and expire 2 years after the grant; oldest days are used first | §4.1a |
| 2026-10-06 | Hourly paid leave: 8 hours = 1 day, capped at 40 hours per grant year | §4.4 |
| 2026-10-06 | Paid leave is deducted on approval, with a pre-check at submission | §4.4 |
| 2026-10-06 | Track the 5-day annual leave duty with warnings | §4.5 |
| 2026-10-06 | Receipts required for taxi, shinkansen and every "other" expense | §5 |
| 2026-10-06 | Shifts can't cross midnight; enter them as two days | §2 |
| 2026-10-06 | Welcome email sends a 72-hour set-password link, never a password | §6.4 |
| 2026-10-06 | Timesheets close on the 7th of the following month | §1 |
| 2026-10-06 | Scheduled jobs run as management commands under supercronic | §12 |
| 2026-10-06 | Part-time members get the statutory proportional grant, decided by scheduled weekly days and hours | §4.1 |
| 2026-10-06 | Leave submit, approve and cancel lock the member's balances before checking them | §4.4 |
| 2026-10-06 | Soft delete only; records kept for the statutory retention period; erasure deferred | §6.5 |
