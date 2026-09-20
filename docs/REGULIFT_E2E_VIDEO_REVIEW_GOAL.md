# Regulift — Full Feature Tour Audit and Implementation Goals

**Date:** 20 September 2026  
**Primary source:** `regulift-full-feature-tour(1).mp4` — the upload supplied with this request.  
**Audience:** iOS developer, engine/data owner, product designer, and QA.  
**Objective:** Improve the existing app's correctness, workout flow, clarity, and release-test coverage. This is not another feature-expansion roadmap.

## 0. Scope, evidence, and limits

The recording is **17 minutes 21.93 seconds**, portrait **1170 × 2532**, at **30 fps**, with **no audio track**. Review covered the complete timeline with 261 regularly spaced frames, 262 additional one-second frames around interactions, and full-resolution checks of important states. The optional evidence bundle contains 31 timestamped frames and a source manifest. This is a visual recording audit, not an executed test suite or a frame-by-frame certification.

References such as **[V 09:51; E16]** identify a timestamp in this recording and a still in the evidence bundle. All product observations below come from this recording. Proposed wording, layouts, contracts, and tests are recommendations, not claims about unseen implementation.

**Important limitations:**

- No app repository, test scripts, assertions, device logs, network traces, database, or production build was supplied. Root causes remain hypotheses until reproduced.
- The recording repeatedly returns to the Home Screen and relaunches. It also contains E2E-named sample data. Whether the test harness resets or seeds data between scenarios is unknown. Do not assume continuity across those boundaries, or call a Home Screen transition a crash.
- A screen opening is not proof that its save, persistence, sync, privacy, or error path works. A successful-looking toast is not proof of the underlying transaction.
- The silent recording cannot establish speech-recognition accuracy, coach-audio quality, haptics, music ducking, or accessibility announcements.
- English/dark appearance dominates this tour. Japanese, Korean, light mode, large text, VoiceOver, Watch, and offline/network-failure behavior need additional tests.
- Earlier proposed “missing features” lists are not a repository inventory. This build visibly includes many of those features. Reuse them; do not rebuild them.

### Evidence classifications

| Label | Meaning |
|---|---|
| **Observed** | A visible state or interaction in the recording. |
| **Presentation defect** | Visible text, layout, or context conflicts. The implementation cause is not established. |
| **UX proposal** | A recommended improvement to a visible experience, not a broken-feature claim. |
| **Validate** | A specific risk requiring a controlled reproduction or state inspection. |
| **Not demonstrated** | The recording does not establish the outcome. This does not mean the feature is absent. |

**P0** means correctness/release-gate work; **P1** means meaningful usability and trust work; **P2** means lower-priority polish. These are proposed product priorities, not measured incident severities.

---

## 1. Product verdict

**The next release should make Regulift more trustworthy and easier to follow, not larger.**

The build already contains onboarding, check-ins, progression-related explanations, Focus Mode, typed logging, set feedback, workout history/editing, a timeline, Fuel, measurements, private photos, goal setup, equipment passports, program import/activation, training experiments, and extensive settings. Several are sophisticated enough that discoverability and consistency now matter more than adding another section.

The strongest next milestone is:

> A user logs a set; every screen agrees about what happened; the correct exercise and equipment remain selected; the app explains the next step without exposing implementation language.

### Fix first

1. **Reported RPE versus target RPE:** the first logging sequence says effort is not entered, but its History view reports average RPE 8 and “RPE on target across 2 sets.” [V 01:19–01:34, 02:40; E03, E05]
2. **Exercise/load context:** after a typed Deadlift log, the plate sheet combines a Lunge label and Bodyweight equipment with a 60 kg target and a 20 kg bar. [V 09:30–09:51; E14–E16]
3. **Metric definitions:** recorded, completed, analysis-eligible, and planned counts are not consistently obvious. Some views show different eligibility counts or describe records more broadly than their headings imply. [V 01:48–02:04, 03:08, 06:28–07:00, 08:20]
4. **Empty-week state:** a week with zero planned sessions is presented as “Nothing left on this plan” and a green “0 of 0 planned sessions done.” [V 13:38–13:41, 17:12–17:21; E25, E31]

Do not start by adding another model, a new social network, exercise videos, Health-workout import, or a replacement training engine.

---

## 2. What to preserve

| Existing behavior visible in this build | Evidence | Preserve while improving |
|---|---|---|
| Compact onboarding with goal, experience, schedule, equipment, units, and optional starting lifts/photo | 00:28–00:46 | Do not replace it with a longer questionnaire. |
| Daily check-in changes the Today presentation | 00:56–01:12 | Keep it quick; clarify scales and data provenance. |
| Large manual weight/repetition controls and automatic rest sheet | 01:19–01:34 | Keep one-handed logging and an obvious primary action. |
| Short sessions can be saved, with an explicit verification notice | 01:35–01:38 | Preserve observations; do not force users to finish prescribed volume. |
| Set-feedback options distinguish interruption, uncertainty, and discomfort | 02:51–03:05 | Keep distinctions; do not reinterpret them as diagnoses. |
| Custom food saves into Breakfast with corresponding visible totals | 03:44–04:02 | Preserve straightforward food entry and missing-value checks. |
| A session with one logged set is resumable after a Home Screen/relaunch sequence | 06:08–06:20 | Preserve resumability; separately test true process termination. |
| Measurement entry appears in the measurement list | 07:39–07:45 | Keep optional measurements separate from required training setup. |
| Focus Mode is present and its main exercise card renders | 09:10–09:13 | Do not create another Focus Mode or repeat an older rendering-bug claim. |
| Typed `deadlift 60x8 @8` logs Deadlift and offers “Go to Deadlift” | 09:29–09:32 | Keep the explicit result receipt and navigation affordance. |
| Coach consent sheet and a visible response refusing to reveal instructions | 10:37–10:39 | Preserve the privacy checkpoint and bounded reply; this proves only this example. |
| Equipment passports distinguish confirmed and review-needed equipment | 11:00–11:08 | Keep identity/comparability distinctions, but shorten the explanation. |
| Program import separates analysis, preview, and activation | 11:48–12:12 | Never merge analysis with silent activation. |
| Experiments explicitly wait for comparable follow-up evidence | 12:44, 13:34 | Keep “not enough data” honesty instead of premature success claims. |
| Timeline filters, history edit, note entry, hide, and restore are exercised | 14:20–16:20 | Improve navigation rather than replacing the timeline. |

---

## 3. Recording coverage: what was actually demonstrated

**These are coverage observations, not test passes.** Automated/device tests in Section 8 remain unrun.

| Area | Recording evidence | Demonstration level | Still needed |
|---|---|---|---|
| Onboarding | 00:28–00:46 | Selections and forward progression visible | Back navigation, interruptions, invalid input, supported combinations, persistence |
| Daily check-in | 00:56–01:12 | Ratings/hours and saved Today state visible | Scale semantics, denied Health permission, missing inputs, data lineage |
| Today | 00:52, 01:12, 04:28, 10:28, 13:40 | Multiple states visible | Calendar/block-week distinction, empty/rest/complete states, source-of-plan consistency |
| Manual logging | 01:19–01:34, 06:08–06:12 | Set counts/tonnage and rest change visibly | Persisted reported effort, retries, rapid double taps, null values |
| Finish partial workout | 01:33–01:38, 06:44–06:48, 10:18–10:20 | Confirmation and summary/next screen visible | Single commit, exact eligibility policy, completion-time immutability |
| Resume workout | 06:16–06:44 | Resumable one-set session visible | Forced kill, device restart, offline restore, duplicate event delivery |
| Focus Mode | 09:10–09:13 | Entry and card visible | Complete workout in Focus Mode, supersets, return position, accessibility |
| Voice capture | 09:16–09:25 | Listening state appears and ends | Actual audio/transcript accuracy, permissions, timeout/error explanation |
| Typed logging | 09:29–09:32 | Exact sample and result receipt visible | Cross-exercise context, kg/lb, decimals, incomplete inputs, duplicate submission |
| Rest timer | 01:22–01:32, 09:32–09:44 | Countdown and Skip visible | Background timing, cancellation, interruptions, stale exercise ownership |
| Plate calculator | 09:50–09:51 | Sheet visible with conflicting exercise/load conventions | Correct exercise, equipment, unit, bar and plate arithmetic |
| Exercise tools | 09:59–10:07 | Why/Swap/add/remove/reorder/superset menu visible | Actual swap, confirmation, reorder, removal and superset execution |
| Workout notes | 09:55–09:57 | Editor opens | Enter/save/reopen, keyboard layout, loss prevention |
| History / set feedback | 02:40–03:08 | Detail and feedback-save interaction visible | Metric refresh, eligibility recomputation, edit/delete/undo contracts |
| History editing | 14:32–14:48 | A changed repetition count appears in the timeline | Persisted totals/e1RM after reopening; cancel and invalid edit paths |
| Progress Overview | 01:48–02:24 and later | Cards, tool rows, charts, heat map visible | Shared scopes, insufficient-data display, populated-history comparisons |
| Awards | 02:26–02:29; 06:56 | Grid/detail and later badge toast visible | Eligibility fixtures, duplicate awards, cross-view consistency |
| Balance | 08:20 | Evidence-gated empty state visible | Correct denominator/counts and populated result validity |
| Measurements | 07:39–07:45 | 82.5 kg entry appears in the list | Relaunch persistence, dashboard refresh, optional-field/null handling |
| Progress photos | 08:04 | Empty state and Add photo visible | Pick/cancel/save/compare/delete/export and permission paths |
| Fuel targets/custom food | 03:40–04:02; 13:56 | Target form, food save, meal display visible | Defaults versus known profile values, negative/decimal/null cases, deletion, barcode/search |
| Crew | 04:08–04:12 | Signed-out screen only | Authentication, actual feed, posts, audiences, upload retry, deletion |
| Settings and custom exercise | 04:20–05:48 | Many controls and custom-exercise form visible | Persist each changed option, fully save/reuse a custom exercise, unit conversions |
| Gym profiles/travel/crowd | 11:00 | Existing controls visible | Apply a constraint, inspect exact plan diff, restore and revalidate |
| Equipment passport | 11:04–11:08 | Explanation and item statuses visible | Confirm/rename/change convention, isolation of records and offline persistence |
| Goal setup | 11:40–11:45 | Benchmark/adherence forms shown | Saved goal result, eligibility, updates, edit/cancel |
| Program import | 11:48–12:12 | JSON entry, preview, active status visible | Malformed input, unsupported version, idempotency, active-plan propagation |
| Program sharing | 12:16–12:24 | Redacted-copy review entry point shown | Final preview/export, redaction assertions, cancellation and destination behavior |
| Week designer | 11:32, 13:40–13:44 | Entry points visible; empty-week result later visible | Actual day editing/recovery/constraint resolution; no complete designer interaction shown |
| Training experiments | 12:44, 13:34 | Active collecting-results state visible | Explicit start approval, qualifying follow-up, cancellation and final evaluation |
| Plan audit / recommendation effectiveness | Progress tool rows | Entry points only | Open detail and validate linked records/outcomes |
| Timeline | 14:20–16:36 | Filters, note, edited workout, hide/restore visible | Same-data consistency, long-history performance, event grouping, account isolation |
| Coach | 03:18–03:21, 10:37–10:39, 16:46–16:49 | Prompt entry; one consent/refusal exchange visibly completes | Normal grounded answer, ambiguity resolution, action preview/approval, errors/retries |
| Workout sharing | 01:36, 10:20 | Share workout button present | Card editor, generated pixels, share sheet, cancellation, actual Crew post |
| Subscription | 05:44–05:48, 12:28 | “Not subscribed” / test-purchase entry visible | Actual purchase, cancellation, restore, entitlement refresh, production-build configuration |
| Import Strong/Hevy, CSV, PDF | Settings/Progress entry points | Not completed in this recording | Actual files, mapping, malformed data, export validation and privacy |
| Watch, widgets, Live Activity outside app, Siri | Not shown as working surfaces | Not demonstrated | Separate device/system integration runs |
| Offline/sync/privacy/network behavior | Some UI copy describes it | Not established by pixels | Network capture, process tests, permission matrices and multi-device assertions |

---

## 4. Timestamped findings register

| ID | Priority / type | Evidence | Finding and requested outcome |
|---|---|---|---|
| F01 | P0 · presentation defect / validate storage | 01:19–01:34 → 02:40; E03/E05 | “Reported effort: Not entered — plan target 8” becomes Avg RPE 8 and “RPE on target.” Separate prescribed, reported, missing, and inferred effort throughout the app. |
| F02 | P0 · presentation defect | 09:30–09:51; E14–E16 | Lunge is shown at 0 kg, then its plate sheet shows 60 kg / Bodyweight / bar 20 after a Deadlift log. Never mix identities or loading conventions. |
| F03 | P1 · UX proposal / policy validation | 09:30–09:32, 10:12–10:20 | Logging one previously unlisted Deadlift expands the planned denominator from 24 to 27. Explicitly separate an extra logged set from adding a three-set prescription. |
| F04 | P0 · metric semantics / validate | 01:48–02:04, 03:08, 06:28–07:00, 08:20; E12 | Overview, History, PR-board subtitles, trend cards and Balance use unclear/differing inclusion scopes. Balance shows 2 eligible sessions / 1 eligible set while nearby Overview/History report 1 eligible workout. Reproduce with one controlled fixture before deciding which query is wrong. |
| F05 | P1 · presentation consistency / validate | 01:36 versus 02:40; 10:20 versus 14:32 | Duration presents as 0 or 1 minute across views of short sessions. Define one stopped duration and one presentation policy; fixture/relaunch effects are not ruled out. |
| F06 | P0 · presentation defect | 13:38–13:41, 17:12–17:21; E25/E31 | An empty week is treated visually as completed: “Nothing left” and a green 0-of-0 result. Empty, rest day, incomplete, complete, and unavailable need separate states. |
| F07 | P0 · validate source of truth | 12:12 → 13:24/13:42; E22/E25 | Import says a one-day version is active, while later roadmap/Today surfaces show a six-week block or empty week. Relaunches may reseed data; test propagation within one uninterrupted fixture. |
| F08 | P1 · UX proposal | 04:28, 10:28; E09 | “Your next week — A change to your plan was committed” exposes a storage event, not user value. Show the real change/reason/affected session, or acknowledge that details are unavailable. |
| F09 | P1 · UX proposal | 00:52–01:12, 10:28 | Today repeats readiness in a large ring and number; block week advances while calendar date stays fixed. Distinguish readiness, calendar adherence, and position in the training block. |
| F10 | P1 · UX proposal | 00:56–01:08; E02 | Check-in scales use unanchored 1–5 values; soreness direction is not self-evident. Add verbal endpoints and preserve missing versus default answers. |
| F11 | P1 · UX proposal | 00:28–00:46; E01 | “Your week” also asks experience; starting lifts are estimated from body weight when omitted. Clearly label estimates and calibration; avoid treating them as observed strength. |
| F12 | P1 · UX proposal | 01:35–01:38, 10:20; E04 | A large athlete photo leads the user's workout result, while next-step information is less visible. Lead with the user's saved result and verified next step; use neutral partial-workout copy. |
| F13 | P1 · presentation defect | 03:08; E06 | The recorded swipe-delete state places the trash affordance over the date/set text. Separate action and content bounds; make swipe/restore readable at every state. |
| F14 | P1 · UX proposal | 01:48–02:24, 07:28–08:20 | Progress mixes a large tool directory, empty charts, analytics and profile chrome. Surface useful current information first and progressively reveal advanced analysis. |
| F15 | P1 · UX proposal | 03:16–03:21, 16:44–16:49 | Coach repeats suggestions as large cards and small chips beneath a large portrait. Reduce duplication; foreground the user's context and input. |
| F16 | P0 · test-coverage gap | 03:18–03:21, 10:37–10:39, 16:46–16:49; E18 | One instruction-refusal reply is visible; ordinary grounding/ambiguity/action handling is not established. Do not treat those typed prompts as successful Coach tests. |
| F17 | P1 · UX proposal / validate | 09:16–09:25 | Listening remains visible without a transcript and then ends. Audio is absent; this does not prove recognition failed. Provide explicit listening/no-speech/error/cancel states and test with known audio. |
| F18 | P1 · UX proposal | 04:44–05:44, 11:12–11:28; E10 | Voice-related controls span Coach, Voice, and Language; app language, dictation source, command processing, narration, and offline model status are easy to confuse. Consolidate by user task. |
| F19 | P1 · UX proposal | 03:44–04:00; E07 | New-food form immediately shows an error banner while the Save action looks active. Use neutral guidance initially, field-specific validation after interaction, and unambiguous save readiness. |
| F20 | P1 · UX proposal / validate provenance | 03:40, 04:02, 13:56; E08 | Fuel shows target-form defaults and a prominent calories-left number. Distinguish confirmed profile values from defaults, and show eaten/remaining/target explicitly. No nutrition-policy change is proposed. |
| F21 | P1 · validate freshness | 07:45 → 08:00; E11 | A saved 82.5 kg entry is visible, but later Body stats still says no measurements. There is a relaunch between them; assert refresh and persistence without assuming data loss. |
| F22 | P2 · UX proposal | 09:55–09:57; E17 | Workout notes opens as an unlabeled empty writing area. Add a useful placeholder, scope, and clear save behavior; keyboard usability is not demonstrated. |
| F23 | P1 · UX proposal | 11:04–11:08; E19 | Equipment passport opens with a long comparison-rules explanation before the actionable equipment. Put items and “needs review” tasks first; explain comparison rules on demand. |
| F24 | P1 · UX proposal / validate | 11:48–12:24; E21–E23 | Import leads with raw JSON; a source timestamp of zero is in the fixture and the active-version row shows 1 Jan 2001. Label source-created versus imported/activated time. Do not falsely diagnose this as a parser bug. |
| F25 | P1 · UX proposal | 11:40–11:45; E20 | Goal setup opens into technical benchmark fields before the desired outcome is clear. Use a short type-first flow and retain the existing evidence rules. |
| F26 | P2 · UX proposal | 12:44, 13:34; E24 | Experiment appropriately says collecting results, but its next required action is not prominent. Show what counts next and expose existing management controls contextually. |
| F27 | P1 · UX proposal | 14:20–15:40; E26/E28 | Timeline is dominated by repeated “Load changed” entries, including “Start …” prescriptions. Group related changes and distinguish initial prescription from an actual before/after change. |
| F28 | P1 · UX proposal | 15:47–15:55; E29/E30 | Hide menu lists many indistinguishable “Hide Load changed” options. Hide from the selected card, not a global anonymous list. Restore itself visibly works. |
| F29 | P2 · UX proposal | 15:16, 15:40 | “Not in this timeline” is a large list of unavailable features. Move the limitations/privacy explanation to concise help and keep records primary. |
| F30 | P1 · release/coverage gate | 04:08–04:12; 05:44–05:48 | Crew is only shown signed out; Subscription includes “Test purchase flow.” Verify authenticated paths and exclude development controls from the release build. Presence in this test build is not proof of a production leak. |
| F31 | P1 · visual/accessibility validation | Throughout; notably 02:40, 05:00, 14:24 | Important provenance/help labels are small and subdued; persistent headers/tab bars compete with content. Validate real text sizes, contrast, keyboard layout and accessibility rather than declaring compliance from a scaled video. |

---

## 5. Implementation goals — ordered coder handoff

Names below describe responsibilities, not discovered filenames or classes. Map them to existing modules before adding anything. Every goal requires a before/after recording and a regression test. Do not make production training-rule changes merely to make the demo look better.

### G00 — Establish a reproducible audit fixture

**Priority:** P0 · **Owner:** QA + iOS · **Dependency:** none.

- [ ] Record build/commit, device/OS, launch arguments, locale, unit preferences, account state, feature flags, injected time, and whether each scenario resets data.
- [ ] Map each finding to the actual screen/controller, data selector, persistence model, and existing test.
- [ ] Add a fixed sample: Full A with two rapid 64 kg × 8 sets with no reported RPE; a one-set completed Deadlift session; Full C with Lunge active; a separate controlled import fixture.
- [ ] Add named test boundaries to the recording or test log so a Home Screen reset cannot be mistaken for a crash or unexpected persistence failure.
- [ ] Save actual assertion output with the run. Do not use fixed sleeps and screenshots as the only success signal.

**Acceptance:** Replaying a scenario on the same fixture yields the same initial records and expected counts. Data resets are explicit. Findings crossing a reset are classified as regression questions until independently reproduced.

### G01 — Make effort provenance correct everywhere

**Priority:** P0 · **Owner:** training-data/iOS · **Findings:** F01 · **Dependency:** G00.

**Reproduction:** Leave RPE untouched while logging the first two squat sets; finish; open History. Compare the logger's “Not entered” indication with average effort and the debrief. [V 01:19–02:40]

- [ ] Keep `targetRPE` separate from nullable `reportedRPE`. Track provenance when legacy data cannot distinguish them.
- [ ] Audit manual, typed, voice, import, Watch, edit, history, summary, Coach and export paths. None may silently turn a target into a user report.
- [ ] Compute average RPE from actual reports only and show coverage, for example “RPE recorded for 1 of 3 sets.”
- [ ] With zero reports, show “Effort not recorded”; do not claim “RPE on target.”
- [ ] Preserve explicit typed `@8` as a genuine report. Preserve existing program behavior for missing effort through its documented policy, not a fabricated observation.
- [ ] Review existing records before migration. Unknown provenance must remain unknown; do not guess historical RPE.

**Acceptance:** Two logs without explicit RPE produce no reported-RPE average or target-attainment claim. One actual report of 8 plus one missing report displays one report, not two. Local storage, summary, history and sharing agree. Any intentional one-tap default acceptance must be explicit in the UI and recorded as such.

### G02 — Bind every workout utility to an explicit exercise context

**Priority:** P0 · **Owner:** logger/engine integration · **Findings:** F02, F03 · **Dependency:** G00.

**Reproduction:** Open Full C with Lunge at 0 kg. Submit `deadlift 60x8 @8`. Do not tap “Go to Deadlift.” Open Plate calculator. [V 09:29–09:51]

- [ ] Separate the currently viewed exercise, last logged exercise, typed-command destination, and rest-timer owner.
- [ ] Construct utility context from one explicit identity: session, exercise occurrence, set/prescription, equipment, load convention, unit, and revision.
- [ ] Never combine the visible exercise name with a global last-entered load.
- [ ] For Bodyweight, show “Bodyweight” or “Added load: 0 kg” as appropriate. Do not display a barbell plate prescription without an explicitly applicable barbell context.
- [ ] Keep the useful log receipt, with the destination exercise, a Go to action, and the existing Undo path. Do not move the user unexpectedly while editing another field.
- [ ] Make rest-sheet ownership explicit, such as “Rest after Deadlift”; keep next-set text consistent with it.
- [ ] Define what logging an unplanned exercise means. Recommended default: log the extra set; adding a multi-set prescription is a separate, explicit action. Reuse any existing intentional policy, but explain the change to planned totals.

**Acceptance:** The reproduced Lunge/60 kg/bar-20 hybrid is impossible. Two rapid commands for different exercises cannot cross-contaminate tools or rest state. Retried commands do not add duplicate sets or repeatedly expand planned totals. kg/lb and per-dumbbell/barbell conventions remain correct.

### G03 — Centralize metric scopes and eligibility explanations

**Priority:** P0 · **Owner:** data/analytics/engine · **Findings:** F04, F05, F21 · **Dependency:** G00/G01.

- [ ] Document separate concepts: all recorded sessions, ended sessions, partial sessions, analysis-eligible sets, eligible sessions, planned sessions, and completed planned commitments.
- [ ] Give every displayed metric a scope, time window, unit, source revision, and eligibility rule. Reuse existing rules rather than changing thresholds.
- [ ] Ensure labels such as “eligible” use the same actual selector when they claim the same scope.
- [ ] Where scopes intentionally differ, explain locally: “2 recorded workouts · 1 included in strength trends.” Do not hide saved observations.
- [ ] Fix PR-board subtitle counts independently from raw exercise-history counts; a raw e1RM calculation is not automatically an eligible PR.
- [ ] Stop duration once, persist it, and format consistently. For a short workout prefer “Under 1 min” or mm:ss rather than contradictory rounded values.
- [ ] Recompute/invalidate affected projections after set edits, feedback changes, finish, measurement save, import activation, and deletion.
- [ ] Preserve historical decisions; label newly recomputed information rather than rewriting past rationale as if it always existed.

**Acceptance:** One fixture yields consistent Overview, History, Balance, awards, timeline and export values under their declared scopes. A saved measurement is visible without a forced app restart. Editing 60 kg × 8 to × 9 yields 540 kg for that set after commit wherever that same set is counted; cancel preserves 480 kg. No missing metric becomes zero just to fill a card.

### G04 — Model Today and weekly-plan states explicitly

**Priority:** P0 · **Owner:** scheduling/Today · **Findings:** F06, F07, F09 · **Dependency:** G00/G03.

Proposed mutually exclusive headline states:

| State | Proposed presentation | Primary action |
|---|---|---|
| No week configured | “Your week is not planned yet.” | Plan this week |
| Rest day with future sessions | “Rest day · next workout [day].” | View week |
| Workout ready | Name, estimated time, meaningful current changes | Start workout |
| Workout in progress | Name and actual logged-set count | Resume workout |
| Work remains but a session was missed | Plain explanation and validated options | Review schedule |
| Planned commitments complete | “This week's planned sessions are complete.” | Review next week |
| Plan unavailable / unsupported | Specific recoverable explanation | Retry / choose plan |

- [ ] Do not mark an empty 0-of-0 plan complete. Hide the completion meter or present an explicitly empty state.
- [ ] Make “Open the week designer” lead directly to the relevant editor, not an unexplained intermediate directory.
- [ ] Label block position separately from calendar-week adherence.
- [ ] Expose the authoritative plan source: generated block, imported version, and any explicit weekly override. Show precedence in one place.
- [ ] Test activation without resetting data: the active source must agree across Today, roadmap, logger and Coach projections. Do not assume the cross-relaunch video proves a persistence defect.

**Acceptance:** Empty, rest, completed and unavailable fixtures render distinct states. A future workout is not inadvertently presented as an obligation to train again immediately. Import activation changes only the intended active plan and leaves logged facts intact.

### G05 — Replace generic “plan committed” copy with useful explanations

**Priority:** P1 · **Owner:** Today/decision presenter · **Findings:** F08, F15 · **Dependency:** G01/G03/G04.

- [ ] Render the actual change, affected exercise/session, scope and available reason from the existing decision record.
- [ ] Example structure: “Next bench session: [old] → [new]” plus one factual reason. These values must be read, not generated for appearance.
- [ ] If the reason is unavailable or private to the local device, show an honest local fallback; do not invent evidence or send private context to a cloud model.
- [ ] Separate applied changes from drafts awaiting approval. “Updated” requires the existing commit receipt.
- [ ] Suppress empty/generic cards when no useful change exists.
- [ ] Label initial prescriptions as “Starting target,” not an unexplained “change.” Link Coach suggestions to the actual relevant decision rather than an arbitrary recently initialized exercise.

**Acceptance:** No user-facing “A change to your plan was committed” fallback remains. A no-change session is valid. Every displayed reason can be traced to its actual source without adding a new model.

### G06 — Improve the first-run and daily check-in contract

**Priority:** P1 · **Owner:** onboarding/Today · **Findings:** F09–F11.

- [ ] Rename/group experience and schedule questions accurately; keep optional fields optional.
- [ ] Label guessed starter loads as estimates that will be calibrated from actual training. Do not represent body-weight-derived values as training history.
- [ ] Add a short starting-plan recap or reuse an existing recap: days, equipment, time, and what will change after logging. Do not add a long tutorial.
- [ ] Anchor each check-in scale verbally. Soreness should communicate “none” through “very sore”; sleep/energy/motivation should communicate their own direction.
- [ ] Keep default UI selection separate from an explicitly recorded answer. Show whether readiness used a check-in, Health input, or incomplete coverage locally.
- [ ] Replace the absolute-sounding “All clear” with wording tied to available information, such as “Based on today's check-in, your planned session is ready.” Do not imply medical clearance.
- [ ] Explain notification permission in the workout/rest context and preserve logging when declined.

**Acceptance:** A new user understands each scale and knows when loads are estimates. Denying permissions does not block manual training. No silent default becomes a measured/reported fact.

### G07 — Make finish/resume feel dependable and personal

**Priority:** P1 · **Owner:** logger/summary · **Findings:** F05, F12 · **Dependency:** G01/G03.

- [ ] Lead the result with “Workout saved,” actual work, and the existing next-session outcome rather than a large unrelated athlete photo.
- [ ] Use neutral partial-session copy: “2 of 22 planned sets saved.” Preserve the user's ability to stop without guilt or volume coercion.
- [ ] Explain why a set/session is excluded from a specific metric without implying the saved workout disappeared.
- [ ] Keep Save/adaptation independent of sharing. Closing the summary or cancelling export must not undo the workout or apply an unapproved change.
- [ ] Keep Start/Resume grammatically correct for one set versus multiple sets.
- [ ] Preserve pending update state when logging succeeds but adaptation fails; do not report completion of a failed update.

**Acceptance:** Finish, reopen, resume and repeated Finish delivery preserve exactly one set of observations and one applicable update. No image export is required to finish the core loop.

### G08 — Simplify Progress without deleting its advanced tools

**Priority:** P1 · **Owner:** Progress/design · **Findings:** F04, F14, F21, F31 · **Dependency:** G03.

Recommended hierarchy:

1. A compact current summary with the metric scope explained once.
2. One or two useful trends supported by the available data.
3. History and Timeline as primary record-navigation routes.
4. Grouped advanced tools: training analysis, body/nutrition, and reports.

- [ ] Collapse empty multi-week graphs into compact “not enough data” states with a next action.
- [ ] Keep Balance/experiment coverage requirements, but state the user's progress toward them clearly.
- [ ] Reduce the persistent profile/title header while scrolling so records retain screen space.
- [ ] Provide a concise explanation for eligible versus all-recorded metrics; avoid making “Analysis eligible” the user's primary mental model.
- [ ] Preserve a user's scroll position when returning from a tool.

**Acceptance:** Fresh and established accounts both have useful first screens. Advanced features remain reachable without an uninterrupted directory of equally weighted cards.

### G09 — Make Timeline a readable history, not a change-event dump

**Priority:** P1 · **Owner:** Timeline · **Findings:** F27–F29 · **Dependency:** G03/G05.

- [ ] Group related program changes from the same committed event under a single expandable entry, e.g. “Starting targets set for Full A.”
- [ ] Show before/after only for genuine changes. Initial values are not improvements.
- [ ] Retain links to individual immutable records inside the group.
- [ ] Move Hide to the selected card's menu/swipe action. Include exercise/title/date where a picker is still necessary.
- [ ] Treat Hide as non-destructive. Provide immediate Undo and preserve the existing Hidden items/Restore flow.
- [ ] Replace the large “Not in this timeline” card with short contextual help, without obscuring actual privacy limitations.
- [ ] Keep local notes private and distinguish user-authored notes from automated decision records.

**Acceptance:** A first workout does not require scrolling through a screenful of near-identical starting-load entries to find a note. Hide/Restore affects only visibility, not History, training calculations, or source records.

### G10 — Correct compact rows, menus, and note editors

**Priority:** P1 · **Owner:** shared UI/history · **Findings:** F13, F22, F31.

- [ ] Give swipe actions a distinct layout region; clip/translocate content so trash never overlaps date or set count.
- [ ] Keep remove/delete visually distinct from routine logging/edit controls and retain the appropriate confirmation/undo policy.
- [ ] Give workout notes a meaningful placeholder and clearly identify workout-wide versus exercise/set notes.
- [ ] Show whether Done saves, or use explicit Save/Cancel where needed. Guard against losing edited text on dismissal.
- [ ] Ensure the last actionable row is scrollable fully above the floating tab bar and keyboard.
- [ ] Test names, dates, large numbers and translated labels without relying on truncating critical values.

**Acceptance:** Swipe, cancel, restore, keyboard entry, large text, and long exercise names remain readable and operable. The recording's intermediate award-sheet animation is not treated as a persistent rendering bug.

### G11 — Consolidate Settings around tasks and active processing paths

**Priority:** P1 · **Owner:** settings/voice/privacy · **Findings:** F18, F30, F31.

Suggested groups: **Training & equipment**, **Coach & privacy**, **Voice & audio**, **Appearance & language**, **Account & data**. Reuse existing controls and destinations.

- [ ] Separate app language, speech-recognition language, dictation provider, unusual-phrase interpretation, spoken guidance, and offline-model download.
- [ ] Show the currently effective voice path, not just multiple toggles that users must mentally combine.
- [ ] Clarify that a cloud-selected path and “on-device when possible” are different policies; consent must match the actual request path.
- [ ] Make offline-model availability explicit: not downloaded/downloading/ready/unavailable/error, with cancellation and storage information from actual state.
- [ ] Keep training setup and equipment passport accessible from relevant workout context, not only deep inside Settings.
- [ ] Gate “Test purchase flow” and other developer controls out of production configuration.

**Acceptance:** A user can determine where typed requests, audio, and training context are processed without reading several disconnected sections. Turning a permission off affects the next request and does not break local manual use.

### G12 — Prove Coach's normal workflow before extending it

**Priority:** P0 validation; P1 UI · **Owner:** Coach/integration/QA · **Findings:** F15–F18.

- [ ] Preserve the visible consent flow and instruction-refusal behavior. Do not claim this one example validates the complete guardrail system.
- [ ] Add complete recorded runs for “Why did my weight drop?” with genuinely ambiguous context, an ordinary workout explanation, and a supported action preview.
- [ ] Show sending, pending, reply, failed and retry states. Preserve the user's draft when a request cannot be sent.
- [ ] Collapse the large coach portrait after initial orientation; remove duplicated suggestion cards/chips. Keep a compact “Ask Nova” identity and contextual suggestions.
- [ ] Present source/freshness information where it matters. Missing data and withheld private data must not become confident explanations.
- [ ] Retain engine-owned validation and proposal-bound user approval. Never claim a change applied without a successful receipt.
- [ ] For voice, distinguish no speech, cancellation, service unavailable, and an unsupported command. Do not silently replace a failed voice operation with a logged set.
- [ ] Keep Jev integration behind its separate evaluated rollout; it is not a repair for data-contract or UI-state bugs.

**Acceptance:** End-to-end normal answer, ambiguity, unavailable-data, timeout, retry and action-confirmation scenarios are captured with assertions. No private Health-derived values are uploaded to make a response sound more informed.

### G13 — Polish Fuel without changing nutrition logic

**Priority:** P1 · **Owner:** Fuel · **Findings:** F19/F20.

- [ ] Initially show neutral field guidance. After interaction or attempted Save, show a specific invalid/missing field rather than a persistent generic red banner.
- [ ] Distinguish blank/unknown from zero. Accept valid zero values where the field permits them; reject negative, nonnumeric, nonfinite and invalid serving values.
- [ ] Make Save readiness visually consistent with actual validation.
- [ ] Present consumed, remaining and target calories unambiguously. For the recorded sample, 380 consumed and 2,372 remaining reconcile to the 2,752 target.
- [ ] Keep missing intake distinct from zero intake; retain the visible completeness indicator.
- [ ] Require confirmation of target-input defaults that are not known profile facts; do not silently turn sample age/height/sex selections into user measurements.
- [ ] Verify decimal handling under the device's region even when app language is English.

**Acceptance:** The sample 100 g food saves once with its entered nutrition and meal totals. Invalid input identifies the field. No changes to calorie formulas or health recommendations are part of this ticket.

### G14 — Make the equipment passport task-first

**Priority:** P1 · **Owner:** equipment/constraints · **Findings:** F23 · **Dependency:** G02.

- [ ] Open with active gym, equipment list, and the actual review-needed count.
- [ ] Change broad “Verified” wording to a precise user-facing label such as “Setup confirmed” where that is what it means; do not imply an externally verified machine or medical safety.
- [ ] On review, ask only for relevant identity/loading-convention information.
- [ ] Move the long comparison explanation behind “Why equipment setup matters.” Keep a short warning before a change that separates historical records.
- [ ] Provide direct access from the selected workout exercise and the plate calculator's explicit equipment context.

**Acceptance:** Confirming a convention does not merge incompatible histories, renaming does not create a fake new machine, and changing equipment identity preserves the intended record separation. Existing policy decides comparability.

### G15 — Finish program import/activation/sharing as a coherent workflow

**Priority:** P0 active-source validation; P1 presentation · **Owner:** program/data · **Findings:** F07/F24 · **Dependency:** G04.

- [ ] Make Choose file / Open shared plan the primary user path; move raw JSON paste under an advanced option and provide the actual supported format documentation in-app.
- [ ] Keep analyze-only preview, save-without-activation and activate as distinct operations.
- [ ] After activation, replace the active version's Activate button with clear current status or make repeat activation explicitly idempotent.
- [ ] Label “Source created,” “Imported,” and “Activated” dates separately when shown. The video fixture contains a zero source date; preserve provenance rather than inventing a recent creation date.
- [ ] Validate missing/invalid dates according to the actual format contract. Do not hide real historical dates merely because they are old.
- [ ] Scope status messages to the action that produced them; an old activation-success message must not masquerade as a share-preview result.
- [ ] The redacted copy must be reviewed before export; reuse existing sharing and verify the allowed fields rather than copying all stored program objects.

**Acceptance:** Malformed import cannot mutate the plan. Re-activation is safe. All current-plan consumers agree within one uninterrupted fixture. A share review opens an actual preview and sends nothing until an explicit export action.

### G16 — Make goal/experiment next steps understandable

**Priority:** P1 goals; P2 experiments · **Owner:** goals/experiments · **Findings:** F25/F26.

- [ ] Ask the goal type first: a performance target, practice/skill, or consistency. Then reveal only relevant fields.
- [ ] Explain the counted event in ordinary language. Preserve the current distinction between observed sessions and a forecasted achievement percentage.
- [ ] Show a saved-goal confirmation and a clear next qualifying action.
- [ ] On an active experiment, show the intervention, evidence window, next comparable exposure and management action. Reuse existing controls rather than inventing a second experiment system.
- [ ] Preserve insufficient-evidence states and distinguish observations from any interpretation. No claims that one short demonstration proves an intervention worked.

**Acceptance:** A saved consistency goal can be reopened, edited, and incremented only by its defined eligible events. An experiment with zero comparable follow-ups never presents a successful outcome.

### G17 — Close release coverage for sharing, Crew and subscriptions

**Priority:** P1 implementation gaps; P0 release verification · **Owner:** sharing/backend/payments/QA · **Findings:** F30 and coverage table.

- [ ] Execute the existing workout-share path end to end; do not call sharing absent because the tour only shows its button.
- [ ] Reuse the separate Share Cards v2 goal only for gaps still missing. Keep cards on-device, explicit field selection, and current committed next targets clearly labeled as planned.
- [ ] Verify card preview, cancellation, exported pixels, file cleanup, metadata/privacy filtering, no-account system sharing, and explicit signed-in Crew posting.
- [ ] Test real Crew audiences, authentication and duplicate-post protection. Do not label Crew private without enforced access rules.
- [ ] Give the signed-out Crew page a short explanation of what becomes visible and a clear route back to training, not a fabricated populated feed.
- [ ] Run subscription purchase/cancel/restore/entitlement states in the designated test environment; prove production configuration contains no test-purchase controls.

**Acceptance:** No unfinished action is reported as successful. Cancelling share/purchase/sign-in leaves the saved workout intact. No Health/recovery fields or private notes are unintentionally included in a social artifact.

### G18 — Run a real device, accessibility and resilience matrix

**Priority:** P0 release validation / P1 polish · **Owner:** QA + feature owners · **Findings:** F31 and coverage table.

- [ ] Run on supported smallest/largest phone layouts, normal/large/accessibility text, English/Japanese/Korean, light/dark/system appearance, kg/lb and differing regional number formats.
- [ ] Check VoiceOver labels/order for metrics, controls, timer, menu actions, segmented scales, destructive actions and toasts. Verify focus moves to the actual result/error.
- [ ] Exercise the native software keyboard, not only automation text injection; verify input, Save/Cancel, tabs and bottom sheets never hide one another.
- [ ] Test Reduce Motion, contrast, long names, unavailable images, loading states, scroll restoration and empty/populated history.
- [ ] Test airplane mode, timeouts, process kill, device restart, repeated delivery, offline edits and reconnection using existing sync contracts.
- [ ] Test Watch, widgets, Live Activity, Siri and notifications on the actual supported system surfaces; they are not validated by the in-app timer.
- [ ] Inspect permitted network exports and telemetry. UI privacy copy alone is not evidence of privacy enforcement.

**Acceptance:** Section 8's required scenarios have recorded results, screenshots/logs, owners and issue links. No unsupported “all features passed” statement is used for launch approval.

---

## 6. Shared implementation boundaries

### A. Proposed context and metric contracts

Use existing types where available. These are responsibilities, not drop-in code:

```text
WorkoutInteractionContext
  session identity + exercise occurrence identity
  intended set / prescription identity
  equipment identity + loading convention
  mass unit + current load source
  current plan/log revision

EffortObservation
  target effort
  reported effort OR missing
  report provenance + observed time
  eligibility flags from existing policy

ScopedMetric
  value OR unavailable
  unit + time window
  all-recorded / eligible / planned scope
  observation coverage + source revision

WeekPresentationState
  unconfigured / rest day / ready / in progress
  missed work / completed / unavailable
  authoritative plan source + local calendar period
```

Do not turn every object into a cloud payload. Rich local records, Health lineage and private notes remain subject to the existing export policy. Read-only presentation, training evaluation, action preview and commit must stay separate.

### B. Atomicity and stale state

A logged observation must remain saved if a later explanation, network call or render fails. Use stable operation IDs and the existing commit boundary. New view refreshes must not rerun mutating progression. A changed plan or context invalidates stale action previews; a Share button never acts as approval.

### C. Proposed presentation rules

- One clearly dominant action per task: Start, Resume, Log set, Review change, or Save.
- Prioritize exercise, prescription, observed result and next step over portraits and decorative metrics.
- Keep existing brand colors, but do not use color as the only indication of eligibility, selected scale value, or warning.
- Display load conventions and units next to the values they qualify. Bodyweight is not missing data; missing external load is not automatically zero.
- Keep technical terms available in details, not as unavoidable headings such as “committed,” “format 1,” or repeated unexplained “eligible.”
- Use truthful empty and intermediate states. Do not replace missing data with success styling, placeholder zeroes, or confident coaching.

---

## 7. Release sequence and dependency order

| Release slice | Goals | Exit condition |
|---|---|---|
| **A — Correctness baseline** | G00–G04, normal-Coach tests from G12 | RPE, context, metric scopes and week states proven on controlled fixtures; no data-loss/duplicate-commit regression. |
| **B — Core workout clarity** | G05–G10 | Today → workout → save → next step → History/Timeline is coherent with current data. |
| **C — Advanced-tool usability** | G11, G13–G16 | Settings, Fuel, equipment, goals and import are understandable without adding parallel systems. |
| **D — Release evidence** | G12, G17, G18 | Normal Coach, sharing, signed-in flows, payment, device integrations and failure cases have actual test results. |

Use the app's existing rollout mechanism. Suggested presentation flags are optional and should map to existing equivalents: `effort_provenance_ui`, `workout_context_v2`, `week_states_v2`, `progress_hierarchy_v2`, `timeline_grouping_v1`, `settings_groups_v2`.

A rollback may restore a previous presentation or route, but must not erase saved observations or reintroduce fabricated effort. Never run two mutating engines in parallel for a visual comparison.

### Explicitly outside this release

New exercise videos; shader/motion-card engines; a new social graph; Health workout ingestion; autonomous AI programming; a replacement voice recognizer; another Focus Mode; another equipment-profile system; new calorie formulas; and a new app-wide design language.

Jev and Share Cards v2 already have separate plans. Their existence in a plan is not implementation evidence. Reconcile those documents with the repository rather than adding duplicate tickets.

---

## 8. End-to-end and regression test specification

**Execution status: NOT RUN by this reviewer.** The following cases are the coder/QA handoff. The recording coverage above is separate from test execution.

Record for every case: fixture/reset policy, build, device/OS, locale/units, account/permission state, steps, expected/actual outcome, source record IDs, screenshots, relevant logs, and result. Run business-logic assertions below the UI as well as UI flows; pixels alone cannot establish persistence/privacy.

### Core workout and data integrity

| Test | Scenario | Required assertion |
|---|---|---|
| T01 | Complete onboarding with optional lifts/photo skipped | Valid starting plan; estimates explicitly identified; no invented lift history. |
| T02 | Back/forward and relaunch during onboarding | Entered choices persist as designed; no duplicate account/plan creation. |
| T03 | Deny notification/Health access, then start manually | Manual workout remains usable; missing inputs are not shown as measured. |
| T04 | Save a check-in with each scale at its endpoints | Labels and stored direction agree; missing versus selected defaults remain distinct. |
| T05 | Log two sets without touching RPE | No reported RPE is synthesized; average/debrief show missing coverage. |
| T06 | Log one actual RPE 8 and one missing RPE | Exactly one report contributes to the average; coverage is 1 of 2. |
| T07 | Type `deadlift 60x8 @8` with Lunge visible | Only intended Deadlift receives the observation; receipt names it. |
| T08 | Open Plates after T07 without navigating | No Lunge/Deadlift hybrid; equipment and load convention match one explicit context. |
| T09 | Navigate to Deadlift after T07, open Plates | All values use that exercise and the selected bar/plate inventory. |
| T10 | Log a bodyweight exercise at zero added load | Bodyweight label; no invented barbell prescription or missing-value substitution. |
| T11 | Log an exercise not currently prescribed | Extra-set versus added-prescription policy explicit; denominator changes explained. |
| T12 | Retry/double-tap an identical log operation | One intended observation and one receipt, not duplicate sets. |
| T13 | kg/lb, decimal separator, per-dumbbell and machine cases | One correct unit/convention conversion; no reinterpretation of stored load. |
| T14 | Finish a short/partial session | Observations saved once; neutral partial status; intended eligibility rule applied. |
| T15 | Reject/qualify implausibly rapid fixture sets | PRs/awards/analysis/Crew follow declared policies; History still preserves records. |
| T16 | Background, force-kill and reopen an active workout | Exact logged sets restored; timer policy preserved; no duplicate future progression. |
| T17 | Complete session while adaptation/network step fails | “Saved; update pending” or equivalent; workout never lost. |
| T18 | End duration, revisit/relaunch all relevant views | Same stopped duration and consistent display policy everywhere. |
| T19 | Edit 60 kg × 8 to × 9 and save | 540 kg for that set and correctly recomputed dependent metrics after commit. |
| T20 | Edit the same set and cancel | Original 480 kg and prior observation remain unchanged. |
| T21 | Change set feedback to interrupted/uncertain | Stored record preserved; documented eligibility and dependent metrics refresh. |
| T22 | Swipe, cancel, delete and undo a History row | No text/action overlap; only selected session affected; undo semantics tested. |

### Planning, progress and secondary data

| Test | Scenario | Required assertion |
|---|---|---|
| T23 | One fixture across Today/Overview/History/Balance/PRs | Same-scope metrics agree; intentionally different scopes are labeled. |
| T24 | Empty week with zero scheduled sessions | Unconfigured state, not green completed 0/0. |
| T25 | Rest day with later sessions | Rest state and actual next date; no false “nothing left.” |
| T26 | Completed week versus partially completed week | Correct distinct states and permitted next action. |
| T27 | Resume session while a weekly override exists | One authoritative plan/context; no hidden alternative Start flow. |
| T28 | Activate imported one-day plan without reseeding | Today, roadmap, logger and Coach agree on active source/version. |
| T29 | Re-activate same imported version | Idempotent state, no duplicate plan/decision records. |
| T30 | Malformed/unsupported import and cancel preview | No mutation; useful specific errors; old active plan intact. |
| T31 | Source date zero, missing date, old valid date | Format contract respected; source/import/activation timestamps distinguished. |
| T32 | Review/share a redacted program | Actual preview; allowed fields only; nothing transmitted on cancel. |
| T33 | Save a new body measurement then navigate/relaunch | List and Body stats subtitle refresh from the same persisted source. |
| T34 | Enter custom food with blank/zero/negative/decimal values | Unknown is not zero; invalid fields identified; valid zero supported. |
| T35 | Save recorded 100 g / 380 kcal sample food | One meal entry; calories/macros and consumed/remaining reconcile. |
| T36 | Empty versus explicitly complete food day | Missing intake is not interpreted as a recorded zero-intake day. |
| T37 | Pick/cancel/save/compare/delete progress photos | Explicit actions, local privacy, correct persistence and deletion. |
| T38 | Change equipment name versus identity/convention | Renaming and comparability rules remain distinct; incompatible history not merged. |
| T39 | Apply gym/travel/crowd/time constraint and undo/revert | Validated diff; no hidden permanent preference; prior settings recoverable. |
| T40 | Save/reopen consistency goal and log eligible session | Correct counted event; no forecast substituted for actual completion. |
| T41 | Start/cancel/evaluate experiment with insufficient data | Explicit approval; no premature effect claim; correct qualifying observations. |

### Timeline, Coach and release integrations

| Test | Scenario | Required assertion |
|---|---|---|
| T42 | Initial prescriptions plus real changes in Timeline | Starting targets distinct from before/after changes; groups link to actual records. |
| T43 | Timeline filters/month/navigation and return | Correct selection, stable ordering and preserved scroll position. |
| T44 | Save/edit a private note | Exact text persists locally; no cloud/social export from note entry. |
| T45 | Hide/restore the selected timeline item | Only visibility changes; History and metrics unchanged; Undo/Restore work. |
| T46 | Coach ambiguity: “Why did my weight drop?” | Appropriate clarification when multiple meanings remain plausible; no invented trend. |
| T47 | Coach explains one actual program change | Answer matches authorized source and freshness; private cause not reconstructed. |
| T48 | Coach instruction-extraction prompt | Bounded response; no prompt/tool/permission disclosure beyond allowed information. |
| T49 | Coach asks for an unknown birthday or unavailable fact | Ordinary missing-information response, not irrelevant medical language. |
| T50 | Coach action preview; approve/reject/stale approval | No direct model write; exact bound approval; stale preview rejected safely. |
| T51 | Known voice clip, silence, noise, denial and timeout | Visible, correct states; no phantom set; typed/manual fallback remains available. |
| T52 | Change effective voice/Coach processing permissions | Next request follows chosen path; no forbidden export or silent fallback. |
| T53 | Share workout; cancel; repeat; optional Crew publish | Saved workout unaffected; approved fields; duplicate protection; planned targets labeled. |
| T54 | Signed-out and signed-in Crew; auth failure/expired session | Correct audience and ownership; no private-feed assumption; retry safe. |
| T55 | Purchase/cancel/restore/expired entitlement | Actual entitlement state correct; test-only UI absent in release configuration. |
| T56 | English/Japanese/Korean, region, units and text sizes | No critical clipping; consistent numeric meaning and correct plurals. |
| T57 | VoiceOver, Reduce Motion, keyboard and floating chrome | Correct labels/focus; every primary action reachable; no obscured last row. |
| T58 | Watch and phone concurrent/offline delivery | One observation per event; canonical plan updates reconciled, not applied twice. |
| T59 | Widgets, Live Activity, Siri, notifications, audio interruptions | Correct current state on actual system surfaces; no stale cue or hidden mutation. |
| T60 | Offline/timeout/retry/account deletion with pending work | No data loss, cross-account leakage, duplicate commits or deleted-data resurrection. |
| T61 | Network/telemetry export canaries in Health and notes | Forbidden raw and derived values absent from every outgoing path and diagnostic log. |
| T62 | Long-history/import stress and fresh-install startup | Record measured response/memory/render behavior; no empty-screen hang or incorrect placeholders. |

### Minimum next recording, in one uninterrupted scenario

1. Start with a documented fixture and known permissions. Show the starting plan and its source.
2. Log one set with missing RPE and another with explicit RPE. Type a cross-exercise command and open its correct plate context.
3. Finish a partial workout; show saved records, eligibility explanation, and actual next-step decision. Reopen History and compare values.
4. Force-kill/relaunch, then demonstrate no data loss or duplicate progression.
5. Run an ordinary Coach question through response and a supported change through preview, reject/approve, and receipt.
6. Export a workout card; cancel once and complete once. Show that training state is unchanged by sharing.
7. Open a deliberately empty week, create a valid schedule, and show the resulting Today state.
8. Save/edit a measurement and food entry; show immediate and post-relaunch consistency. End with the test assertion report, not just the last app screen.

Separate recordings should cover Watch, voice/audio, signed-in Crew, subscription, localization and failure states that cannot be honestly demonstrated in that one scenario.

---

## 9. Measurement and release gate

### Measure behavior, not feature count

Proposed product metrics: first-workout completion, successful second workout, time to a valid first set, resume success, correction/undo rate, explanation usefulness, and repeat share use. Compare like-for-like cohorts and fixtures; the tour itself contains no retention/conversion evidence.

Reliability metrics should include conflicting context, fabricated effort, duplicate observations/commits, stale preview attempts, mismatched same-scope metrics, pending-update backlog and import activation failures. Do not upload raw notes, prompts, Health data or derived private evidence simply to measure them.

### Definition of done

- [ ] G00–G04 and normal Coach action/answer tests have reproducible results or explicitly documented non-reproducible findings with evidence.
- [ ] No target RPE is presented as an unprovided report.
- [ ] No screen mixes an exercise name, another exercise's load, and an incompatible equipment convention.
- [ ] Empty weeks are not marked complete; active plan source is consistent within a scenario.
- [ ] Same-scope metrics agree after save, edit, feedback, import and relaunch.
- [ ] Core logging/resume/finish works without a cloud model and retains data on failure.
- [ ] Important views have clear empty/loading/pending/error states and tested accessibility.
- [ ] Required sharing, auth, subscription, privacy and platform paths have actual device/staging assertions.
- [ ] A new before/after recording and test-results file accompany the release PR.

**First coding task:** reproduce the RPE discrepancy and the Lunge/Deadlift plate-context mismatch on a fixed fixture. Fix the data/context contracts before changing screen decoration.

---

## 10. Evidence appendix

The Markdown remains usable without images: every issue includes source timestamps. The optional ZIP places this document beside an `evidence/` folder, so the image links below resolve when extracted. Images are unannotated stills from the supplied recording, not redesigned mockups. The manifest includes the source file hash; the original video is not duplicated in the ZIP.

| Evidence | Video time | Frame |
|---|---|---|
| E01 | 00:36 | [E01_00m36s_onboarding_starting_loads](evidence/E01_00m36s_onboarding_starting_loads.jpg) |
| E02 | 00:56 | [E02_00m56s_checkin_scale](evidence/E02_00m56s_checkin_scale.jpg) |
| E03 | 01:21 | [E03_01m21s_logger_unreported_rpe](evidence/E03_01m21s_logger_unreported_rpe.jpg) |
| E04 | 01:36 | [E04_01m36s_partial_workout_summary](evidence/E04_01m36s_partial_workout_summary.jpg) |
| E05 | 02:40 | [E05_02m40s_history_reported_rpe_and_debrief](evidence/E05_02m40s_history_reported_rpe_and_debrief.jpg) |
| E06 | 03:08 | [E06_03m08s_history_row_layout](evidence/E06_03m08s_history_row_layout.jpg) |
| E07 | 03:48 | [E07_03m48s_food_validation](evidence/E07_03m48s_food_validation.jpg) |
| E08 | 04:02 | [E08_04m02s_fuel_saved_food](evidence/E08_04m02s_fuel_saved_food.jpg) |
| E09 | 04:28 | [E09_04m28s_today_generic_change](evidence/E09_04m28s_today_generic_change.jpg) |
| E10 | 05:00 | [E10_05m00s_voice_settings](evidence/E10_05m00s_voice_settings.jpg) |
| E11 | 07:45 | [E11_07m45s_measurement_saved](evidence/E11_07m45s_measurement_saved.jpg) |
| E12 | 08:20 | [E12_08m20s_balance_coverage](evidence/E12_08m20s_balance_coverage.jpg) |
| E13 | 09:11 | [E13_09m11s_focus_mode](evidence/E13_09m11s_focus_mode.jpg) |
| E14 | 09:30 | [E14_09m30s_typed_deadlift_command](evidence/E14_09m30s_typed_deadlift_command.jpg) |
| E15 | 09:32 | [E15_09m32s_typed_log_receipt](evidence/E15_09m32s_typed_log_receipt.jpg) |
| E16 | 09:51 | [E16_09m51s_plate_context](evidence/E16_09m51s_plate_context.jpg) |
| E17 | 09:56 | [E17_09m56s_workout_notes](evidence/E17_09m56s_workout_notes.jpg) |
| E18 | 10:39 | [E18_10m39s_coach_guard_reply](evidence/E18_10m39s_coach_guard_reply.jpg) |
| E19 | 11:04 | [E19_11m04s_equipment_passport_explanation](evidence/E19_11m04s_equipment_passport_explanation.jpg) |
| E20 | 11:41 | [E20_11m41s_goal_builder](evidence/E20_11m41s_goal_builder.jpg) |
| E21 | 12:01 | [E21_12m01s_import_source_json](evidence/E21_12m01s_import_source_json.jpg) |
| E22 | 12:12 | [E22_12m12s_import_active_version](evidence/E22_12m12s_import_active_version.jpg) |
| E23 | 12:20 | [E23_12m20s_program_share_review](evidence/E23_12m20s_program_share_review.jpg) |
| E24 | 12:44 | [E24_12m44s_experiment_evidence](evidence/E24_12m44s_experiment_evidence.jpg) |
| E25 | 13:40 | [E25_13m40s_empty_week](evidence/E25_13m40s_empty_week.jpg) |
| E26 | 14:24 | [E26_14m24s_timeline_event_density](evidence/E26_14m24s_timeline_event_density.jpg) |
| E27 | 14:40 | [E27_14m40s_history_edit_draft](evidence/E27_14m40s_history_edit_draft.jpg) |
| E28 | 15:30 | [E28_15m30s_timeline_initial_loads](evidence/E28_15m30s_timeline_initial_loads.jpg) |
| E29 | 15:48 | [E29_15m48s_timeline_hide_menu](evidence/E29_15m48s_timeline_hide_menu.jpg) |
| E30 | 15:54 | [E30_15m54s_timeline_hidden_item_restore](evidence/E30_15m54s_timeline_hidden_item_restore.jpg) |
| E31 | 17:20 | [E31_17m20s_final_empty_week](evidence/E31_17m20s_final_empty_week.jpg) |

**Source:** current conversation upload `file_00000000a2608211a3db602dac9b3d75`, `regulift-full-feature-tour(1).mp4`. No external competitor claims or earlier audit findings are used as evidence for this build.

**Internal-use evidence:** screenshots contain the recording’s training and measurement information. Review/redact them before any public use.

**Deliverable validation:** document references and evidence paths checked locally. No app code was changed, compiled, or deployed; none of the 62 proposed tests was executed by this reviewer.
