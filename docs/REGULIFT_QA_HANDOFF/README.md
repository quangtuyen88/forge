# Regulift — QA package

**Prepared 20 September 2026 · all results NOT RUN.**

The user reports completing the prior implementation goals. This package verifies the resulting candidate; it does not request another feature roadmap.

## Files

| File | Use |
|---|---|
| REGULIFT_RELEASE_QA_PLAN.md | Scope, fixtures, matrix, release gates and evidence instructions. Start here. |
| REGULIFT_TEST_CASES.md | 216 detailed cases with steps, expected outcome, source and evidence. |
| REGULIFT_UI_WORKFLOWS.md | 17 complete recording workflows plus unassisted usability script. |
| REGULIFT_QA_TRACKER.xlsx | Editable execution tracker with dashboard, case index, profiles, scope and defects. |
| REGULIFT_QA_RESULTS_TEMPLATE.md | Fill and send back with the tracker and evidence. |
| release_manifest.json | Freeze real candidate, products, platforms, flags and oracles before execution. |
| qa_cases.json | Machine-readable case catalog. Not executable automated tests. |
| qa_execution_rows.json | 263 proposed case/profile runs, all Not run. Can seed another test system. |
| DEFECT_TEMPLATE.md | Reproduction, expected/actual, evidence, severity and retest. |
| USABILITY_PARTICIPANT_TEMPLATE.md | Anonymous target-user observations. |

## Tracker conventions

Dashboard counts case/profile executions, not unique test cases. Execution rows are prefilled for proposed minimum profiles; append a new run row for each additional device/variant or retest, keeping old failures. The dashboard uses a fixed monitored capacity stated in the workbook; extend its ranges when adding beyond that capacity. Do not remove failed attempts to improve percentages: use the Current attempt field and archive/supersede earlier attempts explicitly.

The initial status is Not run for every row. CORE/PAID applicability is Required; other gates start Review. Resolve them from the actual release manifest. An N/A needs evidence, reason and reviewer; a missing device, unresolved rule or failing integration is Blocked instead. Keep Jev, next-target cards, Photo and Photo-to-Crew scope independent.

Column input colors and status validation aid editing; they do not establish truth. The workbook must not be used to waive P0 checks or declare a launch automatically. The release owner signs the result report only after reviewing actual evidence.

## Delivery back

Complete the result report, manifest and tracker. Include timestamped named videos, critical state screenshots, actual synthetic exported assets, assertion output, sanitized billing/privacy/platform evidence and open defects. Keep real credentials, customer records, private Health samples and unredacted photos out of the bundle.
