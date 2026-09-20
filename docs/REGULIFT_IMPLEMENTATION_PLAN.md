# ReguLift — Complete Feature Implementation Plan

**Version:** 1.0  
**Prepared:** 2026-09-18  
**Status:** In progress. Foundation tasks FND-01 through FND-03 are implemented and verified; later tasks remain unchecked until their acceptance evidence exists.
**Scope:** All eight recommendations, plus their shared infrastructure, integration, measurement, and release work.  
**Product direction:** Understand the user's program, actual equipment, and changing week—and make recommendation quality inspectable.

> Extend ReguLift's existing capabilities. Do not rebuild logging, adaptive programming, Coach chat, RAG, memory, Gym Profiles, imports, experiments, subscriptions, or sync under new names.

## Contents

1. [Scope and decisions](#1-scope-and-decisions)
2. [Architecture and shared contracts](#2-architecture-and-shared-contracts)
3. [Foundation work](#3-foundation-work)
4. [Equipment Passport](#4-equipment-passport)
5. [Recommendation confidence and outcome checks](#5-recommendation-confidence-and-outcome-checks)
6. [Coach My Program](#6-coach-my-program)
7. [Week Designer](#7-week-designer)
8. [Set-limiter feedback](#8-set-limiter-feedback)
9. [Goal roadmaps and benchmark sessions](#9-goal-roadmaps-and-benchmark-sessions)
10. [Conversational voice Coach](#10-conversational-voice-coach)
11. [Shareable adaptive program links](#11-shareable-adaptive-program-links)
12. [Cross-feature UX and platform integration](#12-cross-feature-ux-and-platform-integration)
13. [Testing, privacy, and operational quality](#13-testing-privacy-and-operational-quality)
14. [Analytics and success measurement](#14-analytics-and-success-measurement)
15. [Paid-product and website alignment](#15-paid-product-and-website-alignment)
16. [Delivery sequence and release gates](#16-delivery-sequence-and-release-gates)
17. [Implementation handoff](#17-implementation-handoff)
18. [Sources and verification notes](#18-sources-and-verification-notes)

---

## 1. Scope and decisions

### 1.1 Source of truth

The feature inventory supplied on September 18, 2026 is the baseline. The public website is supporting evidence for public promises, not an authoritative repository inventory. No source repository was inspected for this plan.

All type names, module boundaries, identifiers, endpoint paths, configuration values, and file layouts below are **proposed contracts**. Map them to the actual repository before adding code. The existing deterministic programming engine is called **the engine** throughout; use `ForgeCore` where that is the repository's actual name.

Retain the current SwiftData/offline-first architecture, existing sync, existing Coach routing and action validation, and existing subscription implementation. Reuse the current speech adapters and `VoiceCommandParser` rather than replacing them with an LLM.

### 1.2 Complete feature scope

| ID | Addition | Existing capability to extend | New behavior—not a duplicate |
|---|---|---|---|
| EQP | Equipment Passport | Gym Profiles, variants, plate calculator, progression | Individual machine identity, loading conventions, real available increments, and comparable performance history |
| REC | Recommendation confidence and outcome checks | Coach explanations, engine, Progress, experiments | Evidence support before a decision; prescription-versus-result evaluation afterward |
| PRG | Coach My Program | Onboarding/import, program engine, exercise locks | Import intended programming rules and explicitly control which parts may adapt |
| WKD | Week Designer | Time budgets, travel, missed-workout recovery | Advance weekly scheduling, alternative-plan previews, and optional calendar integration |
| LIM | Set-limiter feedback | Set logging, notes, soreness, Coach memory | Structured reasons for an individual set result and bounded downstream responses |
| GOL | Goal roadmaps and benchmarks | Mesocycles, PRs, e1RM, Progress | A goal connected to repeatable benchmark sessions and explicit block reviews |
| VOC | Conversational voice Coach | Voice logging, Coach chat, routing, confirmations | Short spoken questions and follow-ups; not more logging commands |
| SHR | Shareable adaptive program links | Referrals, Crew, exports, program import | Versioned program definitions that recipients personalize without inheriting private data |

All eight are committed scope in this roadmap. Release order is not a suggestion to omit later features. Manual Week Designer ships before its calendar extension; both have tasks below.

### 1.3 Non-goals

Do not add video libraries, video form analysis, camera-based equipment recognition, an always-listening assistant, a broad social network, a creator marketplace, a new nutrition product, or an unexplained composite fitness score in this implementation.

Do not change pricing amounts, launch a permanent free tier, migrate databases, select a new paid AI vendor, or raise minimum OS requirements merely because this plan introduces new workflows.

### 1.4 Non-negotiable behavior

- The engine owns prescriptions. Models may interpret input, explain decisions, and produce typed proposals; they never write directly to training state.
- New Coach mutations require a visible, specific confirmation. Preserve the existing authorized fast path for deterministic set-logging commands.
- Missing input remains unknown, not zero or evidence of poor recovery.
- Unknown equipment, ambiguous weights, and limited history must not create confident progression or plateau claims.
- Hard constraints and program permissions cannot be silently relaxed. Conflicts produce choices, not hidden overrides.
- Existing workouts, history, and already-available offline behavior must survive failed requests, feature rollbacks, subscription transitions, and schema upgrades.
- HealthKit information must not enter remote Coach prompts, analytics, published templates, or ordinary cloud-sync records. Preserve the site's public Health-data boundary. [S1]
- Do not infer injury diagnoses, causal training benefits, exact muscle growth, or guaranteed goal-completion dates.

---

## 2. Architecture and shared contracts

### 2.1 One decision pipeline

```text
UI / typed input / Coach / program import / week preview
                      |
                      v
               Typed intent or draft
                      |
                      v
  Context snapshot + permissions + privacy classification
                      |
                      v
       Deterministic engine and constraint validation
                      |
             +--------+---------+
             |                  |
       Feasible proposal   Conflict / unsupported /
             |             insufficient information
             v                  |
  Before-and-after preview      v
             |             Explain and offer choices
             v
      Required confirmation
             |
             v
  Revision re-check + one local transaction + audit receipt
             |
             v
       Existing sync/outbox, when permitted
             |
             v
     Actual training result -> outcome evaluation
```

Ordinary adaptive actions already authorized by the user's selected program mode can continue without a new modal every set. Record their policy authorization. A conversational Coach proposal never treats that general authorization as permission for an unrelated mutation.

### 2.2 Proposed service boundaries

| Component | Responsibility | Must not do |
|---|---|---|
| `EquipmentService` | Equipment instances, setup versions, loading options, aliases | Guess that different machines have equivalent resistance |
| `ComparabilityService` | Decide whether records can support a given comparison | Merge ambiguous historical records automatically |
| `ProgramCompiler` | Convert reviewed structured rules into engine inputs | Execute imported scripts or model-generated code |
| `AdaptationPolicyEvaluator` | Enforce program-level permissions and locks | Resolve conflicts by silently widening permissions |
| `WeekPlanningService` | Build bounded, deterministic schedule candidates | Claim a global optimum or proven impossibility without justification |
| `EvidenceService` | Build evidence-support summaries and reason codes | Use model self-confidence as evidence |
| `OutcomeEvaluator` | Compare prescriptions with eligible observed results | Treat acceptance or correlation as proof of effectiveness |
| `SetFeedbackService` | Store set-specific limiters and derived summaries | Convert one temporary limitation into permanent memory |
| `GoalService` | Version targets, benchmarks, and reviews | Mix incompatible measurements to declare success |
| `CoachConversationCoordinator` | Manage voice turns and existing Coach tools | Bypass the command parser or action validator |
| `ProgramShareService` | Publish sanitized templates and manage links | Publish workouts, personal loads, Health data, or private import text |

These are logical responsibilities, not a requirement for ten new packages. Prefer existing modules and small adapters.

### 2.3 Proposed mutation envelope

Use the existing action model where possible. Extend it to carry the following semantics:

```text
ActionProposal
  proposalID: stable identifier
  schemaVersion: integer
  actionType: closed enum
  targetIDs: explicit entity identifiers
  baseRevisions: revisions of every affected entity
  canonicalPayload: validated, bounded fields
  payloadDigest: digest of canonical payload and targets
  beforeAfterDiff: deterministic representation
  reasonCodes: closed enum values
  adaptationPolicyRevision: current policy version
  authorizationKind: explicitConfirmation | existingPolicyAuthorization
  privacyClassification: field-aware classification
  createdAt / expiresAt: timestamps
  status: draft | validated | awaitingConfirmation | applied |
          rejected | expired | stale | conflicted | cancelled
```

A confirmation receipt must bind to the proposal ID, payload digest, target IDs, and base revisions. Model-generated text such as “the user approved” is never authorization.

Revalidate at commit. A changed workout, equipment setup, program contract, or consent state makes a pending proposal stale. Regenerate its preview rather than applying the old payload to new state.

Applying the same action ID twice must not apply the change twice. Persist a receipt with the mutation in one local transaction. Reuse the existing outbox for permitted sync.

### 2.4 Offline and multi-device rules

Local revision checks prevent stale writes on the current device; they do **not** provide a global lock across disconnected devices.

Use the existing sync conflict model. Independent additions such as distinct set records can merge by stable IDs. Concurrent edits to an active program, loading convention, or weekly plan require deterministic conflict handling and, where intent differs, a user-visible resolution.

Never resolve an offline conflict by replaying a Coach command against an unrelated newer workout. Synchronize the committed domain result, preserve provenance, and re-evaluate affected future recommendations after reconciliation.

Keep completed sets immutable through program changes. History editing remains an explicit operation with revisions, not a side effect of replanning.

### 2.5 Shared data conventions

Every new persistent entity needs a stable ID, schema version, timestamps, revision, ownership scope, provenance, and a defined deletion/sync policy. Use existing equivalents rather than adding duplicate fields blindly.

Represent a load with its value **and meaning**:

```text
LoadDescriptor
  originalValue: decimal string
  originalUnit: kg | lb | machineStep | otherSupportedLabel
  domain: externalMass | assistance | machineScale | bodyweight
  convention: perHand | combined | totalIncludingBar |
              platesOnly | perSide | assistanceDisplayed | notApplicable
  equipmentInstanceID: optional identifier
  loadModelRevision: optional revision
  side: left | right | bilateral | unspecified
  normalizationStatus: verified | ambiguous | unsupported
```

Keep the originally logged value and unit. Use decimal-safe conversions and round only at the display or equipment-selection boundary. A machine step number is not automatically a mass measurement. A higher displayed assistance value is not automatically a harder exercise.

Use a shared comparison context incorporating the exercise, relevant variant, equipment/load-model identity, loading convention, side where relevant, and measurement protocol. A purely cosmetic equipment rename must not split a performance series.

### 2.6 Privacy boundaries

| Data category | Default handling in this plan |
|---|---|
| Existing workout records and new equipment/program records | Local; sync only through the user's existing opt-in and approved fields |
| Raw HealthKit records, Health-derived readiness inputs, and Health-specific evidence reasons | Device-local; excluded from remote Coach and normal telemetry |
| Calendar event titles, notes, attendees, and locations | Do not copy into ReguLift storage or Coach context for scheduling |
| Derived calendar busy intervals | Device-local by default; cache only the needed planning horizon |
| Voice audio | Transient processing only; prohibit application-side storage and verify provider retention before making a no-storage claim |
| User-spoken personal information | Disclose that the selected cloud speech route receives the utterance; do not claim semantic redaction of all sensitive speech |
| Set feedback and goal details | Treat as potentially sensitive; no raw values or text in general analytics |
| Published program templates | Explicit, reviewed, allowlisted public projection only |
| Decision snapshots | Local by default; any diagnostics export must be separately sanitized and user-initiated |

Health-derived fields retain their privacy classification through derived evidence and debug output. An approved training-plan projection may contain the resulting prescription but must exclude Health measurements and Health-specific explanations. Review that boundary explicitly rather than labeling derived information anonymous.

The public site says the Coach does not see Health data. Keep Health-specific reasoning in a local engine-rendered evidence panel, outside both local and remote model context, unless the product deliberately revises that promise through a separate privacy decision. [S1]

---

## 3. Foundation work

**Dependencies:** None.  
**Purpose:** Make all subsequent features extensions of one reliable system.

### Implementation tasks

- [x] **FND-01 — Repository map.** Actual modules, boundaries and verification commands are recorded in `docs/architecture/repository-map.md`.
- [x] **FND-02 — Baseline regression fixtures.** Existing unit/integration/E2E evidence and invariants are frozen in `docs/testing/roadmap-baseline.md`; the stateful Maestro suite now contains 15 flows.
- [x] **FND-03 — Shared load semantics.** `ForgeCore/LoadSemantics.swift` defines domains, conventions, sides, normalization status and comparison context. `LoggedSet` persists original meaning; legacy/sync records without semantics remain ambiguous.
- [ ] **FND-04 — Proposal lifecycle.** Extend the current action pipeline with bound confirmations, multi-entity revision checks, idempotency, typed conflicts, and audit receipts.
- [ ] **FND-05 — Privacy projections.** Define separate payload builders for local engine input, Coach context, sync, analytics, diagnostic export, and public templates. Avoid one general-purpose serialized context object.
- [ ] **FND-06 — Versioned persistence.** Add the first additive schema migration, migration fixtures, and a tested recovery path. Use SwiftData's schema/migration mechanisms while preserving the repository's existing persistence choices. [S2]
- [ ] **FND-07 — Sync compatibility.** Define old-client handling, unknown-field behavior, tombstones, duplicate events, and concurrent edits for the new entities.
- [ ] **FND-08 — Evaluation harness.** Add reproducible engine replay using explicit inputs, versions, fixed clocks, and deterministic ordering. Never use future history to construct an earlier decision.
- [ ] **FND-09 — Flags and entitlements.** Add feature flags independently from subscription checks. Do not scatter billing conditions inside the engine.
- [ ] **FND-10 — Analytics contract.** Register event names, allowed fields, consent behavior, deletion rules, and versioned metric definitions before instrumenting features.

### Foundation acceptance criteria

- Existing behavior passes the baseline suite before any feature flag is enabled.
- A duplicate confirmed action is applied once; a stale one is rejected or re-previewed.
- A migration failure does not silently replace the user's store with an empty database.
- Health, calendar details, raw transcripts, and private program text fail closed at inappropriate serialization boundaries.
- An old client cannot erase new program or equipment fields through a partial update.
- Existing no-account and offline training workflows remain usable.

---

## 4. Equipment Passport

**ID:** EQP  
**Depends on:** FND-03 through FND-07  
**Primary surfaces:** Gym Profiles and the existing exercise/workout detail sheet.

### 4.1 User outcome

“I can switch gyms or machines without losing setup notes, receiving impossible loads, or having unrelated machine numbers treated as a PR.”

### 4.2 Required scope

Create individual equipment instances inside Gym Profiles. Each supports a friendly name, supported exercises, setup fields, load model, available increments, and explicit loading convention.

Support both regular increments and explicit available-value lists. Allow minimum/maximum bounds and temporary unavailable weights. Reuse the plate calculator to derive realizable barbell loads when appropriate; do not create a second plate solver.

Separate the exercise library from equipment inventory. One exercise can use multiple equipment instances; one cable station can support multiple exercises and attachment configurations.

### 4.3 Data additions

| Entity | Important fields |
|---|---|
| `EquipmentInstance` | Gym ID, name, equipment kind, active/retired state, capability references |
| `EquipmentLoadModel` | Instance ID, revision, domain, unit, convention, attainable values/rule, bar inclusion, progression direction |
| `EquipmentSetup` | Instance ID, exercise/variant reference, attachment, seat/pad settings, optional user notes, revision |
| `ExerciseEquipmentBinding` | Exercise/variant ID, equipment ID, preferred setup, last confirmed use |
| `EquipmentAlias` | Old/new IDs, explicit equivalence scope, confirmation, effective history range |
| Existing set model extension | Equipment ID, load-model revision, convention, original load, interpretation status |

Version performance-relevant load changes. Keep historical sets tied to the meaning in force when logged. Do not rewrite history when a user edits today's machine settings.

### 4.4 Workout flow

```text
Open exercise -> suggested equipment from this Gym Profile
              -> confirm/change only when necessary
              -> show remembered setup compactly
              -> prescribe an attainable load
              -> log through existing UI/voice/Watch paths
```

A known equipment binding should add no recurring mandatory setup step. Unknown equipment gets a clear “Not linked” state, not a made-up match.

### 4.5 Engine behavior

Before issuing a load, resolve the load domain and select an attainable prescription within the active program rules. If the intended increment is unavailable, use an allowed rep progression or retain the load. If neither is permitted, return a conflict with explicit alternatives.

For assistance, distinguish less assistance from more external resistance. Do not reuse ascending-mass progression without a domain-specific rule.

Keep e1RM and volume interpretation conservative: preserve existing validated metrics where meaningful, label equipment-specific series, and avoid mass-based calculations for arbitrary machine scales. Show raw performance without inventing a comparable aggregate.

### Implementation tasks

- [ ] **EQP-01 — Inventory model and migration.** Add the entities and set references without forcing ambiguous legacy history into a machine.
- [ ] **EQP-02 — Gym Profile editor.** Add, rename, duplicate, retire, and configure equipment; validate units and attainable values.
- [ ] **EQP-03 — Workout binding UI.** Add compact equipment selection and remembered setup fields; support temporary equipment changes.
- [ ] **EQP-04 — Attainable-load adapter.** Integrate load constraints with progression, plate calculations, warm-ups, and substitutions.
- [ ] **EQP-05 — Comparison and charts.** Partition performance where required and explain why a result is not comparable.
- [ ] **EQP-06 — History correction tools.** Preview explicit load-convention corrections and equipment aliases; preserve original records and recalculate derived metrics.
- [ ] **EQP-07 — Voice and Watch parity.** Ensure each log inherits the intended equipment context and retains enough metadata when the phone is unavailable.
- [ ] **EQP-08 — Conflict and edge-case suite.** Cover mixed units, unilateral records, assistance, retired machines, changed stacks, and concurrent setup edits.

### Acceptance criteria

- Two cable stations can have independent histories even when the exercise name matches.
- A per-hand dumbbell entry cannot silently become a combined-weight entry.
- An unavailable weight is never prescribed as directly loadable.
- An assistance exercise progresses according to its defined domain, not a generic ascending-value rule.
- A machine rename preserves continuity; a load-model change preserves the old interpretation.
- Equipment retirement leaves historical sets readable.
- Existing logs remain accessible when new metadata is incomplete or the flag is disabled.

**Primary measures:** User-reported unachievable prescriptions, load-meaning corrections, and mistaken performance-series merges. Do not classify every manual load edit as an engine error.

---

## 5. Recommendation confidence and outcome checks

**ID:** REC  
**Depends on:** Foundation; Equipment Passport enriches comparison quality but is not required for basic recording.  
**Primary surfaces:** Internal evaluation tools, existing recommendation cards, existing Progress details.

### 5.1 User outcome

“I can see what information supports a recommendation and whether the resulting prescription matched my actual session.”

This extends explanations; it does not add another generic AI summary feed.

### 5.2 Separate three concepts

| Concept | Meaning | Must not imply |
|---|---|---|
| Evidence support | Amount, relevance, freshness, and consistency of usable information | A calibrated probability that the recommendation will work |
| Prescription fit | Whether the actual comparable result matched the stated target | That the recommendation caused improvement |
| Longer-term observation | What happened across a defined review period | A controlled causal finding from ordinary training logs |

Use plain support labels such as **Limited**, **Some comparable history**, and **Established comparable history**, backed by visible counts and reason codes. Do not display numerical probability until a separately defined model has been calibrated and evaluated.

### 5.3 Data additions

```text
RecommendationSnapshot
  recommendationID / actionID
  engineVersion / policyVersion / comparisonVersion
  issuedAt / targetSessionOrSetID
  inputRevisionReferences
  originalPrescription
  comparableRecordIDs
  evidenceSummary / missingInputReasons
  originalAuthorization / originalUserDecision
  privacyClassifications

RecommendationExposure
  recommendationID
  actualPrescriptionUsed
  followed | modified | notUsed | unknown
  userCorrectionReason (optional)

RecommendationOutcome
  recommendationID / sourceResultRevisions
  evaluationPolicyVersion / evaluatedAt
  eligibilityStatus
  withinTarget | belowTarget | aboveTarget | notAssessable
  observedValues (local, permitted fields only)
  limitations / invalidationReason
```

Preserve the original decision and the information available at that time. History corrections invalidate or supersede derived evaluations; they must not retroactively make the original prediction look different.

### 5.4 Behavior rules

Missing sleep is missing sleep. It must not be assigned a negative value. Inconsistent units, new equipment, interrupted sets, and stale baselines can reduce comparability or make an outcome not assessable.

The current engine remains the source of progression rules. Add evidence-aware gates around existing decisions: request a focused clarification, avoid unsupported escalation, or preserve the current prescription where allowed. Do not introduce new physiological thresholds from arbitrary sample counts in this document.

A user modification is an exposure change, not automatically a failed recommendation. Evaluate prescription fit only against the relevant executed prescription and disclose when the original recommendation was not followed.

For Training Experiments, reuse the same comparison service and add an **inconclusive** result when missing sessions, equipment changes, mixed interventions, or insufficient comparable data prevent a meaningful keep/revert interpretation.

### Implementation tasks

- [ ] **REC-01 — Decision snapshots.** Record versioned recommendation inputs and targets locally with privacy-aware field selection.
- [ ] **REC-02 — Evidence rules.** Implement structured support reasons, unknown-input handling, and policy-versioned comparability rules.
- [ ] **REC-03 — Exposure tracking.** Distinguish accepted, actually followed, modified, and unused prescriptions.
- [ ] **REC-04 — Outcome evaluator.** Evaluate after eligible results; handle missing effort, changed equipment, excluded sets, and history revisions.
- [ ] **REC-05 — Engine support gates.** Add tested responses for limited evidence without replacing existing progression logic.
- [ ] **REC-06 — Evidence UI.** Add an expandable evidence section with concrete counts and limitations; keep Health-derived evidence local and outside Coach context.
- [ ] **REC-07 — Internal review tools.** Show errors, ineligible outcomes, override reasons, and version comparisons using synthetic or explicitly consented sanitized data.
- [ ] **REC-08 — Experiment integration.** Reuse baseline/keep/revert infrastructure and introduce explicit inconclusive outcomes and changed-condition warnings.
- [ ] **REC-09 — Deletion and recomputation.** Delete snapshots when required and invalidate derived outcomes when underlying facts are corrected or removed.

### Acceptance criteria

- An LLM cannot set its own evidence-support label or mark its action successful.
- A missing signal never silently becomes zero.
- A corrected history entry preserves the original decision snapshot and supersedes the derived evaluation.
- A recommendation that was not followed is not counted as a successful intervention.
- An equipment change can yield “not assessable” rather than a false plateau or success.
- A four-week experiment can end inconclusively without pressuring the user into a keep/revert decision.
- No Health-specific evidence leaks through sync, analytics, or Coach tool responses.

**Primary measures:** Evaluable-outcome coverage, target-fit distribution, correction reasons, reversals, and missing/ambiguous-data rates. Historical replay measures reproducibility and policy behavior; it does not reveal unobserved outcomes under alternative prescriptions.

---

## 6. Coach My Program

**ID:** PRG  
**Depends on:** Shared action, load, migration, and privacy contracts; integrate EQP and REC before general release.  
**Primary surfaces:** Existing program/onboarding flow and Coach settings for the active program.

### 6.1 User outcome

“I can keep a program I trust and choose exactly how much ReguLift may adapt it.”

This imports **planned training structure and progression rules**, not historical sessions. Keep the existing Strong/Hevy history importer intact and label the two workflows differently.

### 6.2 Import and activation flow

```text
Paste text / enter structured rows / open a supported program template
  -> extract an untrusted draft
  -> map exercises and flag ambiguities
  -> review weeks, sessions, sets, rest, targets, and progression rules
  -> resolve unsupported rules
  -> select adaptation permissions
  -> validate against equipment and schedule
  -> preview first session
  -> confirm activation
```

The deterministic structured editor must work without a remote model. Natural-language extraction can use the existing local/server routing with an explicit disclosure before private program text is sent remotely.

Do not require PDF parsing, OCR, web scraping, or images for the first complete implementation. Text, structured entry, and the typed share format cover this roadmap's promised workflow.

### 6.3 Supported rule language

Use a versioned, bounded schema interpreted by the engine, not executable user code. Implement a small explicit vocabulary:

| Rule | Required interpretation |
|---|---|
| Fixed prescription | Sets, rep target/range, rest, and a user-confirmed load or starting-load method |
| Double progression | Rep range, success criterion, permitted increment, and repeat behavior |
| Percentage of baseline | Explicit baseline type, value, unit, comparison context, and version |
| Effort-guided target | Existing supported RPE/RIR semantics and engine bounds; preserve which effort scale the user entered |
| Scheduled variation/deload | Explicit per-week changes with a bounded number of weeks and session definitions |

Unsupported rules remain visible and block activation until resolved or explicitly converted by the user. Never replace an unknown progression rule with “standard progression” without a reviewed change.

Use the existing validated engine limits for sets, reps, effort, load changes, and volume. This document intentionally does not invent new physiological safety thresholds.

### 6.4 Program-level adaptation contract

| Dimension | Follow exactly | Adjust my targets | Coach within boundaries |
|---|---|---|---|
| Execute original supported progression rules | Yes | Yes | Yes |
| Engine-adjust load/rep targets beyond those rules | No | Within reviewed bounds | Within reviewed bounds |
| Change weekly sets | No | No | Only within approved limits |
| Substitute exercises | Only as explicitly encoded | Only as explicitly encoded | Within approved substitution rules and locks |
| Change split/session order | No automatic changes | No automatic changes | Only when explicitly allowed |
| Move scheduled days | Only within separately approved scheduling permissions | Same | Same |
| Override an exercise lock or hard constraint | Never silently | Never silently | Never silently |
| Bypass a safety block | Never | Never | Never |

“Follow exactly” executes the original rules, including their own progression. It does not freeze every weight forever.

A safety block may stop an operation; it does not authorize rewriting the program. If a program and hard constraint cannot both be satisfied, return a conflict and ask the user to approve a specific revision.

### 6.5 Data additions

| Entity | Important fields |
|---|---|
| `ProgramDefinition` | ID, title, source type, owner, private-by-default state, schema version |
| `ProgramVersion` | Immutable structure, sessions/weeks, rule definitions, content digest |
| `ProgramExerciseSlot` | Exercise mapping, variants, target scheme, rest, rule reference, lock references |
| `AdaptationContract` | Mode, allowed dimensions, limits, protected structure, scheduling permissions, consent receipt, revision |
| `ProgramEnrollment` | Program version, user-specific baselines and equipment bindings, start position, active state |
| `ImportDraft` | Original text stored only as needed, field provenance, unresolved mappings, parse warnings |

Separate reusable structure from personal working loads and history. That separation is the basis for program sharing later.

### Implementation tasks

- [ ] **PRG-01 — Program schema.** Extend existing program models with immutable versions, supported rule types, and explicit enrollments.
- [ ] **PRG-02 — Deterministic compiler.** Validate and compile reviewed definitions into current engine inputs; reject unknown types and out-of-bound structures.
- [ ] **PRG-03 — Text/structured import.** Build draft extraction and a usable manual editor. Bound input size, nesting, weeks, sessions, and expressions.
- [ ] **PRG-04 — Review experience.** Show original-versus-interpreted fields, unresolved exercises, ambiguous units, and unsupported rules before activation.
- [ ] **PRG-05 — Adaptation contract UI.** Implement the three modes, plain-language summaries, fine-grained boundaries, and versioned consent.
- [ ] **PRG-06 — Engine enforcement.** Apply the contract to next-set adaptation, deloads, plateau rescue, substitutions, volume changes, and missed-workout handling.
- [ ] **PRG-07 — Lifecycle.** Support duplicate, edit-as-new-version, pause, archive, restart, and explicit migration to a newer version without changing completed history.
- [ ] **PRG-08 — Start and baseline handling.** Resolve units and equipment; use reviewed starting-load methods rather than importing another person's prescriptions blindly.
- [ ] **PRG-09 — Import security.** Treat program text as data, not instructions to the Coach. Validate schema, escape rendered text, reject scripts, and prohibit automatic URL fetching.
- [ ] **PRG-10 — Integration and regression.** Test every adaptation mode against equipment limits, weekly planning, exercise locks, and offline resume.

### Acceptance criteria

- A user can import a supported multiweek program, inspect it, and complete the first two sessions without surrendering its original structure.
- Unknown rules or ambiguous exercise/load mappings cannot silently reach the active plan.
- Strict mode prevents otherwise-valid adaptive changes that are outside the program's permissions.
- Changing the adaptation mode shows the impact and creates a new contract revision.
- Editing a program creates a new version; active and historical sessions retain their original references.
- Instruction-like text inside a pasted program cannot invoke Coach tools or publish data.
- Private imported material is not made shareable merely because import succeeded.

**Primary measures:** Import-to-activation completion, unresolved-field frequency, first/second workout completion, unexpected-change reports, and retained users who bring a program.

---

## 7. Week Designer

**ID:** WKD  
**Depends on:** PRG adaptation permissions, EQP equipment feasibility, REC decision recording, foundation contracts.  
**Primary surfaces:** Today, the existing program calendar, and a compact weekly planning sheet.

### 7.1 User outcome

“Build a feasible week from the time and equipment I will actually have, and let me compare the tradeoffs before committing.”

### 7.2 Manual planning flow

Enter availability for seven days, the intended Gym Profile for each slot, and optional other exercise. Let users protect sessions or priorities and compare proposed schedules.

Example inputs: Monday 40 minutes, Wednesday 55 minutes, Saturday 30 minutes; a hard cycling session on Friday. These are illustrative user constraints, not default prescriptions.

For each scenario show session timing, estimated duration range, exercise distribution, planned sets, priorities retained/reduced, and the exact rules being changed. Do not display predicted muscle gain or an exact date of future strength improvement.

### 7.3 Constraint model

| Hard constraints | Soft preferences |
|---|---|
| User availability and explicit time limits | Preferred training days and start times |
| Actual equipment availability | Preferred Gym Profile |
| Program contract and exercise locks | Less disruption from the previous schedule |
| Completed or in-progress sessions | Balanced distribution across available slots |
| Existing engine safety rules | Optional emphasis priorities within permitted ranges |
| User-marked protected sessions | Convenience around manually entered other exercise |

A preference becomes hard only when the user explicitly protects it. Track that distinction in the model and UI.

Use the existing engine for recovery/volume constraints rather than inventing a new fatigue equation in the scheduler. Manually entered other exercise can influence already-supported planning rules; unsupported impacts should be shown as context, not converted into false precision.

### 7.4 Planning algorithm

Generate candidates with a bounded deterministic search. Start with permitted placements of existing sessions; then consider only contract-authorized changes. Score feasible candidates using a versioned, inspectable preference function and stable tie-breakers.

Estimate duration from warm-ups, work sets, rest, unilateral execution where relevant, setup, and transitions. Show an estimate or range, not a guarantee. Validate against a conservative bound; retain the existing in-session time-budget workflow when reality differs.

Return a typed status:

```text
feasible(candidates, tradeoffs, assumptions)
infeasible(provenConflicts, explicitRelaxationChoices)
searchLimitReached(bestFeasibleCandidate?, unexploredConstraints)
needsInput(ambiguousOrMissingConstraints)
```

“No feasible plan found within the search limit” must not be presented as “No plan is possible.” Do not claim that a weighted candidate score is a medically optimal schedule.

Compare scenarios without persisting them as the active plan. Applying one requires a diff and confirmation, and cannot move completed/in-progress sessions or violate new changes made since preview.

### 7.5 Calendar extension—included scope

Implement calendar integration after the manual workflow passes its release gate. Reading events requires the appropriate EventKit access; write-only access does not enable free/busy discovery. Use a user-mediated event editor for simple add-to-calendar where suitable, and request full access only when the user enables a feature that actually reads or updates existing events. [S3]

Keep calendar processing local. Extract busy intervals for the selected planning horizon without storing event titles, notes, attendees, or locations. Do not transmit calendar contents to the Coach.

Handle denied/revoked access with the manual editor, not a blocked planning flow. Distinguish calendar export from calendar-aware scheduling; one must not silently grant or imply the other.

For app-created events, retain the mapping needed for updates only when authorized. Propose event changes for confirmation. Never edit unrelated events or repeatedly insert duplicates after retries.

A changed calendar creates a proposed schedule revision; it does not silently rewrite the accepted training week.

### 7.6 Data additions

| Entity | Important fields |
|---|---|
| `AvailabilityWindow` | Local date/time components, time zone, duration, recurrence if supported, location/Gym Profile, hard/soft flag |
| `OtherActivityConstraint` | User-entered category, time, self-reported intensity category, protection flag |
| `WeekPlanDraft` | Input revisions, candidate schedules, score/reasons, search status, assumptions |
| `AcceptedWeekPlan` | Baseline version, accepted schedule, later amendments, confirmation receipt |
| `CalendarBusyCache` | Local intervals, selected horizon, retrieval time, expiry; no event content |
| `CalendarExportMapping` | App session ID, event identifier where accessible, revision, export state |

Distinguish floating local availability from fixed-time commitments when traveling. Test time-zone changes, daylight-saving boundaries, cross-midnight slots, and different first-day-of-week settings.

### Implementation tasks

- [ ] **WKD-01 — Availability editor.** Build reusable weekly availability, Gym Profile selection, and manual other-exercise entries.
- [ ] **WKD-02 — Constraint adapter.** Translate program permissions, time budgets, equipment, and protected sessions into a typed planning problem.
- [ ] **WKD-03 — Candidate search.** Implement bounded generation, stable scoring, duration estimates, and explicit search-limit/infeasibility states.
- [ ] **WKD-04 — Scenario comparison.** Show two/three/four-session alternatives only when permitted, with actual plan differences rather than growth predictions.
- [ ] **WKD-05 — Commit and amendments.** Apply a confirmed schedule atomically; retain baseline and amendment versions; protect active/completed sessions.
- [ ] **WKD-06 — Existing recovery integration.** Route later missed workouts and Travel/Crowd changes through the same contract and plan-version model.
- [ ] **WKD-07 — Calendar access and privacy.** Implement separate read-aware planning and export permissions with local busy-interval extraction. [S3]
- [ ] **WKD-08 — Calendar export/reconciliation.** Prevent duplicates, surface external edits, and update only explicitly selected app-created events when authorized.
- [ ] **WKD-09 — Time and search tests.** Cover denied permissions, zero availability, impossible locks, capped search, travel, and concurrent plan edits.

### Acceptance criteria

- A user can create and accept a complete week offline using manual inputs.
- Every accepted scenario obeys hard constraints at commit time.
- An impossible exact program/time combination yields an explicit choice, never hidden reduced volume.
- A preview does not change training state until confirmed.
- Calendar denial or revocation returns to manual availability gracefully.
- A calendar update does not silently move a workout.
- A failed or repeated event export cannot create uncontrolled duplicate events.
- The accepted baseline and later changes remain distinguishable for adherence reporting.

**Primary measures:** Weekly-plan completion, repeat use, user-initiated amendments, unexpected replans, and last-minute scheduling friction. Report baseline adherence and revised-plan adherence separately.

---

## 8. Set-limiter feedback

**ID:** LIM  
**Depends on:** Shared set revisions and comparison context; REC and PRG integration.  
**Primary surfaces:** Existing set detail, unusual-result prompt, and Coach follow-up card.

### 8.1 User outcome

“Help the app distinguish a training limitation from an interrupted set, a setup issue, or a recording mistake.”

### 8.2 Feedback design

Provide optional reasons: target muscles, grip, breathing, setup problem, technique uncertainty, interrupted set, other, or unsure. Keep pain/discomfort in a separate safety-oriented route, not an ordinary performance-optimization reason.

Prompts appear only when requested or when a rule-defined unusual result makes clarification useful. Proposed UX default: at most one unsolicited prompt per workout, configurable and suppressible. This is an interaction choice, not a physiological threshold.

Let the user correct or remove feedback. Do not require a response to complete a workout.

### 8.3 Action rules

| Feedback | Initial allowed response |
|---|---|
| Interrupted set | Offer exclusion from specified progression/baseline calculations; retain the logged work and show the scope |
| Setup problem | Offer to review Equipment Passport setup and ask whether this set is comparable |
| Grip limitation | Record the context; offer a review only after the versioned evidence rule is satisfied |
| Breathing limitation | Record user feedback; consider only already-supported rest/time adjustments within permissions |
| Technique uncertainty | Show existing curated guidance or suggest qualified coaching; do not diagnose technique from text alone |
| Target muscles / unsure | Preserve feedback; avoid manufacturing a corrective intervention |
| Pain/discomfort | Stop ordinary progression optimization for the affected situation and show approved safety guidance; do not prescribe rehabilitation |

Exclusion is specific: a set can remain visible in completed work while being excluded from a particular progression analysis. Do not erase useful volume/history or rewrite the workout summary silently.

Repeated feedback can form a contextual summary keyed to exercise/equipment. Promoting it to a longer-lived Coach memory requires the existing confirmation, provenance, expiry, conflict, and deletion controls.

### 8.4 Data additions

`SetLimiterEvent` stores set ID/revision, a closed reason code, optional note, source, timestamp, and deletion state. `AnalysisEligibilityOverride` stores the user's confirmed inclusion/exclusion choice, affected analysis types, reason, and revision. Derived summaries reference their source events and invalidate when those events change.

Do not infer that an exercise causes more hypertrophy from limiter feedback, comfort ratings, or a few improved performances.

### Implementation tasks

- [ ] **LIM-01 — Event model.** Add optional structured feedback and explicit analysis-eligibility overrides without replacing set notes.
- [ ] **LIM-02 — Feedback UI.** Add an optional sheet and a dismissible, rate-limited unusual-result prompt.
- [ ] **LIM-03 — Bounded responses.** Map reasons to the permitted review/proposal actions; respect program permissions and exercise locks.
- [ ] **LIM-04 — Comparison integration.** Apply exclusions to named analyses and re-evaluate REC outcomes with transparent reasons.
- [ ] **LIM-05 — Contextual summaries.** Summarize repeated signals conservatively and reuse Coach memory controls when a durable fact is proposed.
- [ ] **LIM-06 — Safety and deletion tests.** Verify the pain branch, no forced answers, no automatic permanent memory, and correct recomputation after edits/deletion.

### Acceptance criteria

- A skipped prompt has no negative effect on readiness, adherence, or awards.
- Excluding an interrupted set from progression does not delete the set.
- One grip-limited set cannot silently replace an exercise or increase volume.
- Correcting feedback updates its derived summaries and future evidence.
- Pain feedback never becomes a reason to push through discomfort or a diagnosis.

**Primary measures:** Prompt burden, voluntary feedback use, helpfulness of the resulting proposal, recurrence of the reported problem, and reversal/deletion rates. Keep raw reasons and text out of general telemetry.

---

## 9. Goal roadmaps and benchmark sessions

**ID:** GOL  
**Depends on:** EQP comparison context, PRG program versions, REC evidence, and existing mesocycles/Progress. WKD schedules benchmark opportunities.  
**Primary surfaces:** Progress, existing mesocycle review, and Today when a benchmark is due.

### 9.1 User outcome

“Connect my training block to a measurable goal, check it fairly, and decide what to do next.”

Start with one active performance goal. Support rep-at-load and other already-supported strength targets without making a maximal attempt mandatory. Distinguish measured benchmark results from estimated metrics.

### 9.2 Goal flow

```text
Choose target -> define exercise and equipment/protocol
              -> establish a reviewed baseline
              -> connect to the current program/block
              -> select a review date or block-end review
              -> schedule a benchmark opportunity
              -> evaluate comparability and result
              -> continue / revise / change approach / defer
```

Treat the date as a review point, not a guaranteed achievement deadline. Do not automatically add extra hard sessions to chase a date.

### 9.3 Benchmark protocol

Capture exercise/variant, equipment/load model, load convention, baseline type, target, warm-up/rest instructions supported by the program, and measurement method. Record relevant deviations at execution.

If equipment or protocol changes materially, show that the result is not directly comparable or establish a separately confirmed baseline. A benchmark must remain deferrable when the existing readiness/safety rules or user preference make it inappropriate.

Goal review should summarize the baseline, comparable observations, deviations, evidence limitations, and a small set of explicit next choices. Reuse existing charts rather than building a separate analytics product.

### 9.4 Data additions

| Entity | Important fields |
|---|---|
| `TrainingGoal` | Type, versioned target, active/paused/completed/archived state, review point |
| `BenchmarkProtocol` | Exercise, comparison context, measurement method, setup, instructions, revision |
| `BenchmarkAttempt` | Scheduled/actual session references, executed conditions, result, deviations, comparability |
| `GoalReview` | Baseline and result references, observed status, limitations, chosen next step, receipt |

A target edit creates a new version. Do not rewrite an earlier goal to make it appear achieved. Editing or deleting a benchmark result must invalidate the relevant success state until recalculated.

### Implementation tasks

- [ ] **GOL-01 — Goal/protocol models.** Extend current goals and mesocycles with versioned measurable targets and benchmark definitions.
- [ ] **GOL-02 — Setup flow.** Add baseline review, equipment context, one-active-goal handling, and plain-language estimated-versus-measured labels.
- [ ] **GOL-03 — Scheduling.** Connect review points to WKD/Today without forcing benchmark attempts or creating extra volume silently.
- [ ] **GOL-04 — Benchmark logging.** Reuse workout logging, record protocol deviations, and evaluate comparability before declaring a result.
- [ ] **GOL-05 — End-of-block review.** Add continue, revise, change approach, and defer choices with explicit plan-change confirmation.
- [ ] **GOL-06 — Lifecycle tests.** Cover equipment changes, edited/deleted results, paused goals, missed benchmarks, and target revisions.

### Acceptance criteria

- A measured benchmark and an e1RM estimate are never displayed as the same kind of result.
- An incompatible machine or loading convention cannot produce a false goal achievement.
- A user can defer a benchmark without punitive messaging or a forced make-up session.
- Goal changes and reviews preserve their historical versions.
- Benchmark-driven plan changes respect the active program contract.

**Primary measures:** Goal setup completion, completed/deferred reviews, valid comparable benchmarks, and progression to another purposeful block. Do not optimize for the number of success badges by lowering targets silently.

---

## 10. Conversational voice Coach

**ID:** VOC  
**Depends on:** Existing Coach/context/RAG/actions, shared proposal lifecycle, privacy projections, and recommendation evidence.  
**Primary surfaces:** A separate “Ask Coach” entry inside the workout and the existing Coach conversation.

### 10.1 User outcome

“I can ask why, clarify what happened, and review a proposed adjustment without typing a long message.”

The existing speech-to-command logging path stays deterministic. **Log a set** and **Ask Coach** are different modes with distinct affordances and state.

### 10.2 End-to-end implementation

```text
User starts Ask Coach
  -> microphone permission and explicit listening state
  -> existing speech adapter produces a transcript
  -> transcript is shown and finalized for this turn
  -> existing Coach receives permitted training context
  -> short answer and/or typed action proposal
  -> local speech output plus visible text
  -> user asks a follow-up or reviews an action
  -> explicit on-screen confirmation for mutations
  -> deterministic validation and commit
```

Reuse the current Apple speech and cloud-transcription adapters, including lifting vocabulary injection. Select capabilities at runtime by device, locale, permissions, available assets, and network state. Do not make a newly assumed OS version or third-party API a release dependency.

Use an adapter for speech output and retain a text-only fallback. The initial complete experience is turn-based: tap to start, stop/end-of-turn detection, short spoken replies, follow-up turns, and an explicit stop button. Always-on listening and unrestricted full-duplex conversation are outside this roadmap.

### 10.3 Conversation state machine

```text
idle -> requestingPermission -> listening -> transcribing
     -> thinking -> speaking -> readyForFollowUp

Any active state -> cancelled | interrupted | recoverableError
A proposed mutation -> awaitingConfirmation -> applying -> result
```

Bind every audio segment, transcript, model response, and action proposal to a conversation and turn ID. A cancelled or superseded turn cannot later emit an active proposal or apply an action.

In the initial turn-based mode, avoid listening while speech output is active. Let the user tap to stop the answer before starting another turn; suppress self-transcription and stale callbacks.

Treat interruptions and audio-route changes as first-class state transitions. Apple documents interruption handling and state restoration through audio-session notifications; validate exact API names and availability in the repository's current SDK. [S5]

### 10.4 Action and context boundaries

Expose only the current Coach tool allowlist. New useful read tools can return equipment setup, the active adaptation contract, comparable recommendation evidence without Health details, and week-plan previews.

New write intentions must create proposals such as `requestEquipmentSetupChange`, `requestProgramPolicyChange`, or `requestWeekPlanCommit`. Do not expose a generic SQL writer, arbitrary method invoker, or unrestricted state-edit tool.

For the initial release, spoken “yes” is not sufficient authorization for a mutation. Show the exact before/after card and require the established on-screen confirmation. Questions and explanations require no mutation confirmation.

The current fast voice-logging commands retain their existing validation and authorization behavior. Entering Coach mode must not broaden the command parser's permissions or change the Watch's existing safe command set.

### 10.5 Privacy, reliability, and cost

Do not persist raw audio in app files, worker logs, tracing, crash reports, or analytics. Verify the selected provider's retention and processing controls before claiming end-to-end no-storage. App-side non-storage alone is insufficient.

Keep the existing cloud/on-device route visibly understandable. Do not silently switch from a user's local-only choice to cloud processing after a failure. Explain that spoken content is transmitted on the cloud path, including whatever the user chooses to say.

Save conversation text only according to the existing Coach conversation settings. Disable raw request/response logging in production. Provide deletion through the existing controls and purge temporary buffers on cancellation and interruption.

Meter provider usage with coarse duration/token counters rather than raw speech. Add configurable turn/context limits, server-side quotas, cancellation propagation, request timeouts, and per-session cost ceilings. Use normal authorized provider credentials through the existing backend; no consumer-subscription proxy is part of this design.

### 10.6 Data additions

`VoiceConversationSession` stores only necessary session metadata. `VoiceTurn` is ephemeral by default; retain transcript text only when the current conversation-retention choice permits it. `ConversationActionLink` links a turn to the existing proposal/receipt. Audio buffers are not persistent entities.

### Implementation tasks

- [ ] **VOC-01 — Separate entry and coordinator.** Implement Ask Coach independently from Log a set, with a testable turn state machine.
- [ ] **VOC-02 — Speech adapter integration.** Reuse current transcription routes, vocabulary, locale handling, and permission states.
- [ ] **VOC-03 — Spoken answer and transcript UI.** Add short responses, visible text, stop/replay controls, and a persistent route indicator where useful.
- [ ] **VOC-04 — Coach tool integration.** Add only narrow reads/proposals for the new feature contexts; preserve RAG and current action protection.
- [ ] **VOC-05 — Confirmation binding.** Connect voice proposals to exact on-screen previews; reject stale, cancelled, or replayed responses.
- [ ] **VOC-06 — Audio lifecycle.** Handle phone interruptions, app backgrounding, music, Bluetooth changes, headphones disconnecting, and media-service resets. [S5]
- [ ] **VOC-07 — Backend controls.** Enforce authentication where required, entitlements, request limits, cancellation, and safe telemetry; keep long-lived provider secrets off the client.
- [ ] **VOC-08 — Privacy verification.** Test local-only behavior, no app-side audio persistence, transcript deletion, and provider-retention documentation.
- [ ] **VOC-09 — Voice regression suite.** Test numeric/decimal ambiguities, exercise names, supported languages, noisy environments, echo, and duplicate end-of-turn events.

### Acceptance criteria

- Asking “Why this weight?” cannot accidentally create a set log.
- A Coach reply cannot execute its own suggested change.
- Cancelling a turn invalidates its late transcript/model/tool callbacks.
- Permission denial or network failure leaves manual logging, typed Coach input, and the active workout intact.
- Interrupted audio does not resume listening without appropriate user-visible state and control.
- The user can identify when audio is being sent to a cloud service.
- No new HealthKit data enters spoken explanations or model context.
- A voice-service quota or entitlement failure does not prevent saving a completed set.

**Primary measures:** Completed question-resolution rate, recognition corrections, proposal cancellation, accidental-action reports, response latency, and cost per resolved conversation. Avoid collecting actual utterances for ordinary analytics.

---

## 11. Shareable adaptive program links

**ID:** SHR  
**Depends on:** PRG's structure/enrollment separation, equipment initialization, existing identity/referrals/backend, shared privacy and entitlement contracts.  
**Primary surfaces:** Existing program detail, share sheet, lightweight web preview, and import onboarding.

### 11.1 User outcome

“Share a program's structure so someone else can start it with their own equipment, baselines, and adaptation choices.”

### 11.2 Publication rules

Only allow publishing a program the user created or has permission to distribute. Add explicit rights confirmation, source/provenance, and a report/removal route. This is a product control, not a legal determination that a particular imported program is redistributable.

Use an authenticated existing owner identity for publishing and revocation. Do not make all offline training or local import require an account. A recipient should be able to preview a template without revealing personal training data or creating an account merely to view it.

Default to an **unlisted link**, not a searchable marketplace. Make clear that anyone holding an unlisted link can access it; do not describe it as authenticated private sharing.

### 11.3 Public template versus personal enrollment

| Allowed in the reviewed template | Excluded from publication |
|---|---|
| Title and user-authored description | Owner's personal workout history |
| Session/week structure | Owner's working loads, baselines, body measurements, or goals |
| Exercise IDs or reviewed custom exercise definitions | HealthKit information and recovery records |
| Sets, rep ranges, rest, supported progression rules | Gym names, locations, actual machine IDs, and setup notes |
| Generic equipment requirements | Coach memory, conversations, private notes, and raw import source text |
| Suggested adaptation boundaries | Personal schedule/calendar data |
| Version and optional public author display name | Private account identifiers or access tokens |

A fixed-load or percentage program requiring personal baselines must publish a supported **recipient-input requirement** or reviewed starting-load method. Strip neither the field nor its meaning silently. Block publishing until the resulting template is complete and valid.

Before publishing, show the exact sanitized content. Scan free-text fields for obvious private data and ask for review, but do not rely on a scanner as the privacy boundary. The allowlisted schema is the boundary.

### 11.4 Link and import flow

```text
Owner: select program version -> sanitize -> review -> confirm rights
     -> publish immutable template version -> receive unlisted link

Recipient: open web/app link -> review structure and equipment needs
         -> import as private draft -> bind personal equipment
         -> establish personal baselines -> choose permissions
         -> review first session -> activate
```

Use HTTPS universal links with the app/domain association configuration and a web fallback. Apple documents the website association file and app entitlement as the basis of universal links. [S4]

Do not assume an App Store installation automatically preserves an incoming link. Provide a simple “reopen this link after installation” path and an optional short import code, without device fingerprinting or hidden clipboard reads.

A template version is immutable. An author update creates a new version and must not change an existing recipient's active plan automatically.

Revocation stops future server access to the published template. It cannot reliably erase copies already imported to another device; state that plainly. Keep recipient imports independent of later link availability.

### 11.5 Proposed backend contract

Reuse the current backend and authentication. These are proposed application routes, not existing endpoints:

| Method and route | Behavior |
|---|---|
| `POST /v1/program-shares` | Authenticated publish of a validated sanitized template; idempotent request ID |
| `GET /v1/program-shares/{token}` | Fetch a bounded public projection for a valid unlisted link |
| `GET /v1/program-shares/{token}/versions/{version}` | Fetch one supported immutable version |
| `DELETE /v1/program-shares/{shareID}` | Owner-authorized revocation, audit receipt, cache invalidation |
| `POST /v1/program-shares/{token}/reports` | Rate-limited report without exposing owner/private recipient data |

Use high-entropy random tokens, strict payload limits, server-side schema validation, authorization tests, rate limits, safe text rendering, and supported-version checks. Avoid embedding the entire program, personal data, or credentials in the URL.

Make revoked and expired links unavailable at the origin and purge/bypass relevant caches. Disable indexing and minimize token exposure in logs, referrers, and third-party page assets. An unlisted link is still a bearer access mechanism; disclose that limitation.

### 11.6 Data additions

`PublishedProgramTemplate` stores the sanitized immutable content and schema version. `ProgramShareRecord` stores owner, token digest or appropriately protected token mapping, publication/revocation state, rights confirmation, and version references. `ProgramImportReceipt` records template/version provenance separately from the recipient's personal enrollment.

### Implementation tasks

- [ ] **SHR-01 — Public projection schema.** Build an allowlisted serializer distinct from the internal program/enrollment model.
- [ ] **SHR-02 — Sanitization and completeness.** Remove private fields, replace personal load dependencies with recipient-input requirements, and block incomplete templates.
- [ ] **SHR-03 — Owner publication UI.** Add exact-content preview, rights confirmation, optional author display, publish, and revoke.
- [ ] **SHR-04 — Backend lifecycle.** Implement owner authorization, immutable versions, tokens, rate limits, reports, and cache-safe revocation.
- [ ] **SHR-05 — Web preview and universal links.** Add app routing, website association, unsupported/expired states, and an install/reopen fallback. [S4]
- [ ] **SHR-06 — Recipient onboarding.** Import privately, bind equipment and baselines, choose permissions, and confirm before activation.
- [ ] **SHR-07 — Version and duplicate handling.** Reopening a link does not silently duplicate/replace a plan; updates remain explicit.
- [ ] **SHR-08 — Referral attribution.** Reuse existing referrals with consent-appropriate coarse attribution; do not expose private recipient progress to the author.
- [ ] **SHR-09 — Security and privacy tests.** Cover cross-owner revocation attempts, malformed templates, unauthorized fields, token leakage, stale caches, and replayed requests.

### Acceptance criteria

- A recipient never inherits the author's actual working weights or Health/history data.
- A fixed-load program cannot publish with a hidden unresolved personal baseline.
- Opening a link alone never activates or changes a program.
- A published update does not mutate an imported active plan.
- Revocation blocks new fetches while already imported private copies remain usable.
- The owner can revoke only their own shares, and receives a clear result.
- An unsupported template version fails safely without partial database writes.
- The flow works for a web visitor without the app and an installed-app user; post-install recovery is explicit.

**Primary measures:** Valid preview-to-import conversion, first completed workout, second workout, and retained paid users attributed to a share. Do not equate automated preview fetches with real user interest.

---

## 12. Cross-feature UX and platform integration

### 12.1 Preserve the existing navigation

| Current surface | Additions |
|---|---|
| Today | Accepted week, upcoming benchmark, one relevant planning/evidence prompt |
| Workout / Focus Mode | Compact equipment label, remembered setup, optional limiter feedback, separate Ask Coach |
| Coach | Adaptation-contract summary, bounded action cards, voice turns, evidence without Health details |
| Progress | Comparable equipment series, recommendation outcomes, goal and experiment reviews |
| Gym Profiles / settings | Equipment inventory, relevant permissions, privacy/deletion controls |
| Program detail | Import/edit/version history, adaptation permissions, sharing |

Do not create a top-level tab for each feature. Use progressive disclosure: detailed evidence, contracts, and setup history belong behind an appropriate detail view.

### 12.2 Integration requirements

- [ ] **UX-01 — Component reuse.** Extend existing cards, sheets, confirmation previews, loading states, and empty states rather than introducing unrelated visual systems.
- [ ] **UX-02 — Workout friction.** Known-equipment logging adds no required tap; limiter feedback remains optional; voice has a clear stop control.
- [ ] **UX-03 — Accessibility.** Test screen-reader order, meaningful load/convention labels, large text, non-color-only status, sufficient tap targets, and alternatives to gestures/audio.
- [ ] **UX-04 — Localization.** Localize all new strings through the current system; test exercise-name mapping, decimal separators, plural forms, long translations, units, and first-day-of-week preferences.
- [ ] **UX-05 — Watch parity.** Synchronize accepted equipment and target context; preserve safe offline logging and surface incompatible/stale context without losing the set.
- [ ] **UX-06 — Widgets and Live Activity.** Show only accepted current plan/goal data. Never display an unconfirmed preview as the active prescription.
- [ ] **UX-07 — Permission timing.** Request microphone/calendar access at the feature entry point, with a usable denied-permission path. Do not add an all-permissions onboarding wall.
- [ ] **UX-08 — Notification discipline.** Reuse existing preferences and quiet hours; do not add daily pressure or send Health/limiter details in lock-screen notifications.

### 12.3 Example microcopy

| Situation | Proposed wording |
|---|---|
| Equipment unknown | “Choose this machine to keep its loads and setup separate.” |
| Evidence limited | “There is not enough comparable history for a stronger conclusion.” |
| Unsupported import rule | “This rule needs your review before the program can start.” |
| Program/time conflict | “These time limits do not fit the protected sessions. Review the options.” |
| Search cap reached | “No feasible schedule was found within this search. Try another arrangement.” |
| Interrupted set | “Keep this set in your log, but exclude it from progression calculations?” |
| Benchmark mismatch | “This setup differs from your baseline, so the result is not directly comparable.” |
| Voice cloud route | “Your speech is sent to the selected transcription service.” |
| Unlisted sharing | “Anyone with this link can view the template. Your personal training data is not included.” |

Review all copy against actual behavior. Do not advertise guarantees the implementation cannot enforce.

---

## 13. Testing, privacy, and operational quality

### 13.1 Test strategy

Use unit/property tests for deterministic rules, integration tests for state transitions and persistence, UI tests for critical user flows, and physical-device tests for speech, Watch, background behavior, and permissions.

Use synthetic fixtures by default. Production histories used for diagnostic evaluation require explicit permission, minimization, and an approved deletion path. Ordinary analytics is not a back door for collecting training histories.

### 13.2 Required regression matrix

| Area | Cases | Required outcome |
|---|---|---|
| Loading semantics | kg/lb; decimal comma; per-hand/combined; plates-only; assistance; machine steps | Preserve original meaning; reject ambiguity before comparison or prescription |
| Equipment | Rename; retired machine; unavailable increment; altered stack; duplicate inventory entries | No false PR, silent equivalent-machine assumption, or impossible load |
| Program permissions | Every mode plus locked exercise, required volume, and unavailable equipment | No hidden permission widening; typed conflict when necessary |
| Import | Huge/nested input; unknown rule; unsupported version; malicious instructions; invalid targets | Bounded parsing; no tool execution; atomic activation only after review |
| Weekly planning | Zero slots; short slots; protected days; active/completed session; capped search | Correct conflict/search status; no unauthorized edits |
| Time | Travel; changed time zone; cross-midnight slot; daylight-saving transition | Stable intended dates/times and explicit handling of ambiguous local times |
| Evidence | Missing inputs; new equipment; changed interpretation; unavailable outcome | Unknown/not-assessable remains explicit |
| Outcome evaluation | User deviates; set excluded; history edited/deleted; duplicate completion event | Correct exposure and revision tracking; no false effectiveness claim |
| Feedback | Skipped prompt; conflicting feedback; deletion; pain branch | No penalty; no forced persistent memory; safe bounded behavior |
| Goals | Estimated versus measured; incompatible baseline; missed benchmark; revised target | No false achievement or compulsory maximal attempt |
| Voice | Permissions denied; noise; decimal ambiguity; cancellation; echo; late response | No accidental action, lost set, or cross-mode command execution |
| Audio lifecycle | Incoming interruption; background; route change; media reset | Visible recoverable state; no surprise recording or stale execution |
| Sharing | Missing app; unsupported schema; revoked link; caches; owner auth failure | Safe preview/import, enforceable new-fetch revocation, no private-data leak |
| Sync | Duplicate messages; out-of-order delivery; two offline edits; old client | Deduplicate/converge or expose conflict; preserve sets and program versions |
| Privacy | Model payload; sync; logs; analytics; notifications; public template | Forbidden fields do not cross their boundaries |
| Billing | Restore; expiration; pending state; no network; mid-workout transition | Correct entitlements; no loss of captured work or user-data access |
| Migration | Every supported old store; low storage; interruption; retry | No silent reset, corruption, or unrecoverable launch loop |
| Rollback | Each feature flag off after real use | Existing records remain readable and critical training remains usable |

### 13.3 Deterministic invariants

```text
Same canonical inputs + same engine/policy version -> same decision.
Every applied action has a valid authorization and receipt.
One action ID -> at most one committed domain effect.
Accepted plan -> all hard constraints pass at commit time.
History revision -> affected derived results are invalidated/recomputed.
Public template -> no fields outside its publication schema.
Missing input -> never silently synthesized as a negative measurement.
Disabled feature -> no deletion of the user's underlying records.
```

Add seeded property tests for loading boundaries, plan constraints, revision ordering, and repeated events. Keep seeds and minimal failing cases in CI output without user data.

### 13.4 Proposed performance budgets

These are initial **engineering targets**, not measured app performance or delivery promises. Benchmark on the oldest supported practical test device with a production-sized synthetic store, then record any justified adjustments.

| Path | Initial target |
|---|---|
| Set-save and local UI acknowledgement | p95 below 300 ms; no dependency on network/LLM |
| Equipment lookup / attainable-load resolution | p95 below 100 ms after relevant context is loaded |
| Common manual week-plan search | p95 below 1 second; cancellable search with a 3-second foreground budget |
| Recommendation evaluation | Off the immediate logging path; bounded batches with foreground catch-up |
| Voice | Record end-of-turn-to-first-response latency; visible processing and cancellation immediately; provider-specific target set after a spike |
| Template preview | Bounded payload, responsive loading/error state, no indefinite wait |

Do not rely on an OS background task running at an exact time to keep plans or outcomes correct. Reconcile on app foreground and relevant user actions as well as supported background opportunities.

### 13.5 Rollout and rollback

Evaluate feature flags separately from entitlements. Start flags off for existing users, exercise them in internal builds, and expand to an opt-in cohort before general exposure. The percentages are a release-management choice, not a requirement for a particular rollout platform.

A kill switch disables new entry/generation, not reading completed history. Retain schema compatibility and the ability to log an already-started workout. Do not downgrade a migrated store as a rollback strategy; roll forward with compatible fixes.

For cloud services, include timeouts, rate limits, request IDs, cancellation propagation, sanitized errors, and a documented degraded state. Sharing outages must not invalidate already imported programs. Voice outages must not invalidate manual logging.

### 13.6 Quality tasks

- [ ] **QA-01 — Coverage matrix.** Turn every row above into owned automated/manual cases with fixture IDs.
- [ ] **QA-02 — Load/plan property tests.** Validate invariants against seeded generated inputs and retain reproducible failures.
- [ ] **QA-03 — Migration/sync harness.** Test actual persisted store upgrades and device-version combinations, not only in-memory model creation.
- [ ] **QA-04 — Privacy boundary tests.** Assert forbidden-field absence in every payload projection and verify actual outgoing requests in test builds.
- [ ] **QA-05 — Physical-device audio/Watch tests.** Run interruptions, disconnected devices, backgrounding, and unavailable assets/locales.
- [ ] **QA-06 — Performance profiling.** Benchmark the stated paths without logging sensitive data or blocking the workout UI.
- [ ] **QA-07 — Feature rollback drills.** Disable each new feature after records exist and demonstrate safe read/log behavior.
- [ ] **QA-08 — Deletion drills.** Delete equipment notes, feedback, goals, conversations, program imports, snapshots, and an account; verify derived records, caches, and sync tombstones follow the documented policy.
- [ ] **QA-09 — Release incident playbook.** Document severity, affected flags, backend response, data-repair path, and user communication for each failure class.

No feature passes general release with a known data-loss, unauthorized-mutation, private-data-exposure, or cross-owner-access defect. A zero count in the test suite is a test result, not a guarantee that production has zero risk.

---

## 14. Analytics and success measurement

### 14.1 Event envelope

Use the existing analytics system and consent model. Proposed allowed common fields are event ID, schema version, feature flag cohort, app/engine version, coarse platform/capability category, timestamp, and a consent-appropriate pseudonymous installation/account reference.

Events generated offline retain their original timestamp and deduplicate by event ID. Do not send free text, equipment names, calendar data, precise loads, medical/pain descriptions, raw transcripts, audio, or program contents as event properties. Operational billing/rate-limit records should be separated from optional product analytics.

### 14.2 Event catalogue

| Feature | Proposed events | Safe feature-specific properties |
|---|---|---|
| EQP | `equipment_created`, `equipment_bound`, `load_constraint_conflict`, `load_interpretation_corrected` | Equipment-kind enum, load-domain enum, coarse conflict code |
| REC | `recommendation_presented`, `recommendation_exposure_recorded`, `outcome_evaluated` | Engine version, support category, evaluable/not-assessable, coarse outcome category |
| PRG | `program_import_started`, `program_import_reviewed`, `program_activated`, `program_contract_changed` | Import type, unsupported-rule category, mode, draft-completion status |
| WKD | `week_plan_requested`, `week_plan_previewed`, `week_plan_accepted`, `week_plan_amended` | Candidate count bucket, solver status, amendment source, manual/calendar mode |
| LIM | `limiter_prompt_shown`, `limiter_prompt_dismissed`, `limiter_feedback_saved`, `limiter_proposal_reviewed` | User-initiated versus prompted, action category; no raw limiter reason |
| GOL | `goal_created`, `benchmark_reviewed`, `goal_review_completed` | Measurement category, comparable/not-comparable, selected next-step category |
| VOC | `voice_coach_started`, `voice_turn_resolved`, `voice_turn_failed`, `voice_proposal_reviewed` | Local/cloud route, latency bucket, coarse failure code, cost counters |
| SHR | `program_share_published`, `program_share_revoked`, `program_template_previewed`, `program_template_imported` | Template schema, supported/not-supported, coarse attribution channel |

Potentially sensitive derived properties still require privacy review. When an aggregate cannot be produced within the permitted boundary, keep it local or omit it instead of expanding collection silently.

### 14.3 Metric definitions

| Metric | Proposed definition |
|---|---|
| Second-workout completion | Users who complete a second valid workout within 14 days of their first / users with a first workout and a fully observed 14-day window |
| Four-week training retention | Users with at least one valid completed workout on days 22–28 after their first / first-workout users with a fully observed 28-day window |
| Baseline weekly adherence | Completed planned sessions attributable to the originally accepted week / sessions in that original accepted plan |
| Revised-plan adherence | Completed planned sessions / sessions in the latest accepted revision; always display amendment context alongside it |
| Recommendation evaluability | Recommendations with an eligible observed outcome / recommendations due for evaluation |
| Prescription fit | Eligible outcomes inside their predefined target / all eligible evaluated outcomes, stratified by recommendation type |
| Import activation | Reviewed drafts activated / import drafts started; separately report abandoned and unresolved drafts |
| Voice resolution | Turns explicitly resolved or completed under a predefined interaction rule / started turns; do not infer satisfaction solely from silence |
| Share activation | Recipients completing their first valid workout from an imported template / recipients importing that template |
| Paid conversion | Eligible new/trial users becoming paid in a fixed observation window / fully observed eligible cohort; define refunds and restores separately |

Use existing workout-completion semantics and exclude test/demo data and duplicate records. Do not invent a high minimum workout length that disqualifies Minimum Effective Workouts.

Fix metric definitions and observation windows before evaluating a release. Flag right-censored cohorts instead of reporting incomplete windows as failure. Avoid double-counting one user/session across devices or one template fetch across bots and browser previews.

Compare cohorts by experience, import source, equipment-data completeness, and device capability only when those categories are already permitted and sample sizes are adequate. Report counts and uncertainty; no invented statistical significance.

### Implementation tasks

- [ ] **DAT-01 — Event schema registry.** Add versioned event definitions, allowed properties, consent checks, and schema-validation tests.
- [ ] **DAT-02 — Funnel and cohort queries.** Implement the definitions above against available permitted data, including deduplication and fully observed windows.
- [ ] **DAT-03 — Baseline and experiment setup.** Record pre-release baselines where available; use feature exposure rather than an app-wide before/after average when evaluating adoption.
- [ ] **DAT-04 — Product review dashboard.** Show adoption, retained training, recommendation quality, failures, and voice cost together—not daily opens alone.
- [ ] **DAT-05 — Privacy/deletion audit.** Verify analytics opt-out and deletion behavior, and keep raw training evidence outside ordinary telemetry.

Do not set an arbitrary promised retention lift. Establish the baseline, choose the minimum improvement worth the implementation cost, and predefine the evaluation window before expansion.

---

## 15. Paid-product and website alignment

The public homepage checked on September 18, 2026 describes launch-time free access and future Pro availability. Treat this as a messaging-alignment task against the actual release state, not proof of the in-app billing configuration. [S1]

### 15.1 Proposed entitlement behavior

Use the existing paid/trial product and existing pricing configuration. Group the additions under the ongoing training/coaching value proposition rather than eight separate paywalls.

| Situation | Required behavior |
|---|---|
| Eligible paid/trial user | Access the new features according to existing product policy and enabled flags |
| No network | Preserve the current cached-entitlement policy and available local workflows; do not invent a new online-only dependency |
| Subscription changes mid-workout | Preserve captured sets and permit the active workout to be saved safely |
| Access expires | Preserve reading/exporting/deleting the user's existing data; clearly explain which new generation/service actions require entitlement |
| Shared link visitor | Allow a truthful template preview; disclose any subscription/trial requirement before activation or paid work |
| Cloud voice quota reached | Stop further cloud requests clearly; leave manual logging and available non-cloud paths intact |

Do not require a ReguLift account merely to use the existing local training workflow. Keep subscription receipt handling within the actual billing implementation. Publishing/revoking a share may require an owner account without making ordinary local use account-gated.

### 15.2 Website and store work

- [ ] **BIZ-01 — Entitlement matrix.** Document how every new action maps to current paid/trial access, offline behavior, and active-session protection.
- [ ] **BIZ-02 — Billing regression.** Test restore, expiration, interrupted purchases, offline status, and device changes with the existing billing stack.
- [ ] **BIZ-03 — Website alignment.** Update availability, trial/paid wording, feature descriptions, and store links to match the actual released build. Do not announce an unavailable feature as shipped.
- [ ] **BIZ-04 — Value presentation.** Show three concrete jobs: use your own program, train on your actual equipment, and plan your real week. Use accurate screenshots from implemented workflows.
- [ ] **BIZ-05 — Privacy and permission copy.** Align Health, calendar, cloud voice, transcript retention, and unlisted-sharing explanations with actual data flows and provider settings.
- [ ] **BIZ-06 — Cost controls.** Add voice/Coach usage visibility and alerts to operations, without placing sensitive user content in billing telemetry.

Avoid changing prices in code or static translated strings as part of this plan. Keep localized storefront pricing and current product configuration as their existing source of truth.

---

## 16. Delivery sequence and release gates

### 16.1 Dependency graph

```text
FND: shared load semantics, permissions, revisions, privacy, migrations
 |
 +--> EQP -------------------+
 |                           |
 +--> REC core --------------+--> REC user-facing evidence/outcomes
 |                           |
 +--> PRG core --> PRG contract integration
                     |
                     +--> WKD manual --> WKD calendar
                     |
                     +--> LIM --> contextual summaries
                     |
                     +--> GOL --> benchmark and block reviews
                     |
                     +--> SHR --> recipient onboarding and attribution
 |
 +--> Existing Coach + REC/PRG/EQP context --> VOC

UX / QA / DAT / BIZ apply across every milestone.
```

PRG and REC foundations can be developed in parallel with EQP after shared contracts stabilize. Do not ship their integrated flows until the relevant equipment, evidence, and permission tests pass. Voice and sharing are independent of each other's release, but both depend on mature action/privacy contracts.

### 16.2 Milestones

These are ordered release units, not calendar estimates. Assign dates only after the repository audit and technical spikes establish actual effort.

| Milestone | Deliverable | Required gate before expanding |
|---|---|---|
| M0 — Baseline and contracts | FND-01–10, initial analytics and QA fixtures | Existing app tests pass; migration, privacy, and duplicate/stale-action tests pass |
| M1 — Real equipment | EQP-01–08 plus REC snapshot capture | Correct attainable loads and loading semantics across phone/Watch/offline cases |
| M2 — Inspectable recommendations | REC-01–09 | Evidence/eligibility/exposure rules pass; no causal wording or sensitive-data leakage |
| M3 — Bring your program | PRG-01–10 | Supported import and two-session flow works; all three modes enforce permissions |
| M4 — Plan the week | WKD-01–06 | Feasible/conflict/search-limit states and scenario commits are correct; active sessions protected |
| M5 — Calendar extension | WKD-07–09 | Local-only calendar handling, denied access, exports, duplicates, and external edits pass |
| M6 — Better feedback and goals | LIM-01–06 and GOL-01–06 | Optional feedback and comparison-safe benchmarks work without extra logging friction |
| M7 — Spoken Coach | VOC-01–09 | Physical-device audio, cancellation, confirmations, privacy, and cost limits pass |
| M8 — Program links | SHR-01–09 | No personal-data publication; owner auth/revocation and recipient personalization pass |
| M9 — Full release | Complete UX, QA, DAT, BIZ work and release checklist | All eight features accepted; support/deletion/rollback and public messaging verified |

Within each milestone use the same rollout path: internal testing, opt-in beta, observed limited release, and broader release after the gate passes. Do not ship all engine changes simultaneously just because all features will eventually be implemented.

### 16.3 Work that can run in parallel

Once FND's contracts are stable, equipment UI and loading semantics can proceed alongside REC's evaluation harness and PRG's structured editor. After PRG versioning stabilizes, WKD, goals, and template serialization can be developed separately behind disabled flags. Voice UX can be prototyped against mocked existing Coach responses while action integration is completed.

Keep one owner for each shared schema or action-contract change. Separate branches must not independently invent competing versions of a set record, program definition, or load representation.

### 16.4 Primary risks and planned mitigation

| Risk | Mitigation already required by this plan |
|---|---|
| Wrong load interpretation corrupts progress | Preserve originals, typed semantics, explicit correction preview, comparison versioning |
| Imported rules conflict with adaptation | Program-level contract, deterministic compiler, typed conflicts, no silent relaxation |
| Scheduling claims impossible/optimal incorrectly | Bounded search with separate search-limit and proven-conflict results |
| Evidence UI overstates AI accuracy | Support versus fit versus causality separation; no model-assigned probabilities |
| Offline devices overwrite each other's intent | Stable IDs, local receipts, existing sync conflict resolution, no command replay |
| Voice fires a stale/accidental action | Separate modes, turn IDs, cancellation, bound visible confirmation |
| Share exposes private data | Separate public schema, reviewed projection, server validation, token/cache controls |
| Rich features make logging slower | Existing navigation, no required equipment re-entry, optional limiter prompts, performance budgets |
| Paid launch messaging contradicts behavior | Explicit entitlement matrix and website/store/privacy audit before release |

### 16.5 Final release checklist

- [ ] **REL-01 — Scope completeness.** All eight feature acceptance sections have recorded results; calendar work is included, not silently deferred.
- [ ] **REL-02 — Technical quality.** Required regression, physical-device, performance, migration, and multi-device tests pass on the supported matrix.
- [ ] **REL-03 — Privacy/security.** Payload audits, deletion drills, provider-retention verification, authorization tests, and unlisted-link handling are complete.
- [ ] **REL-04 — User experience.** Accessibility/localization pass; no mandatory new workout questionnaire or new-tab sprawl; denied permissions remain usable.
- [ ] **REL-05 — Operations and measurement.** Feature flags, rollback procedure, quotas, redacted monitoring, cohort definitions, and incident ownership are ready.
- [ ] **REL-06 — Commercial alignment.** Entitlements, active-workout protection, purchase restore, public availability, and paid/trial messaging match the shipped behavior.

---

## 17. Implementation handoff

### 17.1 First executable work package

Start with **FND-01, FND-02, and FND-03**. Produce the repository map, baseline fixture suite, and agreed load semantics before adding feature screens.

Then implement **FND-04–07** as small compatibility-preserving changes. Add REC snapshot capture early so subsequent feature tests can inspect the engine's actual decision inputs and results.

The first user-visible vertical slice should be:

```text
Create equipment instance
 -> select explicit loading convention and attainable values
 -> bind one exercise
 -> receive one valid next-set prescription
 -> log it through the existing flow
 -> inspect its comparison context and recommendation snapshot
 -> close/reopen the app without data loss
```

Expand to PRG and WKD only after that slice proves the shared data/action contracts in practice.

### 17.2 Pull-request template

```markdown
## Task
- Roadmap ID:
- User outcome:
- Existing code reused:

## Changes
- Domain/schema changes:
- Engine/policy changes:
- UI changes:
- Backend/transport changes:

## Compatibility
- Migration and historical-data behavior:
- Offline behavior:
- Old-client / Watch / sync behavior:
- Feature-off behavior:
- Entitlement behavior:

## Evidence
- Acceptance criteria covered:
- Tests added and commands actually run:
- Physical-device checks:
- Performance results, where relevant:
- Privacy projection review:

## Risk and release
- Known limitations:
- Feature flag:
- Rollback/degraded behavior:
```

Use this template for implementation evidence, not as a substitute for running tests. A task is complete when its behavior is demonstrated, not when a screen or model class merely exists.

### 17.3 Coding-agent instruction block

```text
Implement the selected ReguLift roadmap task only after mapping the actual
repository. Reuse existing services, names, architecture, and tests.

Do not assume proposed names in this document already exist. Do not rebuild
existing logging, RAG, memory, subscriptions, or sync. Do not replace the
deterministic voice parser with an LLM.

Preserve offline-first persistence, program permissions, Health-data privacy,
action confirmations, historical load meaning, and active-workout safety.

Before coding, identify the affected models, engine decisions, UI surfaces,
privacy projections, and migrations. Add or update the relevant tests.

Implement a complete vertical slice behind the appropriate feature flag.
Run the available test/build commands. Report only commands actually run
and their actual results. Do not claim device testing from a simulator run.

Do not introduce a new vendor, paid service, database, broad dependency,
minimum OS requirement, or permanent free tier without a separate explicit
decision. Never mark acceptance criteria complete on inference alone.

For each task, report changed files, behavior, migration/compatibility impact,
tests, unresolved risks, and the next unblocked roadmap task.
```

### 17.4 Definition of done for every feature

A feature must have working domain logic, a connected user flow, correct persisted state, permitted offline/degraded behavior, tested privacy boundaries, appropriate entitlement handling, acceptance evidence, and a feature-off recovery path.

All task checkboxes in this document are intentionally unchecked. Creating this plan does not imply that code, integrations, tests, or releases have been completed.

---

## 18. Sources and verification notes

**Baseline:** The user's existing-feature inventory in this conversation, supplied September 18, 2026. Proposed engineering decisions, entities, metrics, and acceptance tests are original recommendations—not claims about code inspected in a repository.

The following primary sources support the specific platform/public-product statements marked in the document. Retrieved September 18, 2026. Historical Apple material is used for stable architectural concepts, not as a substitute for checking current SDK signatures, capability availability, entitlements, or release notes during implementation.

| Reference | Primary source | Use in this plan |
|---|---|---|
| S1 | [ReguLift public website](https://regulift.app/) | Public Health-data/Coach boundary, offline/no-account promises, and launch/pricing-copy alignment |
| S2 | [Apple — Model your schema with SwiftData, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10195/) | Schema evolution and versioned migration planning |
| S3 | [Apple — Discover Calendar and EventKit, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10052/) | EventKitUI, write-only versus full calendar access, and permission-scoped integration |
| S4 | [Apple — Support Universal Links, documentation archive](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppSearch/UniversalLinks.html) | Associated app/domain configuration and web fallback; validate current setup in the shipping SDK |
| S5 | [Apple — Responding to Interruptions, documentation archive](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioInterruptions/HandlingAudioInterruptions.html) | Audio-session interruptions, recovery state, and media-service-reset handling |

**Verification boundaries:** The native app, repository, provider contracts, subscription configuration, and deployment environment were not accessed. No runtime performance, conversion uplift, API cost, or engineering duration is claimed as measured. Confirm actual framework availability and the chosen providers' retention/billing terms in the implementation spikes before release.

---

**Build order:** Foundations → Equipment Passport → Recommendation evidence → Coach My Program → Week Designer and calendar → Set-limiter feedback and goals → Conversational voice Coach → Shareable programs → Full release checks.
