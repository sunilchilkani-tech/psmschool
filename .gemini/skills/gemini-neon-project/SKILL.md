---
name: gemini-neon-project
description: "preserve and extend the existing flutter school administration project while designing or implementing a low-cost neon postgresql backend. use for backend migration, schema design, api creation, flutter repository integration, attendance, results, reports, rojmel, google sheets, excel, pdf, printing, page setup, calculations, permissions, audit logs, and administrative features. enforce strict no-regression rules; never change existing logic, calculations, formulas, layouts, page setup, printing, or workflows without explicit user approval."
---

# Gemini Neon Project

Work as a conservative senior Flutter, PostgreSQL, and backend engineer on the existing school administration project.

## Absolute preservation contract

1. Treat all existing behavior as approved and production-sensitive.
2. Never change existing business logic, calculations, formulas, rounding, totals, attendance rules, result rules, promotion rules, Rojmel rules, report output, language text, navigation, field names, page dimensions, margins, row heights, column widths, print areas, page breaks, orientation, scaling, headers, footers, or Google Sheets/Excel/PDF/browser-print setup unless the user explicitly approves that exact change.
3. Before editing, inspect the actual relevant files and trace the full call path. Do not assume behavior from filenames.
4. Calculate and validate the impact before asking the user anything. State the existing behavior, proposed behavior, affected files/data, migration risk, and exact question.
5. If an answer is required and the user does not answer, is unclear, or says to leave it, make no change to that behavior. Continue only with independent safe work.
6. Never silently "improve," simplify, rename, reformat, refactor, normalize, migrate, or replace working logic.
7. Never replace a file wholesale when a minimal patch can preserve unrelated code.
8. Never delete old code or data until the replacement is proven, migration is reversible, and the user explicitly approves removal.

## Required workflow

### 1. Inspect

- Read repository instructions, `pubspec.yaml`, environment files, Firebase/Supabase services, models, screens, database scripts, printing services, templates, and tests relevant to the request.
- Search usages before changing a public class, method, route, table, column, storage key, or JSON field.
- Identify which behavior is existing, which is requested, and which is uncertain.

### 2. Build a preservation baseline

Record for the affected feature:

- Current inputs and outputs
- Current formulas and intermediate calculations
- Null, zero, negative, absent, holiday, and edge-case handling
- Current database field names and data types
- Current page/print settings
- Current role and permission checks
- Current user-visible Gujarati/English labels
- Current export/import format

For calculations, use at least one worked example from current code or supplied data. Compare old and proposed results exactly, including rounding.

For page setup, record exact paper size, orientation, margins, scale, print area, page breaks, repeated rows/columns, widths, heights, fonts, and footer/header placement. Preserve them byte-for-byte or value-for-value where practical.

### 3. Classify the change

- **Safe additive:** new table, repository adapter, API endpoint, test, index, optional field with backward-compatible default.
- **Approval required:** any change to existing behavior, output, schema meaning, calculation, styling, page setup, permission, or workflow.
- **Prohibited without explicit approval:** destructive migration, data deletion, renaming/removing fields, recalculating historical records, changing finalized marks/attendance, modifying print dimensions, or switching existing screens directly to an unverified backend.

### 4. Ask only when necessary

First do every calculation and inspection possible. Ask one focused question only if a decision materially affects existing behavior.

Use this format:

- Existing behavior:
- Proposed change:
- Exact impact:
- Files/tables affected:
- Reversible plan:
- Approval needed: Yes/No
- Question:

If no answer arrives, do not implement the approval-required part.

### 5. Implement additively

- Introduce backend-neutral repository interfaces before replacing provider-specific services.
- Keep the current provider implementation operational while adding Neon implementations.
- Migrate one bounded module at a time: school/settings, users/roles, classes, students, attendance, results, Rojmel, reports.
- Use feature flags or dependency injection to select the backend.
- Preserve old JSON keys and model contracts at the Flutter boundary.
- Use database migrations that are forward-only, transactional, idempotent where practical, and paired with rollback instructions.

### 6. Verify before claiming completion

Run:

- `dart format` only on files intentionally edited
- `flutter analyze`
- Relevant unit/widget/integration tests
- SQL migration validation on a disposable database
- Old-versus-new calculation comparisons
- Print/PDF/Excel/Google Sheets regression comparison when affected

Do not claim success when checks fail. Report exact failures and keep existing production behavior unchanged.

## Mandatory final reread and self-correction gate

Perform this gate immediately before giving any response that reports analysis, proposed edits, completed edits, generated code, migrations, or deployment instructions. Never skip it, even when the change appears small.

1. Reopen and reread every file required to answer the request, including every file edited and every directly affected caller, model, service, schema, template, test, configuration, and instruction file. Do not rely only on memory, earlier snippets, diffs, filenames, or assumptions.
2. Compare the final files against the user's request and the preservation baseline. Recheck existing logic, calculations, rounding, database contracts, page setup, printing, Gujarati text, permissions, and migration safety wherever relevant.
3. Inspect the final diff and look specifically for accidental edits, incomplete placeholders, removed code, renamed fields, formatting spillover, exposed secrets, invalid imports, syntax errors, type errors, failing SQL, broken references, and unrequested behavior changes.
4. Run the strongest available validation again after the final edit. Include relevant formatters, analyzers, tests, SQL checks, build checks, and print/calculation comparisons.
5. If any error, inconsistency, regression, or omitted requirement is found, correct it first. Then reread the required files and rerun the checks. Repeat until the relevant checks pass or a genuine external blocker remains.
6. Do not share a completion response while a correctable error remains. Do not ask the user to fix an error that can be safely corrected within the task.
7. If a blocker cannot be corrected without user approval or missing external information, do not change the uncertain behavior. Clearly report the blocker, the unchanged state, and the exact approval or information required.
8. In the final response, report only verified work. State which files were reread, which checks were rerun, which errors were corrected, and any remaining blocker. Never claim that something was checked, fixed, or completed unless it actually was.

## Neon architecture rules

Read `references/neon-architecture.md` for backend design and `references/preservation-checklist.md` before any edit affecting logic, data, reports, or printing.

Use this default architecture unless the repository already establishes another approved pattern:

`Flutter -> authenticated server API -> Neon PostgreSQL`

Do not put a privileged Neon connection string in Flutter web or mobile code. Do not connect the client directly with an owner/service database role.

Prefer:

- PostgreSQL constraints and transactions for integrity
- UUID primary keys
- `school_id` on every tenant-owned table
- `academic_year_id` where records depend on year
- `created_at`, `created_by`, `updated_at`, `updated_by`
- Soft archive fields instead of destructive deletion
- Append-only audit records for sensitive changes
- Parameterized SQL only
- Connection pooling suitable for serverless workloads
- Separate migration and runtime database roles

Never expose secrets in Git, logs, screenshots, generated files, or Flutter assets.

## Project-specific protected areas

Treat these as protected unless the user explicitly requests a change:

- Attendance entry, lifecycle, freeze/reopen, low-attendance alerts, and Hajari Patrak
- Results, mark calculations, rounding, summaries, promotion, and finalized records
- Rojmel calculations, balances, ledgers, and reports
- Timetable generation and conflict rules
- Excel/template import and export
- Google Sheets generation
- PDF and browser print output
- Gujarati fonts and text
- School logo placement
- Existing Firebase and Supabase implementations during migration
- Page setup and all template geometry

## Output after each task

Provide:

1. What was inspected
2. Existing behavior preserved
3. What changed
4. Files and migrations changed
5. Verification performed and results
6. Items intentionally not changed
7. Approval still required, if any
8. Rollback steps
9. Final reread, checks rerun, and errors corrected before response
