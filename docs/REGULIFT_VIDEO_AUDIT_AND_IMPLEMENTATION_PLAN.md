# ReguLift — Video Audit and Complete UI/UX Implementation Plan

**Version:** 2.0 — video-informed consolidated roadmap  
**Prepared:** September 19, 2026  
**Status:** Proposed work. No repository changes, device tests, or releases have been performed.  
**Primary evidence:** `regulift-full-feature-tour.mp4`, approximately **10 minutes 21 seconds**, supplied in this conversation.  
**Prior roadmap incorporated:** `REGULIFT_IMPLEMENTATION_PLAN.md`, version 1.0, September 18, 2026.  
**Deliverable:** One self-contained implementation plan covering observed defects, screen-level improvements, all eight previously recommended additions, engineering safeguards, testing, and release gates.

> **Build direction:** Make the existing app easier to understand and more trustworthy before making it larger. Preserve fast logging, the dark visual identity, and the deterministic training engine. Improve the relationship between what users see, what they log, and what the Coach is allowed to change.

---

## Contents

1. [How to use this plan](#1-how-to-use-this-plan)
2. [Executive decisions](#2-executive-decisions)
3. [Recording coverage and evidence register](#3-recording-coverage-and-evidence-register)
4. [Correctness and shared state](#4-correctness-and-shared-state)
5. [Design system and navigation](#5-design-system-and-navigation)
6. [Screen-by-screen implementation](#6-screen-by-screen-implementation)
7. [All eight feature additions](#7-all-eight-feature-additions)
8. [Architecture, persistence, and privacy](#8-architecture-persistence-and-privacy)
9. [Delivery sequence](#9-delivery-sequence)
10. [QA fixtures and release tests](#10-qa-fixtures-and-release-tests)
11. [Usability validation and measurement](#11-usability-validation-and-measurement)
12. [First implementation package and agent handoff](#12-first-implementation-package-and-agent-handoff)
13. [Sources and verification boundaries](#13-sources-and-verification-boundaries)

---

## 1. How to use this plan

### 1.1 What was reviewed

The recording was reviewed chronologically through its ending, using time-indexed frames across the full duration, additional transition samples, and original-resolution inspection of important screens. The video contains **no audio stream**. This is a visual workflow audit, not hands-on testing or an assessment of spoken recognition accuracy.

The review covers onboarding, Today, check-ins, workouts, rest, summaries, Coach, Progress, history, measurements, photos, Balance, Recovery, mesocycles, experiments, Fuel, Crew, settings, training setup, and the program roadmap. Individual subsecond transitions can still escape a frame-based review.

The recording includes test-style names and rapidly completed partial workouts. Treat its data as a test scenario, not a representative user's training behavior. Returning to the Home Screen or relaunching the app does **not** establish a crash. A recording does not reveal database contents, model payloads, analytics, or the cause of a display defect.

### 1.2 Evidence labels

| Label | Meaning | Implementation response |
|---|---|---|
| **Observed** | A visible state or behavior in the supplied recording | Reproduce and fix the demonstrated issue; investigate the cause separately |
| **Investigate** | A plausible defect or confusing behavior, with alternative explanations | Add a controlled fixture and establish intended semantics before changing logic |
| **Proposal** | A recommended interaction or capability | Implement behind a flag and validate with users |
| **Not demonstrated** | The recording does not establish behavior | Inspect the repository or test the existing implementation; do not assume absence |

Evidence references such as **V04, 01:33** refer to the uploaded video, not to an external product review. Times are approximate playback positions; use a few seconds on either side when reproducing.

### 1.3 Priority meanings

- **P0 — Correctness/trust gate:** Wrong or ambiguous training-state interpretation, unrendered implementation text, unauthorized mutation, data loss, or unsafe privacy behavior. Observed display defects can be P0 launch-quality items without being security incidents.
- **P1 — Core task quality:** Readability, workout efficiency, navigation, onboarding, and clear feedback.
- **P2 — Product depth:** The eight additions and secondary workflow improvements, released after their dependencies.

Priority is an implementation recommendation, not a claim about incident severity in production. All checkboxes are intentionally unchecked.

### 1.4 Scope boundaries

Keep existing adaptive programming, onboarding/history import, voice logging, Focus Mode, Gym Profiles, Coach/RAG/memory, experiments, nutrition, Crew, exports, Watch, widgets, sync, subscriptions, localization, and accessibility infrastructure. Extend them rather than creating competing systems.

Do not add exercise-video libraries, video form analysis, camera recognition, an always-listening assistant, a broad social network, a creator marketplace, or a replacement nutrition product in this roadmap. Do not add new paid vendors, a different database, a higher minimum OS, or a permanent free tier without a separate decision.

All component and entity names below are **proposed logical names**. Map them to real repository types before writing code.

---

## 2. Executive decisions

### 2.1 Preserve these strengths

The video already shows a coherent dark appearance, recognizable green primary actions, useful training rings, large load/rep controls, automatic rest, a workout resume path, early-finish confirmation, before/after nutrition adjustments, program structure, and explanations for training decisions. Those are foundations to keep, not features to replace.

The key problem is not a shortage of features. Important actions and explanations are distributed across long screens, while some small cards and labels cannot accommodate their content.

### 2.2 First changes to ship

| Order | Change | Why it comes first |
|---|---|---|
| 1 | Fix the Focus Mode expression and broken narrow labels | These are visible defects in the recording and damage confidence immediately |
| 2 | Define recorded, eligible, planned, remaining, and missed training states | Several screens show different totals or meanings without making the distinction sufficiently clear |
| 3 | Make workout action context explicit | Logging another exercise must not leave the timer, calculator, or Coach action referring ambiguously to a different exercise |
| 4 | Simplify Today, Progress, and the workout summary | Bring the next useful action forward; move explanations and secondary tools behind clear detail entry points |
| 5 | Gate advice when information is sparse or incomplete | A first check-in, partial session, or new experiment should not look like strong evidence |
| 6 | Integrate all eight additions into existing screens | Improve depth without adding a new tab or dashboard for every capability |

### 2.3 Desired product experience

A user should be able to answer these questions without searching through settings or interpreting inconsistent counters:

> **What should I do today? Which equipment and constraints apply? What exactly am I logging? What changed, and why? What did I actually complete? What information supports the next recommendation?**

### 2.4 What this version changes from the previous roadmap

The previous roadmap began with shared engineering contracts and Equipment Passport. This version adds a **correctness and readability release before major feature expansion**.

All eight additions remain in scope. The recording confirms that Program roadmap, Focus Mode, experiment setup, Gym Profiles, and several confirmation/diff surfaces already exist. The implementation must extend those foundations rather than rebuilding them under new names.

---

## 3. Recording coverage and evidence register

### 3.1 Full timeline

| Video time | Reviewed flow | Important review boundary |
|---|---|---|
| 00:00–00:32 | Launch and Home Screen transitions | Not enough evidence to measure launch performance or diagnose crashes |
| 00:33–00:46 | Coach selection, starting information, limitations, optional photo, plan preview, paywall | Purchase completion and trial eligibility are not demonstrated |
| 00:47–01:12 | Today, missed-workout message, check-in, soreness map, readiness | Fresh-start scheduling semantics need reproduction |
| 01:14–01:40 | First workout, notification permission, logging, rest, finish, summary | Rapid partial session is explicitly excluded from some calculations |
| 01:42–02:49 | Progress, empty metrics, tool grid, awards, history | Totals have different apparent eligibility scopes |
| 02:52–02:59 | Coach initial screen | Normal training question quality is not demonstrated here |
| 03:06–03:25 | Progress navigation and lower tools | Long scroll and narrow labels recur |
| 03:26–03:44 | Fuel setup, targets, custom food, meal logging | A name-only, zero-valued test food can be saved/logged |
| 03:51–03:55 | Crew signed-out and sign-in | Joined Crew behavior is not demonstrated |
| 04:03–05:33 | Settings, exercises, voice/language, plates, import, feedback | Many existing capabilities are settings-heavy |
| 05:48–06:21 | Second partial workout, app exit/resume, finish | Useful resume behavior; no basis for a crash claim |
| 06:22–07:16 | Populated Progress, PRs, measurements, photos, Balance, blocks, Recovery | Sparse-data advice and Recovery layout are visible |
| 07:24–08:19 | Third workout, listening state, typed off-screen exercise, calculator, notes, Why, swap, finish | Audio and recognition quality cannot be assessed |
| 08:20–08:43 | Week review, next week, Coach consent and adversarial prompt response | A refusal is not proof of normal coaching accuracy |
| 08:46–09:10 | Settings, Gym Profiles/modes, Focus Mode, empty-workout discard | Raw expression appears in Focus Mode |
| 09:11–09:31 | Progress and experiment creation | Completed experiment evaluation is not shown |
| 09:34–09:44 | Today, existing program roadmap, muscle emphasis, week expansion | A generic program roadmap is already present |
| 09:45–10:21 | Progress, Fuel, target adjustment preview, ending | Nutrition already has a before/after change surface |

### 3.2 Issue register

| ID | Evidence and time | Assessment | Required response | Priority |
|---|---|---|---|---|
| **V01** | Focus Mode, 09:06–09:08: `One set at a time · (max(0, totalSets - loggedCount)) sets left` | **Observed** unrendered expression; cause unknown | Bind a computed localized count; test zero/one/many and all supported strings | P0 |
| **V02** | Recovery, 07:14–07:15: labels split into fragments such as `sl / ee / p` | **Observed** layout failure | Replace narrow nested cards with responsive metric rows/tiles; test large text | P1 release gate |
| **V03** | Progress tool grid, 01:55–02:05 and 03:15–03:25: long names fragment/wrap awkwardly | **Observed** readability issue | Group tools in sufficiently wide rows; preserve full accessible names | P1 |
| **V04** | First summary, 01:33; Today, 01:39–01:42; Progress, 01:42–01:46; History, 02:41–02:44 | **Observed** different totals, partly explained by explicit exclusion | Define and label each metric's scope; do not assume data loss or delete validation rules | P0 investigation |
| **V05** | Fresh onboarding followed by “Missed 3 sessions this week,” 00:47–01:12 | **Investigate** enrollment/date/fixture semantics | Only label elapsed accepted obligations as missed; distinguish remaining sessions | P0 investigation |
| **V06** | Today recovery suggestion with “Do that,” 00:47–01:12 | **Observed** vague consequential action label | Show exact session/set changes and a scope-aware preview/undo | P1 |
| **V07** | Today readiness repeated in the ring area, 01:10–01:12 and 08:26 | **Observed** duplicated emphasis | Keep one primary readiness value, its meaning, freshness, and a details entry | P1 |
| **V08** | First workout notification prompt, about 01:15 | **Observed** permission request interrupts training | Request rest alerts at a deliberate feature entry; preserve denied path | P1 |
| **V09** | Workout logging screens, 01:17–01:22 and 07:43–07:46 | **Investigate** target effort versus default reported effort | Do not store an untouched target/default as a user-reported value without explicit policy | P0 investigation |
| **V10** | Off-screen Deadlift log while Back Squat remains visible, 07:43–07:51 | **Observed** ambiguous exercise context; not proof of a wrong calculation | Bind and label the exercise for log, rest, calculator, and action proposals | P0 investigation |
| **V11** | Workout summaries, 01:33–01:36 and 06:14–06:21 | **Observed** large coach imagery/share actions dominate | Prioritize saved work, eligibility, next step, and compact debrief; consolidate sharing | P1 |
| **V12** | Progress, 01:42–02:05 | **Observed** many zero charts before useful tools | Add honest new-user/sparse-data states; move History and tools upward | P1 |
| **V13** | Coach, 02:52–02:59 and 08:27 | **Observed** large intro portrait and overlapping prompt choices | Compact introduction; context-specific prompts; clearer composer | P1 |
| **V14** | Coach consent/refusal, 08:34–08:43 | **Observed** consent and one attack response | Preserve safeguards; separately test ordinary answers and confirmed mutations | P1 verification |
| **V15** | Custom food, 03:36–03:44 | **Observed** zero-valued food workflow; unknown/default interpretation uncertain | Separate unknown from legitimate zero; explicit review of serving and nutrition | P1 |
| **V16** | Settings, 04:03–05:33; training setup, 08:59–09:01 | **Observed** fragmented settings and buried session constraints | Group settings and expose Gym/time/modes in Today/workout context | P1 |
| **V17** | Voice and language settings, 04:47–05:20 | **Observed** several overlapping language/processing controls | Distinguish app language, recognition language, STT route, Coach route, and data consent | P1 |
| **V18** | Measurements, about 07:00–07:02 | **Investigate** entered decimal versus rounded summary display | Define field-specific display precision; preserve original stored precision | P1 |
| **V19** | Photos empty state, about 07:05 | **Observed** generic chart-like visual | Use a photo-specific empty state and one clear add-photo action | P2 |
| **V20** | Balance, about 07:08: zero ratios and “Push is lagging. Add a pressing set.” | **Observed** strong advice over sparse recorded work | Show coverage, undefined ratios, and plan context; require evidence and permissions for changes | P0 advice gate |
| **V21** | Recovery, 07:14–07:15: limited history and “Recovery looks solid. Train hard.” | **Observed** advice stronger than visible evidence | Describe check-in inputs/coverage; avoid confident physiological conclusions | P0 advice gate |
| **V22** | New experiment, 09:24–09:31: unchanged baseline/current and a zero change | **Observed** initial state can look like an evaluated result | Show “Collecting results,” elapsed stage, comparable observations, and later inconclusive outcome | P1 |
| **V23** | Program roadmap, 09:39–09:42 | **Observed** capability already exists behind a small entry | Improve discoverability; extend it for imported programs, weekly planning, and goals | P1/P2 |
| **V24** | Fuel “Training day” around 03:31 versus “Rest day” around 10:05 | **Investigate** date/planned/actual classification; recording does not establish cause | Label day basis/date and test consistent overrides/target previews | P1 |
| **V25** | Fuel adjustment, about 10:06 | **Observed** before/after values already exist | Reuse that pattern; verify persisted result, stale detection, and cancellation | P1 verification |
| **V26** | Crew signed-out, 03:51–03:55; sharing toggles, about 04:05 | **Investigate** disclosure/default behavior; no actual automatic post demonstrated | Explain audience and require clear participation/sharing consent | P1 |
| **V27** | Partial summary versus History, 01:33 and 02:43; week labels around 08:20–09:16 | **Investigate** rounding and calendar-week/program-week semantics | Use explicit duration and period labels; preserve intentional differences | P1 |

### 3.3 Important correction: different totals do not prove missing data

The first summary explicitly says the session was **not counted for PRs, badges, or Crew because sets arrived too quickly or a load jumped**. The session remains visible in History.

The recording later contains these compatible-looking totals:

| Recorded work | Volume shown in the recording |
|---|---:|
| First, flagged session | 1,024 kg |
| Second session | 585 kg |
| Third session | 480 kg |
| All three combined | 2,089 kg |
| Second and third combined | 1,065 kg, approximately 1.1 t |

This arithmetic explains a plausible source of the dashboard discrepancy. It does **not** verify the application's actual filter implementation. The problem to solve is transparent, consistent scope: users should know whether a number means logged work, work eligible for a particular analysis, or publicly recognized achievements.

Do not “fix” this by counting every entry as a PR, by removing anti-abuse checks, or by deleting flagged training history.

---

## 4. Correctness and shared state

**Outcome:** Every screen tells a consistent story about the same training data, while intentional differences remain visible.

### 4.1 Define the semantics before changing counters

| Concept | Proposed meaning | Must not be confused with |
|---|---|---|
| Recorded session | A persisted workout containing logged work according to existing save rules | A fully completed planned session |
| Planned session | An accepted program/week obligation with identity and intended date/window | A generic frequency target |
| Completed planned work | Explicitly defined fulfillment of a planned session; may include an approved Minimum Effective Workout | Merely opening a workout or logging one arbitrary set |
| Partial session | Saved work with unfinished planned work | A failed workout or invalid history |
| Remaining | Accepted obligations not yet completed whose time has not necessarily passed | Missed |
| Missed | An elapsed, accepted obligation after enrollment, according to a documented grace/date policy | Three weekly sessions minus sessions logged |
| Analysis-eligible | Eligible for a named calculation under a versioned policy | Eligible for every metric or public award |
| Achievement-eligible | Meets the specific PR/badge rule | All useful recorded work |
| Published | Explicitly shared to Crew or another audience | Saved locally or eligible for an award |

A user can have a saved, useful partial session that is not a full planned-session completion and is not eligible for a public achievement. Preserve all three facts.

### 4.2 Shared metric contract

Use an existing aggregate service, or introduce a small shared equivalent. Do not let each screen recreate independent predicates.

```text
MetricDescriptor
  metricID
  periodKind: calendarWeek | programWeek | rollingWindow | allHistory
  intervalStart / intervalEnd / timeZone
  includedSessionStates
  eligibilityPolicyID / policyVersion
  equipmentComparisonScope (when relevant)
  sourceRevision
  coverage / missingDataState
  value / unit / displayPrecision
  explanationKey
```

The same metric descriptor and source revision must produce the same value everywhere. Different descriptors may produce different values, but the label and details must explain why. Calendar week and program week are separate concepts, even when they happen to align.

### 4.3 Shared workout context

```text
WorkoutActionContext
  sessionID / sessionRevision
  exerciseSlotID / exerciseID / variantID
  equipmentInstanceID / loadModelRevision
  plannedSetID or explicit new-set intent
  displayedLoad / originalUnit / loadConvention
  actionSource: manual | typed | voice | watch | coach
```

A timer may deliberately refer to the last logged exercise while the main screen shows another exercise. That is valid only if both surfaces identify their context. Opening the plate calculator must either use the visible exercise's target or explicitly state a different chosen target.

### 4.4 Implementation tasks

- [ ] **COR-01 — Reproduce and map.** Locate actual screen models, metric predicates, set-saving methods, session status rules, date services, and localization entries. Capture fixtures corresponding to V01–V10 before changing logic.
- [ ] **COR-02 — Fix literal rendering.** Replace the Focus Mode expression with computed, localized output. Add tests for zero, one, many, negative intermediate values, changed totals, and every supported locale. Search user-facing resources for similar unrendered placeholders.
- [ ] **COR-03 — Specify training-state semantics.** Document enrollment, planned versus partial completion, remaining versus missed, early finish, discard, and approved minimum-workout behavior. Reconcile these definitions with the existing engine rather than inventing a parallel completion rule.
- [ ] **COR-04 — Unify metric scope.** Implement shared descriptors/selectors for Today, Progress, History, Recovery, weekly review, PRs, and Crew. Add visible explanations wherever scopes intentionally differ.
- [ ] **COR-05 — Preserve and explain eligibility.** Retain recorded work, attach named eligibility reasons, distinguish backfilled entry speed from claimed live execution where possible, and allow appropriate correction/review without weakening public achievement rules.
- [ ] **COR-06 — Bind action context.** Carry explicit session/exercise/set/equipment identity through typed logs, voice, Watch, timers, calculators, substitutions, and Coach proposals. Resolve ambiguous targets before committing.
- [ ] **COR-07 — Preserve provenance and formatting.** Separate planned effort from reported effort, unknown from zero, stored precision from display precision, and seconds from rounded minutes. Use one formatting policy per field.
- [ ] **COR-08 — Correct date transitions.** Test new enrollment late in the week, program-week advancement, local midnight, travel, daylight-saving changes, edited sessions, and overlapping device updates. Only regenerate future obligations under explicit policy.
- [ ] **COR-09 — Stabilize save feedback.** Distinguish saving, saved locally, pending sync, and failed. Do not display transient zeros as final results or signal success before persistence succeeds.

### 4.5 Acceptance criteria

The first flagged session remains in History and can be explained from every affected total. Identical metric scopes reconcile across screens. A first-time Saturday enrollment is not assigned missed obligations from before enrollment unless an explicitly imported historical schedule calls for them.

Logging an off-screen exercise produces an unmistakable receipt naming that exercise; the calculator and rest view identify their own targets. Untouched default effort is not silently treated as an explicit user report. Focus Mode never renders source-like expressions, and no display fix changes the saved training record.

---

## 5. Design system and navigation

**Outcome:** Keep ReguLift recognizable while reducing density, fragmented labels, and competition between actions.

### 5.1 Visual direction

Keep the dark canvas, vivid primary action, and recognizable metric colors. Use a restrained hierarchy of surfaces: page background, primary card, and optional inset detail. Avoid multiple nested rounded cards where each layer consumes label width.

Use functional visuals where they improve understanding: soreness selection, muscle emphasis, equipment setup, plate loading, comparable progress, and program structure. Do not add stock gym photos to replace useful text. Keep coach imagery small outside intentional onboarding/identity screens.

### 5.2 Proposed design tokens

These are starting design specifications, **not measurements of the current app**. Adapt them to the existing type system and supported devices.

| Element | Proposed rule |
|---|---|
| Page margin | Consistent approximately 16–20 pt, adjusted for the existing device/layout system |
| Spacing | A small consistent scale such as 4, 8, 12, 16, 24, 32 pt |
| Interactive target | At least 44 × 44 pt as the project's minimum; larger primary workout controls where practical |
| Primary workout action | Approximately 52–56 pt high before text-size adaptation; no fixed height that clips accessibility text |
| Body text | Prefer native scalable body styles; avoid using tiny captions for actionable explanations |
| Secondary text | Use for metadata, not the only presentation of consequences or errors |
| Numeric metrics | Align values and units; use consistent precision and tabular digits where beneficial |
| Long labels | Prefer a full-width row or flexible stack; do not split ordinary words into fragments |
| Cards | Two columns only when their actual content fits; one column at larger sizes or longer translations |
| Fixed controls | Reserve safe-area content space so the last card/button remains reachable |
| Motion | Respect reduced-motion preferences; avoid celebratory motion blocking set entry |

Use WCAG contrast ratios as an explicit visual-quality benchmark: 4.5:1 for ordinary text and 3:1 for qualifying large text. Measure actual foreground/background combinations in the app, not compressed video pixels. This is a chosen design target, not a claim of accessibility certification. [S2]

### 5.3 Information architecture

Keep the existing top-level tabs initially. Do not launch a large navigation migration simultaneously with changes to training semantics.

| Surface | Primary job | What moves here |
|---|---|---|
| **Today** | Decide and start the next useful session | Program/Week link, current Gym/time/modes, next workout, one relevant adjustment |
| **Coach** | Understand or request a change | Contextual conversation, proposal cards, program permissions, optional spoken questions |
| **Progress** | Understand recorded progress and review results | Overview, History shortcut, goals, evidence, clearly grouped tools |
| **Crew** | Optional, explicitly shared participation | Existing social scope; no additional feed/network product |
| **Settings** | Configure lasting preferences | Account, privacy, units, languages, routing, subscriptions, support |
| **Program detail** | Inspect or edit training structure | Existing roadmap, import, permissions, version history, week planning, sharing |

Fuel can retain its existing entry point initially, with a clear shortcut in the relevant tools area. Promote it to a larger navigation role only if task testing demonstrates frequent demand; do not assume every strength-training user wants a nutrition-first app.

### 5.4 Shared components

Build or adapt a small set of reusable components:

| Component | Required behavior |
|---|---|
| `MetricTile` / `MetricRow` | Label, value, unit, period, coverage, optional explanation; responsive layout |
| `ContextChips` | Gym, time budget, mode, equipment; readable labels and large hit areas |
| `ActionDiffCard` | Before/after, exact scope, rationale, authorization, current status |
| `DataCoverageState` | Empty, collecting, partial, comparable, not assessable; no fabricated zero |
| `WorkoutReceipt` | Saved exercise/set/load, undo or correction route, local/sync state where relevant |
| `PermissionExplanation` | Purpose, actual route, optionality, and denied fallback |
| `ToolRow` | Full title, concise purpose, optional meaningful state; no narrow multi-line word fragments |
| `EvidenceDetail` | Actual support and limitations, separated from promotional Coach language |

### Implementation tasks

- [ ] **DSN-01 — Token audit.** Inventory actual colors, type styles, margins, card padding, control sizes, and light/dark variants. Replace inconsistent instances with existing or consolidated tokens.
- [ ] **DSN-02 — Responsive metrics.** Rebuild the Recovery tiles and Progress tool grid using content-aware layouts. Prevent word fragmentation at ordinary size and at all supported accessibility sizes.
- [ ] **DSN-03 — Action hierarchy.** Define primary, secondary, destructive, and explanation actions. A change of consequence must never be labeled only “Do that” without the nearby exact scope.
- [ ] **DSN-04 — Shared state components.** Implement the metric, diff, coverage, receipt, and tool-row patterns; reuse existing components where equivalent.
- [ ] **DSN-05 — Safe-area and keyboard behavior.** Test every sticky action, tab bar, bottom sheet, keyboard, floating timer, and long form. Ensure the final actionable row is reachable and not hidden.
- [ ] **DSN-06 — Accessibility pass.** Add meaningful VoiceOver grouping/order, spoken units/conventions, selected states, text alternatives to rings/maps, non-color status, reduced motion, and usable large-text layouts.
- [ ] **DSN-07 — Localization pass.** Test long translations, plurals, decimal separators, right-to-left layout where supported, units, and dates. Do not use global text shrinking as a solution.
- [ ] **DSN-08 — Navigation consistency.** Establish one canonical route to each existing destination, preserve back context/scroll position, and add Today-to-Program and Progress-to-History shortcuts.

**Acceptance:** Recovery labels remain whole words; action cards explain their scope; no persistent control obscures content; primary flows work with VoiceOver, large text, and denied audio permissions. Exact visual compliance must be measured in native builds.

---

## 6. Screen-by-screen implementation

The sections below are extensions of the recorded app. Each task should ship as a complete, tested vertical slice rather than an isolated mock screen.

### 6.1 Onboarding and paywall

**Evidence:** 00:33–00:46; V05, V08.  
**Desired outcome:** Understand the product, get a realistic first session, and knowingly enter the correct trial/paid state without unnecessary setup.

Keep coach choice and optional personalization, but prioritize the information needed for the first usable plan. Starting photos and precise lift estimates should remain optional. Make it clear that an unknown lift is acceptable and that starting loads can be reviewed.

The first-plan preview should show frequency, approximate session time, equipment assumptions, and a representative workout. The next action should be unambiguous: start, edit constraints, or review the current paid/trial offer.

- [ ] **ONB-01 — Audit essential fields.** Separate required programming inputs from optional photos, precise baselines, and personalization. Preserve skipped/unknown values explicitly.
- [ ] **ONB-02 — Improve the first-plan preview.** Show the actual first workout, time estimate, equipment, and “Edit” entry before activation. Record the enrollment date/time zone used by scheduling.
- [ ] **ONB-03 — Make first-run Today coherent.** Route new users to a ready-to-start state, not retrospective missed sessions. Ask about the upcoming week without penalizing elapsed pre-enrollment days.
- [ ] **ONB-04 — Verify the paywall.** Use actual StoreKit/product configuration for localized price, period, eligibility, renewal/trial terms, restore, and purchase states. Never promise a trial to an ineligible user or block safe saving after a purchase interruption.
- [ ] **ONB-05 — Defer permissions.** Request notifications, Health, microphone, photo access, and calendars only when their specific feature is chosen. Each denial must preserve an understandable alternative.

**Acceptance:** A fresh user reaches a valid first workout without a photo, estimated max, account requirement beyond existing policy, or unrelated permissions. Trial wording matches actual eligibility. No dates before enrollment become missed obligations by accident.

### 6.2 Today

**Evidence:** 00:47–01:12, 01:39–01:42, 08:20–08:27, 09:34–09:44; V05–V07, V23, V27.

Keep the rings, but make the next session and its constraints more prominent. A readiness score is an estimate, not a task the user should “complete.” Use one readiness value, a plain-language status, and an explanation of its inputs/freshness.

**Proposed hierarchy:**

```text
TODAY                                      Program / Week
Saturday, September 19

NEXT SESSION
Full A · estimated 40–50 min
Gym: Main gym       Time: 45 min       Mode: Normal
[Exercise preview: first few movements + View workout]

[Start Full A]

THIS CALENDAR WEEK
Sessions recorded / planned    Sets recorded / planned
[Compact rings with readable labels and scope details]

CHECK-IN / READINESS
Today's estimate · input coverage · View why

COACH ADJUSTMENT — only when relevant
Move Full B to today; reduce Full C by 3 planned sets
[Review changes]                   [Keep current plan]
```

The sequence can adapt when an active workout needs resuming. An accepted change is not the same as an unconfirmed suggestion.

- [ ] **TOD-01 — Reorder the first viewport.** Put the next/resumable session, duration estimate, equipment context, and primary action before large secondary visualizations.
- [ ] **TOD-02 — Add constraint shortcuts.** Expose current Gym Profile, time budget, and Travel/Crowd/Minimum Effective mode through existing editors. Show which session or future period each change affects.
- [ ] **TOD-03 — Clarify rings.** Remove duplicated readiness emphasis, retain stable color meanings, label data scope, and make details available without relying on color alone.
- [ ] **TOD-04 — Replace vague recovery actions.** Show exact session/set differences, program permission conflicts, confirmation, and a revision-safe undo/compensating action. An undo cannot rewrite subsequently completed work.
- [ ] **TOD-05 — Add daily states.** Implement first session, planned training, rest day, active workout, completed session, remaining week, genuine missed obligation, and insufficient-data states.
- [ ] **TOD-06 — Surface Program/Week.** Give the existing roadmap an explicit entry. Connect it to Week Designer and later goals without adding a new top-level tab.

**Acceptance:** Users identify the next workout and constraints from the first screen. “Missed” and “remaining” have different rules. The last suggestion stays reachable above the sticky control. A rest day is not presented as a failure.

### 6.3 Daily check-in and Recovery

**Evidence:** 00:56–01:12 and 07:14–07:15; V02, V21.

Retain the body map and simple input controls. Distinguish subjective sleep quality from hours slept, and daily stress from a long-term limitation. Show optionality and save behavior clearly.

Recovery should report observations rather than imply medical certainty. For example: “Based on today's check-in; one of the last seven days recorded.” Missing Health data must not become a poor-recovery input.

- [ ] **CHK-01 — Clarify inputs.** Label the meaning and endpoints of scales; distinguish unknown/not entered from the lowest value. Keep sore-area selection accessible through a list alternative.
- [ ] **CHK-02 — Rebuild Recovery layout.** Use full-width rows or adaptive tiles for sleep, sleep quality, soreness, energy, sessions, and sets. Show period and available sample count.
- [ ] **CHK-03 — Gate interpretation.** Replace sparse-data directives such as “Train hard” with descriptive, qualified output based on the actual available signals and the existing engine's rules.
- [ ] **CHK-04 — Separate local evidence.** Keep Health-derived detail in a local engine-rendered panel, outside both server and local model context under the current public Coach boundary. Support missing/revoked permission without negative imputation. [S1]
- [ ] **CHK-05 — Keep feedback optional.** Allow skip, edit, and delete; recompute dependent readiness/evidence after changes. Do not punish an omitted check-in with adherence penalties.

**Acceptance:** No fragmented labels; no false zero for missing sleep; no strong recovery conclusion based on a single unqualified point; no raw or derived Health-specific details leaking through Coach or generic analytics.

### 6.4 Workout logging and Focus Mode

**Evidence:** 01:14–01:32, 05:48–06:13, 07:24–08:19, 09:06–09:10; V01, V08–V10.

Keep the large weight and rep controls, visible last result, rest timer, exercise actions, and current deterministic logging paths. Make Focus Mode a polished option for the existing workout—not a second workout engine.

**Proposed focused layout:**

```text
FULL A                         Exercise 1 of 6      More
Back Squat
Main gym · Rack 1 · load includes bar

Set 2 of 3
Last comparable: 65 kg × 9
Target: 65 kg × 10           [Why this target?]

WEIGHT                      REPS
[ - ]   65 kg   [ + ]        [ - ]  10  [ + ]

Reported effort: Not entered      [Add effort]

[Log set]
[Type / Log by voice]              [Ask Coach]

REST — after saving
Back Squat · 01:24 remaining      [+30 sec] [Skip]

[Exercise details: setup, swap, lock, notes]
```

Numbers are illustrative UI content, not new exercise prescriptions.

- [ ] **WKT-01 — Make Focus reliable.** Fix V01, show current exercise/set and actual remaining work, and ensure Focus and full mode share the same models, completion state, and action pipeline.
- [ ] **WKT-02 — Separate target from report.** Keep prescribed effort visible as guidance. Store actual effort only when reported or under a clearly chosen logging preference; preserve unknown where appropriate.
- [ ] **WKT-03 — Add a precise save receipt.** After manual, typed, voice, or Watch entry, identify the exercise, set, load meaning, and local save result. Provide correction/undo where safe and supported.
- [ ] **WKT-04 — Resolve cross-exercise logging.** When a command targets an off-screen exercise, show the target and offer “Go to Deadlift” or equivalent. Do not switch silently or add an exercise without clear intent handling.
- [ ] **WKT-05 — Bind the plate calculator.** Display the selected exercise, target load, bar inclusion, per-side/total convention, and equipment. Switching calculator context must not change a prescription until explicitly applied.
- [ ] **WKT-06 — Improve rest without adding friction.** Use a compact rest state that preserves exercise context. Drive remaining time from a persisted deadline rather than foreground ticks; reconcile on resume and Watch updates. Move notification permission to an explicit rest-alert action.
- [ ] **WKT-07 — Standardize exercise actions.** Reuse a predictable place for Why, Swap, Lock, Equipment, and Notes. Preserve validated substitution constraints and expose the resulting diff before consequential changes.
- [ ] **WKT-08 — Refine early finish.** Keep the existing confirmation. Clearly distinguish continue, save partial/finish early, and discard empty workout. Show recorded versus planned work without forcing completion or automatically erasing remaining intent.
- [ ] **WKT-09 — Harden interruption behavior.** Verify keyboard dismissal, input focus, accidental double taps, app termination, backgrounding, offline entry, duplicate voice callbacks, and simultaneous Watch logs without losing or duplicating sets.

**Acceptance:** A known-equipment set requires no additional mandatory setup taps. Every log and calculator action names the correct context. Denying notifications or losing the network never prevents saving a set. Minimum Effective Workouts remain valid under their explicitly approved plan semantics.

### 6.5 Workout summary and history detail

**Evidence:** 01:33–01:40, 02:41–02:44, 06:14–06:21, 08:19–08:25; V04, V11, V27.

Compress the coach portrait and move sharing behind one action. Put useful debrief information from History directly into the post-workout summary.

**Suggested order:** saved result → partial/eligibility explanation → concise debrief → next session/adjustment → Done → optional Share. Show “Under 1 minute” or seconds for short test sessions rather than inconsistent zero/one-minute presentations.

- [ ] **SUM-01 — Rebuild the hierarchy.** Show recorded sets, relevant duration, exercise count, and consistent volume scope before portraits, awards, and share-format choices.
- [ ] **SUM-02 — Explain eligibility precisely.** Name the affected calculations and the reason. Preserve the session in History and distinguish a review/correction from an unsupported promise to restore an award.
- [ ] **SUM-03 — Connect debrief to action.** Show one meaningful observation and the next planned step. Any plan adjustment opens the shared diff card instead of appearing as already committed.
- [ ] **SUM-04 — Simplify sharing.** Use one Share action leading to story/square/export choices. Preview exactly what is public and omit sensitive details by default.
- [ ] **SUM-05 — Reconcile history edits.** When a session is corrected or deleted, recompute affected summaries, eligibility, evidence, goals, and charts while preserving action provenance.

**Acceptance:** Users can tell what was saved, whether the session was partial, why some metrics exclude it, and what happens next. Opening History and the summary for the same revision shows consistent values and formatting.

### 6.6 AI Coach

**Evidence:** 02:52–02:59, 08:27–08:43; V13, V14, V17.

Reduce the empty-state portrait to a compact identity header. Use two or three useful prompts based on actual context, not duplicate generic choices across multiple rows. Keep the composer readable and readily reachable.

```text
NOVA · AI COACH                         Data and privacy
Context: Full A · Main gym · Week 2

[Explain today's target]
[Fit this workout into 30 minutes]
[Review my program permissions]

Conversation / evidence / proposed changes

[Type a question...]                  [Ask by voice]
```

Do not offer “Why did my weight drop?” when no relevant reduction occurred. A strong attack refusal in the tour should be preserved, but ordinary coaching accuracy and action confirmation still need testing.

- [ ] **COA-01 — Simplify the start state.** Compact avatar/header, remove duplicated prompt sets, make suggestions contextual, and give the composer adequate size.
- [ ] **COA-02 — Show relevant context.** Identify active session/program/Gym and selected action scope. Let users review permitted context without exposing raw system prompts or sensitive internal traces.
- [ ] **COA-03 — Unify action cards.** Implement proposed, awaiting confirmation, applying, applied, stale, conflict, failed, and cancelled states with exact before/after changes and one clear confirmation.
- [ ] **COA-04 — Make routing understandable.** Explain the actual selected/available Coach route and data use. “Connected” must not be presented as consent, and a local preference must not silently fall back to cloud.
- [ ] **COA-05 — Add evidence and memory entry points.** Link to the existing typed memory controls and recommendation support. Preserve provenance, confirmation, expiry, conflict, and deletion rather than recreating memory.
- [ ] **COA-06 — Test useful coaching.** Cover normal target explanations, ambiguous references, unsupported requests, stale plans, contradictory memory, prompt attacks, and failed actions. Reuse the current RAG and deterministic validator.

**Acceptance:** A question does not mutate the workout. A proposal shows exactly what would change. No model can mark its own suggestion approved or applied. Errors leave the original training state usable.

### 6.7 Progress overview and tools

**Evidence:** 01:42–02:05, 03:06–03:25, 06:22–07:16, 09:11–09:31; V03, V04, V12, V20, V23.

Give Progress a clear overview rather than a long sequence of mostly empty charts followed by tools. Keep detailed charts available, but reveal them when data can support them.

```text
PROGRESS                                      History
This calendar week · scope details

[Recorded sessions]    [Recorded work]
[Current goal or one useful comparable trend]

RECENT SESSIONS
Full A · saved partial · eligibility details
[View all history]

TRAINING TOOLS
Recovery          Today's inputs and recent coverage
Program / Blocks  Structure, permissions, and reviews
Experiments       Active test / collect more observations
Body              Measurements and private photos
Achievements      PRs and awards
Fuel              Intake and targets
```

This is a proposed ordering, not a demand to create new destinations where existing ones suffice.

- [ ] **PRO-01 — Reorder the overview.** Put metric scope, recent sessions, and a meaningful trend/goal above secondary tools. Make History directly reachable.
- [ ] **PRO-02 — Implement data-aware charts.** Distinguish no entries, one observation, partial capture, and comparable history. Do not draw a misleading trend through synthetic zeros or imply a baseline comparison without a baseline.
- [ ] **PRO-03 — Replace the cramped tool grid.** Use grouped full-width rows or genuinely responsive cards. Keep long names intact and show a short purpose/state where useful.
- [ ] **PRO-04 — Clarify chart interpretation.** Show period, units, equipment context, estimated-versus-measured status, data coverage, and an accessible description/table. Provide sensible empty and no-comparable-data states.
- [ ] **PRO-05 — Fix Balance advice.** Render undefined ratios as unavailable, distinguish zero numerator from zero denominator, and show recorded-plan coverage. Recommend extra work only through the engine's evidence/permission checks.
- [ ] **PRO-06 — Preserve useful drill-downs.** Connect PRs, awards, History, Recovery, goals, and experiments to the actual contributing records and exclusion explanations where permitted.

**Acceptance:** A new user can find History without scrolling through numerous zero cards. A single partial workout does not trigger confident imbalance prescriptions. Charts never combine incompatible machines or silently change the meaning of their period.

### 6.8 Measurements and photos

**Evidence:** 07:00–07:06; V18, V19.

- [ ] **BDY-01 — Preserve precision.** Use field-specific formatting for body mass and measurements. Test that entering 82.5 does not misleadingly become 83 in a summary intended to show the exact latest entry; do not infer storage corruption from rounding alone.
- [ ] **BDY-02 — Make common entry fast.** Keep quick weight entry separate from optional advanced measurements. Show a one-point state honestly instead of a fabricated trend.
- [ ] **BDY-03 — Improve photo empty states.** Use a photo-specific symbol, privacy explanation, and Add photo action. Keep photos optional and accessible without promoting unrequested image analysis.
- [ ] **BDY-04 — Verify edit/delete privacy.** Confirm permission denial, local/approved storage behavior, export choices, deletion, and whether derived summaries need recalculation.

**Acceptance:** Stored precision is preserved; display choices are consistent; photo permission is requested only when needed; deleted body data does not remain in derived views or inappropriate exports.

### 6.9 Training Experiments, program roadmap, and blocks

**Evidence:** 07:11, 09:11–09:42; V22, V23.

Experiments and a program roadmap are already implemented surfaces. Improve their state and interpretation instead of adding another experiments or roadmap feature.

- [ ] **EXP-01 — Fix the initial experiment state.** Show “Collecting results” and “Day 1 of 28” or equivalent stage-aware copy. An unchanged baseline at creation is not an observed zero effect.
- [ ] **EXP-02 — Make validity inspectable.** Show the variable being tested, baseline window, comparable observation count, deviations, and what makes a keep/revert decision inconclusive.
- [ ] **EXP-03 — Connect the existing roadmap.** Add clear Today/Progress entries, expose active block and program-week meaning, and retain useful week expansion and muscle-emphasis visuals.
- [ ] **EXP-04 — Integrate review outcomes.** Connect completed block/experiment reviews to REC and GOL, with explicit changes and permissions. Preserve original baseline and protocol versions after edits.

**Acceptance:** A newly started experiment does not claim an effect. Users can find the existing roadmap from Today. Changes to equipment or protocol are visible limitations, not silently comparable results.

### 6.10 Fuel and nutrition

**Evidence:** 03:26–03:44 and 09:45–10:21; V15, V24, V25.

Keep the existing nutrition scope. The main work is input meaning, completeness, and transparent target changes—not adding another food database or meal-planning product.

- [ ] **NUT-01 — Distinguish unknown from zero.** Model missing calories/macros separately from legitimate zero values. Warn on all-zero food entries without banning valid items such as water; require an explicit review where values are intentionally unknown.
- [ ] **NUT-02 — Clarify quantity basis.** Show per-serving versus per-100-g values, serving amount/unit, and the resulting logged totals before save. Preserve source/provenance and allow correction.
- [ ] **NUT-03 — Improve entry validation.** Validate bounds, decimals, units, and required names; use soft consistency warnings rather than rejecting foods solely because calories do not exactly equal a simplified macro formula.
- [ ] **NUT-04 — Reconcile day status.** Define whether targets use planned training, completed activity, or an explicit user override. Show the date and basis; test training/rest transitions with the same fixture and plan revision.
- [ ] **NUT-05 — Preserve the existing adjustment preview.** Connect before/after targets to revision-checked confirmation, persisted result, cancellation, and a safe correction path. Do not silently retune targets because a partial workout ended.
- [ ] **NUT-06 — Show capture completeness.** “No meals logged” is not confirmed zero intake. Mark incomplete days and keep them out of claims that require complete intake records.

**Acceptance:** Name-only custom food cannot masquerade as verified nutrition data. Genuine zero values remain representable. The user can explain why today's target changed and distinguish estimated targets from recorded intake. This plan makes no new medical or individualized dietary prescriptions.

### 6.11 Crew and sharing

**Evidence:** 03:51–03:55 and around 04:05; V26.

- [ ] **SOC-01 — Explain the signed-out value.** Give a small, clearly illustrative preview of what a Crew can do, with join/create/sign-in paths. Do not fabricate live users, testimonials, or activity.
- [ ] **SOC-02 — Verify participation consent.** Require explicit audience-aware choices for workout and PR sharing. Investigate the shown toggles without assuming they already publish while signed out.
- [ ] **SOC-03 — Centralize sharing privacy.** Reuse one preview and audience model across summaries, Crew, exports, and later program links. Keep private training data separate from a public program template.
- [ ] **SOC-04 — Handle unavailable states.** Test signed-out, no crew, invite failure, revoked access, offline, and duplicate-post retries without affecting local logging.

**Acceptance:** Saving a workout does not silently mean posting it. Users know the audience before publication. Crew availability never determines whether a local workout can be saved.

### 6.12 Settings, imports, and support

**Evidence:** 04:03–05:33 and 08:46–09:01; V16, V17.

Group durable settings into **Training and Gyms; Coach and Voice; Account and Crew; Preferences and Accessibility; Data and Privacy; Subscription and Support**. Session-specific choices remain accessible from Today/workout context.

Keep microphone recognition language separate from the app language. Keep speech transcription separate from Coach inference and training-data consent. “Recognition language: English” is preferable to “Listening in English” when the microphone is not active. Do not make an unqualified “most accurate” claim for a route without locale/device evidence.

- [ ] **SET-01 — Regroup settings.** Move existing rows into clear sections and preserve deep links. Avoid duplicating Gym Profile state across several independent toggles.
- [ ] **SET-02 — Separate constraint types.** Distinguish available equipment, movement preferences, temporary limitations, and daily recovery/stress. Show duration/scope of a temporary constraint without diagnosing an injury.
- [ ] **SET-03 — Review custom-exercise defaults.** Make muscle group, equipment, load convention, and aliases explicit during creation. Suggested mappings must remain reviewable; a test name alone does not establish anatomy.
- [ ] **SET-04 — Unify voice/Coach preferences.** Expose actual route, availability, selected language, cloud disclosure, and fallback behavior. Only show listening indicators when recording is actually active.
- [ ] **SET-05 — Protect consequential settings.** Show a scope preview for restart block, reset, delete, and similar actions. Preserve history unless that is the user's explicitly confirmed intent; inspect existing confirmations before adding duplicates.
- [ ] **SET-06 — Distinguish the two imports.** Label existing Strong/Hevy import as history import. Add program import separately under Program, using PRG rather than reusing history semantics.
- [ ] **SET-07 — Harden history import.** Test mapping, units, dates, duplicates, previews, partial failures, and staged commit/rollback. Show imported/skipped/review-required counts. Do not claim a live import was verified from the tour alone.
- [ ] **SET-08 — Improve feedback and diagnostics.** Show required fields and sending/success/failure states. Make attached diagnostics optional and inspectable; omit raw Health data, conversations, audio, and private training notes from ordinary logs.

**Acceptance:** Users can find Gym/time constraints without leaving the training flow. Every voice preference has a distinct meaning. Importing a history file does not activate a new program. Diagnostics do not become a hidden data-export channel.

### 6.13 Microcopy replacements

These are proposed strings; localize them and bind them to actual state.

| Current/ambiguous situation | Proposed copy |
|---|---|
| New user with no accepted past obligations | “Your first workout is ready.” |
| Weekly target not yet completed | “2 sessions remaining this week.” |
| Actual accepted session missed | “Tuesday's Full B wasn't completed. Review this week's options.” |
| Consequential “Do that” button | “Review schedule changes” or the exact authorized action |
| Focus expression | “One set at a time · 24 sets left” / “1 set left” |
| Flagged session | “Saved to History. Excluded from these calculations: …” |
| Sparse Recovery data | “Based on today's check-in. More entries will make the trend easier to interpret.” |
| Undefined Balance ratio | “Not enough recorded push and pull work to compare.” |
| New experiment | “Collecting results · no comparable follow-up yet.” |
| No meal records | “No meals logged. Intake may be incomplete.” |
| Inactive speech language setting | “Recognition language: English” |
| Equipment unknown | “Not linked to a machine. Keep this equipment's history separate?” |
| Stale Coach proposal | “Your workout changed. Review an updated proposal before applying.” |


---

## 7. All eight feature additions

These are complete additions to the current app, not replacements for the screen fixes. Each feature must use the shared state, interaction, permissions, and privacy contracts above.

### 7.1 EQP — Equipment Passport

**Extends:** Gym Profiles, exercise variants, plate inventory/calculator, progression, History, Watch.  
**Does not duplicate:** Equipment availability. This adds the identity and load meaning of the particular machine or setup.  
**Dependencies:** COR, shared load semantics, versioned persistence.

#### User flow

```text
Gym Profile -> equipment instance -> attainable loads and convention
            -> bind an exercise/setup -> prescribe a realizable target
            -> log normally -> retain that equipment's comparable history
```

A known binding adds no mandatory tap to ordinary logging. A new machine starts as a distinct context unless the user explicitly confirms a justified equivalence.

#### Proposed data

| Entity | Required semantics |
|---|---|
| Equipment instance | Gym ID, friendly name, kind, active/retired state |
| Load model | Versioned unit/domain, attainable values or increments, min/max, loading convention, progression direction |
| Exercise setup | Attachment, seat/pad settings, relevant exercise/variant, versioned notes |
| Equipment binding | Exercise slot to equipment/setup; preferred and actual selection |
| Set extension | Original load/unit, convention, equipment/load-model version, side and interpretation status |

Support per-hand, combined, plates-only, bar-included, per-side, assistance, and arbitrary machine-scale meanings where the existing engine can handle them. Higher assistance is not automatically harder. An arbitrary machine step is not automatically kilograms.

- [ ] **EQP-01 — Model and migrate.** Add equipment/load/setup references while keeping ambiguous legacy records explicitly unknown. Preserve original values and meaning.
- [ ] **EQP-02 — Build the inventory editor.** Add, rename, duplicate, configure, and retire instances. Support explicit attainable-value lists as well as regular increments and temporary unavailable weights.
- [ ] **EQP-03 — Integrate workout setup.** Show a compact equipment label and remembered settings, with a quick switch. Keep exercise-library definitions separate from equipment instances.
- [ ] **EQP-04 — Constrain prescriptions.** Reuse the plate solver and engine to choose realizable loads or permitted rep progression. Return a conflict when equipment and protected program rules cannot both be satisfied.
- [ ] **EQP-05 — Protect comparison history.** Partition incompatible records, label equipment-specific charts/PRs, and make load-convention corrections explicit, previewed, and reversible through recorded revisions.
- [ ] **EQP-06 — Complete lifecycle and device parity.** Test renamed/retired equipment, changed stacks, assistance, mixed units, old records, voice, Watch, offline, and simultaneous edits.

**Acceptance:** No impossible load is presented as available. Two cable stations do not silently share a performance baseline. A rename does not split a series, and retirement does not delete history. Changing today's setup never rewrites the interpretation of old sets.

### 7.2 REC — Recommendation evidence and outcome checks

**Extends:** Why cards, Coach explanations, engine evaluation, Progress, Recovery, Balance, experiments.  
**Does not duplicate:** Another AI summary. It records support before a recommendation and interprets the executed result afterward.  
**Dependencies:** COR metric/provenance rules; EQP improves comparability.

Separate **evidence support**, **prescription fit**, and **longer-term observations**. None is automatically proof that the recommendation caused progress.

#### Proposed records

```text
RecommendationSnapshot
  original target and issue time
  engine/policy/comparison versions
  input revisions and comparable past records
  missing information and evidence reasons
  authorization and relevant privacy classifications

RecommendationExposure
  original recommendation
  actually executed prescription
  followed | modified | notUsed | unknown

RecommendationOutcome
  source result revisions and evaluation policy
  eligible | notAssessable
  withinTarget | belowTarget | aboveTarget
  limitations and invalidation/supersession state
```

Use support labels backed by visible observations and rules, such as “Limited comparable history.” Do not display an LLM's self-confidence or a percentage probability that has not been calibrated against a defined task.

- [ ] **REC-01 — Capture decision snapshots.** Record the information available when a decision was issued. Prevent later/future history from leaking into historical replay.
- [ ] **REC-02 — Implement evidence gates.** Treat missing, stale, interrupted, and incompatible inputs explicitly. Apply these gates to sparse Balance/Recovery advice and existing progression rules.
- [ ] **REC-03 — Track actual exposure.** Distinguish accepting a suggestion from following it. A modified or unused recommendation is not automatically a success or failure.
- [ ] **REC-04 — Evaluate eligible outcomes.** Compare the appropriate executed target and observed result; mark outcomes not assessable when the conditions cannot support comparison.
- [ ] **REC-05 — Add compact user evidence.** Extend existing Why/action cards with support, limitations, and outcome details. Keep Health-specific local evidence separate from model context and ordinary sync.
- [ ] **REC-06 — Add internal review and recomputation.** Build deterministic replay, version comparisons, correction reasons, and deletion/history-edit invalidation. Preserve the original issued decision rather than retroactively improving its apparent accuracy.
- [ ] **REC-07 — Integrate experiments.** Reuse comparison rules and expose inconclusive results when capture, equipment, or protocol changes undermine an interpretation.

**Acceptance:** Unknown does not become zero. An LLM cannot approve its own evidence or outcome. A corrected history record supersedes derived evaluations without changing what was originally known. “Inconclusive” is a valid end state, not a forced keep/revert choice.

### 7.3 PRG — Coach My Program

**Extends:** Existing program roadmap, onboarding, exercise locks, adaptive engine, imports.  
**Does not duplicate:** Strong/Hevy historical-workout import. This imports intended future structure and rules.  
**Dependencies:** Shared revisions/actions; EQP and REC integration before broad release.

#### User flow

```text
Paste program / structured entry / supported template
 -> untrusted draft -> map exercises and units
 -> review sessions, weeks, targets, rest, and progression
 -> resolve unsupported rules -> choose adaptation permissions
 -> validate equipment and schedule -> preview -> activate
```

Provide an offline structured editor. Natural-language parsing may help draft a program, but it cannot silently invent rules, run imported scripts, or activate the result.

#### Permissions

| Mode | Permitted behavior |
|---|---|
| **Follow exactly** | Execute the original supported program rules, including their own progression; no extra unapproved adaptation |
| **Adjust my targets** | Also adapt load/reps within explicitly reviewed limits; protect structure/volume unless separately permitted |
| **Coach within boundaries** | Also adapt approved sets, substitutions, or scheduling dimensions within specific limits and locks |

A safety block can stop an operation; it is not permission to rewrite a protected program. A hard conflict requires an explicit choice.

#### Rule and model scope

Support a bounded schema for fixed prescriptions, double progression, percentage-of-explicit-baseline rules, existing effort-guided rules, and scheduled variations/deloads. Store immutable program versions, exercise slots, a versioned adaptation contract, an import draft, and a personal enrollment with equipment/baselines.

- [ ] **PRG-01 — Extend program versions.** Separate reusable structure from personal enrollment and preserve the versions referenced by completed sessions.
- [ ] **PRG-02 — Build the bounded compiler.** Validate supported rules and resource limits; reject unknown types, arbitrary code, unbounded expressions, and silent fallback rules.
- [ ] **PRG-03 — Build draft import and review.** Support text and structured entry, original-versus-interpreted fields, exercise mapping, unit ambiguity, private-source disclosure, and manual correction.
- [ ] **PRG-04 — Add adaptation contracts.** Implement the three modes, fine-grained permissions, clear scope, and versioned confirmation. “Follow exactly” must not freeze a program's own intended progression.
- [ ] **PRG-05 — Enforce every adaptive path.** Apply the contract to next-set targets, deloads, volume, plateau rescue, swaps, locks, missed workouts, Week Designer, and Coach actions.
- [ ] **PRG-06 — Complete lifecycle and security.** Support pause, duplicate, archive, restart, and edit-as-new-version. Treat embedded instructions as data, prevent automatic URL execution/fetching, and keep privately imported material private.
- [ ] **PRG-07 — Validate first-session execution.** Resolve personal baselines and equipment, preview the first session, and verify two successive sessions preserve the chosen permissions offline and online.

**Acceptance:** Unsupported or ambiguous rules block activation until resolved. Editing a program does not rewrite completed workouts. A user keeps their chosen structure without surrendering all control to the Coach. No PDF/OCR pipeline is required for this phase.

### 7.4 WKD — Week Designer, including calendar integration

**Extends:** Today, existing roadmap, time budgets, Gym Profiles, travel/crowd modes, missed-workout recovery.  
**Does not duplicate:** Reactive recovery after a missed workout. It plans the upcoming week before obligations become missed.  
**Dependencies:** COR schedule semantics; PRG permissions; EQP feasibility; REC snapshots.

#### User flow

Enter available windows, Gym Profile, time budget, other exercise if relevant, and protected priorities. Compare feasible scenarios showing actual sessions, estimated time ranges, planned sets, and explicit tradeoffs. Apply one only after confirmation.

Hard constraints include availability, protected program rules, equipment, active/completed sessions, and existing engine safety rules. Preferences such as convenience or preferred days are soft unless explicitly protected.

#### Planning status

```text
feasible(candidates, assumptions, tradeoffs)
infeasible(provenConflicts, reviewedRelaxationChoices)
searchLimitReached(bestFeasibleCandidate?, searchLimitExplanation)
needsInput(ambiguities)
```

Use a bounded deterministic search and stable tie-breakers. Do not equate a search timeout with proof that no solution exists, or a preference score with a medically optimal plan.

#### Calendar scope

Ship manual weekly planning first; calendar work remains included in this plan. Apple distinguishes calendar access modes: a user-mediated event editor can support event creation without broad read access, write-only access does not permit reading events, and reading/updating existing events requires the appropriate full access. Verify exact APIs in the shipping SDK. [S3]

Process selected-calendar busy intervals locally. Do not copy event titles, notes, attendees, or locations into the Coach or ordinary sync. Denied/revoked access returns to manual availability. Calendar changes create proposals rather than silently moving accepted training sessions.

- [ ] **WKD-01 — Build manual availability.** Support seven-day windows, Gym/time constraints, optional other activity, protected sessions, and reusable preferences.
- [ ] **WKD-02 — Implement the planning adapter.** Translate program permissions and existing engine limits into hard/soft constraints. Account for warm-ups, work, rest, setup, transitions, and unilateral timing in duration estimates.
- [ ] **WKD-03 — Generate and compare candidates.** Return the correct feasibility/search state and display actual changes. Only offer two/three/four-session alternatives when the contract allows them.
- [ ] **WKD-04 — Commit accepted revisions.** Preview without mutation; revalidate revisions at commit; preserve original accepted week and later amendments. Protect active/completed sessions.
- [ ] **WKD-05 — Integrate missed-workout recovery.** Use the same accepted-plan and permission model for future travel/crowd/time changes. Report original-plan and revised-plan adherence separately.
- [ ] **WKD-06 — Add scoped calendar access.** Separate calendar-aware planning from export; provide accurate purpose text and manual fallback. Keep busy-interval caching local, bounded, and expiring.
- [ ] **WKD-07 — Add export and reconciliation.** Track app-created events where authorized, prevent duplicate retries, surface external edits, and never modify unrelated events.
- [ ] **WKD-08 — Test time and conflicts.** Cover local versus fixed times, travel, daylight-saving changes, midnight, no availability, search caps, revoked permissions, and concurrent accepted-plan edits.

**Acceptance:** A user can plan the week offline. Every accepted plan passes hard constraints at commit. Calendar access denial does not block planning. No silent compressed make-up volume, automatic calendar rearrangement, or guaranteed future strength gain appears.

### 7.5 LIM — Set-limiter feedback

**Extends:** Set logging, notes, comparability, Coach memory, equipment setup.  
**Does not duplicate:** A daily soreness check-in. It explains one set's result.  
**Dependencies:** Set revisions, COR effort provenance, REC, PRG.

Offer optional reasons such as target muscles, grip, breathing, setup, technique uncertainty, interrupted set, other, or unsure. Treat pain/discomfort through a separate approved safety path, not as a normal invitation to optimize harder training.

**Proposed interaction limit:** At most one unsolicited clarification prompt per workout, suppressible by the user. This is a UX choice, not a physiological threshold.

- [ ] **LIM-01 — Add typed set feedback.** Store the specific set/revision, reason, optional note, provenance, edit/delete state, and named analysis-eligibility overrides.
- [ ] **LIM-02 — Add an optional entry.** Make feedback available in set details and only prompt contextually when useful. Skip must have no adherence/readiness penalty.
- [ ] **LIM-03 — Define bounded responses.** An interruption can offer exclusion from a named analysis; a setup issue can open Equipment Passport. One grip-limited set must not automatically replace an exercise.
- [ ] **LIM-04 — Preserve recorded work.** An analysis exclusion leaves the set in History and explains which calculations change. Recompute affected REC results after edits.
- [ ] **LIM-05 — Integrate memory carefully.** Repeated contextual signals can be summarized; durable memory still requires existing confirmation, provenance, expiry, conflict, and deletion controls.
- [ ] **LIM-06 — Test the safety branch.** Use reviewed safety copy for pain/discomfort, do not diagnose or prescribe rehabilitation, and do not turn pain into a push-through recommendation.

**Acceptance:** Feedback remains optional. One event cannot cause an unauthorized program change. An excluded interrupted set remains recorded. Correcting or removing feedback updates derived summaries.

### 7.6 GOL — Goal roadmaps and repeatable benchmarks

**Extends:** Existing Program roadmap, mesocycles, PRs, e1RM, Progress, Week Designer.  
**Does not duplicate:** A generic block timeline. It connects a measurable goal to a fair review.  
**Dependencies:** Equipment comparison, program versions, REC, accepted schedules.

Start with one active performance goal. Use an explicit baseline and measurement protocol. A review date is a decision point, not a guaranteed achievement deadline. Do not require maximal attempts or automatically add volume to chase a date.

- [ ] **GOL-01 — Add versioned goal/protocol records.** Store target type/value, baseline context, equipment, measurement method, review point, and lifecycle state.
- [ ] **GOL-02 — Build goal setup.** Connect the goal to the existing program/block, show estimated-versus-measured distinctions, and review the baseline before activation.
- [ ] **GOL-03 — Schedule optional benchmarks.** Use Week Designer/Today without silently adding sessions or overriding readiness, user preference, or program permissions.
- [ ] **GOL-04 — Reuse workout logging.** Capture execution conditions and deviations, compare only eligible results, and distinguish an equipment change from a true improvement on the same protocol.
- [ ] **GOL-05 — Add the review decision.** Show baseline, comparable observations, limitations, and continue/revise/change approach/defer choices. Every resulting plan mutation follows the shared confirmation contract.
- [ ] **GOL-06 — Protect history.** Version target edits, support pause/archive, and invalidate achievements/reviews when contributing attempts are corrected or deleted.

**Acceptance:** An e1RM estimate never masquerades as a measured benchmark. A changed machine does not create a false success. Deferring a review is supported without guilt or forced make-up training.

### 7.7 VOC — Conversational voice Coach

**Extends:** Existing speech adapters, Coach/RAG/actions, transcripts, routing.  
**Does not duplicate:** Voice commands that log sets.  
**Dependencies:** Stable context IDs, action proposals, privacy projections, cancellation.

Keep **Log a set** and **Ask Coach** separate. Preserve `VoiceCommandParser` or the repository's actual equivalent for deterministic logging. Models can explain or propose; they do not become the logging authority.

```text
idle -> permission -> listening -> transcribing -> thinking
     -> speaking -> ready for follow-up

Any active state -> cancelled / interrupted / recoverable error
Proposal -> visible preview -> explicit confirmation -> validated commit
```

Use conversation and turn IDs. A cancelled or superseded turn cannot later apply a stale action. In the initial turn-based experience, stop spoken output before recording the next turn to avoid self-transcription. Handle audio interruptions and route changes explicitly; archived Apple guidance documents the lifecycle concepts, but current SDK behavior must be tested on devices. [S6]

- [ ] **VOC-01 — Add separate entry and coordinator.** Make Ask Coach distinct from Log a set, with a testable state machine and explicit stop/cancel.
- [ ] **VOC-02 — Reuse speech capabilities.** Select existing routes by actual locale/device/assets/permissions/network capability. Show transcript and uncertainty; provide typed/manual fallback.
- [ ] **VOC-03 — Add concise spoken responses.** Keep visible text, stop/replay controls, useful follow-ups, and accessible controls. Do not require always-listening or full-duplex architecture.
- [ ] **VOC-04 — Expose narrow Coach tools.** Reuse approved reads and typed proposals. Bind changes to exact action/context revisions; initial conversational mutations require on-screen confirmation, not an ambiguous spoken yes.
- [ ] **VOC-05 — Harden audio lifecycle.** Test interruptions, headphones/Bluetooth changes, backgrounding, music, echo, asset unavailability, late callbacks, and repeated end-of-turn events.
- [ ] **VOC-06 — Enforce privacy and routing.** Do not persist raw audio in app files/logs/traces. Verify provider retention before making a no-storage claim. Never silently switch local-only audio to cloud; disclose that cloud speech includes what the user says.
- [ ] **VOC-07 — Add operational limits.** Use authorized backend credentials, authentication/entitlements as required, rate limits, cancellation, timeouts, bounded context, usage/cost counters, and a clear quota state. Never block saving a set because voice quota is exhausted.

**Acceptance:** “Why this weight?” cannot become a set log. No late response can mutate a cancelled turn. A voice outage preserves manual logging. No HealthKit details enter model context or spoken model answers under the existing privacy boundary.

### 7.8 SHR — Shareable adaptive program links

**Extends:** Program versions, imports, referrals, existing identity/backend, share sheet.  
**Does not duplicate:** Crew workout posts or CSV/PDF export.  
**Dependencies:** PRG structure/enrollment separation, EQP initialization, privacy projections.

Publish a reviewed program definition, not the author's training profile. Use unlisted links initially; anyone with the link can access the template. Do not call an unlisted bearer link private authenticated sharing.

#### Public projection

| May be published after review | Must stay private |
|---|---|
| User-authored title/description | Workout history and personal loads/baselines |
| Weeks, sessions, exercises, sets, rep ranges, rest | Actual gym/machine identity and setup notes |
| Supported progression rules | Health, recovery, body data, personal goals |
| Generic equipment requirements | Calendar, Coach memory, conversations, private notes |
| Suggested adaptation boundaries and version | Raw imported source material without redistribution rights |

A program requiring a personal load/baseline must publish a supported recipient-input requirement. Do not strip that field and leave a program that silently loses its meaning.

- [ ] **SHR-01 — Define an allowlisted template.** Separate the public schema from internal program, enrollment, and account objects. Validate bounded supported versions on client and server.
- [ ] **SHR-02 — Build publication review.** Sanitize, check completeness, show exact content, confirm distribution rights, and default to an unlisted link. A scanner for private text supplements the schema but is not the privacy boundary.
- [ ] **SHR-03 — Implement owner lifecycle.** Authenticate publishing/revocation without requiring all local training to use an account. Use high-entropy tokens, ownership checks, immutable versions, rate limits, reports, and cache-safe revocation.
- [ ] **SHR-04 — Add web/app routing.** Configure universal links and a web preview/fallback. Apple documents the app/domain association mechanism; verify the current deployment configuration. Provide reopen-after-install or an import code rather than assuming deferred linking always works. [S5]
- [ ] **SHR-05 — Personalize recipient import.** Open as a private draft; choose equipment, personal baselines, and adaptation permissions; review the first session; explicitly activate.
- [ ] **SHR-06 — Handle versions and revocation.** Reopening a link must not silently duplicate or replace a plan. Author updates require a new version; revocation blocks future fetches but cannot erase already imported copies.
- [ ] **SHR-07 — Secure and measure.** Test cross-owner access, malformed content, token exposure, cache behavior, stale imports, and duplicate requests. Reuse consent-appropriate referral attribution without exposing recipients' progress to the author.

**Acceptance:** Recipients never inherit the author's working weights or Health history. Opening a link alone never activates a program. Revoked links stop new server fetches, while existing private copies remain usable. There is no marketplace or automatic public program listing in this scope.

### 7.9 Prior-roadmap coverage map

| Previous scope | This plan's implementation home |
|---|---|
| Equipment Passport | EQP, COR-06/07, WKT-05 |
| Recommendation evidence/outcomes | REC, CHK-03, PRO-05, EXP-02 |
| Coach My Program | PRG, SET-06, existing roadmap integration |
| Week Designer and calendar | WKD, TOD-02/04/06, COR-03/08 |
| Set-limiter feedback | LIM, WKT effort/context work |
| Goals and benchmarks | GOL, PRO overview, existing block reviews |
| Conversational voice Coach | VOC, COA, SET-04 |
| Shareable adaptive programs | SHR, SOC sharing privacy, PRG versioning |
| Migrations/sync/actions/privacy | Section 8 and SYS tasks |
| Analytics, billing, website, release | Sections 9–11 and VAL/REL tasks |

All eight additions remain committed scope. Release order is not an instruction to omit the later work.

---

## 8. Architecture, persistence, and privacy

### 8.1 One mutation pipeline

```text
UI / typed command / voice / Watch / Coach / import / week preview
                         |
                    Typed intent
                         |
        Current context + permissions + privacy projection
                         |
          Deterministic engine and validation
                         |
        +----------------+----------------+
        |                                 |
  Valid proposal               Conflict / needs input /
        |                      unsupported / stale state
  Exact before/after                      |
        |                          Explain next choices
  Required authorization
        |
  Recheck entity and policy revisions
        |
  One local transaction: domain mutation + receipt
        |
  Permitted sync outbox / explicit publication
        |
  Eligible observed result -> derived evaluation
```

Already-authorized deterministic fast logging and policy-authorized routine progression can retain their existing low-friction path. A general adaptation permission is not authorization for an unrelated conversational mutation.

### 8.2 Proposal and confirmation contract

A proposal needs a stable ID, closed action type, explicit target IDs, base revisions, bounded canonical payload, payload digest, deterministic diff, policy revision, created/expiry time, authorization kind, privacy classification, and lifecycle status.

A confirmation must bind to the exact payload, targets, and revisions. Model text saying “the user approved” is never authorization. At commit, revalidate the session, equipment, program permissions, consent, and other affected revisions.

The same action ID must not have two domain effects. Persist the receipt with the mutation. A changed target invalidates the preview; regenerate it instead of applying an old instruction to new state.

### 8.3 Shared state and projections

| Boundary | Required behavior |
|---|---|
| Training/metric snapshot | Stable source revision and explicit eligibility/period semantics |
| Local engine context | Only the information needed for the current decision; preserve unknown/provenance |
| Model context | Permitted training data only; no Health-specific data under current policy |
| Sync payload | Existing opt-in plus allowlisted new entities/fields; no accidental general-context dump |
| Analytics | Coarse permitted events, not raw logs, notes, speech, health, or calendar data |
| Public template | Separate allowlisted program definition; no personal enrollment |
| Diagnostic export | User-initiated, reviewable, minimized and separately sanitized |

The public site says Health data is read on-device and never uploaded, and that the Coach does not see it. Preserve that boundary unless a separate explicit product/privacy decision changes it. Do not assume de-identification alone permits a new data flow. [S1]

Health-derived explanatory fields retain their classification. An approved future training prescription may be eligible for normal plan sync without carrying the underlying Health measurements or Health-specific explanation; review this projection deliberately.

### 8.4 Offline and sync

A local revision check is not a global lock across two offline devices. Reuse the actual sync conflict strategy, stable IDs, revisions, and tombstones.

Independent set additions can merge by identity. Conflicting edits to a program, load convention, or accepted week require deterministic handling and a user-facing decision where intent differs. Synchronize committed results; never replay an old natural-language command against a newer workout.

Feature-off behavior preserves history and already-started workout logging. A sharing outage must not invalidate imported private plans. A voice outage must not invalidate manual set entry.

### 8.5 Persistence and migration

Use additive, versioned schema changes and real persisted migration fixtures. SwiftData provides schema-versioning and migration mechanisms; adapt those to the actual repository rather than treating this plan as a replacement architecture. [S4]

Do not silently reset a failed store to an empty database. Do not downgrade a migrated store to roll back a feature. Use compatible forward fixes and disable new behavior independently of reading saved data.

### 8.6 Proposed logical ownership

| Responsibility | Suggested owner; reuse an existing equivalent |
|---|---|
| Recorded/planned/eligible totals | Shared training aggregate service |
| Load meaning and attainable prescriptions | Equipment and existing plate/progression services |
| Record comparability | Shared comparison service |
| Imported rule execution and permissions | Program compiler and adaptation policy evaluator |
| Weekly candidates and accepted plans | Week planning service |
| Evidence and observed results | Evidence service and outcome evaluator |
| Optional set feedback | Set feedback service |
| Goals and review state | Goal service |
| Voice turn lifecycle | Coach conversation coordinator |
| Sanitized publication and imports | Program share service |

These are responsibilities, not a requirement for ten new packages. Prefer small adapters and one source of truth.

### Implementation tasks

- [ ] **SYS-01 — Map the real repository.** Identify the engine, models, routes, views, localization, RAG/tools, memory, sync, speech adapters, Watch transport, billing, and tests. Record actual names and ownership.
- [ ] **SYS-02 — Establish shared contracts.** Agree on load meaning, session/metric scope, program permissions, comparison context, and action revisions before parallel feature branches change them.
- [ ] **SYS-03 — Harden action lifecycle.** Add bound confirmations, idempotent transactions/receipts, stale handling, cancellation, and typed conflicts through existing methods.
- [ ] **SYS-04 — Add privacy projections.** Implement separate local, model, sync, telemetry, diagnostic, and public serializers. Fail closed on forbidden fields and test actual outgoing payloads.
- [ ] **SYS-05 — Build migrations.** Test upgrades from each supported stored schema, interrupted migrations, storage failures, unknown fields, and recovery without data loss.
- [ ] **SYS-06 — Reconcile multi-device intent.** Test old clients, disconnected phone/Watch, duplicate and out-of-order messages, concurrent program/equipment edits, and tombstones.
- [ ] **SYS-07 — Add flags and entitlement boundaries.** Separate feature exposure from billing decisions; keep billing out of the pure engine. Protect active workouts and users' ability to read/export/delete their data.
- [ ] **SYS-08 — Add operational controls.** Use request IDs, bounded requests, timeouts, cancellation, quotas, sanitized errors, and a documented degraded state for each cloud feature.
- [ ] **SYS-09 — Build deterministic replay.** Use fixed clocks, seeded fixtures, explicit versions, stable ordering, and only contemporaneously available inputs. Replays must not pretend to reveal unobserved outcomes under another plan.
- [ ] **SYS-10 — Document deletion and rollback.** Cover source records, derived evidence, memory, voice text, program drafts, public links, caches, sync tombstones, and feature-off behavior.

**Acceptance:** Each committed action has valid authorization and one receipt. No forbidden field crosses a boundary. Existing workout/history access survives feature disablement. Two offline devices cannot silently reinterpret the same load or program rule without the defined conflict behavior.


---

## 9. Delivery sequence

These are dependency-ordered release units, **not delivery-date estimates**. All eight additions are included. Do not enable every engine change in one release simply because the complete scope will eventually be built.

### 9.1 Release map

| Release | Deliverable | Task groups | Required exit gate |
|---|---|---|---|
| **R0 — Correctness and legibility** | Rendered Focus count, readable Recovery/tool labels, reproduced state/eligibility/context fixtures, sparse-advice gates | SYS-01/02, COR, DSN-02, CHK-02/03, PRO-05; foundational QA | Visible defects resolved; recorded data preserved; state semantics documented and tested |
| **R1 — Core experience** | Cleaner onboarding, Today, workout, summaries, Coach, Progress, settings, Fuel, body and Crew states | Remaining DSN and screen task groups | Core tasks succeed without extra required logging steps; accessibility and permission fallbacks pass |
| **R2 — Equipment and evidence** | Equipment Passport plus inspectable recommendations/outcomes | EQP, REC, remaining required SYS work | Realizable loads, comparable history, evidence/exposure semantics, migration and sync tests pass |
| **R3 — Your program, your boundaries** | Reviewed program import and three adaptation modes | PRG, program-related SET/EXP/COA integration | Two-session execution works; all adaptive paths obey permissions |
| **R4 — Plan the real week** | Manual Week Designer, then its calendar extension | WKD, Today/roadmap integration | Feasibility states, accepted revisions, calendar privacy, denial and duplicate-export tests pass |
| **R5 — Better feedback and goals** | Set-specific limiters and repeatable benchmark reviews | LIM, GOL, experiment review integration | Optional feedback, valid comparisons, defer/inconclusive states, safe plan changes |
| **R6 — Spoken Coach** | Turn-based conversational voice on the existing Coach | VOC, COA/SET integration | Real-device audio, cancellation, confirmation, privacy and cost controls pass |
| **R7 — Shareable programs** | Reviewed unlisted templates and personalized recipient import | SHR, SOC/privacy/referral integration | No private enrollment leakage; ownership, revocation and app/web flows pass |
| **R8 — Consolidated release** | Full accessibility/localization, deletion, billing, measurement and public alignment | All outstanding QA, VAL, REL tasks | Recorded acceptance results for every promised feature; safe rollback and support paths |

Within R4, manual planning can release before calendar integration. Both remain required before claiming this roadmap's calendar scope complete. Within R0, the small visible rendering/layout fixes can ship while deeper suspected logic issues remain under controlled reproduction; do not claim those investigations are resolved until verified.

### 9.2 Parallel work

After the shared contracts stabilize, visual components and non-mutating views can proceed alongside equipment models and evidence replay. PRG's reviewed editor can be developed before all advanced engine integration is enabled.

After immutable program versions and permissions stabilize, Week Designer, goals, and template serialization can proceed separately behind disabled flags. Voice UI can use mocked responses during development, but that does not satisfy real-device or action-safety acceptance.

Assign one owner to shared schema/action changes. Separate branches must not independently invent incompatible load descriptors, program versions, metric scopes, or privacy serializers.

### 9.3 Rollout strategy

Use the existing release infrastructure: internal fixtures, internal device testing, an opt-in cohort, a limited release, and wider exposure after observing the predefined metrics and failures. Flagging and entitlements remain independent.

A kill switch disables new generation or entry points—not the ability to read completed history, finish a started session safely, or export/delete personal data. Document the specific degraded mode for each feature before rollout.

### 9.4 Dependency overview

```text
Repository map + shared state + privacy/action contracts
       |
       +--> visible fixes and adaptive design components
       |
       +--> Equipment Passport ----+
       |                           +--> comparable evidence/outcomes
       +--> REC snapshot core -----+
       |
       +--> Program versions and permissions
                    |
                    +--> Week Designer --> Calendar extension
                    +--> Goals and benchmark reviews
                    +--> Shareable program templates
                    +--> bounded set-limiter responses

Existing Coach + shared actions + permitted evidence --> Voice Coach

QA, accessibility, privacy, billing, and measurement apply throughout.
```

### 9.5 Risks to track

| Risk | Mitigation |
|---|---|
| Dashboard “consistency” destroys meaningful eligibility distinctions | Named metric scopes and readable explanations; retain raw recorded work |
| New missed-workout rules rewrite old training history | Separate accepted obligations from recorded sessions; explicit enrollment/date fixtures |
| A UI context mismatch becomes a wrong set or calculator action | Explicit target IDs and context labels across every entry path |
| Machine metadata corrupts old progress | Version load meaning; preserve original entries; explicit corrections |
| More features slow basic logging | No new mandatory known-equipment step; optional feedback; local save path independent of cloud |
| Sparse-data advice sounds more certain than evidence | Coverage states, evidence gates, non-causal wording, inconclusive outcomes |
| Imported program rules lose user intent | Reviewed compiler, explicit permissions, typed conflicts, immutable versions |
| Calendar/voice expands sensitive data collection | Separate consent and payload projections; denied/local-only paths |
| Share links expose personal information | Public allowlist, exact review, server validation, owner checks, token hygiene |
| A disabled feature makes existing records unreadable | Additive schemas, compatibility tests, feature-off drills, forward repair |

---

## 10. QA fixtures and release tests

### 10.1 Recreate the recording's important states

Use synthetic data, a fixed clock, and deterministic IDs. Store fixture definitions in the repository; do not ship test names or test-only records into real-user analytics.

| Fixture | Setup | Expected assertions |
|---|---|---|
| **F01 — Fresh Saturday enrollment** | New store; three-session target; enroll Saturday; no prior accepted schedule | No retroactive missed sessions; clear first-session state |
| **F02 — Flagged partial session** | First session has two sets and 1,024 kg recorded volume; apply the named exclusion policy | History retains it; every metric follows its stated scope; no silent deletion |
| **F03 — Three-session reconciliation** | Add sessions with 585 kg and 480 kg to F02 | All-recorded volume is 2,089 kg; an explicit eligible-only scope can be 1,065 kg; labels explain the difference |
| **F04 — Planned versus recorded** | Save a small partial session; separately complete an approved Minimum Effective Workout | Partial, planned completion, and valid minimum work follow documented distinct rules |
| **F05 — Cross-exercise command** | Back Squat visible; log a Deadlift set through typed/voice paths | Correct target saved once; receipt names it; timer/calculator disclose their own context |
| **F06 — Focus counts** | Zero, one, many, and changed set totals; repeat after resume and in each locale | Correct plural/count; no source expression or negative display |
| **F07 — Sparse evidence** | One check-in; little recorded push/pull work; new experiment with no follow-up | Coverage shown; undefined ratio unavailable; no false experiment effect or strong unsupported advice |
| **F08 — Effort provenance** | Leave default/target effort untouched; explicitly report it in a second case | Unknown and reported effort remain distinct through engine and analytics projections |
| **F09 — Food unknown/zero** | Name-only food; intentionally zero-calorie water; known serving nutrition; no logged meals | Missing values remain unknown; real zero remains valid; no-meals day is not confirmed zero intake |
| **F10 — Decimal and duration formatting** | Body mass 82.5; kg/lb; decimal comma; sub-minute session | Original precision retained; same-field formatting consistent; short duration not misleading |
| **F11 — Week and time boundaries** | Calendar week differs from program week; travel; midnight; DST; history edit | Correct labels and stable accepted obligations; no accidental retroactive misses |
| **F12 — Long labels and large text** | Recovery/tool rows; longest supported translations; small device; accessibility sizes | No word fragmentation, clipped controls, hidden last row, or inaccessible action |
| **F13 — Equipment domains** | Two cable stacks; per-hand dumbbells; assistance; machine steps; unavailable increment | Valid attainable targets; no false merged PR; correct progression direction |
| **F14 — Program permissions** | Same program under all three modes; conflicting locks/equipment/time | Every adaptation path follows the active contract; conflicts are visible |
| **F15 — Stale confirmation** | Preview change; alter workout/program/Gym/consent on another path; confirm old card | Old proposal cannot apply; updated preview required |
| **F16 — Duplicate/reordered events** | Double tap, repeated voice response, Watch replay, out-of-order sync | One committed effect per action; no lost independent sets |
| **F17 — Calendar access** | No permission, write-only, full access, revocation, external event edit | Only supported operations occur; manual fallback; no unrelated event edits or duplicate exports |
| **F18 — Voice interruption** | Cancel during transcription/thinking; interrupt audio; change Bluetooth; go offline | No late mutation, surprise listening, lost set, or unapproved cloud fallback |
| **F19 — Share security** | Malformed template, unsupported version, other owner, revoked token, stale cache | Safe failure; no cross-owner mutation/private projection; imported copies handled honestly |
| **F20 — Migration/rollback** | Upgrade each supported old store; interrupt; flag off after using new entities | No silent reset; history readable; active workouts remain saveable |
| **F21 — Subscription transition** | Trial ineligible, purchase pending, restore, offline entitlement, expiry mid-session | Accurate offer; safe current-session saving; data access preserved under documented policy |
| **F22 — Deletion propagation** | Delete source set, feedback, Health permission, memory fact, voice text, goal, share | Correct local/remote/derived cleanup and invalidation; no retained inappropriate payloads |

Volume numbers in F02/F03 reproduce the video's visible arithmetic only. They are test inputs, not a rule for classifying valid or invalid training.

### 10.2 Required test layers

| Layer | Coverage |
|---|---|
| Unit and property tests | Load domains, attainable values, date semantics, eligibility, permissions, bounded compiler, comparability, action idempotency |
| Persistence/integration tests | Actual schema upgrades, transactions, receipts, deletion, invalidation, multi-device conflicts |
| UI/snapshot tests | All critical flows and state variants; rendered labels, adaptive layouts, keyboard/safe-area interaction |
| Accessibility tests | VoiceOver order/labels, large text, touch targets, non-color status, reduced motion, functional alternatives to maps/charts |
| Physical-device tests | Microphone/assets, audio interruptions, Bluetooth, Watch, background behavior, system permissions, actual frame responsiveness |
| Backend/security tests | Authorization, rate limits, sanitized projections, token/revocation behavior, malformed import/share payloads |
| Privacy tests | Forbidden-field absence in real test requests, logs, crash attachments, analytics, notifications, sync and public templates |
| Regression tests | Existing onboarding/import, logging, deloads, substitutions, RAG/memory, exports, localization, light/dark, purchases and offline flows |

A simulator test is not evidence of physical-device audio behavior. A frame review is not a performance benchmark. A working mock is not proof that a provider retains no audio.

### 10.3 Initial engineering targets

These are **proposed targets**, not measured current performance. Confirm them on the oldest supported practical test device and a production-sized synthetic store.

| Path | Initial target or measurement |
|---|---|
| Local set save and acknowledgement | p95 below 300 ms, independent of network/model availability |
| Known-equipment lookup and load resolution | p95 below 100 ms after context is loaded |
| Common weekly plan search | p95 below 1 second; bounded, cancellable foreground search with an explicit capped-search state |
| Summary and History consistency | Same committed snapshot; no unresolved stale totals after reconciliation |
| Voice | Measure end-of-turn to first useful response by route/device/locale; immediate visible processing/cancel state |
| UI readability | Zero reproduced clipping/word-fragmentation defects in the supported test matrix |
| Interaction burden | Known-equipment set logging requires no additional mandatory tap compared with the validated baseline |

Use supported background opportunities for catch-up, but reconcile on foreground and relevant actions too. Correct training state must not depend on an OS background task executing at an exact moment.

### QA implementation tasks

- [ ] **QA-01 — Commit fixture suite.** Implement F01–F22 with stable IDs, clocks, source revisions, and expected metric scopes. Mark test/demo data so it never enters real-user product metrics.
- [ ] **QA-02 — Add invariant/property tests.** Generate bounded loads, constraints, revision orders, repeated actions, and supported program rules. Keep reproducible seeds and minimized failing cases.
- [ ] **QA-03 — Run real-store migration/sync tests.** Cover upgrades, offline clients, older app versions, Watch, deletion, interruption, and feature-off behavior—not only in-memory models.
- [ ] **QA-04 — Build UI state coverage.** Test all essential screen states, small devices, both themes, keyboards/sheets, largest supported text sizes, and supported languages.
- [ ] **QA-05 — Run physical-device testing.** Record actual device/OS/locale and results for speech, audio, Watch, backgrounding, permissions, and performance.
- [ ] **QA-06 — Audit payload boundaries.** Inspect test traffic and logging for Health, calendar, audio, transcripts, private notes, imported source text, account IDs, and share-token leakage.
- [ ] **QA-07 — Exercise adversarial/stale flows.** Test prompt attacks, malicious program text, replayed proposals, stale confirmations, cross-owner shares, cancelled voice turns, and revoked permissions.
- [ ] **QA-08 — Perform recovery drills.** Disable each feature after use, simulate outages and subscription transitions, exercise deletion/recomputation, and demonstrate a safe forward-repair path.

**Release blocker:** Any known lost training data, unauthorized mutation, private-data exposure, cross-owner access, or reproducible wrong-target logging/calculator action blocks the affected release. A passing test suite reduces risk; it does not prove production risk is zero.

---

## 11. Usability validation and measurement

### 11.1 Test the actual jobs

Recruit a small formative group of representative lifters spanning new users, history importers, own-program users, and people who switch gyms. This is usability discovery, not a statistically representative outcome study.

Give participants tasks without teaching the proposed UI first:

| Task | Observe |
|---|---|
| Find and start today's workout | Whether they identify the primary action, session, equipment and time constraints |
| Explain two different dashboard totals | Whether they understand recorded versus calculation-eligible work without assistance |
| Log a set and correct an error | Steps, uncertainty, wrong exercise/load meaning, and recovery |
| Log a different exercise by text | Whether the receipt, timer, and calculator context remain understandable |
| Finish a partial session | Whether they know what was saved and what remains planned |
| Ask why a target changed | Whether they find the explanation and distinguish proposal from applied change |
| Change gym or time budget | Discoverability and scope understanding; no unintended future-plan edits |
| Find History and Recovery | Whether the tool hierarchy works without repeated scrolling/searching |
| Bring an existing program | Mapping/permission clarity and first-session confidence |
| Plan a busy week | Tradeoff comprehension, conflict handling, and acceptance intent |
| Review an experiment with little data | Whether they understand “collecting” or “inconclusive” instead of assuming no effect |
| Share a program | Whether they understand what is public and what the recipient personalizes |

Record failures and explanations, not just task completion time. Do not count participants' success after heavy facilitator guidance as an unassisted success.

### 11.2 Product measures

Define windows and cohorts before evaluating changes. Avoid treating everyday app opening or long chat sessions as the product's main success.

| Measure | Proposed definition / caution |
|---|---|
| First-workout activation | New eligible users who save a valid first workout in a defined observation window; retain approved minimum-workout semantics |
| Second-workout completion | Users with a second valid workout within 14 days of their first, divided by users with a fully observed 14-day window |
| Four-week training retention | Users with valid recorded training on days 22–28 after first workout, divided by fully observed first-workout users |
| Wrong-target/correction incidents | Confirmed correction categories per logging/action volume; manual edits are not automatically engine errors |
| Dashboard comprehension | Formative task success explaining scopes and next actions; do not infer comprehension from screen views |
| Baseline weekly adherence | Work completed against the originally accepted week, with explicit session-completion semantics |
| Revised-plan adherence | Work completed against the latest accepted revision; show revision context alongside baseline adherence |
| Recommendation evaluability | Outcomes that can be assessed divided by recommendations due for assessment |
| Prescription fit | Eligible results within their defined target; stratify by type and actual exposure, not acceptance alone |
| Program import activation | Started drafts reaching reviewed activation; separately report unresolved and abandoned drafts |
| Voice resolution | A predefined completed/helpful interaction signal per started conversation; silence alone is not satisfaction |
| Share activation | Valid recipient imports leading to a first and then second workout; exclude bot/link-preview fetches |
| Paid conversion | Fully observed eligible trial/new-user cohort becoming paid; define restores, refunds and renewals separately |

No percentage retention improvement or revenue uplift is promised by this document. Establish a baseline and the minimum improvement worth shipping before evaluating a change.

### 11.3 Telemetry rules

Use the existing analytics provider and consent model. Prefer events such as `workout_saved`, `workout_save_failed`, `metric_scope_opened`, `proposal_reviewed`, `proposal_stale`, `program_import_reviewed`, `week_plan_accepted`, `voice_turn_resolved`, and `template_imported` with bounded, non-sensitive categories.

Do not send exact loads, meal contents, raw Health inputs, limiter/pain descriptions, equipment names, calendar titles, notes, conversations, transcripts, audio, or imported program text as ordinary event properties. Potentially sensitive derived categories still require privacy review; keep a metric local or omit it when necessary.

Offline events retain their timestamp and deduplicate by ID. Separate operational quota/billing records from optional product analytics. Exclude demo/test records and incomplete observation windows.

### 11.4 Paid-product and public-message alignment

The inspected public homepage still describes free launch access, a later Pro plan, and forthcoming App Store availability, while the recording shows an in-app trial/paywall surface. This is a **messaging verification task**, not proof of the actual release or billing configuration. Align the website, store listing, trial offer, and shipped feature availability before public rollout. [S1]

Keep current pricing and entitlements as the source of truth. Do not introduce one paywall for each new feature. Explain the paid value through actual jobs: use your own program, train on your real equipment, plan your week, and understand the Coach's decisions.

### Validation and release tasks

- [ ] **VAL-01 — Establish baselines.** Record existing core-flow steps, failure categories, metrics and eligibility definitions before comparing releases.
- [ ] **VAL-02 — Run formative usability.** Test the jobs above with realistic synthetic scenarios, capture unassisted outcomes, and prioritize repeated confusion.
- [ ] **VAL-03 — Implement safe event schemas.** Version allowed properties, consent checks, deduplication, test-data exclusion, and deletion behavior.
- [ ] **VAL-04 — Build cohort queries.** Use fully observed windows, consistent completion definitions, actual feature exposure, and baseline/revised-plan distinctions.
- [ ] **VAL-05 — Review quality and cost together.** Inspect retained training, corrected mistakes, recommendation limitations, failures, voice cost, and paid conversion; do not optimize one in isolation.
- [ ] **REL-01 — Verify scope completeness.** Record acceptance evidence for every screen change and all eight additions, including calendar integration. No inferred completion from a screenshot or class definition.
- [ ] **REL-02 — Complete the supported device matrix.** Accessibility, localization, light/dark, migrations, Watch, interruptions, permissions, offline, and performance results are recorded.
- [ ] **REL-03 — Complete security/privacy review.** Payload audits, deletion drills, ownership tests, provider-retention verification, and public-link behavior pass.
- [ ] **REL-04 — Verify billing and continuity.** Check trial eligibility, localized pricing, purchases, restore, expiry, pending states, offline entitlements, and active-session protection using the existing billing stack.
- [ ] **REL-05 — Align public claims.** Update website/store/privacy/permission copy to match the actual released build and data flows. Do not advertise proposed features as shipped.
- [ ] **REL-06 — Prepare operations.** Record feature flags, kill switches, incident ownership, sanitized monitoring, quota alerts, forward repair, support instructions, and rollback/degraded behavior.

---

## 12. First implementation package and agent handoff

### 12.1 Start with these pull requests

These are small ordered packages, not calendar estimates. Keep unrelated changes separate so failures are attributable.

| PR | Scope | Demonstration required |
|---|---|---|
| **PR 1 — Baseline map and fixtures** | SYS-01/02, initial QA-01; reproduce V01/V02/V04/V05/V10 | Actual source paths, current predicates, fixture outputs and screenshots; no unsupported root-cause claims |
| **PR 2 — Focus and layout fixes** | COR-02, DSN-02, CHK-02, narrow Progress rows | Count/plural tests and native screenshots across text sizes/locales; no unrelated engine changes |
| **PR 3 — State and metric semantics** | COR-03/04/05/08 with F01–F04/F11 | Recorded versus eligible values reconcile; new enrollment is not retroactively penalized |
| **PR 4 — Action context and input meaning** | COR-06/07/09, WKT-02/03/04/05 | Cross-exercise logs, calculator targets, effort provenance, local save receipts and retries are correct |
| **PR 5 — Today and summary hierarchy** | TOD, SUM; shared components as needed | Next action, constraints, saved work, eligibility, and next-step comprehension pass formative tasks |
| **PR 6 — Progress and advice states** | PRO, CHK-03/04, EXP-01/02, REC foundation | Sparse history and new experiments show limitations; no false ratio or effect claim |

Continue with the remaining R1 screen improvements, then the equipment/evidence/program sequence. Do not begin a new architecture migration merely to make the proposed names in this document literal.

### 12.2 Pull-request template

```markdown
## Scope
Task IDs:
Video evidence IDs/timestamps:
User outcome:
Existing code reused:

## Changes
Actual files/modules:
Domain and schema changes:
Engine/permission changes:
UI and localization changes:
Backend/transport changes:

## Compatibility
Historical records and migrations:
Offline and Watch behavior:
Older-client/sync behavior:
Feature-off and entitlement behavior:

## Evidence
Acceptance criteria demonstrated:
Test/build commands actually run and results:
Fixture IDs:
Physical-device checks performed:
Accessibility/localization checks:
Privacy projection review:
Performance measurements, when relevant:

## Release
Flag and exposure plan:
Known limitations and unresolved investigations:
Rollback/degraded mode:
Data repair, if applicable:
Next unblocked task:
```

### 12.3 Coding-agent instruction block

```text
Use REGULIFT_VIDEO_AUDIT_AND_IMPLEMENTATION_PLAN.md as the roadmap.
Implement the selected task/PR only; do not attempt all tasks in one change.

First map the actual repository and verify the relevant recorded issue or
existing capability. Proposed names are not evidence that types already exist.
Differentiate observed defects from investigations and new design decisions.

Reuse the existing SwiftData/offline architecture, deterministic programming
engine, VoiceCommandParser or actual equivalent, RAG, action validation,
Coach memory, Gym Profiles, subscriptions, sync, Watch, and UI components.

Preserve recorded history and original load meaning. Do not remove eligibility
checks merely to make totals match. Make scope explicit. Unknown is not zero;
a remaining session is not automatically missed; an accepted suggestion is
not proof it was followed; correlation is not proof of coaching effectiveness.

Bind every action to explicit context, permissions, and revisions. Mutations
must use the shared validated commit path and appropriate authorization.
Never let a model write state, approve itself, or replay a stale/cancelled turn.

Preserve the Health-data boundary and separate local/model/sync/telemetry/public
projections. No raw sensitive data in ordinary logs or analytics. Verify actual
provider retention rather than claiming no storage from client code alone.

For each change, add relevant fixtures and tests, implement a complete vertical
slice, run available build/test commands, and report actual results only.
Do not claim physical-device testing from simulator results or performance
measurements from the supplied recording.

Do not add a vendor, database, minimum-OS requirement, price change, permanent
free tier, video feature, or broad new product category without a separate
explicit decision. Keep feature flags independent of entitlements.

Leave a task unchecked when acceptance has not been demonstrated. Report
changed files, behavior, compatibility, privacy, tests, remaining uncertainty,
and the next unblocked task. Preserve safe read/log behavior when a feature
is disabled or a cloud service is unavailable.
```

### 12.4 Definition of done

A task is done only when the intended behavior exists in the connected user flow, the persisted state is correct, the relevant tests pass, and compatibility/privacy/recovery behavior has been demonstrated. A screenshot, model class, mock response, or compiling view is not sufficient on its own.

For a suspected issue, completion can be a documented reproduction showing the existing behavior is correct, plus any needed label/test improvement. Do not force a logic change merely because the original audit listed an investigation.

---

## 13. Sources and verification boundaries

### 13.1 Primary product evidence

**Video source:** `regulift-full-feature-tour.mp4`, provided by the user. Evidence IDs V01–V27 and the timeline in Section 3 identify the relevant frames. The file is approximately 10:21, portrait 1170 × 2532 at 30 frames per second, and has no audio stream. No external screenshot package is required to use this plan; reopen the supplied video at the stated times.

**Baseline:** The user's September 18, 2026 feature inventory and the prior `REGULIFT_IMPLEMENTATION_PLAN.md`. The prior file's eight additions and shared safeguards are incorporated here; it need not be opened to follow this roadmap.

**Interpretation:** Product choices, proposed entity names, design tokens, metrics, priorities, release order, and acceptance tests are recommendations. They are not claims about repository code, a clinical validation, measured business outcomes, or completed implementation.

### 13.2 External references

Retrieved September 19, 2026. Historical Apple sources below support architectural concepts; verify exact APIs, permissions, availability, and behavior against the actual shipping SDK and supported devices before implementation.

| Ref | Primary source | Use |
|---|---|---|
| **S1** | [ReguLift public website](https://regulift.app/) | Public Health/Coach boundary and launch/pricing-message verification; not a substitute for repository or billing inspection |
| **S2** | [W3C — Understanding Contrast (Minimum), WCAG 2.2](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) | The explicitly chosen contrast-quality benchmark; actual native colors must be measured |
| **S3** | [Apple — Discover Calendar and EventKit, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10052/) | Permission-scoped calendar creation, reading, and update design |
| **S4** | [Apple — Model your schema with SwiftData, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10195/) | Versioned schema and migration planning |
| **S5** | [Apple — Support Universal Links, documentation archive](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppSearch/UniversalLinks.html) | Associated app/domain configuration and web fallback |
| **S6** | [Apple — Responding to Interruptions, documentation archive](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioInterruptions/HandlingAudioInterruptions.html) | Audio interruption/recovery concepts; validate current behavior on devices |

### 13.3 Not verified by this review

No source repository, database, production telemetry, provider contract, billing configuration, physical device, or deployed backend was accessed. Voice recognition quality, regular Coach answer correctness, full RAG retrieval, memory mutation details, Watch synchronization, actual offline failure behavior, completed experiment outcomes, and production migration safety were not established by this recording.

The video cannot establish exact native contrast ratios, touch-target dimensions, runtime latency, causes of Home Screen transitions, or whether an apparently odd value is stored incorrectly. Investigations in this plan intentionally preserve those distinctions.

---

**Implementation order:** Fix visible rendering and state clarity → simplify the core screens → add equipment and evidence depth → support users' programs and real weeks → add bounded feedback/goals → spoken Coach → shareable programs → complete release verification.

**Product standard:** More capability should make the next training decision clearer—not make the user inspect more cards, settings, or unexplained numbers.

[S1]: https://regulift.app/
[S2]: https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
[S3]: https://developer.apple.com/videos/play/wwdc2023/10052/
[S4]: https://developer.apple.com/videos/play/wwdc2023/10195/
[S5]: https://developer.apple.com/library/archive/documentation/General/Conceptual/AppSearch/UniversalLinks.html
[S6]: https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioInterruptions/HandlingAudioInterruptions.html
