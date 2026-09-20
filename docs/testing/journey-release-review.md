# My Training Journey — implementation record

## Shipped surface

- Progress is titled `My Progress`, keeps its existing Overview, and adds the remembered `Timeline` segment. Settings, History and CSV export stay reachable from the same toolbar.
- Compact private header shows an avatar, the private display name, and separate wrapping lines for `Current goal: …`, the truthful `Training records since …`, and an optional user-entered `Started training …` date.
- The timeline uses an Apple Fitness date rail (`19` / `SEP`, hairline, one semantic dot per entry) at regular text sizes and collapses to a full-width day heading at `xxLarge` and accessibility sizes, so nothing clips.
- Month and `Filter` sit on the header row; `Add note` and the overflow menu stay secondary. Each card carries at most three truthful lines and one explicit trailing action: `View workout`, `View program`, `View change`, `View body record`, `View privately`, or `Edit note`.
- Timeline projects completed workouts, body measurements, progress-photo metadata, accepted program-change receipts, and private reflections from canonical local records.
- Projection is live and month-scoped rather than a persisted duplicate index; this removes cache-rebuild and stale-card failure modes while retaining stable event identity.
- Month selection, OR category filters, 30-card incremental display, original-source navigation, hide/restore, note create/edit/delete, and cold-relaunch persistence are implemented.
- Workout cards are enriched only from canonical records: one deterministic featured lift (localized exercise, real load and reps in the lifter's unit), the eligible working-set count from `analysisSets(.achievements)`, recorded minutes derived from persisted set timestamps exactly as `SessionMath.totalMinutes` does, and the program week. No PR is claimed and no parallel formula exists.
- Photo image bytes remain unloaded while concealed. One-time reveal state clears outside the active view; persistent photo-detail preference exposes pose labels only.
- Journey notes, visibility overrides, and private-profile overrides are device-local and absent from `SyncEngine` payloads.

## Trust boundaries

- Stable event identity uses owner + source kind + canonical source ID + facet; dates, titles, and revisions never change identity.
- Projection reads throw on SwiftData failure; the UI shows an unavailable/error state instead of a false empty history.
- Foreign-owner hide/restore IDs are rejected. Reflection lookups are owner-scoped; a deleted idempotency key cannot resurrect a note.
- Auth activation records local-store provenance. Switching to another authenticated account fails closed instead of exposing or uploading the previous account's unscoped canonical records.
- A legacy store with an existing bound-account witness also fails closed; a store with no owner witness is deliberately treated as first-sign-in local adoption, then becomes permanently bound before sync credentials activate.
- The soft-delete rename was exercised as an actual store upgrade: a legacy build wrote `ZDELETED = 1`, the current build opened the same store through `@Attribute(originalName: "deleted")`, migrated to `ZTOMBSTONED`, and preserved one tombstone plus nine live sessions.
- Hiding changes only Journey visibility and never source records or progress metrics.
- Each card's accessibility element lives on the outer control and reads kind, title, full locale date, detail, photo privacy state and action; rail digits, hairlines and dots are decorative and hidden from VoiceOver. Backgrounding clears a photo reveal and never dismisses an open source screen.

## Repository mapping

| Capability | Source |
|---|---|
| Workout cards and detail | `WorkoutSession` → `SessionDetailView` |
| Body cards | `BodyMeasurement` → `MeasurementsView` |
| Photo cards | `ProgressPhoto` metadata → `ProgressPhotosView` |
| Program changes | allowlisted `DecisionLogEntry` types |
| Reflections / visibility / private identity | device-local SwiftData Journey models |
| Date ordering and stable IDs | `ForgeCore/Sources/ForgeCore/Journey.swift` |
| Local projection | `App/Forge/JourneyRepository.swift` |
| Progress UI | `App/Forge/ProgressView.swift`, `App/Forge/JourneyView.swift`, `App/Forge/JourneySheets.swift` |

## Deliberately disabled adapters

- Milestone and review cards remain disabled because the app has no canonical persisted achievement/review record with stable source identity and invalidation semantics.
- Direct Crew publication remains disabled because the existing social path has auto-post settings and system share images, but no revision-bound audience preview contract suitable for Journey.
- Health records and generated commentary are not projected.

These are disabled capabilities, not fabricated empty results. The Timeline names them explicitly.

## Verification

- Pure Journey identity, ordering, month, filter, and reflection validation: `swift test --package-path ForgeCore --filter JourneyTests`.
- Native SwiftData integration: Forge scheme `ForgeTests` test action.
- Build: `make build-ios`.
- Self-contained native Journey E2E: `make test-journey-e2e` — `My Progress`, Settings, the date heading, the explicit source action, concealed photos, source navigation, in-place edit, cold-relaunch persistence without a duplicate card, hide/restore, month chooser and filters.
- Largest supported text: `xcrun simctl ui <udid> content_size accessibility-extra-extra-large` with the timeline flow — the rail collapses, the action keeps non-zero bounds, and the canonical workout detail opens.
- Full stateful app E2E: `make test-app-e2e`.
