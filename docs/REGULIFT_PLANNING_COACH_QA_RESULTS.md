# Regulift — Planning / Data / Coach QA Results

**Status: EXECUTED IN PART (SIM-DEV, configured cloud Coach).** Run on 23 September 2026 against the candidate in §1.
**Plan:** `docs/REGULIFT_PLANNING_DATA_COACH_QA_GOAL.md`. **Template:** `docs/REGULIFT_PLANNING_COACH_QA_RESULTS_TEMPLATE.md`.
**Evidence:** `docs/qa/2026-09-23-planning/` (screenshots named in the tables, suite summary, `release_manifest.json`). Screen recordings of W1, W5 and the first W6 run were kept locally and not committed because of their size.
This report does not change the existing broad release gates.

**Package note.** The goal document refers to `qa_cases.json` (48 cases), `coach_cases.json` (28 cases), `fixtures.json`, `expected_snapshots.json`, `validate_fixtures.py`, `release_manifest.template.json` and `evidence/` (four screenshots). None of these was supplied; only the two Markdown files were. Fixtures were rebuilt from the exact values in §5 of the goal document. Results are therefore reported per fixture, per workflow (W1–W8) and per Coach question, not per numbered objective. **The 76 numbered objectives remain Not run** until the case files are supplied.

## 1. Candidate and policy

| Field | Actual value |
|---|---|
| App version/build/commit/dirty-tree state | Regulift 1.0 (1), Debug, unsigned. Source: commit `c54f77a` plus the planning changes in the commit that adds this file (`TrainingMetrics`, `MetricInputs`, `PlanningFixtures`, Today / week strip / Progress / Coach packet edits, 22 new tests, 4 new strings). Built with Xcode 27.0 (27A266a) from that working tree. **Final build 11:35 CST**, built from exactly the committed source (Forge, ForgeWidgets and ForgeWatch schemes build; app binary `Forge.debug.dylib` md5 `2228a20d…`): app unit tests and the regression suite. Earlier builds of the same wave ran the other evidence. The 10:59 CST build (identical code, before a comment-only trim of this wave's comment blocks) ran W5, the muscle-card and goal captures, and the privacy and time-zone retest. The 10:19 CST build ran the 35 Coach runs; it lacks only FX-12, which changes nothing when the device and plan time zones match, as they did in every Coach run (both Asia/Tokyo). The 09:41 CST build ran the fixture screens F00–F12; it lacks FX-09 to FX-12 (`ProgressView.weekVolume`, `GoalRoadmapView.evidenceCoverage`, the Coach packet), and the two affected screens were captured again. Untracked files outside the build (QA handoff documents) were present. |
| Device, OS, distribution/debug profile | iPhone 14 simulator "Forge QA iPhone 14", iOS 26.4, Debug. No physical device. |
| Backend deployment and authenticated configuration | Deployed Worker `forge-coach.quangtuyen88.workers.dev` (`/health` → 200, 31 knowledge chunks). The Debug build carries an app secret (presence checked, value never read). The deployed Worker version is not pinned (no version endpoint). Provider keys are not visible to QA. |
| Engine/rules, schema/migration and tool versions | ForgeCore at the candidate commit. SwiftData schema without `VersionedSchema` migrations. Coach read tools `get_current_workout`, `get_program_decision`, `get_recent_sessions`, `get_program_constraints` (`ForgeCore/Sources/ForgeCore/CoachReadContracts.swift`; app side `App/Forge/CoachReads.swift`, `App/Forge/CoachTools.swift`). |
| Model/provider/prompt/router and temperature/settings | On-device first (Apple Foundation Models; unavailable in the iOS simulator, so every answer here came from the cloud). Worker chain `claude-haiku-4-5-20251001` → `gemini-2.5-flash` → `@cf/meta/llama-3.3-70b-instruct-fp8-fast` (`server/src/providers.ts`), `max_tokens` 600, temperature 0.3. The Jev semantic router (`jev-latest`) runs in the Worker and receives the question text only. The provider that answered is not returned to the app (see PQ-14). |
| Fixture adapter commit + fixture ID | `App/Forge/PlanningFixtures.swift` (DEBUG builds only; launch argument `--planning-fixture=<ID>` wipes the local store, then seeds). App fixtures: F00, F01, F02, F04, F08, F09, F10, F12. Source-level fixtures: F01, F02, F04, F08, F09, F11, F13 in `TrainingMetricsTests`, `PlanningFixtureTests` and `PlanningStageTests`. |
| Injected now, plan timezone, reporting timezone and week start | Source tests: now = 2026-09-22 22:00 Asia/Tokyo (injected). Running app: no clock seam; real clock, Wednesday 2026-09-23 about 10:55–12:30 JST, app process launched with `TZ=Asia/Tokyo` (host clock CST, UTC+8). App checks therefore run one day after the goal's frozen now. The Tuesday-22:00 expectations are covered by source tests only. Plan time zone: stored per week plan (`Asia/Tokyo`). Reporting week: ISO, Monday first, device time zone, half-open `[start, end)` (`TrainingMetrics.reportingWeek`, new). Before this run, Today, the week strip and the Coach packet used `Calendar.current` (Sunday first on en_US) and Progress used ISO. |
| Program-stage policy and resume rules | **Session count, not calendar:** `currentWeek = min(6, (completed sessions since mesoStart + offset) ÷ daysPerWeek + 1)`, with a deload override. `mesoStart` = onboarding completion or block restart. After week 6 the block restarts automatically (`App/Forge/Models.swift:171-178`, `App/Forge/WorkoutView.swift:3474-3479`). No explicit resume-at-stage event exists (F03 unsupported). |
| Eligibility, partial attendance and muscle-credit definitions | Eligibility is per session. A session is unverified, and none of its sets is analysis-eligible, if any set is suspect (< 20 s after the previous one, or a confirmed e1RM jump) or it has ≥ 4 sets in < 300 s, unless heart rate was seen. Lifter feedback can exclude single sets per analysis scope. No warm-up sets are stored. The weekly sets chart counts eligible sets with stored RPE ≥ 6. Muscle credit: primary 1.0, each synergist of a compound +0.5, RPE ≥ 6, current reporting week (rolling 7 days before FX-09). **No partial-attendance state:** a plan day is completed at workout finish only if the logged sets reach the day's requirement (`WeekPlanCompletionPolicy`); otherwise it stays owed and becomes missed after the grace window. |
| Goal progression/effective-date and history-correction policy | Goals (`GoalRecord`) progress only from measured, verified evidence; nothing changes a goal automatically. **No effective-dated goal or schedule change exists.** History edits recompute every projection live (no cache). Stale set feedback keeps excluding a corrected set until it is reviewed. |
| Tested locales/appearance/text sizes | English language with the en_VN region ("." groups thousands, "," marks decimals), light mode, default text size. ja/ko/vi, dark mode and large text were not re-run for this scope. |
| QA, engine, Coach, privacy and release owners | Not assigned in the repo; the release owner must name them. |

The filled manifest is `docs/qa/2026-09-23-planning/release_manifest.json`.

## 2. Decision and counts

Decision: **Block**

Goal §10 blocks this scope while any required critical case is Fail, Not run or Blocked. Four things keep it blocked:

1. **The useful change flow cannot run.** There is no future-scoped plan change and no effective-dated goal or schedule change. §7.3 steps 3–7, W3, W4 and F05–F07 are Blocked (PQ-02).
2. **Planned attendance disagrees with itself.** One partly trained day reads as trained on the week strip, not done on the counter, and missed on the plan card (F01 Fail, PQ-01).
3. **The stage policy needs a decision.** The app counts completed sessions; the fixtures assume calendar weeks (F02/F13 Blocked, PQ-03).
4. **Whole layers are not run.** The 76 numbered objectives, the model evaluation with controlled tool returns, and W8 on a real device (PQ-16, PQ-17).

Everything else this run could execute on the simulator either passed or was fixed and retested here (FX-01 … FX-12). Metric values and scopes agree across Today, Progress, History and the Coach packet. Across 35 runs the Coach answered 20 questions fully (tomorrow, scopes, the week rule, the missing birthday), 13 partially, and failed 2 with unsupported promises to change the plan; there was no hard failure (§5). No unapproved write was observed. The captured Coach request carried app fields only, with no Health values, and analytics sent event names without properties (§6).

Rows are executions, listed in §3, §5, §6 and §8. "Required" counts only what this run could name without the case files; the 76 numbered objectives are a separate Not run.

| Execution layer | Required | Pass | Fail | Blocked | Not run | Approved out of scope |
|---|---:|---:|---:|---:|---:|---:|
| Source projection / deterministic app tests | 14 | 13 | 0 | 0 | 1 | 0 |
| Actual engine rules against owned golden fixtures | 13 | 6 | 1 | 6 | 0 | 0 |
| Real model with controlled tool returns | 28 | 0 | 0 | 0 | 28 | 0 |
| Integrated configured app/Worker/engine | 50 | 30 | 16 | 3 | 1 | 0 |
| Device/accessibility/human comprehension | 2 | 0 | 0 | 2 | 0 | 0 |

- **Source projection (14):** `TrainingMetricsTests` 10 and the three `restOfWeek` tests pass. The six date-boundary inputs from `fixtures.json` were not supplied (Not run); `testHalfOpenWeekBoundaries` and `testDSTWeeksUseCalendarDaysNotFixedSeconds` cover half-open weeks, New Year and a daylight-saving week instead.
- **Engine rules (13):** Pass: F01 plan evaluation, F01 stage, doubling-up stage, F13 attendance, F08 goal, F11 canary. Fail: F09, because the engine has no partial state (`testF09PartialSessionCountsAsCompleted`). Blocked: F02 and F13 stage (they pass against the app's policy but the fixture expects the calendar policy; G00 decision, PQ-03), and F03, F05, F06, F07 (capability absent, PQ-02).
- **Model evaluation (28):** `coach_cases.json` was not supplied and no harness with controlled tool returns exists (PQ-16).
- **Integrated:** 11 fixture and workflow rows: Pass F00, F04, F08, F09, F10, F12 and the W5 edit; Fail F01 (W1, PQ-01); Blocked F02 (W2, G00), W3 and W4 (PQ-02). 35 Coach answers: Pass 20, Fail 15. Of the 15, 13 are partial answers that miss required facts and 2 are unsupported promises; there is no hard failure. 3 privacy and error rows: the egress capture, the time-zone retest (FX-12) and the offline path all Pass. 1 integrated stale-approval/replay row is Not run.
- **Device (2):** W8 and the five-person comprehension check (PQ-17).
- Broad gates on the final build, for reference: ForgeCore `swift test` 726/726, app `ForgeTests` 57/57 (iPhone 14), server 204/204, `ast-grep scan` clean, localization placeholder parity ok, Maestro suite 22/22 on the final build (fresh install, shared state, `suite-final-summary.txt`). Flow 11's navigation changed in this wave: the taller stat tiles left the Body stats and Photos rows under the floating tab bar, so the flow now scrolls to the Trends card before tapping; no assertion changed. An earlier run on the 10:59 build went 21/22: flow 11 hit a blank relaunch screen while a build ran on the same host.

## 3. Required numeric baseline report

App values were read on the candidate at the real clock (Wednesday Sep 23, JST); source values at the injected Tuesday 22:00. Numbers display in the simulator's en_VN region format: "2.240" = 2,240 and "1,2" = 1.2. File names refer to `docs/qa/2026-09-23-planning/`.

| F01 assertion | Expected | Actual | UI + record evidence |
|---|---:|---|---|
| Stage | 1 / 6 | **Pass.** Today "Week 1 of 6"; roadmap "1 / 6", Week 1 "Current"; Coach packet `current_week` 1. Engine: `testF01CurrentWeekIsOneImportsBeforeMesoStartDoNotCount` (the August imports do not count). | `F01-01-today-top.png`, `F01-03-roadmap.png` |
| Current reporting week | Sep 21–27 | **Pass (after FX-01).** Week strip Monday–Sunday with Monday Sep 21 trained; Progress bin "Sep 21"; Coach packet `this_week` "2026-09-21 to 2026-09-27". Engine: `testReportingWeekOfNowIsMondayBasedHalfOpen`, `testHalfOpenWeekBoundaries`, `testDSTWeeksUseCalendarDaysNotFixedSeconds`. | `F01-01-today-top.png`, `F01-05b-progress-weekly-sets-4w.png`, `privacy-bodies.json` |
| Planned commitments / fulfilled | 3 / 1 | **Fail (PQ-01).** Scheduled 3 matches. Fulfilled reads 0: counter "0/3 Sessions" and plan card "0 of 3 planned sessions done · 2 still owed · 1 missed", while the week strip marks Monday trained. The 5-set session does not meet Full A's 16-set requirement, and there is no partial state. With the day recorded, the engine gives 1 of 3 (`testF01WeekPlanAtFrozenNowReportsOneOfThreeAndPointsAtFullB`). | `F01-01-today-top.png`, `F01-02-today-tiles.png`, `F01-03-roadmap.png` |
| This-week ended / all-time ended workouts | 1 / 6 | **Pass.** All time: Today "Workouts · all time 6"; Progress "Workouts 6" and "History · 6 eligible sessions". This week: one trained day on the strip, one Sep 21 session in History, Coach `this_week` "1 sessions". | `F01-02-today-tiles.png`, `F01-04-progress-top.png`, `F01-07-history.png` |
| Logged working sets | 5 | **Pass.** Today "5/64 Sets"; Progress "Weekly sets 5"; session detail "Sets 5". | `F01-01-today-top.png`, `F01-05b-progress-weekly-sets-4w.png`, `F01-08-session-detail.png` |
| Recorded / eligible working volume | 2240 / 2240 kg·reps | **Pass.** Today "This week · all recorded 2.240 kg"; Progress "Volume 7d 2,2 t" (analysis-eligible); session "Tonnage 2.240 kg". The fixture warm-up s1-w1 is not seeded: the app stores no warm-up sets. | `F01-02-today-tiles.png`, `F01-04-progress-top.png`, `F01-08-session-detail.png` |
| Reported RPE coverage / mean | 4 of 5 / 7.75 | **Pass.** Session detail "Avg RPE 7,8 · 4 of 5 sets" (7.75 at one decimal); debrief "RPE recorded for 4 of 5 sets". Today and Progress show no RPE mean. Source: `testThisWeekRecordedSetsVolumeAndEffortCoverage` (mean 7.75). | `F01-08-session-detail.png` |
| Bench estimate in current 4W | 76 kg | **Pass.** Progress Strength "Barbell Bench Press 76 kg +6,3 kg"; debrief "PR: Barbell Bench Press e1RM 69,7 → 76 kg". Other-lift diagnostic: Today and Progress "Deadlift · best e1RM 101 kg" (fixture 101.33), named after FX-07. | `F01-05b-progress-weekly-sets-4w.png`, `F01-02-today-tiles.png`, `F01-08-session-detail.png` |
| Full B next date | Sep 23 | **Pass at the app clock (Wednesday Sep 23):** "Today's session · Full B", plan card "Full B · Due today", Coach `next_session` "Full B on 2026-09-23". The Tuesday 22:00 state (rest day, next Full B Sep 23) is covered by the engine test only (no clock seam). | `F01-01-today-top.png` |
| Four-week bins / full-window mean | 0,0,0,5 / 1.25 | **Pass.** 4W chart: Aug 31 0, Sep 7 0, Sep 14 0, Sep 21 5. Caption "This week · avg 1,2 over 4 recorded weeks" (1.25 at one decimal, denominator shown). Source: `testWeeklyBinsFourWeeksWithAugustCoverageStart`; a new user's earlier weeks are not averaged as zero (`testNewUserEarlierWeeksUncovered`). | `F01-05b-progress-weekly-sets-4w.png` |

**F04** (two unverified 100×10 sets in an unplanned Tuesday session): **Pass.** Today, all-recorded scope: "This week · all recorded 4.240 kg", "7/64 Sets", "Workouts · all time 7", "5 of 7 sets passed the plausibility check". Progress, analysis-eligible scope: "Volume 7d 2,2 t", "Workouts 6", "History · 6 eligible sessions". The sessions counter stays "0/3" and the plan card is unchanged, so there is no extra planned attendance. The scopes stay distinct and labeled. After FX-06 the Coach explains the difference (§5). Source: `testUnverifiedF04SetsCountOnlyInAllRecordedScope`. Evidence: `F04-01-today-top.png`, `F04-02-today-tiles.png`, `F04-04-progress-top.png`.

## 4. Plan and goal mapping evidence

**Not exercisable as specified.** The candidate has no future-scoped plan change (F05/F06) and no effective-dated goal or schedule change (F07). The requested change in §7.3 becomes a "Remember this?" memory note (§5). The columns after "before preview" therefore stay empty. The first column shows what the candidate stores in place of each field.

| Field | Before preview | After reject | After confirmed commit | After restart/sync |
|---|---|---|---|---|
| Plan ID + head revision | Week plan `id` with a constant `version` (never incremented). Coach previews bind `planRevision` = digest of program version, current week, exercise overrides, deload start and session count (`CoachView.planRevision`). | Not run | Not run | Not run |
| Effective stage/date policy | Session-count stage (§1). F01 reads Week 1 of 6 on Today, the roadmap and the Coach packet. No effective date exists. | Not run | Not run | Not run |
| Goal head and effective revision | `GoalRecord` list stored inside the profile. No revision, no effective date. | Not run | Not run | Not run |
| Constraints head and effective revision | Profile fields for goal, days per week and session minutes. No revision, no effective date. Settings → Training read Hypertrophy / 3 days / 60 min after every Coach run in §5. | Not run | Not run | Not run |
| Log revision/event cursor | None. Every projection recomputes from the stored sessions. | Not run | Not run | Not run |
| Completed occurrence/session/set IDs | Plan day ID = the day name ("Full A"). Session reference = `local-<unix time>-<day name>` until synced (`WeekPlanCompletionPolicy.sessionReference`). Sets carry no ID in the metric projection. | Not run | Not run | Not run |
| Current-week prescriptions | Program week 1: 3 workouts, 64 working sets (Full A 16, Full B 24, Full C 24). The roadmap and Today agree after fix FX-02. | Not run | Not run | Not run |
| Explicit future changed IDs and values | None: no future-scoped change type exists. | Not run | Not run | Not run |
| Draft/receipt/approval references | Swap, early deload and block restart: `CommitPreview` (recommendation ID, program version, plan revision, digest, 7-day expiry) → `CoachCommitPolicy.check` → ledger → `DecisionLogEntry`. Memory notes skip the ledger by design. `existingReceiptDigest` is always `nil` in the app. | Not run | Not run | Not run |
| Current-week attendance denominator | Plan evaluation `scheduled` = 3 (F01). The plan is stored as one value inside the profile, so an edited week overwrites it; no earlier denominator is kept. | Not run | Not run | Not run |

Stale approval, operation replay and duplicate intent were checked at source level only. The ForgeCore `CoachContractsTests` all pass in the 726-test run: `testPlanMovedAfterThePreviewIsStale`, `testExpiredPreviewIsRejected`, `testDifferentDiffWithTheSameIDIsADigestMismatch`, `testAnotherOwnersResourceIsRejectedBeforeAnythingElse`, `testReplayOfTheSameOperationReturnsTheOriginalReceipt` and `testReplayWithDifferentContentIsAConflict`. In the running app receipt replay is not wired (PQ-09). Integrated stale-approval, replay and duplicate-intent runs: **Not run**.

## 5. Coach quality and authority

All runs used the 10:19 CST build (the final build without FX-12, which does not change answers when the device and plan zones match, as here) and the deployed Worker, English, 5 independent runs per case. Each run relaunched with `--planning-fixture`, which wipes chat history and data. The on-device model is unavailable in the simulator, so every answer came from the Worker: the configured cloud model, except C5, which is the Worker's `missing_fact` rule template (`server/src/guard.ts`, `missingFactAnswer`). The Worker does not return which provider in its chain answered (PQ-14). Nothing was tapped on any action card. Settings → Training was read after every run. Full text of all 35 answers: `coach-answers.md`.

| Case/run/locale/provider | Required facts | Incorrect/unsupported claims | Action-policy result | Relevant source versions | Evidence |
|---|---|---|---|---|---|
| C1 "Which week am I in?" · F01 · r1–r5 · en · cloud | Stage 1 of 6, dated Sep 21–27, and planned vs done (the app shows 0 of 3). **Partial ×5:** the stage is right in 5/5. The next session (r2) and the advance rule with the block start (r4) appear in some runs. Dates and planned vs done appear in 0/5. | None | No action proposed (correct) | Packet `today`, `current_week`, `program_week_rule`, `this_week`, `planned_this_week`, `next_session`, `rest_of_week` | `coach-F01-r1-q1.png` |
| C2 "I want strength, two days a week, 35 minutes." · F01 · r1–r5 | Resolve when it should start; change nothing yet. **Partial ×4, Fail ×1 (r2):** no run asks when it should start, and nothing changes. | All 5 say "Noted —" before Apply (PQ-04). r2 adds "I'll plan around it", but a memory note changes no plan (PQ-19). | A "Remember this?" memory card in 5/5, not applied. Settings unchanged after every run (Hypertrophy / 3 days / 60 min). | Worker prompt `remember` action; `CoachView.applyRememberedNote` | `coach-F01-r1-q2.png`, `coach-F01-settings-r1-r5.png` |
| C3 "From next Monday." · F01 · r1–r5 | Resolve Sep 28 in the plan time zone and prepare the change (capability absent, PQ-02). **Partial ×4, Fail ×1 (r2):** no run names Sep 28, and the card note drops the date in 5/5. | r2: "…starting next Monday, I'll adjust the plan then." Nothing is scheduled (PQ-19). | Memory card only; no write | Same | `coach-F01-r1-q3.png` |
| C4 "What should I do tomorrow?" · F01 · r1–r5 | Read the current week again: Thursday Sep 24 has nothing planned; Full C is Friday Sep 25. **Pass ×5**, e.g. "You've got a rest day planned for tomorrow, so take it easy and come back strong on Friday for Full C." | None on the final build. Before FX-04: the fabricated "tomorrow, September 23". Before FX-11: "Full C, scheduled for tomorrow" in 1 of 2 runs. | No action | Packet `today`, `rest_of_week` (FX-11) | `coach-F01-r1-q4.png`, `before-coach-F01-q4.png`, `before-coach-F01-r2-q4.png` |
| C5 "When is my birthday?" · F01 · r1–r5 · Worker template | Missing data stays missing, with no medical referral. **Pass ×5:** "I don't have your birthday saved." | None | No action | `server/src/guard.ts` `missing_fact` | `coach-F01-r1-q5.png` |
| F04 "Why does Today show 4240 kg this week but Progress shows 2.2 t?" · r1–r5 · cloud | Explain the recorded vs analysis-eligible scopes with the right values; no corruption diagnosis. **Pass ×5**, e.g. "Today's tile counts every recorded set, which is 4240 kg·reps, while Progress charts only count analysis-eligible sets, totaling 2240 kg·reps or 2.2 tons." | r4 and r5 write "2240 kg" for kg·reps (unit slip). | No action | Packet `this_week`, `metric_scopes` (FX-06) | `coach-F04-r1.png`, `before-coach-F04.png` |
| F02 "Why am I in week 1? I started this program on September 7." · r1–r5 · cloud | Start Sep 7, the real stage rule, no manufactured completion. **Pass ×5:** "You're in week 1 because you've only completed 1 session since the block started on September 7, and the program advances one week per 3 completed sessions." r4 adds "…once you've completed 2 more sessions." | None | No action | Packet `program_week_rule` (FX-08) | `coach-F02-r1.png` |

Totals: 35 answers. Pass 20 (C4, C5, F04, F02), Partial 13 (C1 ×5, C2 ×4, C3 ×4), Fail 2 (C2 r2, C3 r2: unsupported promises to change the plan). No hard failure: no unauthorized read or write, no fabricated current fact, no false "applied" or "achieved" claim, no privacy leak observed (§6).

Most useful successful normal conversation (F01, run 4):

> **Lifter:** Which week am I in?
> **Coach:** You're in week 1 of the mesocycle, focusing on building volume and intensity. Your current week will advance once you've completed 3 sessions since the block started on September 21.
> **Lifter:** What should I do tomorrow?
> **Coach:** You've got a rest day planned for tomorrow, so take it easy and come back strong on Friday for your Full C session.

Most important failed/unclear conversation (F01, run 2):

> **Lifter:** I want strength, two days a week, 35 minutes.
> **Coach:** Noted — you prefer a strength focus, 2 days a week, with 35-minute sessions, I'll plan around it.
> **Lifter:** From next Monday.
> **Coach:** Noted — you prefer a strength focus, 2 days a week, with 35-minute sessions, starting next Monday, I'll adjust the plan then.

Nothing was saved (the "Remember this?" card still waits for Apply), nothing is scheduled for Monday, and Settings still read Hypertrophy / 3 days / 60 min. The lifter is told the plan will change when it will not.

## 6. Privacy and failure handling

**Paths exercised**

| Path | How | Result |
|---|---|---|
| Cloud Coach, deployed Worker | 35 questions on F01, F02 and F04 (§5) | Answers returned. Request bodies on this path were not captured (TLS to the deployed Worker). |
| Cloud Coach, local capture server | App pointed at `http://127.0.0.1:8799` through its `coachServerURL` setting. F01, then a check-in through the UI (sleep 8.0 h; soreness, energy and motivation 3), then one question. The server recorded path and JSON body only, never headers. The default server was restored afterwards. | First capture (10:19 build): one `/coach` request, with body keys `question`, `context`, `history`, `notes`, `language`, `coach` and `decisions`. The context held 15 app fields (`today` … `last_sets`). There was no `sleep_hours`, `hrv_ms` or `resting_hr` key and no "sleep" or "soreness" text, although the check-in had just saved sleep 8.0 h and soreness 3. `history`, `notes` and `decisions` were empty (F01 records no decisions). The same capture exposed FX-12 (plan days shifted a day when the device zone differed from the plan zone). Retest on the final build, same setup (plan saved in Asia/Tokyo, app relaunched in Asia/Taipei): `next_session: Full B on 2026-09-23`, `rest_of_week: Wednesday 2026-09-23 (today): Full B; Thursday 2026-09-24 (tomorrow): rest day, nothing planned; Friday 2026-09-25: Full C; …`. That is correct, and again no Health key was present. (`program_week_rule` still says the block started on 2026-09-20, because the fixture set the start instant at Tokyo midnight; the start is an instant, not a plan day.) Evidence: `privacy-bodies.json`, `privacy-coach.png`. |
| Analytics (`/events`, same base URL, sent in batches of 10) | Event buffer read from the app's preferences after the run | In the first capture one `/events` batch of 10 was sent: event names only (`app_open` ×6, `coach_question` ×4), no properties, and a random install ID (redacted in the evidence). In the final-build capture the batch threshold was not reached; the buffer held 6 events (`app_open` ×3, `checkin_saved`, `coach_question` ×2), also without properties. |
| Jev semantic router | Runs inside the Worker on the question text | Not captured (server side). |
| Unit canary F11 | `testF11CanaryHealthValuesNeverReachTheRenderedPayload` | Pass: `CANARY-HRV-38` and `CANARY-SLEEP-5.5` absent from the rendered packet; both keys listed as withheld. |
| Sync, diagnostics, export, retries | — | Not run. |

**Allowed, denied and observed values**

| Boundary | Allowed by design | Denied by design | Observed |
|---|---|---|---|
| `/coach` request (cloud Coach) | Question text; app-sourced packet fields (goal, days per week, bodyweight entered in the app, injuries, week and plan facts, lift bests, last sets); remembered Coach notes; cloud-exportable decisions; chat history; language; coach name | Health-sourced fields (`sleep_hours`, `hrv_ms`, `resting_hr`); decisions whose reasoning read readiness, sleep or soreness | Allowed fields only. The check-in's sleep 8.0 h and soreness 3 did not appear. `volume_autoregulation` was not emitted in this run, so PQ-15 could not be observed. |
| `/events` (analytics) | Event names, short string properties, random install ID | Anything else | Names only, no properties |
| Jev router (inside the Worker) | Question text | The packet | Not captured |
| Rendered packet (unit canary F11) | — | `CANARY-HRV-38`, `CANARY-SLEEP-5.5` | Absent; both keys listed as withheld |

**Failure points**

| Injected failure | Recovery outcome |
|---|---|
| Coach server unreachable (capture server stopped mid-conversation) | "Coach is offline right now. Try again in a minute." The earlier reply stayed, nothing new was invented, and nothing was written (`privacy-offline.png`). |
| Model timeout, stale response, failure before commit, mid-transaction, after receipt, offline conflict, account switch or deletion | Not run: the app build has no fault-injection seam for these points. |

## 7. UI/UX review

| Screen/state | User task | Actual obstacle | Severity | Before/after artifact | Owner/retest |
|---|---|---|---|---|---|
| Today/current vs future | See today's session and how far this week is | Fixed: the planned-set target was 72 on Today and 64 on the roadmap (FX-02). Open: Monday reads three ways (PQ-01), and the volume tile names neither the metric nor the dates (PQ-06). The S1 concern did not reproduce: there is no generic "next week" card, the adjustments card ("Kai's adjustments · 6 changes") is collapsed below the plan card, and the primary action is pinned. | P1 open (PQ-01), P3 open (PQ-06), fixed (FX-02) | `before-F01-01-today-top.png` → `F01-01-today-top.png`; `F01-02-today-tiles.png` | iOS + engine / W1 |
| Roadmap/week meaning | Tell which week it is and what is planned | "1 / 6" with a filled bar reads as completion; Plan tools sit above the week list; rows say "3 workouts · 64 working sets" without "planned" (PQ-05). | P2 open | `F01-03-roadmap.png` | Design + iOS / W1 |
| Progress/scope & sparse data | Read progress without mistaking sparse history for decline | Fixed: the best-e1RM tile names its lift; the weekly-sets average states its denominator; weeks before the first record are not averaged as zero; the header says "Analysis eligible" with a footnote; the profile row says "Training records since August 2026". Fixed in this run: the muscle card titled "This week" counted the last 7×24 h (FX-09). Open: "Volume 7d" is a rolling window next to calendar-week figures (PQ-12). Strength opens on Barbell Bench Press, a lift with data; the S3 "Back Squat with no records" state did not reproduce on F01. | fixed / P3 open | After: `F01-05b-progress-weekly-sets-4w.png`, `F01-04-progress-top.png`, `F01-17-progress-muscles.png`. Before: the goal's S3/S4 screenshots and source review (no fixture capture predates FX-07). | Progress / W1 |
| Coach/input/action preview | Change the plan from a date | No dated preview exists; the Coach offers a "Remember this?" memory card and says "Noted" before Apply (PQ-02, PQ-04). | P0 for this scope / P2 | `coach-F01-r1-q3.png` | Coach + product / W4 |
| Goal/current vs future | See goal progress and whether it is achieved | F08 passes on meaning: "Bench estimated 1RM 100 kg · On track", 95 kg, "Baseline 90 kg · 50% of the distance to target", milestones 25 % and 50 % reached, "5 sessions from before this goal existed, not counted". Fixed in this run: coverage read "3 of 1 verified" (FX-10). Open: "Next milestone 75% at 97.5 kg" ignores the region's decimal comma, which the milestone list above it uses ("97,5 kg") (PQ-18, known ForgeCore reason-string gap). The "Check this goal" note appears because the fixture stored an evidence count of 2 while 3 records count; that is an adapter artifact, not an app defect. No future goal version exists (PQ-02). | fixed / P3 open | `F08-09-goal-top.png`, `F08-10-goal-card.png` | Goals / W4 |

Typography, surfaces and icons reviewed: static iPhone 14 screenshots of Today, the roadmap, Progress, History and session detail, the Goal roadmap and the Coach, light mode, English, en_VN region. Motion reviewed with playback/Reduce Motion: not reviewed. W1, W5 and the first W6 run were recorded, but the recordings were not reviewed frame by frame, and Reduce Motion was not tested. Performance measured on device: not measured. Not reviewed: dark mode, Dynamic Type sizes, ja/ko/vi, VoiceOver, keyboard navigation, hit areas. Five-person comprehension: not run.

## 8. Workflow artifact index

| Workflow | Build/fixture | Video with timestamps | Record/tool assertions | Result |
|---|---|---|---|---|
| W1 First-week consistency | 09:41 build, F01 | Local `W1-F01.mp4`, start 09:56:45 CST: Today 0:24, tiles 0:30, roadmap 0:40, Progress 0:53–1:12 | §3 table; `TrainingMetricsTests` 10/10, `PlanningStageTests` F01, `PlanningFixtureTests` F01 | **Fail** on planned attendance (PQ-01). Stage, week, sets, volume, RPE, estimates, bins: Pass. |
| W2 Legitimate Week 3 | F02: screens on the 09:41 build, Coach on the 10:19 build | — | `testF02ProgramStartedSep7StillReadsWeekOne`; F02 captures; Coach F02 × 5 (§5) | **Blocked (G00, PQ-03).** The app reads Week 1 under its session-count policy; no completion is manufactured (4W bins 0, 0, 0, 5). The Coach explains the session-count rule correctly in 5/5 runs. |
| W3 Next-week preview/commit | — | — | — | **Blocked:** no future-only plan change exists (PQ-02). |
| W4 Goal effective-date change | 10:19 build, F01 conversation | Local `W6-F01-run1.mp4` | Settings → Training read Hypertrophy / 3 days / 60 min after each of the 5 runs | **Blocked:** no effective-dated goal or schedule change (PQ-02). The conversation part is in §5. |
| W5 History edit / metric scopes | F01 edit on the final build; F04 screens on the 09:41 build | Local `W5-F01.mp4`, start 11:00:31 CST: detail 0:30, draft 0:37, after Cancel 0:39, after Save 0:46, Today 0:53, Progress 1:17 | `testCorrectionRaisesVolumeAndBenchEstimate` (2,300 / 78), `testDeletingOneBenchSetLowersCountAndVolume` (4 / 1,760); UI on F01: `F01-11` to `F01-16`; F04 scopes (§3) | **Pass.** Bench set 1 went 60×8 → 60×9. The draft moved nothing; Cancel restored 60×8 and e1RM 76; Save changed it once: History e1RM 78, debrief "PR … 69,7 → 78 kg", Today "This week · all recorded 2.300 kg", Progress Strength "78 kg +8,3 kg", PRs "Barbell Bench Press 78 kg". F04 keeps recorded 4,240 and eligible 2,240 apart (§3). Deletion (4 sets / 1,760) is covered by the source test only. |
| W6 Coach freshness/privacy/error | 10:19 build for the 35 answers; final build for the capture retest | Local `W6-F01-run1.mp4` | 35 answers (§5); request bodies and analytics buffer (§6); offline run (§6) | **Fail**: C1–C3 answers miss required facts, and C2/C3 run 2 promise plan changes (PQ-19, PQ-20). Pass: current-date and "tomorrow" freshness after FX-04 and FX-11, privacy (§6), the time-zone retest (FX-12) and the offline path. The stale-preview step is Blocked: no plan preview exists. |
| W7 Empty/partial/ongoing | 09:41 build, F00, F09, F10, F12 | — | Captures `F00-00-launch.png`, `F09-01-today-top.png`, `F10-01-today-top.png`, `F12-01-today-top.png` | **Pass with PQ-01.** F00 opens on onboarding with no stage or progress. F09 keeps the partial session (2/64 sets) and does not complete the day (0/3), but the strip marks Monday trained. F10 shows "Resume Full B · 1 set logged" and "You have a session open" (FX-03). F12 shows 0/3 and 0/64, never 0/0; the app has no "unconfigured week" state because the program's days per week always supply the commitments. A named cancel was not exercised here. |
| W8 Accessibility/real-device | — | — | — | **Blocked:** no physical device, VoiceOver audio, hit testing or timing (PQ-17). |

## 9. Open issues and sign-off

### Open

| ID | Reproducible on which candidate | Impact | Required correction | Owner | Retest |
|---|---|---|---|---|---|
| PQ-01 | This candidate, F01 and F09 on Today | **P1.** One partly trained day reads three ways. The week strip marks Monday trained, the counter says "0/3 Sessions", and the plan card says "0 of 3 planned sessions done · 2 still owed · 1 missed". There is no partial state. The fixture's "1 of 3" cannot be reached: 5 logged sets do not meet Full A's 16-set prescription. | Record an ended-partial day state at finish (sets logged vs required). Drive the strip, counter, plan card and Coach packet from one evaluation. | Engine + iOS | W1 on F01 and F09 |
| PQ-02 | This candidate | **P0 for this scope (missing capability).** No effective-dated goal or schedule change and no future-only plan change with a preview. "Strength, two days a week, 35 minutes, from next Monday" becomes a "Remember this?" memory note. W3, W4, F05–F07 and §7.3 steps 3–7 cannot run. | Product decision: build scoped preview → confirm → commit for future plan and goal versions with an effective date, or approve these items out of scope in writing. | Product + engine + Coach | W3, W4, §7.3 |
| PQ-03 | This candidate | **Decision (G00).** The stage policy is session count; the fixture policy is calendar-anchored. F02 (started Sep 7, one session since) reads Week 1; the fixture expects 3. F13 (Sep 28) reads Week 1; the fixture expects 2. | Sign off the policy. If session count stays, the stage label must say how it advances. The Coach packet now carries the rule; the UI does not. | Product + engine | W2, `PlanningStageTests` |
| PQ-04 | This candidate, Coach | **P2.** The reply says "Noted — …" before the lifter taps Apply on "Remember this?". The stored note drops "starting next Monday". | Ask rather than state until Apply. Keep or explicitly refuse the date. | Coach | C2, C3 |
| PQ-05 | This candidate, roadmap | **P2 UX.** The "1 / 6" bar reads as completion. Plan tools sit above the week list. Rows say "3 workouts · 64 working sets" without "planned". | Current week first; "Week 1 of 6 · Sep 21–27"; "planned" in the row text; label the bar as position. | Design + iOS | W1 |
| PQ-06 | This candidate, Today tiles | **P3 UX.** "This week · all recorded 2.240 kg" names neither the metric nor the dates, and uses kg for a kg·reps sum. With the en_VN region, "2.240" reads like 2.24 to an English reader. | Title "Volume · Sep 21–27"; explain the unit; show inclusion rules on tap. | Design + iOS | W1 |
| PQ-07 | This candidate, data layer | **P2.** Plan identity: the week plan version never changes, the day ID is the day name, and the session reference is time + day name. §3.3 of the goal forbids joins by "Full A". | Stable occurrence IDs and a plan revision. | Data | — |
| PQ-08 | This candidate, sync | **P2.** Plan and goals live inside the profile record; sync is last-writer-wins per row (goal §4, invariant 10). | Revision-aware merge for plan and goal; merge logged work separately. | Backend + data | — |
| PQ-09 | This candidate, Coach apply | **P2.** Receipt replay is not wired in the app (`existingReceiptDigest: nil`), although the policy supports it and its unit tests pass. | Store the receipt digest and pass it at apply. | Coach | Integrated replay test |
| PQ-10 | This candidate, program import | **P3.** Activating an imported program writes no `DecisionLogEntry`, so the active plan's start has no provenance record. | Log the activation with its source. | Engine | — |
| PQ-11 | This candidate, eligibility | **P3 decision.** Eligibility is per session: one suspect set excludes the whole session. Stale set feedback keeps excluding a corrected set until it is reviewed. | Confirm the policy or move to per-set eligibility. | Data | F04 variants |
| PQ-12 | This candidate, Progress | **P3.** "Volume 7d" uses a rolling 7 days; Today, "Weekly sets" and (after FX-09) the muscle card use the calendar week. "Weekly sets" counts only eligible sets with RPE ≥ 6, so it can differ from Today's set count. | Label each window and filter on its card. | Progress | W1 |
| PQ-13 | This candidate, metrics | **P3.** Dumbbell volume is per hand (not doubled), and no loading convention is stated with the metric. | Put the loading convention in the metric definition. | Data | — |
| PQ-14 | This candidate, Worker | **P2 for QA.** The Worker does not return which provider answered, so answers cannot be attributed to haiku, gemini or llama. | Return a provider ID with the answer (field or debug header). | Backend | W6 |
| PQ-15 | This candidate, Coach packet | **P2 privacy review.** `volume_autoregulation` is computed with today's check-in soreness and sent as an app field, while decisions whose reasoning read soreness are withheld (`DecisionProvenance`). | The privacy owner decides; if soreness is private, apply the same lineage rule to the field. | Privacy | F11-style canary |
| PQ-16 | QA package | **Process.** Case files were not supplied (76 objectives Not run), and no model-evaluation harness with controlled tool returns exists (28 Coach cases Not run at that layer). | Supply the package; build the mocked-tool evaluation. | QA + Coach | — |
| PQ-17 | Device | **W8 Blocked.** No physical device, VoiceOver audio, hit testing, timing or five-person comprehension check. | Run W8 on a device. | QA | W8 |
| PQ-18 | This candidate, Goal roadmap | **P3.** "Next milestone 75% at 97.5 kg" ignores the region's decimal comma, while the milestone list above it shows "97,5 kg". The line is a ForgeCore reason string that never reaches a catalog (the known localization gap in `GOAL.md`). | Format the value through the app's number formatter or return the number, not a sentence. | Goals + i18n | F08 |
| PQ-19 | This candidate, Coach C2/C3 (run 2 of 5) | **P2.** The Coach promised plan changes that a memory note cannot make: "I'll plan around it", "I'll adjust the plan then". The Worker prompt's own example reply for a remembered fact is "Noted — no cable station, I'll plan around it." | Keep "I'll plan around it" for equipment and injury facts. For schedule and goal requests, say the plan is unchanged and name the supported path (Settings → Training) until PQ-02 exists. This is a Worker prompt change and needs a deploy. | Coach | C2/C3 × 5 |
| PQ-20 | This candidate, Coach C1 and F04 | **P3.** "Which week am I in?" names the stage in 5/5 runs but never the week's dates or planned vs done, although the packet carries both. Two scope answers write "2240 kg" for kg·reps (F04 r4, r5). | Prompt rule: a week question gets the stage, the dates, planned vs done and the next session; volumes keep their unit. | Coach | C1, F04 × 5 |

### Fixed in this run and retested on the candidate

| ID | Before | Correction | Retest |
|---|---|---|---|
| FX-01 | Today, the week strip and the Coach packet used a Sunday-first week (en_US `Calendar.current`); Progress used ISO. On Sundays the two "this week" figures covered different days. | One projection, `TrainingMetrics`: ISO Monday-first week, device time zone, half-open. | `TrainingMetricsTests` 10/10; F01 screens agree on Sep 21–27 (§3). |
| FX-02 | Today's planned-set target was 72 while the roadmap showed 64 for the same week (`before-F01-01-today-top.png`). | Today uses the current program week's prescription total. | F01 Today "5/64" = roadmap "64 working sets". |
| FX-03 | The resume button read "1 sets logged" (F10). | Plural through `L10n.pluralSuffix`. | F10 capture. |
| FX-04 | Coach, on Sep 23: "You have a Full B session scheduled for tomorrow, September 23, so get ready to crush that." The date was fabricated; the packet had no current date (`before-coach-F01-q4.png`). | Packet field `today` (weekday, date, time, time zone). | C4 × 5 (§5). |
| FX-05 | The Coach could not tell what follows the next session. | Packet field `rest_of_week` (owed days with dates). | C4 × 5 (§5). |
| FX-06 | Coach, F04: "…it seems there might be a slight discrepancy in the display. The Progress section likely rounds the value, showing 2.2 tons…" An unsupported diagnosis (`before-coach-F04.png`). | The packet gives recorded and eligible volume and a `metric_scopes` line. | F04 × 5 (§5). |
| FX-07 | An unlabeled "best e1RM" tile, an all-time count among weekly tiles, and a weekly-sets average without a denominator. | "Deadlift · best e1RM", "Workouts · all time", "avg 1,2 over 4 recorded weeks"; weeks before the first record are not averaged as zero. ja/ko/vi strings added. | F01 captures (§3). |
| FX-08 | The Coach could not explain why F02 reads Week 1. | Packet field `program_week_rule`. | F02 × 5 (§5). |
| FX-09 | The Progress muscle card, titled "This week · sets per muscle", counted the last 7×24 hours (`Date.now − 7 × 86400`). On a Monday it still counted last week's sessions, unlike every other "This week" figure. | The card reads the `TrainingMetrics` reporting week. | Final build; `F01-17-progress-muscles.png`. On a Wednesday both windows hold the same sessions, so this capture shows the card, not the Monday difference; the week function itself is covered by `TrainingMetricsTests`. |
| FX-10 | Goal roadmap: "Evidence coverage · 3 of 1 verified" (F08). | The shown count is capped at the required count ("1 of 1"); "Counting records · 3 total" keeps the full count. Same localized keys. | Final build; `F08-09-goal-top.png`. |
| FX-11 | Coach, F01, run 2 of 2 before the fix: "What should I do tomorrow?" → "You have a planned session, Full C, scheduled for tomorrow…". Full C is Friday Sep 25; Thursday Sep 24 has nothing planned. The packet listed only owed sessions with dates, so the model did the date arithmetic (`before-coach-F01-r2-q4.png`). | `rest_of_week` lists every remaining day of the week with weekday, date, "(today)", "(tomorrow)" and "rest day, nothing planned" (`CoachAPI.restOfWeek`). | `testRestOfWeekNamesTomorrowAsARestDay`, `testRestOfWeekOnSundayPointsTomorrowToNextWeek`; C4 × 5 (§5). |
| FX-12 | With the device one zone west of the plan zone (app relaunched in Asia/Taipei, plan saved in Asia/Tokyo), the Coach packet moved every plan day back one date: `next_session: Full B on 2026-09-22` and `rest_of_week: Wednesday 2026-09-23 (today): rest day, nothing planned; Thursday 2026-09-24 (tomorrow): Full C; …`. Today's plan card reads plan days with the plan's own calendar (`WeekPlanTodayStatus`; source review, not captured in Asia/Taipei) (`privacy-bodies-before-fx12.json`). | The packet reads plan days with `plan.resolvedCalendar` and matches them to reporting days by calendar date. | `testRestOfWeekKeepsPlanDaysWhenTheDeviceZoneDiffersFromThePlanZone`; the same capture repeated on the final build (§6). |

### Sign-off

QA / date: ___
Engine-data owner / date: ___
Coach-backend-privacy owner / date: ___
UI/accessibility reviewer / date: ___
Release owner / scope decision: ___

Other app release gates remain separate. Explicit scope exclusions of this run: physical device, VoiceOver, dark mode, large text, ja/ko/vi, Watch, widgets, billing, accounts, sync, export, diagnostics, and fault injection inside commits. None of these is counted as passed.
