# Jev integration — repository inventory (JEV-001 … JEV-004)

**Date:** 20 September 2026  
**Method:** repository read. Proposed names from the goal document are mapped to real
symbols; anything genuinely new is marked as such.

This is the `docs/REGULIFT_JEV_GOAL.md` §11 M0 audit.

## Existing integrations this extends

| Goal row | Status | Real symbol |
|---|---|---|
| Coach intent router / ambiguity | reuse | `CoachIntentClassifier`, `CoachConversation` (`ForgeCore/Sources/ForgeCore/CoachIntent.swift`, `CoachConversation.swift`) |
| Local typed/voice parser, first refusal | reuse | `VoiceCommandParser`, `VoiceIntentClient` — a complete recognized command never reaches a model |
| Jev provider adapter | extend | `server/src/jev.ts` — `jevChoice` existed; `jevAsk` added for the multi-question set |
| Export policy before any cloud call | extend | `CloudExportPolicy` / `DecisionProvenance` (`TrainingIntegration.swift`) for decisions; `SemanticExportPolicy` added for free text |
| Decision reader for explanations | reuse | `CoachReadContracts.decision`, `CoachLocalReads` — lineage-gated, no new causal text |
| Proposal / approval / receipt boundary | reuse | `CoachCommitPolicy` + `RecommendationLedger.apply` — still the only write gate |
| Worker auth, limits, secrets | reuse | `unauthorized()`, `deps.limiter`, Worker bindings |

## What this release added

| Capability | Where |
|---|---|
| Six-question set, versioned | `server/src/semantic-route.ts` — `ROUTE_QUESTIONS`, `QUESTION_SET_VERSION = regulift-coach-v1` |
| Decode before branching | `decodeRoute` — every answer present, every choice inside its own enum, distribution sums within 0.02, model on the tested allowlist |
| Endpoint | `POST /coach/semantic-route` (`server/src/app.ts`) — app secret, 8 KiB body, 1500-byte message, surface and locale allowlists, unknown field refused, `no-store`, one provider call per turn |
| Mode flag | `semanticRouteMode` = `off` \| `shadow` \| `enabled`, from `SEMANTIC_ROUTE_MODE`. **Default off** |
| Local privacy gate | `ForgeCore/Sources/ForgeCore/SemanticExport.swift` — placeholder slots, sensitive-term floor, evaluated-locale gate, prompt-attack gate |
| Confidence policy | `ForgeCore/Sources/ForgeCore/SemanticRouter.swift` — `decide()` with separate top-probability and margin checks; related answers are never multiplied |
| Client | `App/Forge/SemanticRouteClient.swift` — 2.5 s budget, request/context identity checked on the way back, late replies discarded |

## Boundaries this actually enforces

- **The model never sees a value.** `[duration_1]`, `[equipment_1]`; the real minutes and the
  resolved equipment identifier stay on the phone in `SemanticProjection.slots`.
- **Health stays local, including when the lifter types it.** HRV, sleep, soreness, pain and
  injury wording deny the export outright — masking a number does not launder the sentence.
- **Confidence can select a handler; it can never approve a change.** `preview` only
  authorizes *attempting* a preview. Perfect confidence still earns a preview, not a commit.
- **Half a request is never applied.** Two constraints compose into one preview or fall back
  to guided controls; mixed scope asks.
- **Off by default, everywhere.** `SEMANTIC_ROUTE_MODE` unset means the endpoint answers
  `fallback: routing_disabled` without touching the provider, and the client returns
  `.disabled` before building a request.
- **English only for now.** `SemanticExportPolicy.evaluatedLocales = ["en"]`; Japanese and
  Korean are separate gates that have not been evaluated.

## Not built in this release

| Item | Why |
|---|---|
| P1 Coach Follow-through | The goal gates it behind P0 passing evaluation |
| Cloud orchestration (D1 + Workflows) | Not required; no new table, Durable Object or Cron |
| Live rollout | Needs the M5 calibration and held-out datasets. Ship order is `off` → `shadow` → per-locale `enabled` |

## Tests

- `ForgeCore/Tests/ForgeCoreTests/SemanticRouterTests.swift` — 21 cases covering AT-01…AT-12,
  AT-16 and the decisiveness gate.
- `ForgeCore/Tests/ForgeCoreTests/SemanticExportTests.swift` — 11 cases: masking, typed health
  detail, locale gate, over-length refusal, prompt attack.
- `server/src/test/semantic-route.test.ts` — 19 cases: decoder, auth, unknown fields, shadow
  vs enabled, provider failure, rate limit, no-store.
