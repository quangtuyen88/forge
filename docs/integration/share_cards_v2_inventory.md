# Share Cards v2 — repository inventory (SC-00)

**Date:** 20 September 2026  
**Method:** repository read. Every row names the actual symbol, not a proposed one.

This is the `docs/REGULIFT_SHARE_CARDS_V2_GOAL.md` §12 SC-00 ticket. **reuse** = it exists and
is used as-is, **extend** = it exists and this release added to it, **added** = genuinely new,
**out of scope** = deliberately not in this release.

## What already existed

| Capability | Status | Where |
|---|---|---|
| Story/square workout card render | reuse | `SessionCardView` (`App/Forge/SessionSummaryView.swift`), `PRCardView` (`App/Forge/PRSheet.swift`) — both already `ImageRenderer` + `ShareLink` |
| System share hand-off | reuse | `ShareLink` on the summary, PR sheet, Progress CSV and program share |
| PR eligibility / plausibility guard | reuse | `PRRecord` + the existing verified-set rules; `summary.verified` gates auto-post today |
| Session aggregates | reuse | `SessionSummary` (sets, duration, tonnageKg, exercises, muscles) built once in `WorkoutView.finish()` |
| Crew publication + auto-post | reuse | `App/Forge/SocialClient.swift`, `autoPostWorkouts` / `autoPostPRs` in `SessionSummaryView.autoPost()` |
| Unit + load conventions | reuse | `Plates`, `Fmt`, `UserProfile.isLb(for:)`, `LoadValue` milli-units |
| Local-only journey notes and photos | reuse | `App/Forge/JourneyModels.swift`; absent from the sync allowlist |

## What this release added

| Capability | Status | Where |
|---|---|---|
| Card document + projection policy | added | `ForgeCore/Sources/ForgeCore/ShareCard.swift` — `CardDocument`, `ShareDisclosure`, `ShareCardBuilder` |
| Truthful qualifiers | added | `ShareCardQualifier` — `planned_not_completed`, `estimated_1rm`, `unverified`, `selected_top_sets`; never dropped to fit |
| Top-set selector | added | `SessionTopSet.best(in:)` (`App/Forge/SessionSummaryView.swift`) — heaviest logged set per exercise, then most reps, in training order |
| Composer | added | `App/Forge/ShareCardComposer.swift` — format and per-card detail toggles, `share.*` identifiers |
| Fixed-canvas renderer | added | `App/Forge/ShareCardView.swift` — 1080×1080 / 1080×1920, opaque, template only (never a screen grab) |
| Caption + accessibility text | added | `ShareCardBuilder.caption(for:…)` — built from the SAME document, so a hidden field cannot reappear in text |
| Entry point | extend | `SessionSummaryView` — one **Share workout** action opens the composer; `Done` stays reachable and unblocked |

## Deliberately out of scope in this release

| Item | Why |
|---|---|
| Personal Best / My Week templates | SC-06 / SC-07 follow the Top Sets slice; the builder and document already carry their shapes |
| Photo look | SC-12 / SC-13 — needs the picker, bounded loading, crop state and a metadata-scrub suite |
| Next-session target | `share_cards_next_target_v1` stays off until the prescription-only export boundary is reviewed (SC-10). `CardDocument.nextTarget` exists and the summary passes `nil` |
| Crew attachment | Phase C. Local export works signed out; no media upload path was added |
| Save to Photos | Not needed for v1: the system share sheet already covers it |

## The rules this slice actually enforces

- **Training never waits on sharing.** The composer is a sheet over a summary of an
  already-saved session; opening, editing, cancelling or failing an export writes nothing.
- **Nothing is invented.** A missing RPE is absent, not zero (`ShareCardTests`,
  `ShareCardSourceTests`). An unverified set keeps its qualifier. A planned target needs both
  the toggle and a committed target, and always carries *Planned — not completed*.
- **A subset says so.** Fewer highlights than exercises sets `selected_top_sets`, in the
  image, the caption and the accessibility description.
- **Hidden is hidden everywhere.** Disclosure is applied in the builder, so the image, the
  caption and the text alternative come from one document.
- **Aggregates carry their scope.** `ShareAggregate.scopeLabel` travels with the number, so a
  filtered total cannot be labelled as the whole workout.

## Tests

- `ForgeCore/Tests/ForgeCoreTests/ShareCardTests.swift` — 17 cases: fabrication, subsets,
  bounded layout, caption/disclosure parity, safe defaults.
- `App/ForgeTests/ShareCardSourceTests.swift` — 7 cases: top-set selection, training order,
  unreported effort, empty session, accessibility-text parity.
