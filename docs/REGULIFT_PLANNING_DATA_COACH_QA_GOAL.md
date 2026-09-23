# Regulift — Planning, Data Consistency & Coach QA Goal

**Prepared:** 22 September 2026  
**Audience:** iOS/SwiftUI owner, training-engine owner, backend/Coach owner, QA and product/design reviewer.  
**Basis:** Four screenshots supplied with this request, the attached interface-polish skill, and the supplied earlier QA report.  
**Status:** Specification and synthetic reference fixtures. **No current Regulift build, database, live Coach request or app test was executed for this document.**

## 0. The decision

**Keep this week's work primary. Keep future planning available, but label its date, scope and status. Make Coach explain the same current data the screens use.**

The goal is not another model, dashboard, design system or planning engine. It is one coherent experience:

> The user knows which program week they are in, sees accurate training progress, can change a plan or goal without losing history, and receives a Coach answer grounded in that exact state.

### Answers to the immediate product questions

**Should next week be visible before this week is finished?** Yes, as an optional upcoming preview or a genuine saved future change. No, it should not displace today's workout or imply that the current week is finished. A six-week roadmap can contain future weeks from day one. Future prescriptions may still adapt. Do not require 100% completion before allowing future planning; skipped, partial, rescheduled and rest cases are legitimate states.

**Is Week 3 wrong when charts show the first week of data?** Not necessarily. Program position, calendar attendance and available training-history coverage are different. A calendar-anchored program starting September 7 is in its third stage on September 22 even if the first recorded workout is September 21. A program genuinely activated September 21 with no resume override should be in stage 1 under the fixture policy. The screenshot does not reveal the stored start date or progression policy, so this is a P0 verification question, not proof of a wrong database value.

**Should user goals update from training data?** Derived progress can update automatically under the existing rules. A user's chosen objective, target, deadline, training days or persistent preferences must not silently change just because the model sees a trend. A consequential Coach-requested change needs its exact scope, preview and existing confirmation policy.

## 1. What the screenshots support

| Ref | Source | Visible observation | What is not established |
|---|---|---|---|
| S1 | `evidence/01_today.png` | The captured portion has “Nova's adjustments — 6 changes,” a separate generic “Your next week” card, four statistic tiles, and “Start Full B · ≈ 60 min.” Tiles mix weekly/all-recorded and analysis-eligible wording. | Exact query scopes, current scroll origin, stored plan revision, whether the six changes are draft or committed, or the locale meaning of `4.749`. |
| S2 | `evidence/02_roadmap.png` | “Your 6-week block” shows `3 / 6`, a green bar, tools before the week list, and Week 3 marked CURRENT. Weeks show planned-looking workout/set totals. | Actual activation/resume event, time-zone policy, whether the bar measures elapsed position or completion, and whether counts include future prescriptions. |
| S3 | `evidence/03_progress_sets.png` | Weekly sets shows 5; a 4W chart has one nonzero bar near September 21; an average is shown; Strength selects Back Squat with no records in the last 12 weeks. | Whether zeros mean observed no-training weeks or no history; whether chart filters are global; which exercise produced the 101 kg estimate on Today. |
| S4 | `evidence/04_progress_muscles.png` | A blue chart and front/back muscle highlights are visible with “sets per muscle.” The chart title is outside this crop. | Exact chart metric, values and scope, muscle-credit algorithm, or whether detail/legend exists outside the crop. |

**Do not treat 6 all-time workouts and 5 weekly sets as automatically contradictory. Do not compare the Today volume tile with the cropped chart until their metric, dates, inclusion policy and revision match.** Missing screenshot content is not a missing app feature.

The earlier QA report described an unconfigured Debug simulator and incomplete normal Coach/network testing. That is historical evidence, not proof the new candidate is still unconfigured. Freeze and verify the current environment again; do not inherit old Pass claims or old defects without retesting.

## 2. Focused UI/UX review

**Review mode:** full for these four static screenshots only. Framework: the existing native SwiftUI implementation as described in the project context; source files were not inspected. Keep the current light/dark semantic styling and established components. The supplied polish skill is guidance for review, not an instruction to introduce CSS, React or another theme.

### Coverage

| Category | Inspected | Review boundary |
|---|---|---|
| Typography | Visible headings, scope labels, number/unit combinations, roadmap labels | Actual point sizes, Dynamic Type and contrast are not measured from these reduced screenshots. |
| Surfaces | Card hierarchy, repeated sections, tool placement, chart framing | Safe areas and all scroll positions require a running app. |
| Icons | Visible metric/action/tab icons and color coding | Accessibility names, exact SF Symbol weights and hit areas are not verified. |
| Animations | Static end states only | Not reviewed; require playback and Reduce Motion testing. |
| Performance | None | Not reviewed; device measurements required. |

### Findings and proposed replacements

| Severity | Location | Before | After | Why |
|---|---|---|---|---|
| MEDIUM | S1 Today / upcoming content | A generic next-week message and a separate six-change entry compete above Start in the captured area. | One compact contextual Coach summary; date-stamped upcoming preview is secondary. Start/Resume/rest is the primary task. | Hierarchy and motion restraint: no duplicated attention claim. |
| MEDIUM | S1 “Your next week” | “Your plan changed…open the changes…” without an actual example or effective date. | Display the real affected session/exercise, scope and available reason, or hide the empty message. Distinguish draft from saved future change. | Concrete content and truthful intermediate states. |
| MEDIUM | S1 statistics | “this week · all recorded,” “best e1RM · analysis eligible,” an unqualified KG value. | “Working-set volume · Sep 21–27,” or “Bench estimated 1RM · 4 weeks”; detailed inclusion rules on tap. Move all-time metrics to Progress. | Number typography and explicit metric meaning; no unsupported cross-exercise comparison. |
| MEDIUM | S2 block indicator | `3 / 6` with a green bar can read as work completed. | “Week 3 of 6 · Sep 21–27” plus separate actual completed/partial counts. Label the bar as position or replace it with a step indicator. | Separate planned position from observed achievement; color is not the only cue. |
| MEDIUM | S2 Plan tools | Week designer, goals and import/share precede the actual current week. | Current week/session list first; one “Plan options” action or secondary grouped tools. | Task-first grouping without removing functionality. |
| MEDIUM | S2 week rows | Workout/set quantities do not visibly state whether prescribed or completed. | “3 sessions planned · 72 working sets planned,” with separate recorded completion when relevant. | Planned is not observed. Never turn schedule totals into training history. |
| MEDIUM | S3 early-history chart | A large mostly empty chart and an unexplained low average. | Compact “5 working sets recorded this week”; show evidence coverage. Defer a trend claim until supported. A full-window average may remain only with a clear denominator. | Do not make missing history look like poor performance. |
| MEDIUM | S3 Strength | Back Squat has no records while other lift data may exist. | Suggest a supported lift with data only when no preference exists; respect an explicitly selected no-data lift and offer Change exercise. | Helpful default without silently overriding user choice. |
| MEDIUM | S3/S4 period and chart identity | 4W selector appears alongside a Strength message about 12 weeks; S4 crop lacks its chart heading. | Decide global versus per-card time scopes, label each, and preserve chart title/units/context during navigation and scrolling. | Consistent chart scope and continuity. |
| MEDIUM | S4 muscle graphic | Color indicates muscle coverage without numeric detail visible in this crop. | Provide an accessible numeric list/selection: muscle, sets, period and credit policy. Retain any existing equivalent. | Color alone cannot explain counts; no inference of recovery or growth. |

**Verification verdict: Needs changes to the visible presentation; data correctness not verified.** A confirmed wrong week, stale applied action, incorrect metric or privacy violation is a separate P0 release blocker. Animations, performance, hit targets, runtime contrast, VoiceOver and actual data queries remain unverified.

### Considered but rejected

| Candidate | Rejected because |
|---|---|
| Hide every future week until every current set is complete | Prevents useful planning and mishandles skipped/partial sessions; label and prioritize instead. |
| Add more Rive illustrations, rings or a new visual theme | Does not resolve ambiguous week position, metric scope or stale Coach context. |
| Make all counts equal by using one broad total | Destroys legitimate distinctions between planned commitments, observed sets and eligible strength evidence. |

## 3. Approve the data contracts before changing screens

Record the selected policy and actual code owner in `release_manifest.template.json`. These are proposed contracts, not an inventory of existing implementation. Reuse existing equivalents.

### 3.1 Three distinct meanings of “week”

| Concept | Authoritative input | Display use |
|---|---|---|
| Calendar reporting week | Explicit reporting calendar, timezone, first weekday and half-open date interval | Attendance and weekly charts. |
| Program stage/week | Active program identity, activation/resume/restart event and declared progression policy | Roadmap and current prescriptions. |
| Training-history coverage | Real dated observations and known data-coverage metadata | Whether trends and averages are meaningful. |

Do not derive program stage from all-time workout count, number of imports, number of regeneration calls, or the first nonzero bar. Do not use imported source creation time as activation time.

**Fixture policy:** `calendar_anchored`, six seven-calendar-day stages starting September 21, reporting Monday–Sunday in Asia/Tokyo. This is an explicit test choice, not a claim about Regulift's current policy. If the production engine instead advances an explicit stage after qualifying exposures, test its actual transition event and acceptance rules. Do not change it silently to fit these fixtures. The optional resumed-stage fixture must be excluded with evidence if unsupported.

Date intervals are half-open: `[start, end)`. Work with calendar dates/timezones, not elapsed 604800-second divisions or week-of-year subtraction across New Year. Distinguish `plan_timezone` from `reporting_timezone`. A locale/timezone change may affect presentation but must not quietly reschedule the plan or rewrite event-time provenance. Plan-timezone changes need explicit migration/preview behavior.

Before activation show upcoming/not started, not a clamped Week 1 as if active. After the final stage show completed/needs review according to actual policy, not an eternal Week 6. Deload/recovery transitions remain owned by the existing engine; do not make 100% adherence a prerequisite to rest or safe replanning.

### 3.2 Current planning versus upcoming planning

Use separate dimensions rather than one ambiguous `updated` flag:

- **Proposal lifecycle:** draft, awaiting approval, rejected, expired, superseded, committed.
- **Effective scope:** next set, next exposure, remaining current week, named future calendar week, future block.
- **Effective interval:** precise start/end and timezone where applicable.
- **Observed-work state:** in progress, ended partial, completed, skipped, deleted/corrected.

A committed future change can raise the plan head revision today while leaving today's effective prescriptions unchanged. A persisted future schedule is not necessarily final forever: later approved/automatic engine rules may supersede it. Use “Saved for Sep 28” or “Upcoming preview,” not “locked forever.”

| Current situation | Today primary content | Upcoming content |
|---|---|---|
| No plan/week configured | Set up/review this week | No fake completion or next-week success banner. |
| Workout ready | Today's actual workout + Start | Optional collapsed preview. |
| Workout active | Resume + actual logged work | No replacement of the active session snapshot. |
| Rest day | Rest + next scheduled session/date | Optional upcoming preview. |
| Missed/partial work | Neutral status + Review schedule | Future planning remains available. |
| Current commitments complete | Actual summary + next valid step | A next-week review may become prominent; no pressure to train again immediately. |
| Real future edit waiting for review | Current task remains usable | Specific dated proposal + Review; no already-applied wording. |

### 3.3 Canonical identity and provenance

The existing data layer should provide these responsibilities, whatever the real types are named:

```text
Plan identity + content revision + active/effective interval + source lineage
  ├─ Program stage policy and explicit start/resume/restart events
  ├─ Scheduled occurrence ID (stable through date moves)
  │    └─ Prescription ID + exercise/equipment/loading convention
  ├─ Effective objective version and effective constraints version
  └─ Decision/proposal ID + exact affected IDs + reason/evidence + receipt

Actual workout/session ID
  ├─ Performed-against plan/goal/constraint revision
  ├─ Optional planned-occurrence link; null is valid for unplanned work
  └─ Set ID + observation revision + target vs reported RPE + eligibility
```

Never join by exercise name, “Full A,” day label, array position or the user's most recent active plan. A workout performed under an old plan remains linked to that plan after a replacement. A correction should preserve its audit history while updating the current observation projection. Do not make all historical values immutable forever if editing is a supported user action.

### 3.4 One application read model, not one oversized cloud prompt

A local `PlanningReadModel` should assemble current state from owned records and return versioned projections to Today, roadmap, Progress, goals and Coach tools.

Suggested diagnostic envelope:

```json
{
  "as_of": "2026-09-22T22:00:00+09:00",
  "plan_id": "plan-a",
  "plan_head_revision": 20,
  "effective_goal_revision": 1,
  "goal_head_revision": 1,
  "constraints_revision": 1,
  "log_revision": 6,
  "local_context_revision": 1,
  "program_stage": 1,
  "stage_policy": "calendar_anchored",
  "reporting_week": {"start": "2026-09-21", "end_exclusive": "2026-09-28"},
  "today_state": "rest_day"
}
```

This is a proposed local/synthetic QA envelope, not blanket authorization to export it. Sensitive-derived revisions, hashes, reasons and evidence may themselves reveal private state. Use a reviewed minimal cloud projection. A global head revision and an effective version are deliberately different: a future goal can be saved while the current goal remains unchanged.

Every metric also needs a definition ID, unit, time window, inclusion policy, selected exercise/comparability group, source revision and known coverage. Cache keys must include the real dependencies; refreshing a view must not rerun mutating progression. Never display values from different revisions as one coherent answer without making the stale state explicit.

## 4. Plan-change transaction and data mapping

### Required flow

```text
Explicit user intent / existing automatic engine trigger
  → resolve exact owner, target occurrences and effective dates
  → take a consistent local snapshot
  → existing engine calculates a proposed change
  → show exact goal/constraint/prescription diff when approval is required
  → bind trusted approval to that preview and its revisions
  → revalidate at the atomic write boundary
  → write patch + decision records + receipt together
  → publish committed result and invalidate dependent projections
  → sync only permitted projections through the existing contract
```

Normal automatic progression continues under the existing product policy. Do not add a new confirmation solely because an audit record exists. Coach-requested consequential edits retain their existing explicit confirmation contract. A high-confidence model response is not user approval.

### Before / after invariants

1. **Completed observations remain present** after regeneration, replacement, goal changes and date moves.
2. **Active sessions keep their performed snapshot.** Applying changes to unlogged remaining work requires an explicit supported scope; it cannot reinterpret logged sets.
3. **IDs stay stable through renaming/reordering/moving.** Replacement occurrences have explicit lineage; they do not inherit attendance by index.
4. **Past adherence denominators stay versioned.** Changing next week from three days to two does not rewrite last week's 1/3 into 1/2.
5. **Goal, constraints and corresponding plan changes are coherent.** A crash must not leave a new objective attached to a plan that failed to update. Use atomic local storage or an explicitly modeled recoverable pending transition.
6. **An edit does not become a fabricated historical explanation.** Old messages/decisions stay historical; new evaluations supersede them.
7. **One operation is applied once.** Same ID/fingerprint returns its receipt; same ID/different content is conflict. Two legitimate identical sets with different IDs are distinct.
8. **Expiry and staleness are checked at commit.** Log, plan, goal, equipment or private-context changes can invalidate a proposal. A new preview needs new consent.
9. **Observed work is saved before derived adaptation.** If adaptation fails, show saved/pending rather than lose the workout or claim a completed update.
10. **Sync is owner-bound and revision-aware.** Merge actual offline work, not stale plan patches. Never resolve a plan conflict only by wall-clock arrival time.

For existing Cloudflare D1 code, prepared statements and transactional batches are relevant. A batch rollback on a statement error does not, by itself, enforce the business rule that a guarded update must change exactly one row. Verify affected rows and gate dependent writes in the same tested transaction design. Do not add D1/SwiftData tables just because suggested contract names appear here. [A3]

## 5. Synthetic fixtures and exact values

`fixtures.json` contains **14 isolated snapshots** plus **six calendar boundary examples**. `expected_snapshots.json` contains their reference projections. They are not the user's screenshot data and not recommended training programs.

### Central F01 fixture

- Frozen now: **September 22, 2026, 22:00 in Asia/Tokyo**. This is a test setting, not an inference about the user's timezone.
- Active six-stage calendar-based plan starts **September 21**; revision **20**.
- This week has **Full A Monday / Full B Wednesday / Full C Friday**. Each has only five working sets for compact QA.
- Five older imported workouts are dated in August. They explain an all-time ended count of six without changing the new program week.
- Monday's Full A has:

| Set | Exercise | Load × reps | Reported RPE | Fixture inclusion |
|---|---|---|---|---|
| s1-b1 | Bench | 60 kg × 8 | 8 | Working, eligible |
| s1-b2 | Bench | 60 kg × 8 | 8 | Working, eligible |
| s1-b3 | Bench | 60 kg × 8 | Missing; target is 8 | Working, eligible |
| s1-r1 | Row | 40 kg × 10 | 7 | Working, eligible |
| s1-r2 | Row | 40 kg × 10 | 8 | Working, eligible |
| s1-w1 | Bench warm-up | 20 kg × 10 | Missing | Warm-up; excluded from working totals |

**Exact expected baseline:**

| Metric | Value |
|---|---|
| Program stage | **1 of 6** |
| Current calendar reporting week | **Sep 21–27** |
| Today state at Tuesday 22:00 | **Rest day**; next scheduled Full B is Sep 23 |
| Fulfilled planned commitments | **1 of 3** |
| Ended workouts this week / all time | **1 / 6** |
| Logged working sets this week | **5** |
| Working-set volume | **2,240 kg·reps** (`3×60×8 + 2×40×10`) |
| Reported working-set RPE | **4 of 5**; arithmetic mean **7.75** |
| Bench e1RM in current four-calendar-week window | **76 kg**, using the fixture's stated Epley formula |
| All-time other-lift diagnostic | Deadlift **80×8 → approximately 101.33 kg**; not Back Squat or a performed 1RM |
| Four-week set bins | **0, 0, 0, 5** for Aug31/Sep7/Sep14/Sep21 |
| Full-four-week arithmetic mean | **1.25**, only meaningful with its denominator/coverage explained |

No observed Back Squat exists in this fixture. A general “best e1RM 101 kg” and an empty Back Squat chart can therefore coexist without a broken calculation. The UI should still identify the lift and window.

### Most useful variations

| Fixture | Change | Critical expectation |
|---|---|---|
| F00 | No plan/history | No fake stage, progress or 0/0 completion. |
| F02 | Program starts Sep 7 | Stage **3**, but not three completed training weeks. |
| F03 | Explicit approved resume at stage 3 | Use the resume source only if this policy is supported. |
| F04 | Two unverified 100×10 sets in an unplanned session | Recorded **7 sets / 4,240 kg·reps**; eligible **5 / 2,240**; no extra planned attendance. |
| F05 | Draft next-week bench 60 → 62.5 | Revision **20**, no active change; pending preview only. |
| F06 | Approve the same future-only proposal | Revision **21** once; w2-a changes; this week's prescriptions and historical values do not. |
| F07 | Confirm Strength / two days / 35 min from Sep 28 | Current goal stays Hypertrophy until the effective date; future objective/constraint versions and plan agree. |
| F08 | Goal evidence 75×6 then 75×8; e1RM target 100 | Estimates **90 → 95**; **50%** of original 10kg gap closed. Not an observed 100×5 lift. |
| F09 | End after two of five working sets | Partial session saved; not all planned work completed. |
| F10 | Active session with one logged set | Resume pinned snapshot; no silent plan replacement. |
| F11 | Private Health/derived-context canaries | No forbidden content in cloud context, prompts, diagnostics or telemetry. |
| F12 | Active block but no current-week commitments | Unconfigured week, not completed zero-of-zero. |
| F13 | Clock advances to Sep 28 | Stage **2** under this fixture policy; prior attendance stays incomplete. |

The fixture's e1RM equation, eligibility booleans, commitment status and short sessions are deliberately explicit oracle inputs. They **do not validate production progression or eligibility rules**. Run a separate integration layer through the actual pinned engine and inspect its source decisions. Do not force the engine to emit a 62.5 kg recommendation based on these logs: that particular preview is an explicitly user-requested synthetic change, not a claim that missing RPE satisfied progression.

### Metric variants QA must cover

- An actual 60×8 → 60×9 correction changes current volume from **2,240 to 2,300** and current-window bench estimate to **78**. Cancel leaves the original values.
- Deleting one 60×8 working set leaves **4 sets / 1,760**; restoration returns the original values once.
- Planned sets are not recorded sets; warm-ups are not automatically working sets.
- Per-dumbbell, combined dumbbell, barbell, assisted, bodyweight and machine-stack values need the existing loading convention, not generic multiplication.
- kg/lb and locale separators affect presentation, never stored meaning.
- A muscle map uses the existing versioned credit policy. Secondary muscle credits may mean muscle totals do not sum to session set count. Do not invent coefficients from the silhouette.
- Zero training in a known interval differs from missing observation coverage. Do not silently fill missing history with zero and then claim a negative trend.

## 6. User goal and adaptive-progress rules

Keep these three entities distinct:

| Entity | Can update from logged data? | Requires user choice? |
|---|---|---|
| Derived progress toward a defined metric | Yes, after qualifying records/edits under the declared rules | No new consent merely to recompute a display. |
| Program recommendation toward the confirmed objective | Existing automatic engine policy may update it | Preserve existing action-specific approval policy. |
| Main objective, target value/deadline, persistent schedule or preference | Not silently | Explicit confirmed intent and exact effective scope. |

For an increasing quantitative milestone, a **gap-closed** display can use `(current−baseline)/(target−baseline)`. F08 yields `(95−90)/(100−90)=50%`. This is a proposed display definition, not a physiological forecast. Handle missing/zero-length baselines, downward targets, regressions and values above target explicitly; preserve raw values when a progress bar is bounded. An estimate/target ratio is a different metric and must be labeled differently.

Achievement must match the goal type: estimated strength, an observed lift with specified reps, adherence, or another supported metric. No substitution of e1RM for an actual 100 kg lift; no future prescription counted as achievement. Distinct equipment histories require the existing comparability rules.

After a goal change, profile labels, roadmap, next prescription and Coach use the same effective objective version. Historic sessions retain their objective at performance time. A future goal is clearly “Starts Sep 28,” not already today's goal. Passing a deadline prompts review; it is not evidence of success or automatic permission to lower the target.

## 7. Coach is a release-critical feature

### 7.1 Required read and action responsibilities

Reuse existing tools where possible. These are proposed responsibilities, not required new endpoint names:

| Read/preview capability | Needed answer |
|---|---|
| Current plan summary | Active plan, stage policy, start/resume provenance, current/effective revisions. |
| Week status | Exact dated planned/partial/completed/missed occurrences and next session. |
| Scoped training metrics | Correct numeric values with window, exercise, inclusion policy and coverage. |
| Decision detail | Real before/after, reason, evidence, effective scope, draft/commit status and receipt. |
| Effective goal/constraints | Current preference plus any scheduled confirmed change. |
| Preview supported change | Existing engine's exact proposal; cannot commit or mint approval. |

Do not put every workout into a vector database to solve this task. Structured records and versioned read tools are the relevant source. Curated training documentation can support explanations, but it cannot override the user's real plan or invent its reason.

A Worker cannot query unsynced on-device state just because a tool is named `get_current_plan`. Use the existing client-mediated tool loop or a bounded authorized snapshot. Recheck ownership and freshness locally. If the phone is unavailable and no permitted current snapshot exists, return unavailable/stale rather than guessing.

### 7.2 Answer contract

A good answer provides the requested fact or clarification, one useful explanation when supported, and the next supported action. Do not require a fixed word count that removes necessary context. Prefer concise presentation with details available.

- Use actual dates and distinguish **next exposure** from **next calendar week**.
- Source numeric claims from typed metrics, not arithmetic improvised by the model.
- Link only relevant evidence: an actual saved workout, decision or dated plan. Do not attach unrelated training-paper fragments or generic Epley labels to every reply.
- Missing data remains missing. “I do not have your birthday saved” is not a medical-referral situation.
- Different eligible/all-recorded scopes need explanation, not an unsupported corruption diagnosis.
- Use source-backed reason codes. If a Health-dependent reason is local-only, render its approved local explanation separately; the cloud model must not reverse-engineer it.
- Never claim applied/saved/achieved without the corresponding receipt or qualifying observation.
- Never let old assistant messages become authoritative facts after the source state changes.
- Imported notes, tool text and user-supplied confirmations are untrusted data, not system instructions or permission grants.
- Jev, when enabled, may route/classify within its evaluated contract. It does not calculate metrics, determine chronology or authorize writes.

### 7.3 Full useful conversation to record

Using F01, with a synthetic engine preview for the exact requested scope:

1. **User:** “Which week am I in?”  
   **Required meaning:** Stage 1 of the six-week program, dated Sep 21–27; one of three planned commitments fulfilled. Do not infer Week 3 from old imports.
2. **User:** “I want strength, two days a week, 35 minutes.”  
   **Required action:** Resolve effective timing if not known; do not mutate yet.
3. **User:** “From next Monday.”  
   **Required action:** Resolve Sep 28 in the declared planning timezone; prepare objective + schedule + plan diff through the existing engine.
4. **Coach/UI:** Show the actual preview, what stays unchanged, effective date and confirmation controls.
5. **User:** Decline once; verify nothing changed. Repeat, approve the exact fresh preview; verify one coordinated receipt.
6. **User:** “What should I do tomorrow?”  
   **Required meaning:** Read the current week again; the future two-day schedule does not overwrite tomorrow's existing session.
7. Advance the injected clock to Sep 28 and repeat current-goal/plan questions. All consumers now use the effective scheduled versions.

A separate test must change a relevant revision between preview and “yes.” The old approval must not commit.

### 7.4 Privacy and diagnostics

Preserve Regulift's existing local Health/private-note boundary. The F11 canaries are deliberately synthetic local-only values. Place the export policy **before** any cloud classifier, Jev call, conversation model, analytics or error logger. Redaction after sending the prompt is too late. A derived recovery label or a snapshot hash is not automatically harmless.

Record a minimal synthetic diagnostic showing the actual tool status, metric definition, source revisions, proposal/receipt relationship and allowed fields. Never ask QA to return production credentials, personal medical data, private photos or raw real-user logs. The report must differentiate unit projection tests from a configured device/network run. No outbound request because a key is missing is not a privacy pass.

### 7.5 Evaluation

`coach_cases.json` / `COACH_TEST_CASES.md` contain **28 semantic cases**. They prioritize ordinary useful answers and changes, not only adversarial refusals.

Run three layers independently:

1. **Read-model / tool tests:** deterministic exact source records, scopes and authorization.
2. **Model evaluation:** real configured model/provider/prompt with mocked, explicitly versioned tool returns; evaluate required facts, forbidden claims and proposed actions.
3. **Integrated app conversation:** client, Worker, permissions, local engine, UI approval and persistence together.

For each core semantic case, start with five independent runs of the pinned model/prompt. This is a proposed regression sample, not proof of a zero production error rate. Repeat applicable questions in every shipped locale; the earlier report mentions Vietnamese as well as English/Japanese/Korean, so freeze actual release scope. Record case × locale × provider/routing mode × run number. Do not label all languages passed from one screenshot.

**Hard failures:** any unauthorized data read/write, fabricated current numeric fact, false applied/achieved claim, privacy leak, wrong owner, stale approval committed, or safety-boundary bypass. A model-based grader cannot be the sole judge of these: assert the tool/store state and use human review of meaning.

**Usability grading:** did the answer address the question, use understandable dates/terms, distinguish relevant uncertainty and offer a supported next step without a wall of text? Store examples of misses, not just an average score. Release thresholds and latency budgets must be frozen before the run. Log TTFT/full-answer time separately from local UI response; manual logging must not depend on them.

## 8. Implementation goals and owners

| Goal | Owner / dependencies | Work | Exit evidence |
|---|---|---|---|
| G00 — Freeze semantics and candidate | QA + engine + release owner | Complete manifest; map real types/queries; approve week, scope, goal and eligibility definitions. | No unresolved interpretation used as an expected value. Current backend/model is configured or the run is explicitly blocked. |
| G01 — Authoritative planning projection | iOS/data; G00 | One source of current stage, calendar interval, active plan and effective goal. | PL-01/02/04/10/17 and cross-surface revision assertions. |
| G02 — Safe plan and goal transitions | Engine/data/backend; G01 | Stable IDs, scoped previews, bound approval, atomic commits, replay/conflict handling. | PL-07–20, DM-10/11, GO-04/07 with before/after mappings. |
| G03 — Consistent metrics and corrections | Data/Progress; G01 | Metric definitions, date windows, comparability, warm-up/missing-RPE handling and invalidation after edits. | DM-01–12 and exact F01/F04 values. |
| G04 — Goal meaning and derived progress | Goals/engine; G02/03 | Effective goal versions, actual versus estimated milestones, progress recomputation, no automatic goal drift. | GO-01–08; F08 gap/achievement assertions. |
| G05 — Grounded Coach | Coach/backend/iOS; G01–04 | Bounded tools, useful current answers, actual reasons, freshness, full preview conversation and privacy gating. | All 28 Coach cases with real semantic evidence and independent action assertions. |
| G06 — Current-task UI hierarchy | iOS/design; G01/03 | Merge redundant Today messages; week/date clarity; task-first roadmap; sparse chart states; explicit lift/scope. | UX-01–07 before/after runtime screenshots; unassisted understanding. |
| G07 — Resilience, access and performance | QA/platform; prior goals | Offline, sync conflicts, dynamic type, keyboard, VoiceOver, localization and measured refresh. | Failure traces plus actual-device evidence, not only end-state screenshots. |
| G08 — Candidate decision | QA + feature owners | Resolve scope, attach artifacts, mark each required execution honestly, retest fixed defects. | Filled results report and signed scoped verdict; no unrun case counted as pass. |

**Start with one complete fixture:** F01 → view all consumers → ask the Coach → prepare next-week change → decline → approve → reopen → compare. Expand only after that one path is coherent.

## 9. QA package and execution order

- `QA_TEST_CASES.md` / `qa_cases.json`: **48 planning/data/goal/UI cases**.
- `COACH_TEST_CASES.md` / `coach_cases.json`: **28 Coach cases**.
- **76 total objectives; 25 are marked smoke.** This is not the number of device/locale/provider executions.
- `fixtures.json`: 14 synthetic snapshots and six date-boundary inputs.
- `expected_snapshots.json`: reference aggregate outputs.
- `validate_fixtures.py`: standard-library fixture checker; run with Python 3.9+ and IANA timezone data.
- `release_manifest.template.json`: actual candidate and semantics to freeze.
- `RESULTS_TEMPLATE.md`: results, mapping assertions, evidence and sign-off.
- `evidence/`: the four supplied screenshots and a manifest of their identities/hashes.

### Fixture adapter requirements

The JSON is **not an existing Regulift import format**. QA/dev must create a test-only adapter or equivalent seed factories:

1. Reset only a disposable synthetic account/store. Never mutate a real profile or enable fixture controls in Release.
2. Inject time/calendar and set exact stable IDs, relationships, nullable fields and revisions.
3. Seed source records—not just final UI strings. Existing engine eligibility can be stubbed only in the explicit projection layer; run its real rule tests separately.
4. Map each conceptual field to the actual model and document any semantic difference before changing expected results.
5. Load one fixture per scenario. Do not reseed midway through a continuity test.
6. Capture source-record IDs, snapshot revisions and expected/actual values alongside screenshots. An animation or toast is not a transaction assertion.
7. Distinguish simulator projection tests, configured integration tests and physical-device tests. Keep the earlier broad release suite for other shipped features.

### Eight recording workflows

| Workflow | Required visible path | Additional evidence |
|---|---|---|
| W1 — First-week consistency | F01 Today → roadmap → Progress → Coach “Which week?” | Same revision, stage1, 1/3, five working sets and 2240 across equivalent scopes. |
| W2 — Why Week 3? | F02 program dates → first recorded week → Coach explanation | Start Sep7; stage3; no manufactured completion. Separate F03 if supported. |
| W3 — Future change, not current replacement | F05 preview → decline → repeat/approve → current and future sessions → relaunch | Exact IDs, unchanged history/current targets, rev20→21 once. |
| W4 — Goal change over effective date | F01 multi-turn goal request → F07 commit → current profile → advance Sep28 → profile/roadmap/Coach | Coordinated effective versions, preserved old denominator and performed mappings. |
| W5 — Correction and scopes | F01 edit/cancel/save → History/Progress/Coach; then separate F04 | 2240→2300 only on Save; recorded/eligible distinction 4240 vs2240. |
| W6 — Coach freshness and permission | Normal answer → stale preview → retry → private/no-data → actual timeout | Allowed payloads, no forbidden canaries, no unapproved write. |
| W7 — Empty/partial/ongoing states | F00/F09/F10/F12 in explicitly separate test segments | Named cancel, no 0/0 success, exact resume context. |
| W8 — Real-device usability | Small-screen/light-dark/large text/keyboard/VoiceOver → main read/preview/approve/cancel path | Audio for VoiceOver, real hit testing, screenshot/build identity, timing measurements. |

### Unassisted comprehension check

Use synthetic records and ask five target users, without explaining the UI:

1. Which program week are you in, and how much of this week's work have you completed?
2. Is the shown next-week change already saved, or waiting for approval?
3. What is tomorrow's session after changing the goal from next Monday?
4. Why can recorded volume differ from strength-analysis volume?
5. Has the displayed estimated-strength milestone been performed as a real lift?

Record misunderstandings and hesitation. This is a small discovery study, not a statistical conversion claim. A repeated misunderstanding of saved versus draft, current versus future, or actual versus estimated calls for a concrete UI fix.

## 10. Release gate for this scope

**Block this scope** on a confirmed wrong current stage/plan, silent history remapping, fabricated effort or metric, unapproved goal/plan change, duplicate commit, cross-account leakage, private export, or false Coach saved/achieved claim. Block any required critical case that is Fail, Not run or Blocked; a disabled capability needs approved scope evidence, not an invented Pass.

Before approving:

- [ ] Current and future week semantics signed off and reproducible.
- [ ] Every displayed metric in equivalent scopes agrees at the same snapshot.
- [ ] Plan changes preserve logs, occurrence identity, historical denominator and exact consent.
- [ ] Goal progress is source-backed; preference/target changes are explicit and effective-dated.
- [ ] Coach ordinary answers and the useful multi-turn change flow pass on configured services.
- [ ] Private and stale contexts take the correct local/unavailable/repreview paths.
- [ ] Today/roadmap/Progress hierarchy is reviewed in the actual light/dark app.
- [ ] Critical actions remain accessible; no animated success before save.
- [ ] Results identify candidate, fixtures, layers, actual assertions, unresolved issues and owners.

This is not a complete paid-launch certification. Billing, other account/social functionality, distribution configuration, Watch and other shipped features retain their existing release gates.

## 11. What was checked for this deliverable

The four screenshots were read visually. No current app code or store was inspected. Static text/data ambiguities are identified without assuming corruption.

The supplied fixture checker ran **32 standalone Python reference tests**, including six date-boundary subcases. These validate synthetic fixture relationships and selected manually specified totals, scopes, goals and date expectations. The generated case IDs and references were checked locally. **They do not constitute app, SwiftData, D1, device, privacy-capture or live-model tests.** None of the 76 QA objectives has been executed here.

## Sources and reference boundaries

**S1–S4:** User's four screenshots dated September 22, 2026; original filenames/attachment identities in `evidence/manifest.json`. The screenshot observations in §1–2 are the primary visual evidence.

**S5:** Supplied `make-interfaces-feel-better` skill, especially existing-styling-system preservation, five-category review, typography/numeric stability, hit areas, state review and motion restraint. Use native equivalents; its literal browser/CSS recipes are not iOS implementation contracts.

**S6:** Supplied `REGULIFT_QA_RESULTS(1).md`, revision2, September21: earlier candidate/configuration, partial tests and unresolved Coach/network coverage. Historical context only; does not prove today's candidate state.

**A1 — Apple, Design app experiences with charts.** Supports useful summaries, progressively disclosed chart detail, and preserving values/context between chart views. Consulted September22,2026.
`https://developer.apple.com/videos/play/wwdc2022/110342/`

**A2 — Apple HIG, Accessibility.** Supports adaptable typography, understandable labels, sufficiently sized/separated controls, accessible chart alternatives and non-color-only communication. Consulted September22,2026. A 44×44 pt target is this project's proposed touch-control goal, not a claim that screenshot pixels prove compliance.
`https://developer.apple.com/design/human-interface-guidelines/accessibility`
Readable source: `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/accessibility.json`

**A3 — Cloudflare D1 Database API.** Documents prepared statements, batch execution and rollback on statement failure. The compare-and-swap and identity invariants in this plan are application requirements, not guarantees automatically supplied by any one API call. Consulted September22,2026.
`https://developers.cloudflare.com/d1/worker-api/d1-database/`

Calendar and model-data documentation pages were reachable only as JavaScript stubs during this research. No detailed claim in this handoff is attributed to unread documentation. The date rules, synthetic oracle and data contracts are explicitly proposed engineering requirements to reconcile with the real application.
