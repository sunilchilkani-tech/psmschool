# Neon architecture for the school project

## Security boundary

Use Flutter only as a client. Put authentication, authorization, validation, database access, audit logging, exports, and privileged operations in a server API. Never ship `DATABASE_URL`, an owner password, or a migration role in Flutter.

Recommended low-cost deployment:

- Neon PostgreSQL
- A small Node.js/TypeScript API using Fastify, Hono, or NestJS, or an existing approved server layer
- Neon serverless driver or `pg` with pooled connection string
- Firebase Hosting for Flutter web if already working
- Existing school logo path or one small object only; do not move it unless requested

## Tenant isolation

Every school-owned table must include `school_id uuid not null`. Every query, update, and delete must be scoped by authenticated `school_id`. Do not accept a client-supplied school ID without comparing it to the authenticated membership.

Use membership and role tables:

- `schools`
- `users`
- `school_memberships`
- `roles`
- `role_permissions`

Sensitive operations require server authorization and an audit event.

## Core relational model

Keep names compatible with the current Flutter models where possible. Prefer additive mapping over renaming application fields.

Suggested tables:

- `academic_years`
- `classes`
- `sections`
- `students`
- `student_enrollments`
- `staff`
- `subjects`
- `attendance_sessions`
- `attendance_records`
- `exams`
- `exam_subjects`
- `marks`
- `leave_requests`
- `rojmel_entries`
- `certificates`
- `approval_requests`
- `audit_logs`

Do not create all tables automatically. Add only those required by the current migration module.

## Data integrity

- Use foreign keys and explicit unique constraints.
- Use `numeric`, not floating point, for marks, money, percentages, and balances when exact decimal behavior matters.
- Match the current calculation precision and rounding exactly. Do not move a formula into SQL until old-versus-new tests prove equivalence.
- Store dates as `date` where time is irrelevant and timestamps as `timestamptz` in UTC.
- Use transactions for attendance finalization, result finalization, promotion, Rojmel posting, restore, and approval workflows.
- Keep finalized records immutable except through an approved reopen workflow.

## Migration strategy

1. Create repository interfaces in Flutter.
2. Wrap the existing Firebase/Supabase implementation without behavior changes.
3. Add the Neon API implementation behind a feature flag.
4. Migrate a copy of data.
5. Compare record counts, required fields, totals, calculation outputs, and reports.
6. Run dual-read comparison without changing the displayed result.
7. Switch one module after explicit approval.
8. Keep rollback available.

Never dual-write financial, attendance, or result data without idempotency keys and reconciliation.

## API rules

- Validate every payload server-side.
- Use pagination and bounded limits.
- Use idempotency keys for create/finalize/promote/post actions.
- Return stable error codes; preserve current user-facing messages unless asked.
- Log request IDs, not secrets or full student data.
- Rate-limit login and expensive reports.
- Do not expose unrestricted SQL or generic table endpoints.

## Backup and recovery

Before any destructive or bulk migration:

- Create a database backup or Neon branch.
- Record source and destination counts.
- Produce a rollback command/procedure.
- Verify a sample from each school and academic year.

Do not delete the source provider data after cutover unless the user explicitly approves it after a stable verification period.
