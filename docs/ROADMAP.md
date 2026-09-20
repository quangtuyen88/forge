# Regulift roadmap

Status: `[x]` shipped · `[~]` foundation exists, next flow still needed · `[ ]` planned

## Product goal

**Import an old log → Regulift explains what it learned → programs the next session → explains every change → adapts when life breaks the plan.**

Principle: **every engine decision produces a readable reason.** One `Decision` object in ForgeCore carries subject, action, causes and whether the lifter may override it. Today, the logger, Coach, weekly review and notifications render the same source so explanations cannot drift.

## Existing foundation

| Status | Feature | What exists now |
|---|---|---|
| [x] | Decision ledger | Structured decision records, reason codes, source values and a training timeline. |
| [x] | Explain why program changed | Why cards, exact figures, decision summaries and Keep original / Make easier / Make harder overrides. |
| [x] | Coach Context API | Read-only privacy-filtered context packet with profile, logs, PRs and decision history; Health-only fields are withheld by construction. |
| [x] | Coach guardrails | Ambiguity and missing-fact handling, direct/indirect prompt-attack detection, escaped data blocks, quarantined context/history, output validation and confirmed action execution. |
| [x] | Import foundation | Strong/Hevy CSV import, exercise matching and Plan Audit. |
| [x] | Smart Import Analysis | Strong/Hevy import now flows into “what we learned,” inferred frequency/split, recommended first week, seeded loads and next-session handoff. |
| [x] | Missed-workout recovery | Recommended repair plus shift, compress, skip, light and restart alternatives. |
| [x] | Workout Focus Mode | Dedicated one-set-at-a-time logger mode with persistent default, minimal chrome, rest takeover and resume. |
| [x] | Plateau rescue foundation | Plateau detection, variant rotation and volume/fatigue interventions exist. |
| [x] | Structured Coach memory | Confirmed typed facts store kind, source, confirmation, expiry and supersession metadata. |
| [x] | Constraint system | Named Gym Profiles, equipment rules, Exercise Lock/exclusion, Travel/Crowd modes, session budget and Minimum Effective Workout share one synced model. |
| [x] | Training Experiments | One four-week lift intervention records baseline e1RM, changes one variable, and supports keep/revert. |

## Priority order

1. Explain why program changed.
2. Smart Import Analysis.
3. Coach Context API + guardrails + ambiguity and action validation.
4. Smart missed-workout recovery.
5. Workout Focus Mode.
6. Plateau Rescue.
7. Training Experiments.

Experiments wait for enough clean history. Import, explanation and recovery create value immediately.

## 1.0.1 — Trust Pack

- [x] Decision ledger as the source of truth for every prescription change.
- [x] Why-this-changed cards with exact source figures and reversible overrides.
- [x] Read-only Coach Context API.
- [x] Prompt-injection protection for server and on-device Coach paths.
- [x] Ambiguity, missing-fact, medical and scope handling.
- [x] Output/action validator; swaps must target the active plan and a valid replacement, then require confirmation.

**Goal:** users trust that Regulift knows what it is doing.

## 1.0.2 — Activation Pack

- [x] Smart Import Analysis over Strong/Hevy history.
- [x] “We learned this about you” summary covering frequency, volume, preferred rep ranges, estimated maxes and stalled lifts.
- [x] Recommended starting program generated from imported evidence.
- [x] Import-to-next-session handoff with no configuration dead end.

**Goal:** a new user imports and immediately feels understood.

## 1.1 — Real-Life Training Pack

- [x] Smart missed-workout recovery with ranked repair options.
- [x] Persistent and per-session 20/30/45/60/90-minute budgets.
- [x] Minimum Effective Workout preserves locked/main lifts and caps working sets.
- [x] Workout Focus Mode provides one-task-at-a-time logging with rest takeover and minimal chrome.

**Goal:** Regulift survives real life without breaking the adaptive loop.

## 1.2 — Moat Pack

- [x] Structured Coach memory with typed facts, provenance, confirmation, expiry and supersession metadata.
- [x] Named persistent Gym Profiles plus a shared constraints layer for equipment, locks and temporary modes.
- [x] Plateau Rescue exposes one recommended intervention and its proof.
- [x] Training Experiments change one variable for four weeks, compare e1RM and support keep/revert.

**Goal:** Regulift learns the lifter better over time.

## Platform bundles

### Coach Platform Bundle

Coach Context API, prompt guardrails, ambiguity detection, action validation, structured memory, model routing and curated RAG share one contract. New Coach features must use the same read-only context and validator rather than creating parallel prompts.

### Constraint System Bundle

Gym Profiles, program constraints, Exercise Lock, Travel Mode, Gym Crowd Mode, session time budget and Minimum Effective Workout should share one persistent constraints/preferences model.

### Adaptation Proof Bundle

Why changed, proactive Coach insights, monthly review, fatigue timeline, Plateau Rescue, Training Experiments and smarter share cards all consume the decision ledger plus training timeline.

## Deferred until the adaptive loop wins

Live Voice Coach, a broad exercise-video library, video form feedback, broad social expansion, complex nutrition correlations, goal-probability projections, direct Instagram Stories and Watch complications.

## Success metrics

- Why-change view rate.
- Prescription accept vs revert rate.
- Import → first workout conversion.
- First workout → second workout retention.
- Missed-workout recovery acceptance rate.
- Coach answer helpful rate.
- Hallucination / wrong-data rate.
- Paywall conversion after plan explanation.

Trust should reduce manual overrides and increase second-session retention.
