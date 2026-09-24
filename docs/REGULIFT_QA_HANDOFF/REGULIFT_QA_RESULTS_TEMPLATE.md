# Regulift — QA result and launch decision

**Fill this after execution. Template status: NOT RUN.**

## 1. Candidate identity

- App version/build/commit:
- Backend deployment, rules/schema and configuration/feature flags:
- Distribution and billing environment:
- QA dates, lead and release owner:
- Manifest path:
- Source test-pack revision/checksum:
- Implementation changes since previous evidence:

## 2. Proposed decision

**NOT READY / READY FOR LIMITED RELEASE / HOLD** (choose only after evidence review)

Decision owner/date:
Reason supported by evidence:
Unverified areas and explicitly disabled features:

## 3. Coverage summary

| Measure | Result |
|---|---|
| Applicable case/profile executions | |
| Pass with required evidence | |
| Fail | |
| Blocked | |
| Not run | |
| Noncritical approved waivers | |
| N/A with scope evidence | |
| Unresolved scope rows | |
| Required P0 not passed | |
| Open S0 / S1 defects | |
| Core smoke on final candidate complete | |

Do not present N/A, Blocked or Waived as Pass. Distinguish unique cases from case/profile/variant runs. List all materially different variants, including devices, locales, payment states and feature subsets.

## 4. First-priority regressions

| Question | Result + case/profile + evidence |
|---|---|
| Target RPE never becomes an unprovided report | |
| Lunge/Deadlift plate context remains correct | |
| Same-scope metrics agree after edit/relaunch | |
| Empty, rest, ready, resume and complete states distinct | |
| Workout survives force-kill/offline/update failure | |
| No duplicated observation or progression on retry | |
| Normal Coach answer/clarification/preview works | |
| Paid purchase/restore/expiry and active-session save correct | |
| Health/private data excluded from forbidden paths | |
| Critical controls usable with keyboard/large text/VoiceOver | |

## 5. Workflow recordings

| ID | Profile/build | Pass / Fail / Blocked / N/A | Video path + important timestamps | Additional assertions |
|---|---|---|---|---|
| W01 — First install → clear plan → first set | | | | |
| W02 — Complete workout, correction and explicit exercise context | | | | |
| W03 — Saved result → interruption recovery → next workout | | | | |
| W04 — Week states → move/miss → constraint → imported plan | | | | |
| W05 — Ordinary Coach → ambiguity → preview → failure | | | | |
| W06 — Voice and audio with sound + understandable settings | | | | |
| W07 — Progress, History and Timeline as a coherent record | | | | |
| W08 — Fuel, measurements, equipment, goals and import/export | | | | |
| W09 — Card editor → exact image → cancel/export → Crew attachment | | | | |
| W10 — Account, guest merge and Crew audience | | | | |
| W11 — Paid launch purchase and entitlement lifecycle | | | | |
| W12 — Accessibility and UI state review | | | | |
| W13 — Watch and actual Apple system surfaces | | | | |
| W14 — Failure, privacy, migration and backend assertions | | | | |
| W15 — Jev optional routing and follow-through | | | | |
| W16 — Release candidate and operational sign-off | | | | |
| W17 — Unassisted target-user usability study | | | | |

## 6. UI/UX findings

| Screen/state | Observed issue (not guess) | Impact on task | Screenshot/time | Severity | Action/owner |
|---|---|---|---|---|---|
| | | | | | |

Include Today, logger/Focus, result, Progress/Timeline, Coach, settings, paywall and each enabled card/look. Capture fresh and mature accounts. Distinguish “I prefer this spacing” from “the Save control is inaccessible.”

## 7. Five-person usability findings

| Participant alias | Locale/device | Tasks unaided / assisted / incomplete | Confusion in own words | Case/defect |
|---|---|---|---|---|
| P01 | | | | |
| P02 | | | | |
| P03 | | | | |
| P04 | | | | |
| P05 | | | | |

Repeated obstacle(s):
Whether users could explain the next-session change:
What QA changed by coaching (record separately):
Consent and redaction status for returned clips:

## 8. Billing, privacy and platform evidence

Billing: actual product/storefront configuration, tested state matrix, simulated versus live-sandbox evidence, restore/cancel/expiry limitations.
Privacy: inspected outbound channels, server/provider logs and storage; canary results; unavailable observability. Do not claim universal privacy proof from a finite test corpus.
Watch/audio/system: hardware/OS and exactly what was tested. Do not mark sound passed from a silent recording.
Migration/recovery: previous schemas tested, fault boundaries, whether user data/active session survived.
Performance: repetitions, dataset/device/network, p50/p95, peak memory/energy, preapproved budgets and any revised budget with sign-off.
Jev if enabled: exact model/question/policy versions, locale sample sizes and held-out evaluation; no real private prompt corpus.

## 9. Defects, waivers and retests

| Defect | Severity | Affected case/profile | Fixed build | Retest evidence | Status / owner |
|---|---|---|---|---|---|
| | | | | | |

| Waiver | Noncritical behavior and workaround | Scope / expiry | Approver | Evidence |
|---|---|---|---|---|
| | | | | |

No waiver for a confirmed S0/S1 or required P0 failure. Fix and retest, or actually disable a non-core feature and verify new release scope.

## 10. Sign-off

- QA lead:
- iOS/engine/data owner:
- Backend/privacy/security owner:
- Billing owner:
- Design/product reviewer:
- Release owner, candidate identity, decision and date:

Attachments verified to contain only approved synthetic/consented evidence:
Post-release monitoring owner and rollback plan:
