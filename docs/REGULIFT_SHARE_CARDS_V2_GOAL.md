# Regulift Share Cards v2
## Implementation goal and coder handoff

**Date:** 20 September 2026  
**Status:** Proposed implementation specification; the app repository has not been inspected or changed.  
**Scope:** Upgrade existing workout sharing. Do not build a new training app, social network, or image-design application.  
**Primary goal:** A user can turn a saved workout or training week into an accurate, attractive, privacy-controlled card in a few taps, without disrupting logging or next-session adaptation.

> Make the workout worth sharing without making sharing the purpose of the workout.

---

## 0. Instructions for the implementing coder

1. Read this document, then audit the actual repository before creating new modules. Mark each proposed component **reuse / extend / missing**.
2. Start with **one saved workout → Top Sets → Clean → square image → existing share sheet**. Do not start with photos, Crew storage, or all templates at once.
3. Reuse existing metric selectors, PR eligibility, entitlement checks, authentication, render/export services, and Crew publication logic. Do not introduce parallel training calculations.
4. Treat dimensions, UI defaults, limits, and rollout gates below as proposed product requirements—not claims about existing code or platform requirements.
5. Keep Health import, Jev, generative captions, maps, video, animation, and new social features out of this release.
6. Finish with real Xcode/device tests and the acceptance matrix. The standalone Swift checks included here do not test the app, renderer, photo pipeline, or backend.

**First pull request:** repository inventory plus a fixture-driven Top Sets builder using existing shareable workout data. No new backend dependency.

## 1. Baseline and actual delta

### Documented existing capabilities

The supplied `OVERVIEW(1).md` already describes story/square workout sharing, PRs, tonnage, summary/debrief, Crew, auto-post toggles, offline operation, and three app languages. It also documents a plausibility guard that excludes unverified records from PRs, badges, and Crew. These are starting points, not features to recreate. [B1]

The earlier ForgeCore integration handoff separates saved workout facts from subsequent adaptation and requires explicit export projections for private information. Preserve that separation. [B2]

These documents are specifications, not proof that every implementation is present or complete. The repository audit determines what needs work.

### What this release adds or improves

| Area | Required delta |
|---|---|
| Templates | Top Sets, Personal Best, My Week using shared data selectors. |
| Presentation | Two looks: Clean and Photo; existing brand tokens and story/square formats. |
| Editor | Select eligible content, hide optional details, change format, preview exact export. |
| Regulift identity | Optional, clearly labeled next-session target from a committed prescription. |
| Personalization | Remember style locally, without silently retaining a photo or disclosure consent. |
| External export | Reuse the system share sheet; optional caption from the same selected fields. |
| Crew | Add a card attachment to existing publication only where attachment support is missing. |
| Reliability | Fresh snapshots, no duplicate Crew posts, bounded photo memory, clean temporary files. |

### Explicitly excluded

- Health-workout ingestion or fatigue recalculation.
- Readiness, HRV, sleep, soreness, injury, body-composition, or recovery-explanation cards.
- Progress-photo gallery integration or automatic reuse of private photos.
- Volume-versus-MEV/MAV/MRV graphics. No new volume-landmark model.
- Shaders, route maps, flyovers, animation, video, stickers, free-form layouts, font pickers, or glow sliders.
- A new feed, follower graph, private group system, moderation product, or messaging system.
- Direct Instagram-specific integration; first use the existing system share path.
- A new paid/free tier or entitlement migration. Preserve current product access rules.
- Jev, an LLM, a cloud renderer, image-generation APIs, or AI-written achievement claims.

## 2. Non-negotiable rules

**Training does not depend on sharing.** Saving, adaptation, awards, and Watch synchronization remain on their existing paths. Opening, cancelling, or failing an export must not change any training state.

**The card is a snapshot, not a live query.** Build from a coherent saved source revision. Recheck freshness before handoff, then publish the exact approved image. Do not silently redraw a different image during sharing.

**No invented accomplishments.** Planned loads are not completed lifts. Estimated 1RM is not a tested 1RM. Missing RPE is not zero. An unavailable comparison is not a personal best.

**Eligibility is reused, not recreated.** Existing selectors decide which records can supply PRs, highlights, aggregates, and Crew content. Never run a new PR detector in a SwiftUI view.

**Only selected, permitted fields leave.** Construct a small card projection. Do not screenshot the existing summary or serialize its complete view model.

**Consent is destination-specific.** Choosing a photo or creating a preview does not authorize an upload. A Crew auto-post preference does not authorize new photo-card uploads.

**Local rendering is not a promise of local-only publication.** External sharing hands the finished asset to another app; Crew posting uploads it to the existing service. Explain that distinction in the preview.

**Basic export is independent of sign-in.** Preserve existing access/entitlements, but do not require a Crew account merely to render and export a card locally.

## 3. Product experience

### 3.1 Entry points

Reuse the existing Share entry on the saved workout result. Also expose the same composer from an eligible historical workout and the existing weekly review/history surface.

- Workout entry suggests **Personal Best** when the existing selector reports an eligible PR; otherwise **Top Sets**.
- A valid saved template preference may take precedence. Do not default to an unavailable template.
- Weekly entry opens **My Week** for the explicitly selected week.
- No automatic composer presentation after every workout.
- The ordinary **Done** action remains visible and usable without sharing.
- No share rewards, fake urgency, or confirmation intended to prevent the user leaving.

### 3.2 Main flow

```text
Existing logger durably saves workout
    ├─ Existing adaptation / results / next-session updates continue independently
    └─ Optional Share
         → Select eligible template
         → Choose content and look
         → Render locally
         → Inspect exact exported image
         → Share… OR Post to Crew
```

A saved workout can be shared while adaptation is still pending. In that case omit the optional next-session section. Do not make image export wait for cloud Coach or block workout completion.

### 3.3 Composer layout

```text
Share workout                                      Close

[ Exact card preview; tap to inspect at larger size ]

Template       Top Sets | Personal Best | My Week
Format         Square | Story
Look           Clean | Photo

Selected sets / record / weekly highlights
Details        RPE · comparison · date · name · next target

Optional caption                                Off

[ Share… ]                  [ Post to Crew ]
```

Only show template controls relevant to the source. A workout entry may offer a link to its week rather than silently changing the source behind the same preview.

On smaller screens, put secondary controls in a sheet. The editor supports Dynamic Type, VoiceOver, large touch targets, and Reduce Motion. Fixed export dimensions do not justify tiny editor controls.

### 3.4 Safe defaults

| Option | Initial behavior |
|---|---|
| Look | Clean. Remember a Photo preference, but require a fresh photo for each new card. |
| RPE | Hidden until selected; a selected row with missing RPE still shows no fabricated value. |
| Comparison | Hidden until selected and a valid comparable record exists. |
| Exact date | Hidden initially; My Week can show weekday labels without a date range. |
| Display name | Hidden initially. Crew still uses the signed-in Crew profile outside the image. |
| Next-session target | Off; requires explicit selection for the current card. |
| Caption | Off; user can enable or explicitly copy the generated caption. |
| Session title | Standard program titles may be used; custom titles require selection because they may contain private text. Generic fallback: “Strength session.” |
| Photo | None; never automatically choose the latest camera-roll or progress photo. |

Persist template/format/look only in v1. Keep disclosure toggles, selected content, caption choice, and photo selection scoped to the current composer draft. Changing template must not turn hidden details back on.

## 4. Template specifications

The following layouts and values are illustrative design fixtures, not new programming rules.

### 4.1 Top Sets

**Purpose:** Share what was actually logged, not a screenshot of the full table.

- Show one to three selected exercise highlights in square format; one to four in story format.
- Default to one eligible set per exercise using the current top-set/highlight selector.
- Let the user replace/reorder highlights from the existing eligible list. Do not let this editor change logged values.
- Show exercise name, load convention, reps, and optional RPE.
- Allow up to two optional summary metrics from the existing shareable aggregate selector. Do not require tonnage when exercise loads are incomparable.
- Label partial selections “Selected top sets” where necessary; do not imply that the entire workout is displayed.
- Optional previous-performance comparison must match exercise variant, load convention, units, and existing comparison rules. Missing comparison means omit it.

```text
UPPER A
SELECTED TOP SETS

BENCH PRESS
82.5 kg × 8

CHEST-SUPPORTED ROW
70 kg × 10

14 working sets · 48 min

[Optional]
NEXT BENCH TARGET
85 kg × 6–8
Planned — not completed

REGULIFT
```

The summary numbers above are permitted only when the existing selector returns those exact aggregates for the declared scope.

### 4.2 Personal Best

**Purpose:** Celebrate one eligible achievement with an unambiguous metric.

Reuse the existing PR record and its eligibility status. No new Epley calculation, percentage calculation, rep-to-load conversion, or arbitrary cross-exercise ranking in the composer.

Supported presentations:

| Existing record kind | Display rule |
|---|---|
| Repetition PR | Same load and comparable exercise: show previous reps and achieved reps. |
| Load PR | Label the reps/load context; do not imply a tested 1RM. |
| Estimated-strength best | Always show “Estimated 1RM” or localized equivalent. Preserve estimator/version comparability. |
| First eligible record | Use “First recorded best” or existing equivalent; no invented previous value or percentage. |

Display one main record per card. When multiple PRs exist, let the user choose. Do not compare an estimated 1RM against an actual tested lift as though they are the same measurement.

Example:

```text
PERSONAL BEST
BENCH PRESS · REP RECORD

Previous: 80 kg × 8
Today:    80 kg × 9

REGULIFT
```

A strike-through on the old value may be decorative, but it must remain legible. Use neutral labels as well as color/arrows. No verified badge unless the existing product explicitly supports that claim.

When the record is invalidated by an edit before export, invalidate the preview and explain why Personal Best is unavailable. Do not silently switch to a different achievement.

### 4.3 My Week

**Purpose:** Make consistency shareable without requiring a PR.

- Use the app’s configured week-start, calendar, timezone, and existing session-completion definition.
- Display a seven-day strip with completed, planned, and rest states using existing schedule data.
- Distinguish a missing plan from a rest day.
- Show up to two selected highlights and an optional date range.
- Count unique completed sessions after existing sync/deduplication rules.
- Multiple sessions on one day may show a count, not duplicate indistinguishable dots.
- A skipped day is not automatically a failure. Rest is not incomplete training.

**Planned-versus-done requires an honest denominator.** Reuse the existing adherence policy and clearly identify whether it uses the original commitment or current schedule. When an appropriate plan snapshot is unavailable, show “3 sessions completed,” not “3 / 3 planned.” Do not retrospectively rewrite the denominator to make adherence look perfect.

Do not compare session tonnage with weekly sets-per-muscle landmarks. Those are different metrics and the landmark template is out of scope.

### 4.4 Template availability and eligibility

The audit must identify destination-aware selectors. The overview’s guard expressly restricts PRs, badges, and Crew; it does not establish a universal ban on exporting ordinary logs. Preserve existing behavior. [B1]

For v2:

- PR/estimated-improvement highlights use only eligible existing records.
- Default Top Sets highlights use the existing permitted/eligible selection; do not promote unverified entries as records.
- When ordinary external log sharing already permits an unverified set, preserve its explicit unverified label or omit it according to that existing policy. Never treat it as a verified PR or make it Crew-eligible.
- For any aggregate, use a selector whose scope matches its displayed label. Do not filter some values and continue labeling the total as all-workout tonnage.
- Unknown eligibility means unavailable until resolved, not implicitly permitted.
- No eligible content means a clear empty state; workout save and ordinary navigation remain unaffected.
- Destination changes re-run the relevant policy. External permission does not imply Crew permission.

Record the exact existing selectors and any missing product decision in SC-00 before enabling v2 templates.

## 5. Optional next-session section

This is the Regulift-specific extension, not a prerequisite for the basic release.

Read the current committed prescription through the existing engine/application adapter. Do not call the engine merely to render an image. Do not turn a pending Coach proposal into an applied target.

The section can be included only when:

1. The user enables it for this card.
2. A next-session target is already committed and still current.
3. An existing, explicitly reviewed prescription-only sharing projection permits these fields.
4. The exercise, load convention, units, and rep target are unambiguous.
5. The output includes a mandatory localized label such as **“Planned — not completed.”**

Never include the causal reason, sleep, readiness, injury note, or private engine evidence. A recommendation can indirectly reveal information; calling it a prescription does not automatically make it safe to export. Preserve the explicit declassification review described in the earlier handoff. [B2]

If that sharing boundary is not implemented, keep `share_cards_next_target_v1` off and ship the three achievement templates without it.

For the initial version, use this section on Top Sets only. Limit it to one selected exercise. No predicted dates, guaranteed gains, “strength increased” headline, or plan-application button inside the share composer.

If the target changes while the composer is open, invalidate the final asset. Show the revised preview and require the user to share again. Do not swap the number after they approved the previous image.

## 6. Visual and export contract

### 6.1 Two looks, not a theme marketplace

**Clean:** Existing Regulift brand palette, typography, icon assets, high contrast, restrained hierarchy. Use existing design tokens rather than introducing unrelated colors.

**Photo:** One explicitly selected background image plus a predictable readability treatment. Text positions remain template-driven; the only photo adjustments are crop/reposition and remove/replace.

Branding is small and consistent. No tracking QR code, unique referral ID, watermark containing account identity, or hidden identifiers. Preserve any existing entitlement rules rather than inventing paid branding removal.

### 6.2 Proposed output profiles

| Profile | Pixel dimensions | Initial encoding |
|---|---:|---|
| Square / Clean | 1080 × 1080 | Opaque PNG |
| Story / Clean | 1080 × 1920 | Opaque PNG |
| Square / Photo | 1080 × 1080 | Opaque JPEG |
| Story / Photo | 1080 × 1920 | Opaque JPEG |

Use standard sRGB output. Match MIME type, actual bytes, extension, and share item type. These sizes are product choices, not guaranteed safe areas for every destination application.

Suggested starting layout:

- Square: 72-pixel side padding, with a separately reserved footer.
- Story: 96-pixel side padding, 180-pixel top and 220-pixel bottom breathing room.
- Keep mandatory labels and unit conventions readable; fit exercise names with wrapping and bounded content before shrinking text.
- Start at a 32-pixel minimum for essential exported labels on a 1080-pixel-wide canvas, then verify on real destination previews.
- Never truncate the “Estimated 1RM,” “Planned,” unverified qualifier, or load-convention label merely to fit.

Do not reuse phone safe-area insets as export padding. Render into a fixed canvas; do not take a screenshot of a screen containing buttons, navigation bars, or notifications.

### 6.3 Preview equals delivered asset

The final approval preview should display the encoded asset that will be handed off, not a separate approximation. During editing a lower-resolution preview is acceptable, but sharing remains disabled until the full asset is ready and current.

If a destination needs different encoding/compression, prepare that variant before its final preview. The visual content must not change after approval. A byte digest may be used internally for asset identity; do not use it as analytics or a hash of private engine inputs.

### 6.4 Performance targets to measure, not promised results

Initial targets on the oldest supported test iPhone:

- Clean full-size export: p95 under 1 second after data is ready.
- Photo full-size export: p95 under 2 seconds after the selected photo is locally available.
- One active full-size render at a time; cancel/ignore obsolete renders.
- Start with an 8 MiB exported-file ceiling, subject to the existing Crew limit. Never silently reduce legibility to hit it.
- Profile peak incremental memory; target under 64 MiB for a single render path, then revise with measured evidence if necessary.

Photo retrieval from iCloud is outside those render timings and may require a network connection. A failure to load it must leave Clean export available. Apple describes selected-asset loading, iCloud failure, and file-lifecycle handling in its Photos picker guidance. [A1]

## 7. Data and rendering architecture

```text
Existing saved workout / PR / week repositories
    ↓
Existing metric, eligibility, unit and calendar selectors
    ↓
ShareCardSnapshotBuilder [read only]
    ↓
ShareCardProjectionPolicy [allowlisted selected fields]
    ↓
CardDocument + local preview/source revisions
    ↓
Existing renderer adapter / template views
    ↓
Image encoder + metadata inspection
    ↓
Exact final asset preview
    ├─ Existing system share coordinator
    └─ Existing Crew publisher, after explicit destination confirmation
```

### 7.1 Responsibility boundaries

| Proposed component | Responsibility | Must not do |
|---|---|---|
| `ShareCardSnapshotBuilder` | Read one coherent saved source and its revisions. | Mutate workout, run progression, or fetch cloud Coach. |
| `ShareCardProjectionPolicy` | Select permitted fields for content and destination. | Serialize a raw model then try to remove sensitive keys. |
| `CardDocument` | Carry only renderable selected values and mandatory qualifiers. | Contain private notes, raw Health context, or database identifiers. |
| `ShareCardComposerModel` | Manage selection, style, consent, loading and stale state. | Calculate PRs or authorize Crew from a default preference. |
| `ShareCardRenderer` | Draw local templates into a fixed image. | Query a repository, load remote fonts, or publish. |
| `SharePhotoLoader` | Load one selected image, normalize and downsample it. | Enumerate the library or access the progress-photo store. |
| `ShareCardAssetStore` | Own temporary files and lifecycle. | Create a permanent gallery or silently upload backups. |
| `ShareDestinationCoordinator` | Hand off the approved image / selected caption. | Treat a callback as verified social publication. |
| Existing Crew service | Authenticate, enforce audience and idempotency, publish. | Accept arbitrary user/owner IDs or reveal an attachment by public URL. |

All names are suggestions. Extend equivalent existing code rather than creating duplicates.

### 7.2 Presentation correctness

Keep original meaning through the shared metric formatter:

- kg versus lb; the device display preference must not trigger a second conversion.
- Per-dumbbell versus combined load, machine-stack conventions, assistance, and bodyweight movements.
- Reps and RPE; missing values remain absent.
- Actual performance versus derived e1RM versus a future prescription.
- Pause-aware session duration according to the existing summary definition.
- Comparable exercise variant and estimator version for any delta.
- Locale-appropriate decimal separators and dates in English, Japanese, and Korean.

Do not format from `Double.description` or compare localized display strings. Use the existing metric/value representations. Do not infer comparable load conventions from exercise display names.

### 7.3 Source and draft revisions

Each editor draft maintains:

```text
draft ID and incrementing draft revision
source identity/revisions — LOCAL ONLY
PR index or weekly aggregate revision when relevant
plan revision only when a next target is included
selected template, format, look, selected content and disclosure choices
photo selection generation and crop state — LOCAL ONLY
renderer and locale versions
```

Increment the draft revision for every visible change, including hiding a field, changing units, switching format, changing language, removing a photo, or changing a caption. A late image-load or render response may update state only when its generation still matches the current draft.

Before external handoff, recheck source existence, source revision, eligibility, entitlement, current draft revision, and next-target validity when included. Before Crew posting, also recheck account and audience. Rebuild and re-preview on a material change; do not silently publish a replacement.

After publication, the image is an immutable snapshot. Source edits must not silently mutate an approved post. Replacing the image is a new explicit publication/update flow through the existing service.

### 7.4 Renderer choice

Reuse the existing rendering implementation when it can meet these requirements. A SwiftUI implementation may evaluate `ImageRenderer`; a working Core Graphics renderer need not be rewritten. Verify supported OS versions, actor isolation, and exact APIs in the project SDK. [A3]

Keep view snapshot work on its required actor and perform heavy decoding/encoding through the project’s controlled image pipeline. Do not assume an `async` method is off-main-thread. Await a fully loaded photo before the final render.

Encoding should create a new image destination from the composited raster, with an explicit property allowlist. Apple’s Image I/O guide documents the destination/add-image/finalize model; its archived code is not a modern drop-in Swift implementation. [A2]

## 8. Privacy and photo handling

### 8.1 Share projection allowlist

| Field | Treatment |
|---|---|
| Selected logged sets | Allowed only through current destination/eligibility policy. |
| Exercise labels | Existing canonical labels; custom labels require review in preview. |
| RPE | Optional user-selected field; no inference for missing data. |
| Comparable PR/e1RM record | Existing eligible record, correctly labeled. |
| Selected workout/week aggregates | Existing shareable selectors, truthful scope labels. |
| Date/name/title | Optional reviewed display strings; no automatic raw profile export. |
| Next prescription | Off by default; reviewed prescription-only projection and current commitment required. |
| Health values / readiness / soreness / body measurements | Not in v2 model, captions, alt text, metadata, or telemetry. |
| Private Coach notes / reasons / check-ins | Never read by this feature. |
| Coordinates / routes / exact workout start time / gym location | Never included automatically. |
| Progress-photo collection | Not a source for this feature. |
| User-selected background | Local processing; finished card shared only after explicit action. |

A string field can still contain private information. A narrow type is not sufficient by itself: use a reviewed builder, controlled source fields, preview, and tests. Photos can visibly show faces, signs, or other private content; stripping metadata cannot remove information visible in pixels. Do not claim automatic anonymization.

### 8.2 Photo pipeline

1. Use the system picker for a single still image; no camera permission or camera capture in this release. Apple documents picker selection without broad library-access authorization. [A1]
2. Load only the selected asset. Prefer a bounded/file-based representation through the existing pipeline, not an eagerly decoded full-resolution library image.
3. Show inline loading and cancellation. Selected assets may be cloud-only; offline failure is expected and recoverable.
4. Validate the actual media type. Support the app’s reviewed still-image formats; use a still representation of a Live Photo only when supported, never its movie/audio.
5. Correct orientation, convert to a controlled color space, and downsample to the required export/crop bounds.
6. Maintain crop/reposition state only within the current draft. A new selection invalidates the old asynchronous load.
7. Composite the complete card, then encode to a new file. Do not copy the original image container or arbitrary EXIF/XMP/IPTC/PNG-text properties.
8. Inspect output properties in tests. Allow required dimensions/encoding/color properties; reject location, capture date, camera serial, comments, thumbnail metadata, original filename, and arbitrary user identifiers.
9. Remove temporary original copies as soon as their consumers finish. Keep final files only for the active share/upload lifecycle.

Use the project’s existing protected file/cache service. Keep temporary assets out of backup and generic image/crash caches. Hide sensitive previews when the app backgrounds using the existing privacy overlay, where available. Do not automatically reopen a previous user’s draft after account switching.

A remembered Photo look should show **“Choose a photo for this card”** on the next session, or explicitly fall back to Clean. It must never silently reuse a past photo.

### 8.3 Captions and accessibility text

Use deterministic text from the **same selected projection**. No free-form AI caption generation and no automatic copy to the clipboard.

- A field hidden on the image must not reappear in a caption, accessibility description, filename, share subject, or link metadata.
- Preserve “Estimated,” “Planned,” load conventions, and unverified qualifiers in text alternatives.
- Provide an optional **Copy caption** action because destinations may handle image-plus-text differently.
- Do not automatically append a session link, tracking ID, date, or name.
- A caption may name only the displayed subset; no unseen exercise list or full workout dump.

The native preview exposes a concise VoiceOver description of the same visible information. The exported flat image may not carry that accessibility description into every destination; do not promise it will.

## 9. External sharing and local lifecycle

Reuse the existing `UIActivityViewController` or equivalent coordinator. Apple’s completion interface reports activity completion/dismissal; use those callbacks for lifecycle and cautious telemetry, not as proof of public posting. [A4]

### Required behavior

- Share a finalized local image file and optional caption only.
- Use a neutral temporary filename such as `regulift-card-<random>.png`; never a workout title, user name, timestamp, or Health field.
- Keep the file readable for the receiving activity’s actual consumption lifecycle; do not delete it immediately after presentation.
- Protect temporary files and clean them on completion/cancellation when no consumer still needs them. Sweep abandoned unleased files after restart; initial retention ceiling: 24 hours.
- A failed render, full disk, permission error, or missing asset shows a retryable state, not “Shared.”
- Support repeated exports as distinct user actions without changing source data.
- Use the proper presentation anchor on supported iPad layouts; do not assume only a full-screen iPhone presentation.
- Do not promise a selected app is installed or will accept image and caption together.

No new “Save to Photos” API path is required for v1. Use existing/system capabilities. Add separate authorization handling only if a later dedicated save action is intentionally scoped.

### State model

```text
idle → loadingSource → editing → rendering → ready
                            ↑          ↓        ↓
                            └── error/stale ← revalidation
                                               ↓
                                          sharingExternally
                                               ↓
                                          editing or closed
```

A completed external handoff does not mean the user published a social post. Never fire `instagram_posted`, `viral_share`, or `new_user_acquired` from a generic share-sheet callback.

## 10. Crew integration — explicit, staged, and reused

Treat this as a separate flag after local export works. Do not assume Crew is private. Resolve the actual current audience from the existing service and show its truthful label, such as “Your followers,” only when accurate.

### 10.1 User flow

```text
Post to Crew
    → Sign in when needed; return to the same local draft
    → Refresh eligibility and audience
    → Preview exact image + optional caption + posting identity
    → Explicit Post
    → Existing authenticated publisher
    → Successful publication receipt
```

When the card hides the display name, clarify that the Crew post still uses the account’s Crew identity. Hiding a name in an image does not make a social post anonymous.

No upload on preview, template selection, photo selection, sign-in, or app backgrounding. Photo-card publication is manual even when ordinary workout auto-posting is enabled.

### 10.2 Existing posts and duplicates

If the workout already has an auto-post, the UI should offer attaching/replacing its card through the existing edit capability, or explicitly disclose that a separate post will be created. Do not silently produce two posts from one Share action.

Use a stable publication request ID bound to authenticated owner, source, approved asset digest, caption, and audience. Double taps, connection retries, and repeated completion callbacks return the existing receipt; a reused request ID with different content is a conflict.

The final source revision check occurs before sending the approved snapshot. A later source edit does not retroactively mutate an already sent image.

### 10.3 Backend requirements only where missing

Audit existing attachment/media support before introducing storage. No new Workflows, Durable Objects, Jev service, or renderer is needed for this feature.

If media attachments are missing, extend the existing publication flow with:

- Authenticated owner binding and audience-authorized reads.
- MIME, byte-size, dimensions, and decoded-file validation, not extension-only checks.
- A private, temporary upload stage and attachment finalization tied to the publication request.
- An unpublished-upload expiry and orphan cleanup.
- Idempotent publication, explicit account/post deletion, and cache invalidation consistent with existing retention rules.
- Existing UGC/report/block/moderation paths for photos; stage Photo-to-Crew separately if those paths do not support image content yet.

Upload only the finalized card, not the original photo, full workout model, or internal snapshot. Do not place image bytes in a new D1 table by default; reuse the existing approved media storage pattern. Actual schema and storage technology are repository-dependent.

Client PR labels are not a basis for awarding Crew points or trusting performance. Existing server/product eligibility still applies. A user-provided image cannot prove a verified lift.

### 10.4 Offline, deletion, and cancellation

External rendering/sharing remains usable without Crew connectivity. Offline **Post to Crew** should explain the connection requirement. Do not automatically queue a photo upload for later unless the existing explicit queue-consent flow already supports it.

An in-flight failure must not leave a visible half-post. Retain only what the existing retry policy permits; revalidate auth/audience before retry. Sign-out, deletion, and cancelled drafts must not resurrect uploads in the background.

Deleting a source workout does not automatically retract copies already sent to external apps. Crew deletion uses the authorized post/attachment record, and the UI should expose the existing delete path. Do not claim that local deletion erases recipients’ copies.

## 11. Persistence and migration

**Phase A needs no new cloud database.** Reuse local style preferences and the existing temporary asset service.

| Local state | Lifetime | Storage rule |
|---|---|---|
| Template/format/look preference | Until reset | Per local profile/device; versioned; no photos or personal fields. |
| Composer content/disclosure choices | Current composer | Memory/session-scoped; reopening requires review. |
| Selected original/cropped image | Active draft/load | Protected temporary storage; no backup; prompt cleanup. |
| Final export image | Active handoff/upload | Leased temporary file plus abandoned-file sweep. |
| Source/render revisions | Current draft | Local only; not exported or placed in analytics. |
| Crew receipt | Existing publication lifetime | Existing owner-bound publisher/receipt store. |

Unknown preference versions or removed templates fall back safely. Switching accounts clears draft/photo state and loads that profile’s style. Resetting style restores Clean defaults without affecting training history.

Do not manipulate SwiftData’s internal SQLite schema directly. Use the repository’s existing migration mechanism only if a genuinely new persistent entity is needed.

## 12. Implementation tickets

Each checkbox is a reviewable task. Merge by vertical slice, not by creating all abstractions before a card can render.

### Phase A — Core local sharing

#### SC-00 — Inventory and scope lock
- [ ] Locate existing summary share buttons, renderer, export coordinator, PR/highlight selectors, aggregate formatter, and entitlement rules.
- [ ] Locate Crew audience, auto-post, attachment, moderation, retry, and deletion implementations.
- [ ] Record destination-specific eligibility and the behavior for unverified ordinary logs.
- [ ] Record minimum iOS target, supported devices, local image/cache service, and app languages.
- [ ] Mark each proposed component reuse/extend/missing. No duplicate engine or metric calculation.
**Exit:** `share_cards_v2_inventory.md` in the repository with actual symbols and test owners.

#### SC-01 — Fixtures and baseline regression tests
- [ ] Add sanitized fixtures for normal session, PR, missing RPE, bodyweight/assisted/per-dumbbell, edited session, and multiple timezones.
- [ ] Record existing exported numbers and entitlement behavior.
**Depends on:** SC-00. **Exit:** existing behavior is reproducible before changes.

#### SC-02 — Snapshot builder and eligibility adapters
- [ ] Read coherent saved sources and current destination policy.
- [ ] Reuse highlights/PRs/aggregates; preserve provenance and unit conventions internally.
- [ ] Produce missing/ineligible/stale states rather than inventing values.
**Depends on:** SC-01. **Exit:** unit tests prove no training writes and no duplicate calculations.

#### SC-03 — Share projection and selected-field policy
- [ ] Build a minimal `CardDocument` from reviewed sources.
- [ ] Apply disclosure toggles across image, caption, accessibility description, and filenames.
- [ ] Exclude private fields and raw source identifiers; add canary tests.
**Depends on:** SC-02. **Exit:** forbidden fields cannot enter the standard render/export path.

#### SC-04 — Top Sets / Clean / square vertical slice
- [ ] Implement the fixed template through the existing renderer adapter.
- [ ] Render one to three eligible highlights with optional correctly scoped summary metrics.
- [ ] Show the encoded final image and export through the current share coordinator.
**Depends on:** SC-03. **Exit:** full offline, no-account flow works for entitled users.

#### SC-05 — Composer and historical entry
- [ ] Add content selection, format controls, state handling, and non-blocking dismissal.
- [ ] Route existing summary and historical sharing into the same composer.
- [ ] Invalidate exports after source edits or late asynchronous results.
**Depends on:** SC-04. **Exit:** no stale or different image can be shared after preview.

#### SC-06 — Personal Best template
- [ ] Map supported existing record kinds into explicit labels.
- [ ] Handle missing comparator, estimated-strength records, and revoked eligibility.
**Depends on:** SC-02–05. **Exit:** no calculated or inferred new PR inside the card feature.

#### SC-07 — My Week template
- [ ] Integrate the existing week selector and calendar policy.
- [ ] Handle planned denominator availability, rest, multiple daily sessions, and duplicates.
**Depends on:** SC-02–05. **Exit:** displayed adherence and counts match their declared semantics.

#### SC-08 — Story format and bounded layout
- [ ] Add portrait layout for all three templates.
- [ ] Test mandatory qualifiers, long names, kg/lb, all languages, and maximum content.
**Depends on:** SC-04, SC-06, SC-07. **Exit:** no clipping or illegible forced shrinkage.

#### SC-09 — Caption, style preference, and lifecycle
- [ ] Generate optional captions from the same projection; add explicit Copy caption.
- [ ] Save only versioned template/format/look preferences.
- [ ] Finalize file leases, cancellation, cleanup, and full-disk errors.
**Depends on:** SC-05, SC-08. **Exit:** hidden fields stay hidden and repeated sharing leaves no orphaned assets.

### Phase B — Regulift-specific detail and photo look

#### SC-10 — Next-session projection review
- [ ] Map the existing prescription-only sharing boundary and source revision checks.
- [ ] Confirm that Health-derived reasons/evidence cannot enter the section.
- [ ] Keep the flag off if that boundary is missing or unreviewed.
**Depends on:** SC-03. **Exit:** explicit reviewed field list, or documented deferral.

#### SC-11 — Optional next-session section
- [ ] Add current-card toggle, mandatory Planned label, and committed-only target.
- [ ] Remove eligibility when target is stale/pending without silently altering an approved preview.
**Depends on:** SC-10, SC-05. **Exit:** planned work cannot appear as a completed achievement.

#### SC-12 — Selected-photo loader
- [ ] Add one-image system picker and cancellable, bounded loading.
- [ ] Handle iCloud-only assets, unsupported format, orientation, and rapid reselection.
- [ ] Reuse protected temporary storage; no progress-photo dependency.
**Depends on:** SC-05, SC-09. **Exit:** Clean sharing survives every photo-load failure.

#### SC-13 — Photo crop, composition, and metadata scrub
- [ ] Add crop/reposition/replace/remove controls with fixed text layout.
- [ ] Encode a new composite with explicit property allowlist and inspect output metadata.
- [ ] Add background privacy behavior and cleanup tests.
**Depends on:** SC-12. **Exit:** only the reviewed composite is exportable; original metadata is absent.

### Phase C — Crew attachment

#### SC-14 — Crew capability/privacy readiness gate
- [ ] Confirm true audience labeling, image attachment support, moderation, authorization, and deletion.
- [ ] Resolve the existing-auto-post case without silent duplicates.
**Depends on:** SC-00, SC-09. **Exit:** media capability is reused or minimal extensions are documented.

#### SC-15 — Explicit Crew composer action
- [ ] Add sign-in return flow, destination preview, identity notice, and explicit Post.
- [ ] Re-run destination eligibility and entitlements.
- [ ] Do not upload photos because an old auto-post toggle is enabled.
**Depends on:** SC-14, SC-05. **Exit:** zero network media upload before explicit publication.

#### SC-16 — Publication idempotency and attachment lifecycle
- [ ] Reuse stable request IDs, owner binding, receipts, safe retry, and existing storage.
- [ ] Implement orphan expiry, post/account deletion, and authenticated media reads when missing.
- [ ] Keep Photo-to-Crew off until image-content controls pass review.
**Depends on:** SC-15. **Exit:** duplicate taps/retries create one authorized post with no leaked asset.

### Phase D — Quality and release

#### SC-17 — Localization and accessibility audit
- [ ] Validate English, Japanese, Korean, localized decimals/dates, VoiceOver, large text, and Reduce Motion.
- [ ] Review exercise labels and photo contrast on final exported images.
**Depends on:** applicable templates/look phases. **Exit:** golden images and device accessibility checklist pass.

#### SC-18 — Privacy and failure-mode suite
- [ ] Execute the acceptance matrix below across bytes, text alternatives, telemetry, files, and requests.
- [ ] Verify no Health/Coach/progress-photo reads and no publication caused by preview.
**Depends on:** SC-09; extend for SC-11/13/16. **Exit:** zero known private-field leakage or unauthorized uploads.

#### SC-19 — Performance and storage budget
- [ ] Measure clean/photo latency, memory, rapid template switching, low disk, and background interruptions.
- [ ] Record measured limits on the oldest supported device.
**Depends on:** SC-08, SC-13 when enabled. **Exit:** budgets met or revised with explicit approval and evidence.

#### SC-20 — Metrics, flags, and staged rollout
- [ ] Add aggregate-only events, separate flags, kill switches, and no training-path dependency.
- [ ] Run internal/beta release; audit legacy fallback before enabling it.
**Depends on:** SC-17–19. **Exit:** release checklist passes and rollback is exercised.

## 13. Acceptance matrix

| ID | Scenario | Required result |
|---|---|---|
| T01 | Saved normal workout, offline, signed out | Entitled user can export Clean card without network. |
| T02 | Workout save fails | Composer cannot represent it as saved; retry does not invent a result. |
| T03 | Adaptation pending | Logged-results sharing works; next target is unavailable. |
| T04 | Cancel sharing at any stage | No plan/log/award changes, no media upload. |
| T05 | RPE missing | Omitted, never zero or inferred. |
| T06 | kg/lb switch | Same underlying result with correct single conversion and labels. |
| T07 | Per-dumbbell, bodyweight, assisted, machine load | Existing conventions preserved in image and caption. |
| T08 | Unverified/ineligible record | Existing restrictions preserved; no PR or Crew bypass. |
| T09 | Unknown eligibility | Unavailable state; not treated as eligible. |
| T10 | Estimated-strength best | Estimated label retained in image and text alternatives. |
| T11 | First eligible record, no baseline | No fictitious old value or percentage. |
| T12 | Variant or estimator mismatch | Comparison omitted or handled by existing explicit comparator rule. |
| T13 | Session edited/deleted during composer | Preview invalidated; no stale publication. |
| T14 | Several PRs in one workout | User-selected eligible record is the one exported. |
| T15 | Week lacks plan baseline | Completed count only; no invented denominator. |
| T16 | Week start/timezone/DST/year boundary | Existing calendar policy and selected week preserved. |
| T17 | Watch/phone duplicate event; two real same-day sessions | Deduplicate only duplicate events; count distinct sessions correctly. |
| T18 | Next target off | No target in pixels, caption, accessibility text, or metadata. |
| T19 | Target pending, stale, or export-restricted | No export of that section; require valid preview without it. |
| T20 | Plan changes after target preview | Invalidate/re-preview before handoff. |
| T21 | Private canaries in Health/reasons/notes/nested metadata | Absent from projection, files, captions, uploads and telemetry. |
| T22 | Date/name/RPE/custom title hidden | Hidden across every export surface, including share subject. |
| T23 | Photo selected but no share/post action | No Regulift media upload or publication. |
| T24 | Source photo has GPS/EXIF/XMP/comments/thumbnail | Newly encoded card contains none of those private properties. |
| T25 | iCloud-only photo offline or access/load failure | Inline error; Clean remains usable. |
| T26 | Rapid photo A→B selection; old A loads last | Only B can appear; stale result discarded. |
| T27 | Remove photo or switch to Clean while render is running | No old photo in the next preview/export. |
| T28 | Saved Photo look, new session/account | No previous image/disclosure settings silently reused. |
| T29 | Final encoding differs from editing preview | Exact encoded asset is reviewed before delivery. |
| T30 | Repeated format/toggle/language changes | Only current draft revision can be handed off. |
| T31 | App backgrounds/terminates, disk full, memory pressure | No training loss; no unexpected photo reveal; cleanup/retry safe. |
| T32 | Share sheet cancel, completion, receiving-app failure | Correct local state; no claim of confirmed social publication. |
| T33 | Receiving activity reads file late | File remains available for its legitimate consumption lifecycle. |
| T34 | Crew signed out | Sign-in optional for Crew; external share still available. |
| T35 | Crew audience/identity | Truthful audience shown; hidden image name not claimed anonymous. |
| T36 | Existing workout auto-post | No silent duplicate; attach/update or explicit separate-post choice. |
| T37 | Double tap/retry/lost response | One publication receipt; no duplicate post. |
| T38 | Same request ID with different asset/caption/audience | Conflict; no silent overwrite. |
| T39 | Wrong owner/media ID or revoked audience access | Rejected; attachment not accessible outside current authorization. |
| T40 | Old auto-post preference plus new photo card | No automatic upload or expanded consent. |
| T41 | Cancel/sign-out/delete with pending upload | No resurrected publication; unbound assets expire. |
| T42 | Source edit after a successful post | Existing image remains a historical snapshot; delete/update explicit. |
| T43 | Long EN/JA/KO names, large editor text, VoiceOver | Usable controls, readable image, mandatory qualifiers not clipped. |
| T44 | Huge image/unsupported type/oversize export | Bounded processing and actionable error; no unsafe fallback. |
| T45 | Feature flag disabled during editing | Stop new v2 publication safely; preserve workout and discard draft. |
| T46 | Legacy fallback has weaker privacy | Do not fall back through it until audited; disable sharing rather than leak. |

Tests should inspect the **actual encoded file and outgoing request**, not only the visible SwiftUI preview. Use synthetic canary values and known photo fixtures; no production personal data in CI artifacts.

## 14. Analytics and rollout

### Approved event shape

```text
share_card_editor_opened   {entry_point}
share_card_asset_ready     {template, format, look, duration_bucket}
share_card_render_failed   {stage, reviewed_error_code}
share_card_handoff_started {destination_class: external | crew}
share_card_activity_ended  {outcome: completed | cancelled | failed | unknown}
crew_card_post_confirmed  {template, look}
```

Use only the existing analytics-consent path. Avoid adding a new analytics SDK. No user/session identifiers beyond the existing approved analytics design, precise activity timestamps, values, names, image hashes, image bytes, captions, photo identifiers, or source reasons in these events.

Template selection itself can reveal limited behavior; collect only what is necessary and reviewed. Never send Health-dependent selectors or prompt text to analytics. Crash reporting must not attach draft images, raw errors containing filenames, or serialized source objects.

### Metrics

- Composer opens per eligible result/weekly entry.
- Asset-ready rate and render failure rate.
- External handoffs per editor open, explicitly not confirmed public posts.
- Verified Crew publications from successful server receipts.
- Repeat use through existing consented analytics, or locally aggregated counts.
- Editing time, cancel rate, and photo-load failure rate.
- Guardrails: workout-completion regression, memory/crash regression, unauthorized upload count, private-field leak count, duplicate post count.

No claim of increased retention or acquisition until measured. Share-sheet completion does not prove an install, a referral, or public visibility.

### Flags

```text
share_cards_v2_core
share_cards_personal_best
share_cards_my_week
share_cards_next_target_v1
share_cards_photo_v1
share_cards_crew_attachment_v1
share_cards_photo_to_crew_v1
```

Flags must be available locally with defaults that preserve offline training. Turning a flag off must not change logged workouts, plan revisions, existing PRs, or already published posts.

### Release order

1. Internal Clean Top Sets vertical slice with privacy/freshness tests.
2. Clean Personal Best and My Week, story format, remembered style and optional captions.
3. Next-session section only after the prescription-export review.
4. Photo look for local/external sharing after metadata and memory tests.
5. Crew attachment; then Photo-to-Crew only after media audience/moderation/deletion gates.

Roll back for any private-field leak, unexpected upload, duplicate publication, incorrect achievement label, or training-path regression. Prefer disabling the affected look/destination instead of the entire training app. Do not switch to an unaudited legacy renderer as a privacy fallback.

## 15. Definition of done

- [ ] The repository audit identifies reused implementations and genuine gaps.
- [ ] Three templates and two formats work with current saved data and correct metric semantics.
- [ ] Clean export works offline for existing entitled users without Crew sign-in.
- [ ] Photo look is bounded, locally processed, explicitly selected, and absent from saved style state.
- [ ] Hidden/private fields are absent from pixels, metadata, captions, alternative text, requests, and logs.
- [ ] Optional next targets are committed, current, explicitly export-permitted, and labeled planned.
- [ ] The final approved image is the delivered asset; stale previews cannot be published.
- [ ] Sharing never saves, recalculates, approves, or applies a training change.
- [ ] Crew audience, identity, idempotency, attachment authorization, deletion, and photo moderation gates pass.
- [ ] Original auto-post consent is not expanded to photo cards.
- [ ] Localization/accessibility and the applicable acceptance tests pass on real targets.
- [ ] Performance/memory measurements and screenshots are attached to the release PR.
- [ ] Rollback and temporary-file cleanup are exercised.

**Ship report from the coder:** reused/new symbols, screenshots of all enabled template/look/format combinations, device/OS matrix, test results, measured export latency/memory, migration/storage changes, known limitations, and enabled flags.

---

## Appendix A. Reference Swift contracts and preview checks

The following is a small **local policy reference**, not a complete privacy validator, renderer, backend, or app integration. It relies on existing repository selectors to supply truthful destination eligibility and approved fields. Map it to existing types rather than copying a second set of policies.

The contract was type-checked and exercised with 25 standalone checks in this working environment. Actual SwiftUI/UIKit/Image I/O execution, pixel/metadata inspection, Xcode compilation, and Crew integration have not been tested here.

```swift
import Foundation

// Reference contracts only. Map to existing Regulift types and selectors.
// These are LOCAL contracts, not Worker request/response DTOs.
enum CardTemplate: String, Codable, Sendable { case topSets, personalBest, myWeek }
enum CardFormat: String, Codable, Sendable {
    case square, story
    var pixelWidth: Int { 1080 }
    var pixelHeight: Int { self == .square ? 1080 : 1920 }
}
enum CardLook: String, Codable, Sendable { case clean, photo }
enum Eligibility: Sendable { case eligible, ineligible, unknown }
enum CardIssue: String, Error, Sendable {
    case sourceMissing, workoutNotSaved, eligibilityUnavailable
    case sourceIneligible, noEligibleSets, noEligiblePR, noEligibleWeekSessions
    case previewObsolete, sourceChanged, nextTargetUnavailable, photoUnavailable
}

struct TemplateFacts: Sendable {
    let sourceExists: Bool
    let sourceSaved: Bool
    // Verdict for THIS destination; supplied by the existing sharing policy.
    let eligibility: Eligibility
    let eligibleSetCount: Int
    let eligiblePRCount: Int
    let eligibleWeekSessionCount: Int
}

// All strings must be produced from reviewed, selected fields by the builder.
// String typing alone does NOT prevent private information entering a card.
struct CardRow: Equatable, Sendable {
    let label: String
    let value: String
    let qualifier: String?
}
struct PlannedTarget: Equatable, Sendable {
    let exerciseLabel: String
    let prescriptionLabel: String
    let statusLabel: String // Localized "Planned - not completed"; never optional.
}
struct CardDocument: Equatable, Sendable {
    let schemaVersion: Int
    let template: CardTemplate
    let title: String
    let dateLabel: String?
    let displayName: String?
    let rows: [CardRow]
    let summaryLines: [String]
    let plannedTarget: PlannedTarget?
    let brandLabel: String
    // No notes, Health fields, causal explanations, raw IDs or photo metadata.
}
struct SavedCardStyle: Codable, Sendable {
    let schemaVersion: Int
    let template: CardTemplate
    let format: CardFormat
    let preferredLook: CardLook
    // Deliberately excludes photo, identity/date toggles and next-target consent.
}
struct PreviewStamp: Equatable, Sendable {
    let draftRevision: Int64 // Increment for EVERY content/format/photo/toggle edit.
    let sourceRevision: String // Opaque local reference; never a Health-data hash.
    let rendererVersion: String
}
struct PlannedTargetFacts: Sendable {
    let isCommitted: Bool
    let isCurrent: Bool
    let exportPermitted: Bool // Explicitly reviewed prescription-only projection.
}

enum ShareCardPolicy {
    static func checkTemplate(_ template: CardTemplate, facts: TemplateFacts) throws {
        guard facts.sourceExists else { throw CardIssue.sourceMissing }
        guard facts.sourceSaved else { throw CardIssue.workoutNotSaved }
        switch facts.eligibility {
        case .unknown: throw CardIssue.eligibilityUnavailable
        case .ineligible: throw CardIssue.sourceIneligible
        case .eligible: break
        }
        switch template {
        case .topSets:
            guard facts.eligibleSetCount > 0 else { throw CardIssue.noEligibleSets }
        case .personalBest:
            guard facts.eligiblePRCount > 0 else { throw CardIssue.noEligiblePR }
        case .myWeek:
            guard facts.eligibleWeekSessionCount > 0 else {
                throw CardIssue.noEligibleWeekSessions
            }
        }
    }

    // Re-run destination eligibility, auth, entitlements and source existence
    // outside this function at handoff. Do not trust stale TemplateFacts.
    static func checkPreview(
        rendered: PreviewStamp,
        current: PreviewStamp,
        includesNextTarget: Bool,
        target: PlannedTargetFacts?,
        look: CardLook,
        photoReady: Bool
    ) throws {
        guard rendered.sourceRevision == current.sourceRevision else {
            throw CardIssue.sourceChanged
        }
        guard rendered.draftRevision == current.draftRevision,
              rendered.rendererVersion == current.rendererVersion else {
            throw CardIssue.previewObsolete
        }
        if includesNextTarget {
            guard let target, target.isCommitted, target.isCurrent,
                  target.exportPermitted else { throw CardIssue.nextTargetUnavailable }
        }
        if look == .photo && !photoReady { throw CardIssue.photoUnavailable }
    }
}
```

### Reference test harness

Save the preceding block as `ShareCardPolicy.swift` and the next block as `PolicyTests.swift` to reproduce the standalone checks. These fixtures do not establish actual app privacy or correctness; add repository tests from the acceptance matrix.

```swift
import Foundation

@main enum PolicyTests {
    static func main() throws {
        var count = 0
        func check(_ expected: CardIssue?, _ body: () throws -> Void) {
            do {
                try body()
                precondition(expected == nil, "Expected \(String(describing: expected))")
            } catch let error as CardIssue {
                precondition(error == expected, "Unexpected \(error), expected \(String(describing: expected))")
            } catch { preconditionFailure("Unexpected error: \(error)") }
            count += 1
        }
        func facts(exists: Bool = true, saved: Bool = true,
                   eligibility: Eligibility = .eligible, sets: Int = 1,
                   prs: Int = 1, sessions: Int = 1) -> TemplateFacts {
            TemplateFacts(sourceExists: exists, sourceSaved: saved,
                          eligibility: eligibility, eligibleSetCount: sets,
                          eligiblePRCount: prs, eligibleWeekSessionCount: sessions)
        }
        for template in [CardTemplate.topSets, .personalBest, .myWeek] {
            check(nil) { try ShareCardPolicy.checkTemplate(template, facts: facts()) }
        }
        check(.sourceMissing) { try ShareCardPolicy.checkTemplate(.topSets, facts: facts(exists: false)) }
        check(.workoutNotSaved) { try ShareCardPolicy.checkTemplate(.topSets, facts: facts(saved: false)) }
        check(.eligibilityUnavailable) { try ShareCardPolicy.checkTemplate(.topSets, facts: facts(eligibility: .unknown)) }
        check(.sourceIneligible) { try ShareCardPolicy.checkTemplate(.topSets, facts: facts(eligibility: .ineligible)) }
        check(.noEligibleSets) { try ShareCardPolicy.checkTemplate(.topSets, facts: facts(sets: 0)) }
        check(.noEligiblePR) { try ShareCardPolicy.checkTemplate(.personalBest, facts: facts(prs: 0)) }
        check(.noEligibleWeekSessions) { try ShareCardPolicy.checkTemplate(.myWeek, facts: facts(sessions: 0)) }
        check(.noEligibleSets) { try ShareCardPolicy.checkTemplate(.topSets, facts: facts(sets: -1)) }
        let current = PreviewStamp(draftRevision: 2, sourceRevision: "session-v3", rendererVersion: "1")
        let good = PlannedTargetFacts(isCommitted: true, isCurrent: true, exportPermitted: true)
        func preview(_ rendered: PreviewStamp = current, next: Bool = false,
                     target: PlannedTargetFacts? = nil, look: CardLook = .clean,
                     ready: Bool = false) throws {
            try ShareCardPolicy.checkPreview(rendered: rendered, current: current,
                includesNextTarget: next, target: target, look: look, photoReady: ready)
        }
        check(nil) { try preview() }
        check(.previewObsolete) { try preview(PreviewStamp(draftRevision: 1, sourceRevision: "session-v3", rendererVersion: "1")) }
        check(.sourceChanged) { try preview(PreviewStamp(draftRevision: 2, sourceRevision: "session-v2", rendererVersion: "1")) }
        check(.previewObsolete) { try preview(PreviewStamp(draftRevision: 2, sourceRevision: "session-v3", rendererVersion: "0")) }
        check(.nextTargetUnavailable) { try preview(next: true) }
        check(.nextTargetUnavailable) { try preview(next: true, target: PlannedTargetFacts(isCommitted: false, isCurrent: true, exportPermitted: true)) }
        check(.nextTargetUnavailable) { try preview(next: true, target: PlannedTargetFacts(isCommitted: true, isCurrent: false, exportPermitted: true)) }
        check(.nextTargetUnavailable) { try preview(next: true, target: PlannedTargetFacts(isCommitted: true, isCurrent: true, exportPermitted: false)) }
        check(nil) { try preview(next: true, target: good) }
        check(.photoUnavailable) { try preview(look: .photo) }
        check(nil) { try preview(look: .photo, ready: true) }
        check(nil) { try preview(next: false, target: PlannedTargetFacts(isCommitted: false, isCurrent: false, exportPermitted: false)) }
        precondition(CardFormat.square.pixelHeight == 1080 && CardFormat.story.pixelHeight == 1920)
        count += 1
        let style = SavedCardStyle(schemaVersion: 1, template: .topSets, format: .story, preferredLook: .photo)
        let bytes = try JSONEncoder().encode(style)
        let keys = Set((try JSONSerialization.jsonObject(with: bytes) as! [String: Any]).keys)
        precondition(keys == ["schemaVersion", "template", "format", "preferredLook"])
        count += 1
        print("Passed \(count) standalone policy checks")
    }
}
```

Run:

```sh
swiftc -typecheck ShareCardPolicy.swift
swiftc ShareCardPolicy.swift PolicyTests.swift -o share-card-policy-tests
./share-card-policy-tests
```

Expected output: `Passed 25 standalone policy checks`.

## Appendix B. Basis, references, and verification limits

### Product sources

**[B1] User-provided `OVERVIEW(1).md`, dated 17 September 2026.** Program-engine/verification behavior at lines 18–24; existing sharing at lines 31–36; Crew at lines 51–52; offline/account/privacy at lines 57–60; languages at lines 13–14. This establishes the documented baseline, not the current repository implementation.

**[B2] Previously generated `FORGECORE_INTEGRATION.md`.** Sections “Workout completion integration,” “Privacy: correct the earlier ‘send all context’ idea,” “One commit path for UI, Coach and voice,” and “Connect existing interfaces.” Reuse its saved-fact/adaptation distinction and explicit prescription-versus-private-evidence export boundary. It is a prior proposed handoff, not evidence that these interfaces already exist.

**[B3] The immediately preceding agreed Share Cards v2 discussion.** Source of the three templates, Clean/Photo looks, explicit Crew sharing, no recovery-sharing template, no Jev, and separate Health-ingestion scope. No And Done shipping claims are relied on in this plan.

### Official engineering references checked on 20 September 2026

**[A1] Apple — What’s new in the Photos picker, WWDC22.** Supports the selected-asset picker, on-demand asset loading, cloud-only asset failure, and explicit file-lifecycle considerations. This is platform guidance, not a promise that selected photos are always locally available.

`https://developer.apple.com/videos/play/wwdc2022/10023/`

**[A2] Apple — Image I/O Programming Guide: Working with Image Destinations.** Archived conceptual reference for image destinations, explicit properties, adding an image, and finalization. The metadata allowlist and inspection tests in this plan are additional product requirements, not an Apple guarantee that arbitrary re-encoding removes every private property.

`https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/ImageIOGuide/ikpg_dest/ikpg_dest.html`

**[A3] Apple — ImageRenderer.** Candidate API entry point only. The reference page exposed a JavaScript-required shell during this lookup; its complete current API content could not be retrieved. Verify exact availability, isolation and behavior in the project SDK. No renderer code in this document was compiled against an Apple SDK.

`https://developer.apple.com/documentation/swiftui/imagerenderer`

**[A4] Apple — UIActivityViewController / completionWithItemsHandler.** The indexed property summary describes completion when the service finishes or the controller is dismissed. Full reference content was JavaScript-limited in this lookup. This plan deliberately does not treat the callback as proof of public social publication.

`https://developer.apple.com/documentation/uikit/uiactivityviewcontroller`

`https://developer.apple.com/documentation/uikit/uiactivityviewcontroller/completionwithitemshandler-swift.property`

### Explicit verification limits

- The supplied product overview and the relevant prior integration sections were reviewed.
- The small Foundation-only reference policy type-checks; 25 standalone policy/serialization checks passed.
- No actual Regulift source, existing renderer, entitlement, live Crew API, image storage, or moderation implementation was inspected.
- No real card image was rendered or inspected in this deliverable, and no export latency/memory claim is a measured result.
- Regulift’s live website/privacy endpoints were not retrievable in this session. Reconcile current published copy with the implemented behavior before release; this document uses the supplied baseline and earlier agreed privacy boundaries.
- Official Apple guidance informs the implementation choices above. Current SDK compilation, device behavior, security review and all application acceptance tests remain the coder’s release work.

---

**Recommended first delivery:** Top Sets + Clean + square export using existing sharing, with selected-field privacy and stale-preview tests. Expand from that working vertical slice; do not start with photos or backend infrastructure.
