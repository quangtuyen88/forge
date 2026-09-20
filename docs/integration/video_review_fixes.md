# Full feature tour — findings fixed

**Date:** 20 September 2026  
**Source:** `docs/REGULIFT_E2E_VIDEO_REVIEW_GOAL.md`, audit of `regulift-full-feature-tour.mp4`.

Release slice **A — correctness baseline**. Every row names the actual defect, the actual
fix and the test that holds it. Nothing here changes a training rule: the engine decides the
same loads it decided before, and the screens stop claiming more than the log supports.

## F01 · G01 — effort is an observation, not a field

`LoggedSet.rpe` always holds a number: the plan's target sits in it until the lifter changes
it. Three readers averaged that field and reported the result as the lifter's own effort, so
two sets logged without touching RPE came back as **Avg RPE 8** and *"RPE on target across 2
sets"* — the plan grading itself.

| Where | Before | After |
|---|---|---|
| `ForgeCore/Debrief.swift` | averaged every set | `DebriefSet.effortReported`; only rated sets count. Zero rated → *"Effort not recorded for these N sets."* Partial → the claim plus *"RPE recorded for 1 of 3 sets."* |
| `App/Forge/HistoryView.swift` | `sets.reduce(rpe) / count` | rated sets only; none rated shows `—` / *not recorded*, partial shows *"1 of 3 sets"* under the value |
| `App/Forge/MetricGrid.swift` | value only | `MetricItem.caption` carries the coverage next to the number |

Tests: `DebriefTests` (3 new), `SessionClaimsTests` (2).

## F02 · G02 — the plate calculator reads one identity

`focusedKg` and `platesLbUnit` were **global last-logged** state, while the sheet's exercise
came from the slot on screen. A typed `deadlift 60x8 @8` with Lunge open produced a Lunge
card, Bodyweight equipment, a 60 kg target and a 20 kg bar — three different sources in one
sheet.

- `platesTargetKg` / `platesUsesLb` now read the open slot's own entered load and unit.
- `focusedKg` and `platesLbUnit` are deleted; there is no global load left to cross-read.
- `platesAreLoadable` is true only for a barbell. Bodyweight, dumbbell, machine, cable and
  band movements get their loading convention stated instead of a per-side prescription they
  cannot honour (`plates.notLoadable`).

## F06 · G04 — an empty week is not a finished week

A week with nothing scheduled rendered *"Nothing left on this plan"* over a green
**0 of 0 planned sessions done** — praise for work that was never scheduled.

- `WeekPlanTodayStatus.countsLine` returns *"No sessions scheduled this week"* when
  `scheduled == 0` rather than a completed meter.
- `planRestCard` splits the two weeks it used to merge: *"No sessions planned this week"* with
  **Plan this week** (`today.planWeek`), against *"Nothing left on this plan"* with
  **Open the week designer** for a week that really is finished.

## F08 · G05 — the brief names the change

*"A change to your plan was committed"* describes a storage event. `WeekBriefFact` now
carries `exerciseName` and `isRealChange`, and the brief reads:

- a real before/after → **"Next Bench Press: 82.5 → 80."**
- an exercise with no prior value → **"Bench Press changes next session."** (a starting target
  is not an improvement)
- no exercise identity, or an unreviewed reason code → **"Your plan changed for next week.
  Open the changes to see what moved."**

Every value is read from the committed decision record. Tests: `WeekBriefTests` (5 new).

## F05 · G03 — one duration, written one way

The same short session showed 0 min on the summary and 1 min in History. `SessionMath` now
owns `totalSeconds` and `durationText`, `SessionSummaryView.durationText` applies the same
rule, and a session under a minute reads **Under 1 min** instead of rounding in two
directions. No elapsed time is `—`, never `0`.

## F19 · G13 — Fuel asks before it accuses

The new-food form opened with a red error banner over an untouched form while Save looked
active. Guidance is now neutral until the lifter types or taps Save; Save dims when it cannot
proceed and carries a hint saying why. No nutrition formula changed.

## F04 · G03 — one definition of "eligible"

Not deferred after all: the review's own evidence (Balance *"2 eligible sessions · 1 eligible
set"* beside Overview's *"1 eligible workout"*) proves the predicate has two implementations,
which is a source fact, not something a fixture is needed to discover.

| Surface | Predicate it used |
|---|---|
| `BalanceRadarView:30` | `completed` only — so a session the plausibility guard excluded still raised the session count while contributing zero sets |
| `ProgressView:353` | `verified && completed` |

`[WorkoutSession].analysisEligibleSessions` (`App/Forge/Models.swift`) is now the single
predicate — finished **and** readable — and both surfaces call it. Disagreement is no longer
possible rather than merely detectable, the same discipline `PlanRevision` uses.

## Guarding the fix

- `App/Forge/DemoSeed.swift` seeds `effortReported: true`. Without it every demo screen — and
  the feature tour that produced this audit — would read "effort not recorded", which is true
  of the fixture and false about the lifter it portrays.
- `App/Forge/HistoryView.swift` explains the dash: *"RPE starts on your plan's target. Only
  sets you rated yourself count toward effort."* An honest empty state that does not say why
  reads as lost data.
- `scripts/check-localization.py` + `make check-l10n` compare the format-token multiset of
  every localization against its source key. It found five live Vietnamese strings that had
  silently dropped a `%@` — including `Day %lld of %lld · %lld comparable set%@` — where the
  missing argument shifts every later one. All fixed; 1,034 localizations now pass, and
  `make test` runs the check first.

## The engine reads the same field — now measured

The display layer stopped reading unrated effort as an observation. The engine had not:
`Autoregulation.signals` compares `SetLog.rpe` against the same target the field was
pre-filled from, so an unrated set agrees with the plan by construction and the loop closes
with no feedback in it.

No training rule changed. Instead the divergence is now measurable:

- `SetLog` carries `effortReported` (defaulting to `true`, so existing callers and fixtures
  keep their meaning) and `reportedRPE`. Rows written before the flag existed decode as
  reported — guessing otherwise would rewrite history.
- The six app call sites that build a `SetLog` from a `LoggedSet` now pass the real flag, so
  the measurement reflects real data rather than a default.
- `ForgeCore/EffortDivergence.swift` runs `Autoregulation.signals` twice — once over the
  field as stored, once over rated sets only — and reports every muscle where the two
  conclusions differ, plus how many counting sets had no report behind them. Pure: no clock,
  no storage, nothing applied.
- `PlanAuditView` surfaces it only when it is true: *"N of your recent counting sets carry
  the plan's target rather than a rating you gave."*

What the tests establish (`EffortDivergenceTests`, 10 cases):

| History | Today's verdict | Rated-only verdict |
|---|---|---|
| Two unrated sets at target | `onTarget` | no signal — **diverges** |
| Two unrated sets at target, top of rep range | `easy` → adds volume | no signal — **diverges** |
| Rated sets at RPE 9.5 | `overreached` | `overreached` — clean |
| Fully rated history | any | identical — clean |

So unrated sets do not merely pad an average: at the top of a rep range they manufacture the
`easy` verdict that **increases weekly volume**. What progression should do with no effort
signal — hold, fall back to reps, or refuse to progress — is a training-rule decision and
gets its own reviewed change, now argued from a measured delta.

## Not in this slice

| Finding | Why |
|---|---|
| F07 active plan source | Same: the recording crosses a relaunch, so propagation has to be reproduced inside one fixture |
| F14/F27/F28 Progress + Timeline hierarchy | Release slice B; presentation work with no correctness claim behind it |
| F16/F12 Coach coverage | Needs recorded runs with assertions, not another UI change |
| F30 release gates | `Test purchase flow` must be excluded from a production configuration, which is a build-config change, not a code fix |
