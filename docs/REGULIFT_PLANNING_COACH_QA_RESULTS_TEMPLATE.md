# Regulift — Planning / Data / Coach QA Results

**Status: NOT RUN.** Complete against one declared candidate. This template does not change the existing broad release gates.

## 1. Candidate and policy

| Field | Actual value |
|---|---|
| App version/build/commit/dirty-tree state | |
| Device, OS, distribution/debug profile | |
| Backend deployment and authenticated configuration | |
| Engine/rules, schema/migration and tool versions | |
| Model/provider/prompt/router and temperature/settings | |
| Fixture adapter commit + fixture ID | |
| Injected now, plan timezone, reporting timezone and week start | |
| Program-stage policy and resume rules | |
| Eligibility, partial attendance and muscle-credit definitions | |
| Goal progression/effective-date and history-correction policy | |
| Tested locales/appearance/text sizes | |
| QA, engine, Coach, privacy and release owners | |

Attach the filled `release_manifest.template.json`. Fields still unknown prevent assertions that depend on them.

## 2. Decision and counts

Decision: **Not evaluated / Block / Needs changes / Approve this scope**

| Execution layer | Required | Pass | Fail | Blocked | Not run | Approved out of scope |
|---|---:|---:|---:|---:|---:|---:|
| Source projection / deterministic app tests | | | | | | |
| Actual engine rules against owned golden fixtures | | | | | | |
| Real model with controlled tool returns | | | | | | |
| Integrated configured app/Worker/engine | | | | | | |
| Device/accessibility/human comprehension | | | | | | |

A case objective can have several executions. Count rows, not a mixture of cases and runs. Attach failed attempts and later retests separately. An automation script ending green is not proof of every linked acceptance criterion.

## 3. Required numeric baseline report

| F01 assertion | Expected | Actual | UI + record evidence |
|---|---:|---|---|
| Stage | 1 / 6 | | |
| Current reporting week | Sep 21–27 | | |
| Planned commitments / fulfilled | 3 / 1 | | |
| This-week ended / all-time ended workouts | 1 / 6 | | |
| Logged working sets | 5 | | |
| Recorded / eligible working volume | 2240 / 2240 kg·reps | | |
| Reported RPE coverage / mean | 4 of 5 / 7.75 | | |
| Bench estimate in current 4W | 76 kg | | |
| Full B next date | Sep 23 | | |
| Four-week bins / full-window mean | 0,0,0,5 / 1.25 | | |

For F04: recorded 7 sets/4240; eligible 5/2240. Do not change scopes just to make totals equal.

## 4. Plan and goal mapping evidence

| Field | Before preview | After reject | After confirmed commit | After restart/sync |
|---|---|---|---|---|
| Plan ID + head revision | | | | |
| Effective stage/date policy | | | | |
| Goal head and effective revision | | | | |
| Constraints head and effective revision | | | | |
| Log revision/event cursor | | | | |
| Completed occurrence/session/set IDs | | | | |
| Current-week prescriptions | | | | |
| Explicit future changed IDs and values | | | | |
| Draft/receipt/approval references | | | | |
| Current-week attendance denominator | | | | |

Show stale approval rejection, operation replay and true duplicate user intent separately. Use synthetic local assertions; never upload private snapshot hashes from real users.

## 5. Coach quality and authority

| Case/run/locale/provider | Required facts | Incorrect/unsupported claims | Action-policy result | Relevant source versions | Evidence |
|---|---|---|---|---|---|
| | | | | | |

Attach actual output, minimal permitted tool envelopes and independent no-write/commit assertions. Explain whether an answer came from a local template, on-device model, configured cloud model or injected fake.

Most useful successful normal conversation:

> [Actual text]

Most important failed/unclear conversation:

> [Actual text]

No tested hard failure may be hidden behind an average prose grade. Report repeated-run failures as individual failures.

## 6. Privacy and failure handling

Record paths exercised: cloud Coach, Jev if enabled, sync, analytics, diagnostics, export and retries. Use canaries. A missing API key/no egress is **not** a privacy pass. List which values were allowed, denied and observed at each boundary; do not paste secrets or real personal records.

Record injected failure points and recovery outcome: before commit, mid-transaction, after receipt, model timeout, stale response, offline conflict and account switch/deletion.

## 7. UI/UX review

| Screen/state | User task | Actual obstacle | Severity | Before/after artifact | Owner/retest |
|---|---|---|---|---|---|
| Today/current vs future | | | | | |
| Roadmap/week meaning | | | | | |
| Progress/scope & sparse data | | | | | |
| Coach/input/action preview | | | | | |
| Goal/current vs future | | | | | |

Typography, surfaces and icons reviewed: ___. Motion reviewed with playback/Reduce Motion: ___. Performance measured on device: ___. State explicitly what was not reviewed. Five-person comprehension results, if run: ___.

## 8. Workflow artifact index

| Workflow | Build/fixture | Video with timestamps | Record/tool assertions | Result |
|---|---|---|---|---|
| W1 First-week consistency | | | | |
| W2 Legitimate Week 3 | | | | |
| W3 Next-week preview/commit | | | | |
| W4 Goal effective-date change | | | | |
| W5 History edit / metric scopes | | | | |
| W6 Coach freshness/privacy/error | | | | |
| W7 Empty/partial/ongoing | | | | |
| W8 Accessibility/real-device | | | | |

## 9. Open issues and sign-off

| ID | Reproducible on which candidate | Impact | Required correction | Owner | Retest |
|---|---|---|---|---|---|
| | | | | | |

QA / date: ___
Engine-data owner / date: ___
Coach-backend-privacy owner / date: ___
UI/accessibility reviewer / date: ___
Release owner / scope decision: ___

Other app release gates remain separate. Include explicit scope exclusions, not silent skipped tests.
