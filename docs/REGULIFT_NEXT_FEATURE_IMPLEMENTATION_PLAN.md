# Regulift — New Feature Implementation Plan

**Purpose:** Implement the next set of features that make Regulift more differentiated, easier to use during training, and more obviously adaptive.

**Scope rule:** This plan intentionally focuses on features Regulift does **not already ship**. Existing capabilities such as adaptive programming, RPE-based progression, fatigue handling, Strong/Hevy import, Coach chat, voice quick-log, Live Activity rest timer, Fuel tracking, Crew, Watch logging, widgets, and standard progress tracking are treated as existing infrastructure to build on.

---

# 0. Product Direction

Regulift should not compete by becoming the app with the longest feature list.

The product should make this loop extremely obvious:

```text
TRAIN
  ↓
REGULIFT OBSERVES
  ↓
REGULIFT LEARNS
  ↓
NEXT WORKOUT CHANGES
  ↓
REGULIFT EXPLAINS WHY
  ↓
USER TRAINS AGAIN
```

Core product message:

> **Just train. We'll handle what comes next.**

Internal product principle:

> **The engine decides. AI explains.**

---

# 1. Recommended Build Order

## Phase 1 — Make adaptation visible

1. Adaptive Result screen
2. “Why did this change?” explanations
3. Coach Context API
4. Better ambiguity handling
5. AI action validation

## Phase 2 — Make workouts feel guided

6. Workout Focus Mode
7. Exercise transition screen
8. Dynamic in-ear Coach
9. Music/audio ducking
10. Narrow hands-free workout commands

## Phase 3 — Make the plan fit real life

11. Flexible Weekly Plan
12. Smart missed-workout recovery
13. Session rescheduling engine
14. Session Time Budget
15. Gym Profiles

## Phase 4 — Make Regulift learn the individual

16. Training Model
17. Structured Coach Memory
18. Plateau Experiments
19. Goal/Event Mode
20. Productive Volume Range

## Phase 5 — Improve acquisition

21. Web “Find My Plan” quiz
22. Personalized result before install
23. Deep link into app onboarding
24. Import-based onboarding
25. First-week adaptive education

## Phase 6 — Improve retention / growth

26. Monthly “What Regulift Learned” review
27. Personal progression gamification
28. Smarter share cards
29. Crew challenges
30. Referral prompts at milestones

---

# 2. P0 — Adaptive Result Screen

## Goal

Make the most important part of Regulift visible immediately after every workout:

> **What did Regulift learn, and what changes next?**

The current workout summary should remain available, but the main hero should become adaptation.

---

## User Experience

After the user finishes a workout:

```text
WORKOUT COMPLETE

Regulift learned 3 things today

Bench Press ↑
82.5 × 8 @7.5 was easier than expected.

NEXT WORKOUT
82.5 kg → 85 kg

Chest Volume →
Recovery and performance were normal.

NEXT WEEK
10 sets → 10 sets

Cable Fly ✓
You reached the top of the rep range.

NEXT WORKOUT
Increase load

--------------------------------

Your next workout has been updated.

[ See changes ]
[ Done ]
```

---

## Data Requirements

For every completed workout, ForgeCore should emit structured decisions.

Suggested object:

```json
{
  "sessionId": "uuid",
  "learned": [
    {
      "type": "load_progression",
      "exerciseId": "bench_press",
      "previousValue": 82.5,
      "newValue": 85,
      "unit": "kg",
      "reasonCode": "target_rpe_passed",
      "confidence": "high"
    }
  ]
}
```

---

## Decision Types

Support at least:

```text
load_progression
load_reduction
rep_range_change
set_increase
set_decrease
volume_maintained
exercise_rotation
exercise_maintained
rest_change
deload_triggered
deload_cancelled
fatigue_adjustment
plateau_detected
plateau_resolved
```

---

## UI Components

Create:

```text
AdaptiveResultView
AdaptiveResultCard
AdaptiveChangeBadge
AdaptiveReasonSheet
NextWorkoutPreview
```

---

## Acceptance Criteria

- Every meaningful ForgeCore decision can be rendered.
- User can see at least one explanation when a change happened.
- No explanation is generated only by the LLM.
- The explanation must be backed by structured engine state.
- User can open the next workout directly.
- No more than 3–5 adaptation cards are shown by default.
- Low-value decisions are collapsed under “More changes”.

---

# 3. P0 — “Why Did This Change?”

## Goal

Every meaningful program change should be inspectable.

---

## Surfaces

Add `Why?` access in:

- Today
- Workout Focus Mode
- Exercise detail
- Next workout preview
- Post-workout Adaptive Result
- Coach responses
- Weekly Plan

---

## Example

```text
Bench Press

85 kg × 6–8
↑ 2.5 kg

[ Why? ]
```

Tap:

```text
WHY THIS CHANGED

Last session
82.5 kg × 8 @7.5

Target
6–8 reps @ RPE 7–8

Result
You reached the top of the rep range
without exceeding target RPE.

Regulift increased the load by 2.5 kg.

[ Ask Coach ]
[ Keep recommendation ]
[ Adjust ]
```

---

## Architecture

ForgeCore should provide:

```swift
struct ProgramDecisionExplanation {
    let decisionID: UUID
    let decisionType: DecisionType
    let reasonCode: ReasonCode
    let inputs: [DecisionInput]
    let output: DecisionOutput
    let userFacingSummary: String?
}
```

Do not depend on free-form AI generation for core explanation.

LLM may rephrase:

```text
structured engine explanation
→ optional natural-language Coach explanation
```

---

## Reason Codes

Examples:

```text
target_rpe_passed
target_rpe_exceeded
top_of_rep_range
below_rep_floor
recovery_low
recovery_high
volume_landmark_reached
plateau_detected
exercise_stale
early_deload
scheduled_deload
missed_session_recovery
equipment_constraint
user_preference
time_constraint
```

---

## Acceptance Criteria

- Every automatic program change has a reason code.
- The app can display a deterministic explanation offline.
- Coach may add conversational detail but cannot invent a different reason.
- User can revert only when the engine says reversal is allowed.

---

# 4. P0 — Coach Context API

## Goal

Make Coach answers grounded in live Regulift data.

Do not dump the entire user database into every prompt.

Use narrow structured tools.

---

## Initial Read Tools

```text
getCurrentWorkout()
getCurrentExercise()
getProgramDecision(exerciseId)
getRecentSessions(exerciseId, count)
getReadiness()
getRecoverySignals()
getBodyWeightTrend(days)
getPRHistory(exerciseId)
getWeeklyMuscleVolume()
getCurrentMesocycle()
getUserGoal()
getSchedule()
getGymProfile()
getExercisePreferences()
```

---

## Suggested Response Example

```json
{
  "exercise": "Bench Press",
  "currentPrescription": {
    "loadKg": 80,
    "sets": 3,
    "repRange": [6, 8],
    "targetRPE": 8
  },
  "previousSession": {
    "loadKg": 85,
    "reps": [6, 6, 5],
    "averageRPE": 9.5
  },
  "decision": {
    "type": "load_reduction",
    "reasonCode": "fatigue_adjustment"
  },
  "signals": {
    "sleep": "below_baseline",
    "soreness": ["pecs"],
    "readiness": 58
  }
}
```

---

## Coach Flow

```text
User question
→ intent classify
→ request structured context
→ generate answer
→ validate any proposed action
→ show response
```

---

## Example

User:

> Why is my bench lighter today?

Coach:

> I dropped bench from 85 to 80 kg because your last session averaged RPE 9.5 and today's recovery is below your normal range. This is a temporary fatigue adjustment, not a reset.

---

## Acceptance Criteria

- Coach can answer program questions using actual engine decisions.
- Tool responses are small and typed.
- Tool failures are handled explicitly.
- Coach must say when data is unavailable.
- Coach does not invent workouts, PRs, readiness, or history.

---

# 5. P0 — Better Coach Guardrails + Ambiguity Handling

## Problem

Generic “fitness-only” prompts can make harmless questions fail strangely.

---

## Intent Categories

Classify every Coach request into one of:

```text
training_question
program_explanation
app_help
action_request
ambiguous
unknown_personal_info
medical_risk
off_topic_safe
unsupported
```

---

## Example Rules

### Unknown personal information

User:

> When is my birthday?

Response:

> I don't have your birthday saved.

---

### Ambiguous

User:

> Why did my weight drop?

Possible meanings:

- body weight
- prescribed exercise weight
- e1RM

Response:

> Do you mean your body weight or the weight prescribed for an exercise?

---

### Medical-risk

Do not diagnose.

Instead:

- identify the limit
- recommend stopping/adjusting training where appropriate
- recommend qualified medical evaluation when warranted

Do not add medical warnings to normal fitness questions.

---

## Acceptance Criteria

- No blanket “consult a professional” for missing information.
- Ambiguous questions trigger one short clarification.
- Unknown data is never invented.
- Medical guardrails trigger only when relevant.
- App-help questions remain answerable.

---

# 6. P0 — AI Action Validation Layer

## Goal

The LLM can propose; ForgeCore owns programming decisions.

---

## Flow

```text
User
↓
Coach
↓
Action proposal
↓
ForgeCore validator
↓
Validation result
↓
User confirmation
↓
Execution
```

---

## Example

Coach proposes:

```json
{
  "action": "reduce_sets",
  "exerciseId": "back_squat",
  "from": 4,
  "to": 3
}
```

Validator returns:

```json
{
  "allowed": true,
  "reason": "within_minimum_effective_volume",
  "requiresConfirmation": true
}
```

---

## Reject Conditions

Reject if:

- violates minimum volume
- conflicts with locked exercise
- violates mesocycle rules
- exceeds safe progression cap
- breaks recovery spacing
- unsupported action
- stale plan version
- invalid exercise
- corrupted session state

---

# 7. P0 — Workout Focus Mode

## Goal

Make the active workout feel guided rather than database-like.

---

## Main Screen

```text
BENCH PRESS

SET 2 / 4

85 kg
6–8 reps
Target RPE 8

Last:
82.5 × 8 @7.5

[ COMPLETE SET ]

🎙 Say “7 reps at 8”
```

---

## After Set

```text
REST

01:48

Next set
85 kg × 6–8
Target RPE 8

[ +30 sec ]
[ Skip rest ]
```

---

## Design Requirements

- full-screen
- large numbers
- large touch targets
- one-hand friendly
- minimal navigation
- haptics
- screen stays readable at arm's length
- no unnecessary analytics mid-set

---

## Modes

Allow:

```text
Standard Logger
Focus Mode
Watch-only
Voice-assisted
```

---

## Acceptance Criteria

- Start Focus Mode from Today or Logger.
- Complete a full workout without leaving Focus Mode.
- Logger state remains synchronized.
- App-kill resume still works.
- Watch mirrors current exercise / set.
- Voice quick-log works from Focus Mode.

---

# 8. P0 — Exercise Transition Screen

## Goal

Make movement from one exercise to the next feel intentional.

---

## Example

```text
✓ BENCH PRESS COMPLETE

3 working sets
Top set: 85 × 8 @8

UP NEXT

Cable Fly
3 × 12–15

Chest isolation

[ Start ]
```

Optional short explanation:

> Moving from heavy pressing to lower-fatigue chest work.

---

## Acceptance Criteria

- Transition appears after final working set.
- Can skip or swap next exercise.
- No forced delay.
- Works with supersets.
- Works offline.

---

# 9. P1 — Dynamic In-Ear Coach

## Goal

Give users the “coach in your headphones” feeling, but make it responsive to their actual performance.

---

## Initial Scope

Speak only high-value events:

- first set prescription
- set logged
- rest complete
- next exercise
- meaningful adaptation
- unexpected RPE
- PR
- workout complete

---

## Example

Before set:

> Bench press. 85 kilos for 6 to 8. Target RPE 8.

After user logs:

> Logged. That was harder than target, so keep the same load next set. Rest two minutes thirty.

---

## Audio Priority

Do not talk constantly.

Default:

```text
critical coaching > timers > workout transitions > optional encouragement
```

---

## Settings

```text
Coach Audio
[ Off ]
[ Minimal ]
[ Standard ]
[ Detailed ]
```

---

# 10. P1 — Music / Audio Ducking

## Goal

Coach speech should coexist with music.

---

## Behavior

```text
Music playing
↓
Coach audio begins
↓
Music volume temporarily reduces
↓
Coach finishes
↓
Music returns
```

---

## Requirements

- respect system audio session
- avoid pausing music when ducking is sufficient
- restore correctly after interruption
- work with headphones / speakers
- do not break rest timer sounds

---

# 11. P1 — Hands-Free Workout Commands

## Goal

Keep voice narrow and useful.

---

## Initial Commands

```text
“What’s next?”
“Repeat target.”
“Log 8 at 8.”
“Same weight.”
“Undo last set.”
“Add 30 seconds.”
“Skip rest.”
“Skip exercise.”
“Swap this.”
```

---

## Do Not Build Yet

Avoid arbitrary natural-language control over the whole app.

The high-value context is:

> hands busy + workout active

---

# 12. P0 — Flexible Weekly Plan

## Goal

Make the weekly schedule editable without breaking programming logic.

---

## UI

```text
THIS WEEK

MON  Upper A ✓
TUE  Lower A ✓
WED  Rest
THU  Upper B
FRI  Lower B
SAT  Rest
SUN  Rest
```

Allow drag-and-drop or tap-to-move.

---

## Example

User moves Thursday workout to Friday.

Regulift:

> I'll adjust the rest of the week.

```text
Upper B → Friday
Lower B → Sunday
```

Reason:

> This keeps enough recovery between overlapping sessions.

---

## Engine Constraints

When moving sessions, consider:

- muscle overlap
- heavy compound proximity
- minimum recovery window
- weekly volume
- session priority
- user constraints
- deload week
- goal/event timeline

---

# 13. P0 — Smart Missed-Workout Recovery

## Trigger

A planned session was not completed.

---

## UX

```text
You missed Lower A yesterday.

RECOMMENDED
Move Lower A to today and shift the week.

Other options:
- Skip it
- Compress this week
- Replace today's workout
- Choose manually
```

---

## Engine Output

```json
{
  "missedSessionId": "...",
  "recommendedRecovery": "shift_week",
  "newSchedule": [...],
  "impact": {
    "weeklyVolume": "preserved",
    "recovery": "acceptable"
  }
}
```

---

# 14. P1 — Session Time Budget

## Goal

Let users adapt the workout to the time they actually have.

---

## Quick Options

```text
20 min
30 min
45 min
Full
```

---

## Reduction Priority

1. Preserve highest-priority compound work.
2. Preserve minimum useful muscle stimulus.
3. Reduce low-priority isolation.
4. Superset compatible movements.
5. Reduce unnecessary warm-up volume.
6. Avoid changing too many variables at once.

---

## Example

User selects 30 min.

Regulift:

```text
Original: 58 min
New: ~31 min

Kept:
Bench Press
Chest-supported Row
Lateral Raise

Changed:
Cable Fly 3 sets → 2
Triceps Extension removed
Row + Lateral Raise supersetted
```

---

# 15. P1 — Gym Profiles

## Goal

Adapt programming to equipment availability automatically.

---

## Profile Examples

```text
Main Gym
Home
Work Gym
Hotel
Travel
```

---

## Stored Equipment

```text
barbell
rack
bench
cable
smith_machine
machines[]
dumbbell_min
dumbbell_max
dumbbell_increment
plates[]
specialty_bars[]
```

---

## Behavior

When gym changes:

> Cable station unavailable in Home Gym.

Regulift swaps using the existing substitution system.

---

# 16. P1 — Training Model

## Goal

Create a user-facing summary of what Regulift has learned over time.

This should become a long-term retention moat.

---

## Example

```text
YOUR TRAINING MODEL

Strength Response
Bench        Fast ↑
Squat        Moderate →
Deadlift     Fast ↑

Volume Response
Chest        10–12 sets appears productive
Back         12–14 sets appears productive
Quads        Not enough data

Recovery
Upper body   ~48 h
Lower body   ~72 h

Preferences
Avoid Bulgarian split squats
Prefer DB incline press
```

---

## Important

Do not claim certainty where evidence is weak.

Use states:

```text
insufficient_data
early_signal
moderate_confidence
strong_signal
```

---

# 17. P1 — Structured Coach Memory

## Goal

Save explicit user preferences.

---

## Examples

- exercise dislikes
- preferred substitutes
- schedule constraints
- session duration
- coaching style
- equipment preferences

---

## Memory Confirmation

User:

> I hate Bulgarian split squats.

Coach:

> Remember that you prefer alternatives to Bulgarian split squats?

Only store after confirmation.

---

# 18. P1 — Plateau Experiments

## Goal

Turn plateau detection into an explicit guided intervention.

---

## Flow

```text
Plateau detected
↓
Select one intervention
↓
Run for N exposures / weeks
↓
Evaluate
↓
Keep / revert / try next
```

---

## Example

```text
PLATEAU DETECTED

Bench Press
No meaningful improvement across 4 exposures.

Recommended experiment:
Change rep range
8–10 → 5–7

Duration:
3 exposures

[ Start experiment ]
```

---

## Evaluation

```text
EXPERIMENT COMPLETE

Before e1RM: 116 kg
After e1RM: 121 kg
Average RPE: stable

Result:
Positive signal

[ Keep ]
[ Revert ]
```

---

# 19. P1 — Goal / Event Mode

## Goal

Give the adaptive engine a destination.

---

## Examples

```text
Bench 140 kg
Powerlifting meet
Vacation
Wedding
Target body weight
Photoshoot
Return-to-training date
```

---

## Fields

```text
goal_type
target_value
target_date
priority
acceptable_tradeoffs
```

---

## Engine Impact

May influence:

- exercise specificity
- block length
- volume distribution
- deload
- peaking
- nutrition targets

---

# 20. P1 — Productive Volume Range

## Goal

Estimate where the user appears to make good progress.

---

## Example

> Your best recent bench progress occurred around **10–12 chest sets/week**.

Use wording like:

> “This appears to be your current productive range.”

Never present as permanent physiological truth.

---

# 21. P0 — Web “Find My Plan” Quiz

## Goal

Turn the website into a personalized acquisition funnel.

The user should receive value before installing the app.

---

## Suggested Questions

### Q1 — Main goal

```text
Build muscle
Get stronger
Both
Lose fat while maintaining strength
```

### Q2 — Training frequency

```text
2
3
4
5
6 days/week
```

### Q3 — Session duration

```text
30 min
45 min
60 min
90+ min
```

### Q4 — Equipment

```text
Commercial gym
Home gym
Dumbbells
Minimal equipment
```

### Q5 — Experience

```text
<1 year
1–2 years
2–4 years
4+ years
```

### Q6 — Current training data

```text
Import Strong
Import Hevy
I'll set it up manually
```

---

# 22. P0 — Personalized Quiz Result

## Goal

Do not end the quiz with generic marketing.

Show a real starter plan.

---

## Example

```text
YOUR REGULIFT PLAN

4-Day Upper / Lower

Goal
Strength + hypertrophy

Session length
~55 min

Starting volume
Chest       10 sets
Back        12 sets
Quads        9 sets
Hamstrings   8 sets

MON  Upper A
TUE  Lower A
THU  Upper B
SAT  Lower B

Progression
RPE-based + double progression
```

Then:

> **This is only the starting point.**

> After every workout, Regulift adjusts the next one based on how you actually perform.

CTA:

```text
[ Start My Plan ]
```

---

# 23. P0 — Web → App Deep Link

## Goal

Do not make the user repeat the quiz in the app.

---

## Result Payload

Generate a short-lived onboarding token:

```json
{
  "goal": "strength_hypertrophy",
  "daysPerWeek": 4,
  "sessionMinutes": 60,
  "equipmentProfile": "commercial_gym",
  "experience": "2_4_years"
}
```

App opens:

```text
regulift://onboarding?token=...
```

Server retrieves the result and pre-fills onboarding.

---

## Acceptance Criteria

- Quiz result survives App Store install where technically possible through account / deferred-link strategy.
- If deep-link recovery fails, user can enter a short recovery code.
- No sensitive data required.
- User can edit all imported answers.

---

# 24. P1 — Import-Based Onboarding

## Goal

Make Strong / Hevy import more valuable.

---

## After Import

Analyze:

- common exercises
- working loads
- frequency
- usual training days
- rep ranges
- estimated 1RM
- weekly muscle volume
- repeated swaps
- likely plateaus

---

## Result Screen

```text
WE LEARNED THIS FROM YOUR LAST 12 WEEKS

Training frequency
4.2 sessions/week

Most consistent lifts
Bench Press
Squat
Pull-up

Likely preference
Upper / Lower structure

Current plateau
Bench Press

Recommended starting plan
4-day Upper / Lower
```

---

# 25. P1 — First-Week Adaptive Education

## Goal

Teach the user what makes Regulift different through use.

---

## Examples

After first session:

> Regulift will use today's reps and RPE to set your next exposure.

After first adjustment:

> This load changed because you reached the top of the rep range below target RPE.

End of first week:

> Your next week is now different from the plan you started with.

Avoid tutorials that explain everything up front.

---

# 26. P2 — Coach Communication Styles

## Goal

Create attachment without pretending the AI is a human trainer.

---

## Options

### Concise

> 85 × 8. Good. Add 2.5 kg next week.

### Analytical

> You reached the top of the rep range at RPE 7.5. Progression threshold passed, so the next exposure increases 2.5 kg.

### Motivating

> Strong set. You cleared the target without overshooting effort, so you're ready for 87.5 next time.

---

## Important

Only wording changes.

ForgeCore decision remains identical.

---

# 27. P2 — Personal Progression Gamification

## Goal

Make progress visible without encouraging ego lifting.

---

## Avoid

Generic:

```text
Bronze lifter
Silver lifter
Gold lifter
```

based only on absolute strength.

---

## Prefer

Personal progression:

```text
BENCH PRESS

Progress Level 19

Strength Trend     ████████░░
Consistency        ██████████
Target Completion  ███████░░░
```

Possible categories:

- exercise progression
- consistency
- mesocycle completion
- adherence
- training history

---

# 28. P2 — Monthly “What Regulift Learned” Review

## Goal

Show adaptation over a meaningful timeframe.

---

## Example

```text
AUGUST

Regulift learned:

Your bench responds well around 10–12 chest sets/week.

Lower-body recovery averages ~72 hours.

Your final-set RPE is consistently higher on Friday sessions.

You completed 14 / 16 planned sessions.

NEXT MONTH

- Keep chest volume stable
- Move heavy lower session away from Friday
- Continue current bench progression
```

---

# 29. P2 — Fuel → Training Performance Integration

## Goal

Make Fuel useful for strength outcomes instead of becoming another calorie tracker.

---

## Example

```text
YOUR CUT MAY BE AFFECTING PERFORMANCE

Body-weight trend
-0.82% / week

Bench e1RM
-1.6%

Average readiness
-9%

Suggested calorie target
2,250 → 2,390 kcal
```

---

## Rules

Do not claim direct causation.

Use:

- “may be contributing”
- “appears associated”
- “worth testing”

---

# 30. P2 — Smarter Share Cards

## New Share Types

- mesocycle completed
- plateau broken
- training experiment result
- monthly progress
- consistency milestone
- goal achieved
- personalized “Regulift learned” insight

---

## Example

```text
PLATEAU BROKEN

Bench Press
116 → 121 kg e1RM

3-week experiment
Lower rep range

Regulift
```

---

# 31. P2 — Crew Challenges

## Good Challenges

```text
3 workouts this week
Complete your planned week
12 workouts this month
Finish a mesocycle
4-week consistency streak
```

---

## Avoid

```text
Lift the most weight
Highest bench wins
Most total tonnage
```

These favor body size and may encourage poor behavior.

---

# 32. Analytics / Experimentation Requirements

Before shipping all phases, instrument the core funnel.

---

## Acquisition

```text
quiz_started
quiz_completed
quiz_result_viewed
app_store_clicked
app_opened_from_quiz
onboarding_completed
```

---

## Activation

```text
program_created
workout_started
first_set_logged
workout_completed
adaptive_result_viewed
adaptive_reason_opened
second_workout_started
third_workout_completed
```

---

## Retention

Track:

```text
D1
D7
D14
D30
week_6
mesocycle_completion
```

---

## Adaptive Value

```text
program_change_count
reason_open_rate
engine_recommendation_accept_rate
recommendation_revert_rate
coach_program_question_rate
plateau_experiment_start_rate
plateau_experiment_completion_rate
```

---

## Focus Mode

```text
focus_mode_started
focus_mode_workout_completed
voice_log_success
voice_command_failure
manual_fallback
time_between_sets
```

---

# 33. Suggested Feature Flags

Use flags for staged rollout:

```text
adaptive_result_v1
decision_explanations_v1
coach_context_tools_v1
focus_mode_v1
voice_coach_v1
audio_ducking_v1
weekly_plan_v2
missed_workout_recovery_v1
gym_profiles_v1
training_model_v1
plateau_experiments_v1
web_quiz_v1
personal_progression_v1
fuel_performance_insights_v1
```

---

# 34. Suggested Data Model Additions

## ProgramDecision

```text
id
sessionId
exerciseId?
decisionType
reasonCode
beforeValue
afterValue
inputs
createdAt
engineVersion
```

---

## TrainingInsight

```text
id
type
metric
value
confidence
evidenceWindow
createdAt
expiresAt?
```

---

## CoachPreference

```text
id
type
value
source
confirmedByUser
createdAt
```

---

## TrainingExperiment

```text
id
type
targetMetric
startDate
endDate
baseline
intervention
result
status
```

---

## ScheduleConstraint

```text
id
type
value
priority
active
```

---

## GymProfile

```text
id
name
equipment
isDefault
```

---

# 35. Rollout Recommendation

## Release A

Ship:

- Adaptive Result
- Why This Changed
- Coach Context API
- guardrail fixes
- action validation

### Success condition

Users understand that Regulift is adapting their program.

---

## Release B

Ship:

- Focus Mode
- transition screen
- narrow voice controls
- in-ear Coach beta
- audio ducking

### Success condition

Users can complete workouts with less screen interaction.

---

## Release C

Ship:

- Flexible Weekly Plan
- missed-workout recovery
- session time budget
- gym profiles

### Success condition

Users do not abandon the plan when real life interferes.

---

## Release D

Ship:

- Training Model
- Coach Memory
- Plateau Experiments
- Goal/Event Mode

### Success condition

Long-term users feel Regulift increasingly understands them.

---

## Release E

Ship:

- Web quiz
- personalized result
- deep-link onboarding
- import analysis

### Success condition

More visitors reach first workout with less onboarding friction.

---

# 36. What NOT to Prioritize Yet

Do not delay the roadmap above for:

- huge exercise-video library
- full video form analysis
- generic food-photo AI
- broad public social network
- general-purpose voice assistant
- autonomous LLM programming
- body scan / genetics claims
- dozens of new dashboard metrics

These can be revisited after the core adaptive loop is visibly working and measured.

---

# 37. Top 10 Implementation Priority

If engineering bandwidth is limited:

1. **Adaptive Result**
2. **Why This Changed**
3. **Coach Context API**
4. **Workout Focus Mode**
5. **Smart Missed-Workout Recovery**
6. **Flexible Weekly Plan**
7. **Web Find My Plan Quiz**
8. **Training Model**
9. **Plateau Experiments**
10. **Dynamic In-Ear Coach**

---

# 38. Definition of “Better Regulift”

Regulift is better when a user can say:

> “I don't have to decide what to do next.”

and:

> “I understand why the app changed my workout.”

and eventually:

> “The app understands how I respond to training.”

That is a stronger product direction than simply adding more tracking features.

---

# 39. North-Star Experience

The target experience should look like this:

```text
TODAY

Upper A

Your readiness is slightly below normal.

Regulift changed:
Bench Press 4 sets → 3

[ Why? ]
```

User starts Focus Mode.

```text
BENCH PRESS
85 kg × 6–8
Target RPE 8

SET 1 / 3
```

User:

> “8 at 9.”

Regulift:

> Logged. That was harder than target, so keep 85 kg for set two. Rest 2:30.

Later:

```text
WORKOUT COMPLETE

Regulift learned 2 things today.

Bench
Performance was harder than expected.
Next session remains at 85 kg.

Chest volume
Recovery was below baseline.
No volume increase next week.

Your next workout is ready.
```

That is the experience the roadmap should optimize for.
