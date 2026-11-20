# Preservation checklist

Use this checklist before editing existing code.

## Logic and calculations

- [ ] Trace all callers and downstream outputs.
- [ ] List formulas exactly as implemented.
- [ ] Confirm decimal type, precision, and rounding mode.
- [ ] Test zero, null, absent, holiday, maximum, minimum, and duplicate cases.
- [ ] Compare at least one current worked example.
- [ ] Do not recalculate historical/finalized data without approval.

## Printing and page setup

- [ ] Preserve paper size and orientation.
- [ ] Preserve margins, scale, fit-to-page, and print area.
- [ ] Preserve column widths, row heights, merged cells, page breaks, repeated titles, headers, and footers.
- [ ] Preserve Gujarati fonts and fallback behavior.
- [ ] Preserve logo size, position, aspect ratio, and print resolution.
- [ ] Compare page count and cell/text placement before and after.

## Schema and data

- [ ] Make additive changes by default.
- [ ] Preserve IDs and public field names.
- [ ] Provide migration and rollback.
- [ ] Validate tenant isolation by `school_id`.
- [ ] Verify counts, totals, foreign keys, and null rates.
- [ ] Never delete or overwrite source data automatically.

## Approval gate

Approval is mandatory before changing:

- Existing formulas or totals
- Attendance/result/promotion/finalization rules
- Rojmel balances
- Permissions
- Page setup or report design
- Existing user flow or labels
- Existing Firebase/Supabase behavior
- Historical data

If approval is missing, do not change it.

## Final response gate

Before responding:

- [ ] Reopen and reread every required and edited file.
- [ ] Reopen directly affected callers, models, services, schemas, templates, tests, and configuration.
- [ ] Inspect the final diff for accidental or unrequested changes.
- [ ] Recheck calculations, rounding, page setup, Gujarati text, permissions, and data contracts where relevant.
- [ ] Rerun the strongest applicable validation after the last edit.
- [ ] Correct every safely correctable error before sharing the response.
- [ ] Repeat reread and validation after each correction.
- [ ] Do not claim completion if a relevant check fails.
- [ ] If blocked by missing approval or information, preserve the existing behavior and report the exact blocker.
