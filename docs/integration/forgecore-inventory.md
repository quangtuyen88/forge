# ForgeCore integration — capability inventory

**Date:** 20 September 2026
**Method:** repository read of `App/Forge`, `ForgeCore`, `server`, `web`. Every row links the
actual symbol. Status is what the code does today, not what a roadmap claims.

This is the `docs/FORGECORE_INTEGRATION.md` §2 audit and the `docs/REGULIFT_LADDER_DELTA_PLAN.md`
§12 checkpoint, in one table. **exists** = reuse it, **partial** = extend it, **not built** =
genuinely missing, **out of scope** = deliberately not in this phase.

## Engine and decisions

| Capability | Status | Where |
|---|---|---|
| Progression rule (next load/reps/sets) | exists | `ForgeCore/Sources/ForgeCore/Progression.swift`, called from `App/Forge/Adjustments.swift:87` `buildDecision` |
| Reason emitted by the deciding branch | exists | `ForgeCore/Sources/ForgeCore/DecisionBuilder.swift` → `Decision.causes` (`Decision.swift:71`) |
| Decision persistence | exists | `DecisionLogEntry` (`App/Forge/Models.swift`), written on workout start (`TodayView.writeDecisionLedger`) |
| Idempotent decision write | **added** | `App/Forge/DecisionTrace.swift` — operation fingerprint, replay returns the first receipt |
| Machine reason-code namespace | **added** | `TrainingReasonCode` (`ForgeCore/Sources/ForgeCore/TrainingIntegration.swift`) next to the existing `DecisionSignal.code` vocabulary |
| Typed prescription/load contracts | **added** | `LoadValue`, `SetPrescription` — integer milli-units, `nil` load means uncalibrated |
| Proposal/approval/commit receipt types | partial | `RecommendationLedger` + `RecommendationSnapshot` (`TrustFeatures.swift`) already bind a coach proposal to a program version; `CommitReceipt`/`TrainingRequest` added for the ledger path |
| Why? UI over committed records | exists | `App/Forge/CoachView.swift` decision cards, `App/Forge/PlanAuditView.swift` |
| Watch/offline envelope | partial | `App/Forge/WatchSync.swift`, `SyncEngine` outbox — durable IDs exist. Identity is now covered by tests: the same start from two devices, and interleaved arrival order, produce one operation (`CoachContractsTests`), and a retried start writes the ledger once (`DecisionTraceTests`) |

## Privacy

| Capability | Status | Where |
|---|---|---|
| Health fields withheld from cloud Coach | exists | `ContextField.source == .healthKit` filtered in `CoachContextBuilder.packet` |
| Health-derived **decision reasoning** withheld | **fixed** | `DecisionProvenance` + `CloudExportPolicy` (`TrainingIntegration.swift`); `CoachContextBuilder.packet` now filters decisions, not only fields |
| Export allowlist DTO | **added** | `CloudDecisionProjection` — no evidence text, no health metadata, reviewed reason codes only |
| Journey notes/photos local-only | exists | `App/Forge/JourneyModels.swift`, absent from `SyncEngine` allowlist |
| Sleep duration stripped at sync | exists | `CheckIn.syncData`, `server/migrations/0003_remove_synced_sleep_hours.sql` |

### The defect this pass closed

`CoachContextPacket.rendered()` appends `DecisionLedger.payload(decisions)`. A decision's
evidence lines are formatted strings — `"readiness 82"`, `"5.1 h"` — produced from HealthKit
sleep/HRV/resting-heart-rate and the daily check-in. The builder filtered *fields* and never
filtered *decisions*, so recovery reasoning left the device inside the ledger payload while the
matching `hrv_ms` field was correctly withheld. Lineage now decides: a decision whose reason
codes include `readiness_*`, `sleep_short` or `soreness_high` stays local, and the packet
reports the withheld codes so the app can say so instead of pretending nothing was dropped.

## Coach

| Capability | Status | Where |
|---|---|---|
| Typed on-device tools | exists | `App/Forge/CoachTools.swift` (swap, early deload, restart block, remember) |
| Bounded read projections | **added** | `CoachReadContracts` + `CoachEnvelope` (`ForgeCore/Sources/ForgeCore/CoachReadContracts.swift`), four read tools in `CoachTools.swift`, backed by `CoachLocalReads` (`App/Forge/CoachReads.swift`) |
| Freshness / status vocabulary | **added** | `CoachReadStatus` — `ok`, `not_found`, `not_shared`, `stale`, `needs_clarification`, `unavailable`; every read stamped with `plan_revision` and `as_of` |
| Plan identity | **added** | `PlanRevision.digest` — a content digest, equality only. No counter, no migration: the store has no version column and a row count is not a version |
| Bound consent | **added** | `CommitPreview` / `CommitApproval` / `CoachCommitPolicy` (`ForgeCore/Sources/ForgeCore/CoachCommitPolicy.swift`), checked in `CoachView.apply` before `RecommendationLedger.apply` |
| Action validation through one executor | partial | The coach path is now preview-bound; `RecommendationLedger.apply` is still the only write gate, and voice/UI edits keep their existing confirmation policy |
| Prompt-injection handling | exists | `ForgeCore/Sources/ForgeCore/PromptSecurity.swift`, `server/src/guard-input.ts` |

## Ladder candidates

| Ticket | Status | Where |
|---|---|---|
| WEB-00 accurate funnel | **done** | `web/index.html` — no App Store install claim, TestFlight/waitlist path, real trial and price |
| WEB-01 Find my plan | **done** | `web/index.html`, `web/app.js` — engine-supported options only, versioned starter template, opaque local code |
| AUDIO-01 spoken guidance | **added** | `App/Forge/CoachAudio.swift` + Settings mode picker + workout wiring |
| Offline speech-to-text | **added** | WhisperKit 1.1.0 (pinned exact) as a third `VoiceInputPipeline`: `App/Forge/WhisperKitPipeline.swift`, model download in `App/Forge/WhisperModel.swift`, Settings rows `settings.voice.*`. Finals only, opt-in, Wi-Fi-only download, unloads under memory pressure, and `--os-speech-only` forces the OS path for E2E |
| WEEK-01 forward brief | **added** | `ForgeCore/Sources/ForgeCore/WeekBrief.swift`, rendered inside the existing week review in `TodayView` |
| FLEX-01 optional sessions | out of scope | Needs a reviewed catalog and add/replace intents; plan says gather evidence first |
| ACTIVITY-01 external activity | out of scope | `App/Forge/Health.swift` reads recovery only; workout import is a separate consent design |
| CREW-01 shared blocks | out of scope | `App/Forge/CrewView.swift` exists; shared blocks are a pilot, not this release |
| Videos / form analysis | out of scope | Explicitly excluded by the plan |

## The Coach chat defect this pass closed

`CoachIntentClassifier` fired its "body weight or the load for an exercise?" clarification on
any sentence containing `body weight` — including the sentences that had already answered it.
Worse, `CoachView.request()` classified only the last message, so the lifter's reply to the
clarification ("Yes") reached the model as a brand-new question with no link to the original,
and came back as an unrelated swap prompt. The rule is now qualifier-aware, and a pending
`CoachClarification` re-asks with tappable option chips and sends the **original** question
merged with the answer. A bare affirmation re-asks once, then falls back to answering the
original rather than stalling.

## Already implemented — do not rebuild

Focus Mode, Gym Profiles, Equipment Passport, missed-workout recovery, structured Coach memory,
imported-history analysis, training experiments, Journey timeline, program roadmap, PR board,
voice logging and dictation. Each has code and tests in the repository today.
