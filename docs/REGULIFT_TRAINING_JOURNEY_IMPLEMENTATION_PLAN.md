# ReguLift — My Training Journey
## Coding-ready implementation plan

**Version:** 1.0  
**Prepared:** September 19, 2026  
**Status:** Proposed implementation; no repository changes or tests have been performed.  
**Deliverable:** A private personal profile and chronological training timeline inside the existing Progress surface.  
**Navigation label:** `Timeline`  
**Product name:** `My Training Journey`

> Build a connected view of the user's real training records, meaningful changes, and optional reflections. Do not build a second workout database, a public social profile, or another top-level tab.

---

## Quick start for the coding agent

Read Sections 1–7 before changing models. Execute **J0 → J1 → J2 → J3 → J4 → J5 → J6 → J7**, using the task IDs in Section 12. Begin with **TJ-FND-01**: map the actual repository and identify which dependencies are already implemented.

The first working slice is:

```text
Save a workout through the existing flow
  → open Progress → Timeline
  → see one truthful, private workout card
  → open the original workout detail
  → edit that workout through the existing editor
  → see the corrected card without a duplicate
  → reopen the app offline and retain the same result
```

This document is self-contained for the Journey feature. The earlier audit remains the authority for existing correctness fixes and shared contracts. It does not need to be reimplemented from scratch. All proposed names below must be mapped to the repository's actual architecture.

## Contents

1. [Product outcome and scope](#1-product-outcome-and-scope)
2. [Integration with the existing app and roadmap](#2-integration-with-the-existing-app-and-roadmap)
3. [Navigation and screen specification](#3-navigation-and-screen-specification)
4. [Event and card specification](#4-event-and-card-specification)
5. [Dates, metrics, and truthful presentation](#5-dates-metrics-and-truthful-presentation)
6. [Data model and service contracts](#6-data-model-and-service-contracts)
7. [Projection, pagination, and lifecycle rules](#7-projection-pagination-and-lifecycle-rules)
8. [Profile, reflection, and visibility flows](#8-profile-reflection-and-visibility-flows)
9. [Privacy and selective sharing](#9-privacy-and-selective-sharing)
10. [Visual design, accessibility, and copy](#10-visual-design-accessibility-and-copy)
11. [Persistence, offline operation, and compatibility](#11-persistence-offline-operation-and-compatibility)
12. [Implementation milestones and task checklist](#12-implementation-milestones-and-task-checklist)
13. [Required regression fixtures](#13-required-regression-fixtures)
14. [Measurement and usability validation](#14-measurement-and-usability-validation)
15. [Release gates and definition of done](#15-release-gates-and-definition-of-done)
16. [Coding-agent execution instructions](#16-coding-agent-execution-instructions)
17. [Pull-request handoff template](#17-pull-request-handoff-template)
18. [Source basis and verification boundaries](#18-source-basis-and-verification-boundaries)

---

## 1. Product outcome and scope

### 1.1 The job to solve

Users should be able to answer:

- What have I recorded, and when?
- What milestones or meaningful program changes happened along the way?
- How do I open, correct, hide, or intentionally share the original record?

The timeline adds context to existing Progress charts. It is not itself a new training engine, health assessment, adherence score, or causal explanation of results.

### 1.2 Included in the complete feature

| Capability | Required outcome |
|---|---|
| Compact personal header | Optional identity, an existing active goal, and accurately labeled training dates |
| Progress navigation | `Overview` and `Timeline` views, with full History still directly reachable |
| Unified private timeline | Existing saved workouts, eligible milestones, body records, program/block events, and reviews in one chronological view |
| Optional reflections | Short private notes, either standalone or linked to an existing training record |
| Filters and month navigation | Find a past event without scrolling the entire training history |
| Source-linked details | Reuse the original workout, measurement, photo, program, goal, or experiment destination |
| Applied-change context | Show meaningful committed program changes with their real scope and status |
| Visibility controls | Hide an item without deleting its underlying record; restore hidden items |
| Body-photo discretion | Photo previews concealed by default; explicit reveal and optional preference |
| Selective sharing | Reuse the existing explicit Crew/share preview for eligible workouts and verified milestones |
| Reliability | Correct edits, deletions, imports, sync, account switching, offline use, and cache rebuilding |

### 1.3 Explicitly excluded

Do not add a followers/following system, public profile discovery, likes/comments, a new social feed, gym-location check-ins, live location, leaderboards, exercise-video content, automated photo analysis, or AI-generated daily journaling.

Do not auto-publish personal events. Do not add a separate paywall for the timeline, replace the existing database/sync stack, introduce a new paid vendor, or raise minimum OS requirements as part of this feature.

Do not put raw Coach chats, voice transcripts, soreness, sleep, readiness measurements, food logs, or every next-set adjustment in the timeline. Important applied training changes can appear through a deliberately limited projection.

### 1.4 Product defaults

| Decision | Default |
|---|---|
| Ownership | Private, personal, available without a new social account requirement |
| Top-level navigation | Keep current tabs; extend Progress |
| First landing | Existing Overview; remember an explicitly selected Timeline view locally |
| Timeline order | Newest training date first, with deterministic ordering within each day |
| Default filter | All included event categories |
| Photo previews | Hidden on a new installation/device until explicitly enabled |
| Reflection requirement | Never mandatory for logging or finishing a workout |
| Notifications | No new Journey push notifications or streak pressure |
| New AI dependency | None; deterministic cards from real records |
| Default publication | None |

---

## 2. Integration with the existing app and roadmap

### 2.1 Preserve the existing separation of responsibilities

The prior audit assigns Progress to reviewing recorded progress, Crew to optional shared participation, Settings to durable preferences, and Program detail to training structure. Keep that separation. [B1, Section 5.3]

| Existing surface | Journey integration | Do not replace |
|---|---|---|
| Progress | Compact header; Overview/Timeline switch; direct History action | Existing charts, tools, and History |
| Workout summary | Optional `View in timeline` link after successful save | Save receipt, eligibility explanation, editing, sharing |
| History | Open the same canonical workout detail from a timeline card | Full session browsing and existing history import |
| Body / Measurements / Photos | Show private source-linked entries | Existing storage, photo viewer, precise measurement editor |
| Program / Blocks | Project actual starts and meaningful committed changes | Program roadmap, versions, enrollment, permissions |
| PRs / Achievements | Attach verified milestones to their originating sessions | PR calculations, eligibility rules, award policies |
| Experiments / Goals | Surface real review results, including inconclusive reviews | Evaluation logic and benchmark protocols |
| Crew | Explicit share action with the existing audience preview | Existing social identity, permissions, publication records |
| Settings | Journey visibility and private profile preferences | Training settings and Gym Profiles |

**Terminology:** `My Training Journey` concerns the person. `Gym Profiles` concern training locations and equipment. Never reuse the same model or menu label for both.

### 2.2 Dependencies on the previous roadmap

| Previous work | How Journey uses it | When it is needed |
|---|---|---|
| Correctness and readability release | Shared recorded/partial/eligible semantics, reliable save feedback, readable components | Before broad Journey release |
| Shared metric/comparison services | Consistent values, units, equipment scope, and milestone eligibility | Core cards |
| Equipment Passport | Equipment-specific PR/comparison context | Enrich when implemented; never invent equivalence meanwhile |
| Recommendation evidence | Applied-change reason and outcome-review links | Enhanced change cards |
| Coach My Program | Program versions and permission summaries | Enhanced program cards |
| Week Designer | Meaningful accepted schedule changes, when intentionally exposed | Optional integration; no card per daily planning operation |
| Set-limiter feedback | Existing analysis eligibility, where the source explains it | Source details only; do not publish limiter reasons |
| Goal benchmarks | Real measured/estimated goal review results | Goal review cards |
| Conversational voice Coach | No new dependency | Keep conversations out of Journey |
| Shareable program links | A separate program-sharing action | Do not confuse sharing a program with publishing a personal timeline |

A roadmap task being written does not mean its code exists. In J0, classify each dependency as **implemented**, **partially implemented**, or **not implemented** using repository evidence.

The workout/body/notes timeline must be able to ship without waiting for every advanced coaching feature. For unavailable event sources, leave the adapter disabled and document its dependency. Do not ship fabricated records or placeholder success cards, and do not report the integration as complete until it is connected and tested.

### 2.3 Source-of-truth rules

1. Existing domain records remain authoritative. Journey may hold a rebuildable index, not a second editable copy of workouts or measurements.
2. Existing aggregate, comparison, PR, and eligibility services determine values and status. A card must not contain a parallel formula.
3. Timeline browsing cannot mutate training prescriptions, completion status, awards, program permissions, or published content.
4. Source changes invalidate dependent cards, including badges and hidden/cached images.
5. Training-data, Health-data, sync, and publication boundaries remain separate. [B1, Sections 4.2 and 8.3–8.5]

---

## 3. Navigation and screen specification

### 3.1 Progress shell

Keep the existing Progress destination. Add a small identity header and a segmented switch:

```text
PROGRESS                                      History

[Avatar] Alex                                  Edit
         Goal: Build strength
         Training records since June 2026

[ Overview ] [ Timeline ]
```

These names, dates, and values are illustrative fixture content, not real user data.

The header should fit in roughly two or three text rows at normal text size, without a fixed height that clips larger text. Show an active goal only when an actual goal exists. Do not add a large cover photo, public follower counts, a badge wall, or fabricated zero-value statistics.

Use the existing Overview below the switch. Do not duplicate its trend charts above the timeline. Preserve navigation and scroll position independently for both views.

### 3.2 Timeline view

```text
September 2026                    Filter: All ▾
                                      Add note

19 SEP
│
├─ Upper Body A
│  Saved workout · 48 min · 16 working sets recorded
│  Bench press: 60 kg × 8
│  Rep PR at this load
│                            View workout ›
│
17 SEP
│
├─ Training block started
│  Upper / Lower · Four sessions per week
│  Adaptation: Adjust my targets
│                            View program ›
│
15 SEP
│
├─ Progress photo saved · Private
│  [Preview hidden]
│                            View photo ›
│
12 SEP
│
├─ Program change applied
│  Next week's planned sets: 12 → 10
│  Scope, reason, and current status
│                            View change ›
```

The date rail is optional decoration. At large text sizes or narrow widths, move the date above the cards and recover the horizontal space. Never use the decorative rail as the only date information.

### 3.3 Filters

Use one filter sheet, not a cramped row of six horizontal tabs. Supported categories:

| Filter | Included entries |
|---|---|
| All | Every enabled, visible Journey category |
| Workouts | Saved workout cards, with eligible inline milestones |
| Milestones | Workout cards that currently contain verified milestones, plus valid standalone achievements |
| Program changes | Actual block/program starts and meaningful committed changes |
| Body | Measurement records and photo records |
| Notes | User-authored reflections |
| Reviews | Available goal and experiment review records |

Support multiple categories using **OR**, not AND. `All` means no category restriction. An empty category selection resolves visibly to `All`; it must not silently produce a confusing blank state.

A session matching both Workouts and Milestones appears once. Restore hidden entries through a separate `Hidden items` management view; ordinary filters must never bypass hiding.

Provide a clear reset action and show a concise selected-filter label. Keep the current filter locally; it is a view preference, not a public profile setting.

### 3.4 Month navigation and chart links

Tapping the month heading opens a month/year chooser with known record coverage. Selecting a month queries that date range directly; do not load all preceding months to reach it.

A month with no visible matches says `No matching entries this month` and offers `Clear filters` or navigation to adjacent months. Do not show fabricated activity.

Where an existing chart point maps to one record, offer `View record` or `View in timeline`. An aggregate chart point covering several workouts should open the corresponding filtered period/list, not choose an arbitrary workout.

### 3.5 Source routes and return behavior

Define or reuse canonical routes to workout detail, body entry, photo viewer, program version, applied-change detail, goal review, experiment review, and reflection editor.

Every route resolves the current owner and source existence. A deleted, inaccessible, or unsynchronized source has an explicit unavailable state. Never fall back to another user's record or an unrelated latest workout.

Opening a card and returning preserves the selected segment, filters, month, and a stable item anchor. If that item was deleted or hidden, restore to the nearest surviving neighbor without crashing.

### 3.6 Primary empty and loading states

| State | Required UI |
|---|---|
| No training records | `Your training journey starts with your first saved workout.` Link to the existing start-workout route; note creation remains optional |
| Records exist; first index is building | `Organizing your history…` Keep Overview and History usable; never claim there are no workouts |
| No filter matches | `No entries match these filters.` Provide reset |
| No entries in selected month | Month-specific empty state, not a global new-user screen |
| Photo unavailable locally | Private placeholder with an explicit permitted retrieval/view action |
| Source not yet synced | `Waiting for this record` or equivalent accurate state, without a stale sensitive preview |
| Index/query failure | Explain the failure, provide retry and History; never reset the source store |
| Offline | Show locally available entries normally; explain only actions that actually need connectivity |
| Feature disabled | Preserve access to History, source records, notes, and data controls as specified in Section 11 |

---

## 4. Event and card specification

### 4.1 Event inclusion matrix

| Event kind | Canonical source | Feed behavior | Do not show |
|---|---|---|---|
| Saved workout | Existing saved session | One card per session; explicit partial/completion status | A card for every set; in-progress drafts; discarded empty sessions |
| Workout milestone | Existing validated achievement linked to a session | Inline on the parent workout; parent also matches Milestones filter | A second identical PR card or an unverified achievement |
| Standalone achievement | Existing achievement without a usable parent session | One card with honest source/context | A guessed parent or synthetic achievement |
| Program/block start | Recorded activation/start event or historical enrollment | One real start card; link to the relevant version | A start inferred only from today's active program configuration |
| Applied program change | Persisted action/change receipt | One card per meaningful committed change | Suggested, rejected, cancelled, or unconfirmed proposals as applied events |
| Measurement entry | Existing body/check-in record | Exact recorded fields; group only by an existing stable source group | An assumed health benefit or a fabricated trend |
| Photo entry | Existing private photo record | Concealed preview by default; use the existing viewer | Raw image bytes in the index or automatic social publication |
| Goal review | Existing review + benchmark references | Observed outcome, measurement type, limitations, next step | A promised achievement date or an incompatible comparison |
| Experiment review | Existing completed/inconclusive review | Variable, observed result/status, next decision | A new experiment described as a proven result |
| Reflection | User-authored journal record | Short text preview and original date | Generated notes attributed to the user |

A grouped measurement or photo event may reuse a real check-in/batch identity. Do not invent unstable group IDs from the current date, localized titles, or array positions. A source without grouping can remain its own card.

### 4.2 Workout card

Required fields are session title, recorded date, actual persisted duration where known, saved/partial/completed status, and a compact recorded-work summary. Use the existing duration and precision formatters.

Show no more than one featured lift or verified milestone in the compact card. A `+N milestones` disclosure can open the existing achievement detail when more exist. Featured content must be deterministic and backed by actual records, not ranked by a language model.

Use the canonical workout eligibility outcome. A saved partial or flagged workout remains visible privately even when it is not eligible for PRs, badges, a particular metric, or Crew publication. Add a concise scope explanation and the existing detail route. The earlier audit explicitly distinguishes recorded work, planned completion, analysis eligibility, achievement eligibility, and publication. [B1, Section 4.1]

Do not turn `Saved partial` into `Failed`. Do not equate every saved workout with a completed planned session. Do not compute header totals from the currently loaded feed rows.

### 4.3 Milestone rules

A PR badge must carry the existing achievement identity and comparison context, including equipment and load convention where relevant. Do not compare two machines as equivalent because their displayed weight matches.

When history edits invalidate a PR, remove or correct its badge and its Milestones-filter membership. Do not retain a celebratory cached summary as if it were still valid. If the existing achievement system retains a superseded award for audit purposes, display that state only in the source detail.

Hiding a workout hides its inline milestones in every feed filter. Restoring it does not recompute or award anything.

### 4.4 Meaningful program changes

Use a small, versioned display policy for which committed changes deserve a standalone card. Initial included classes: program activation, block activation, material weekly-volume change, adaptation-permission change, and explicit split/session-structure change.

Routine next-set adjustments remain inside the workout. Ordinary day moves need not produce standalone events. Do not guess whether an old change was "material" from the current plan; evaluate the actual receipt using the display policy.

Show:

```text
Title: Program change applied / Change scheduled / Change reverted
Recorded: When the user/authorized policy committed the change
Effective: The actual affected date or period
Before → After: Existing immutable receipt fields
Authorization: Confirmed by you / Applied within your chosen permissions
Reason: Approved local projection, or a neutral detail link
Source: The exact program version and change receipt
```

A committed change that takes effect next week is **scheduled**, not already active. A later reversal updates the original card's status and may link to the separate reversal receipt. Preserve the historical before/after snapshot; do not replace it with today's plan.

Do not reconstruct historical adjustments when no reliable receipts exist. Start recording compatible receipts from the integration date and document the coverage boundary.

### 4.5 Body cards

Use the original stored precision and unit. A single measurement is a measurement, not a trend. Do not label an increase/decrease as inherently good or bad.

Photos remain optional. The concealed state shows only a generic photo symbol, date, and `Private`. Reuse the existing photo asset/storage service and viewer. Do not create an additional image library or run image analysis.

### 4.6 Review cards

Use the existing review state: achieved, not yet achieved, not comparable, inconclusive, deferred, or the repository's equivalent. Distinguish a measured result from an estimate. Preserve the baseline/protocol/version referenced by the review.

A review that is invalidated by an edited or deleted result must stop displaying a current success claim. The underlying original decision record can remain as historical context, with an explicit superseded/needs-review status.

Use observational wording such as `Recorded result after this change`, not `This change caused your improvement`.

### 4.7 Reflections

A reflection is short user-authored plain text with a chosen date and an optional source link. Suggested empty prompts may include `Something you want to remember?`; do not prefill fabricated personal content.

Initial limit: **2,000 user-perceived characters**, enforced consistently by editor and storage validation. This is a product limit, not an SDK requirement. Preserve Unicode, line breaks, and normal punctuation. Do not render HTML, execute code, fetch pasted URLs, or send the text to Coach automatically.

The compact card shows a bounded preview with `Read more`. Do not force a title or attach a mood score. Attach photos through the existing Body feature, not a new journal attachment system in this release.

---

## 5. Dates, metrics, and truthful presentation

### 5.1 Explicit date semantics

Distinguish at least these concepts:

| Field | Meaning |
|---|---|
| `occurredAt` | Known event instant, when the source actually has one |
| `recordedLocalDate` | Source's explicit training/measurement/note date |
| `sourceTimeZone` | Known source/import time zone; may be unknown |
| `createdAt` / `updatedAt` | Persistence timestamps, not substitutes for the event date |
| `effectivePeriod` | When a committed program change applies |
| `importedAt` | Import metadata; never the workout's timeline date |

Use the shared app date service, not separate per-card date arithmetic. The intended Journey behavior is to preserve known source-local training dates and original dates from imports. Do not replace unknown source time zones with a confidently asserted location or true occurrence time.

During J0, verify the current History/date policy. If it intentionally groups records by the viewer's current time zone, resolve the difference in that shared service before release; do not make History and Timeline disagree silently. Record the agreed policy and its version in the implementation note.

Legacy records with incomplete date information must use the existing documented import/legacy interpretation and carry an inferred/unknown provenance where relevant. A new fallback must be deterministic, shared, and reviewable; it must not change whenever a background job happens to run in another time zone.

Date-only entries remain date-only. A sort surrogate must not be presented as a real midnight timestamp. Journal entries may be dated today or in the past; future planning belongs in the existing program/week workflow.

### 5.2 Deterministic ordering

After the shared date policy resolves an entry's display date, order by:

```text
resolvedLocalDate descending
then precision rank: timed records before date-only records
then known occurrence/commit instant descending for timed records
then stable event ID descending
```

Use the same ordering in query predicates, cursors, month boundaries, restoration, and tests. Date-only records appear after timed records within the same day, ordered by stable ID; they never acquire a fabricated displayed time. Do not use a localized title or current insertion order as a tie-breaker.

Changing an entry's date moves the existing event. It does not create a new event. A device time-zone change must follow the agreed shared policy and invalidate affected cursors/grouping when necessary.

### 5.3 Profile dates

`Training records since …` is derived from the earliest applicable saved workout source, including supported imports. It is not the account creation date and is not proof that the person first started lifting then.

`Started training …` appears only when explicitly entered by the user. Keep its provenance separate. An older imported workout can prompt a gentle review of a conflicting self-reported date, but must not silently overwrite it.

If there are no workout records, omit the records-since line. Notes or photos alone do not establish a lifting start date. While a history import/backfill is incomplete, show an accurate updating state rather than a final earliest date.

### 5.4 Consistent numbers and sparse data

Request metrics through the same descriptors used by Progress and History: period, eligibility, equipment scope, source revision, coverage, units, and precision. Identical metric scopes must reconcile; intentionally different scopes need labels. [B1, Section 4.2]

A hidden timeline item is still part of source-based metrics unless the user separately edits or deletes the source. Hiding is a presentation choice, not analysis exclusion.

Do not derive total workouts, training adherence, total volume, or personal bests from a paginated timeline. Empty/unknown values remain distinct from zero. No new streak, shame score, or return-from-break diagnosis is introduced.

---

## 6. Data model and service contracts

### 6.1 Architecture

```text
Existing domain records and shared eligibility/comparison services
             │
             ├── existing editors / logging / sync remain authoritative
             │
             ▼
     Read-only Journey projection adapters
             │
             ▼
   Rebuildable, owner-scoped, local-only index
             │
             ▼
   Batched source hydration + privacy-safe view models
             │
             ▼
       Progress → Timeline → existing source detail

New private source data only:
  optional profile overrides + reflections + visibility preferences

Publication only:
  explicit selection → separate allowed-field preview → existing share service
```

These are logical responsibilities. Reuse existing services and keep the number of new modules small. Do not introduce event-sourcing infrastructure, a new cloud database, or a separate analytics backend merely for this feature.

### 6.2 Stable event identity

Define one stable identity per canonical source/facet. For example:

```text
JourneyEventID = canonicalEncode(ownerNamespace, sourceKind, sourceID, facet)
```

The actual serialization must be unambiguous and versioned. Reuse existing stable identifiers. The ID must **not** contain a source revision, date, localized title, or random value generated during projection.

Edits change content/revisions while identity remains stable. An attached workout PR changes the parent's derived tags; it does not become a second workout identity.

Owner namespace must follow the existing local-account/account-merge policy. Do not casually use a changeable email address. Account linking and deduplication may need an alias from a superseded source ID to its canonical identity so visibility settings and deep links are reconciled correctly.

### 6.3 Proposed local index record

Use existing equivalents where available:

```text
JourneyIndexRecord
  eventID
  ownerNamespace
  sourceKind
  canonicalSourceID
  sourceFacet
  resolvedLocalDate
  occurredAt? / datePrecision
  sourceTimeZone? / datePolicyVersion
  categoryTags
  dependencyRevisionFingerprint
  projectionVersion
  indexGeneration
  privacyClass
  sourceAvailability
```

The index stores the minimum information needed for filtering, sorting, invalidation, and source lookup. It does **not** store full workout copies, journal text, raw change reasons, precise body values, photo bytes, raw Health data, or model prompts.

`dependencyRevisionFingerprint` covers all records/services needed for a card, such as the session, linked achievements, comparison-policy version, and source eligibility. It is not a probability or a cross-device lock. Do not send it to ordinary analytics.

The index must be in a verified **local-only** persistence boundary. Adding a property called `localOnly` to a record does not prove it is excluded from the existing sync exporter/store. Inspect and test the actual storage and payload paths.

### 6.4 New authoritative records

| Record | Required fields/behavior |
|---|---|
| Private profile extension | Optional private display-name override, private avatar reference if needed, explicit training-start date/provenance; reuse existing local profile where possible |
| `JourneyReflection` | Stable ID, owner, plain text, user-selected date, optional typed source reference, created/updated timestamps, revision, deletion/tombstone policy |
| `JourneyVisibilityOverride` | Stable event ID, hidden state, revision, owner, timestamps; independent of the rebuildable index |
| Local view preferences | Selected segment/filter, photo-preview preference, scroll anchors; per-device by default |
| Optional source alias | Canonical mapping for import/account reconciliation, only when the existing source system requires it |

Use existing revision, deletion, and sync mechanisms rather than creating incompatible replacements. Notes and private profile data are not automatically approved for cloud sync merely because ordinary workouts already sync. Explicitly register each new field under the existing opt-in/privacy model.

Hidden-item overrides can follow the existing permitted preference-sync policy. If two offline devices explicitly conflict on hidden/shown state, prefer hidden until the user resolves or explicitly restores it. Document this rule; do not confuse it with deleting the source.

### 6.5 View models

Produce immutable, owner-scoped card DTOs from current sources. Suggested variants:

```text
JourneyCard
  id / sourceRoute / displayDate / categoryTags / availability
  workout(approved summary, status, eligible milestone?)
  achievement(verified source details)
  programStart(versioned source summary)
  programChange(approved receipt summary, state, effective period)
  measurement(formatted current source values)
  photo(private asset reference, preview state)
  review(result state, measurement kind, limitations, source route)
  reflection(user-authored bounded preview, source-link state)
```

Do not send persistence-managed objects across concurrency boundaries unsafely. Use the repository's current persistence/concurrency pattern, batched reads, and value-type projections. No new framework behavior is assumed by these conceptual types.

### 6.6 Proposed interfaces

```text
JourneyRepository
  loadPage(query, cursor?) -> page | restartRequired | failure
  loadMonthCoverage(query) -> coverageWithCompleteness
  resolveEvent(eventID, owner) -> currentCard | unavailable
  rebuildIndex(owner, cancellation) -> progress/result

JourneyProjectionCoordinator
  handleCommittedSourceChange(sourceReference)
  reconcile(owner, scope, cancellation)

JourneyProfileService
  readPrivateProfile(owner)
  savePrivateProfile(reviewedChanges, expectedRevision)

JourneyReflectionService
  create(draft, requestID)
  update(id, changes, expectedRevision)
  delete(id, expectedRevision)

JourneyVisibilityService
  hide(eventID, expectedRevision)
  restore(eventID, expectedRevision)
  listHidden(owner, cursor?)

Existing share adapter
  prepareShare(eventID, selectedFields, audience) -> reviewedPreview
  confirmShare(previewID, boundSourceRevisions, requestID)
```

`expectedRevision` uses the actual repository conflict contract. The model cannot authorize these operations on the user's behalf. Ordinary UI note editing does not need a heavy training-change modal; consequential publication and source deletion do require appropriate explicit user action.

---

## 7. Projection, pagination, and lifecycle rules

### 7.1 Projection algorithm

```text
On a source-change notification or reconciliation:
  1. Resolve current owner and canonical source identity.
  2. Read current canonical source state, not the old notification payload.
  3. Resolve source eligibility, dependents, and current deletion/access state.
  4. Determine whether a Journey event currently belongs in the index.
  5. Upsert its stable index record or remove its derived index record.
  6. Invalidate dependent cards/tags/thumbnails and advance feed revision.
  7. Notify the visible UI without changing the source record.
```

Repeated or out-of-order notifications must converge on current source state. A stale "saved" notification cannot recreate a deleted workout. Source revision equality/fingerprints are not a substitute for the existing sync conflict resolver.

If a session's achievements change without the session itself changing, reproject the parent so its badge and filter membership remain correct.

### 7.2 Do not block set saving

A successful workout save must not depend on rebuilding Timeline. Observe source commits and schedule bounded work outside the immediate logging path.

A failed index write must leave the original save intact. Show index failure/retry where relevant; do not report that the workout failed when the authoritative save succeeded.

For the immediate post-save `View in timeline` action, hydrate the newly saved source directly or prioritize that event's indexing. Only show a saved card after the source transaction actually succeeds.

### 7.3 Initial history backfill

Build from local authoritative records in bounded batches, newest first. Keep existing History usable. Report index coverage honestly while backfilling; a partially populated index is not evidence that older records do not exist.

Persist a resumable progress marker only where it is reliable. Reconcile changes that occur during the build. A crash between a source save and its projection notification must be repairable by a later reconciliation, not leave a permanent missing event.

A replacement full index can be built under a new generation and swapped after validation. Do not restore deleted or hidden items during that swap. Hydration must still check current source existence and visibility.

### 7.4 Keyset pagination

Use bounded pages; a starting page size of **30 events** is a proposed tuning value, not a measured optimum. Avoid loading all workouts, all notes, or all full-size images into memory.

A cursor should bind to:

```text
owner namespace
query/filter fingerprint
resolved date-policy version
index generation + feed revision
last complete sort key
```

When relevant source changes invalidate a cursor, return `restartRequired` and refresh while preserving the nearest stable visible anchor. Do not silently combine incompatible generations. Coalesce rapid updates to avoid repeated jumping while someone is reading older entries.

Visibility and category conditions must apply before a page is considered full. When hydration discovers a deleted, hidden, or newly ineligible match, skip it and continue scanning within a bounded work budget. Return a continuation/loading state when the budget is reached, not a false end of history.

Do not use offset-only pagination where inserts/edits would create duplicate or skipped cards. Use the same tie-breaker in forward paging, month jumps, and source-date edits.

### 7.5 Lifecycle behavior

| Event | Required response |
|---|---|
| Workout edited | Same event ID; refresh summary, date, eligibility, and PR tags |
| Source deleted | Remove card; invalidate cached content/routes; respect source tombstones |
| Source hidden | Hide card and inline milestones only; retain source and metrics |
| Source restored to visibility | Show one current card; no new award, workout, or publication |
| Older history imported | Place on original source dates; update coverage/records-since; no import-time flood |
| Import deduplicates records | Use canonical source identity and existing alias rules; reconcile visibility deliberately |
| Photo deleted | Remove card and owned thumbnails/in-memory decoded assets promptly |
| Achievement invalidated | Remove badge/filter membership; retain truthful workout record |
| Review superseded | Show current valid status or source's explicitly historical/superseded state |
| Program change reversed | Retain source receipt context and actual status; do not rewrite the past |
| Two devices edit reflection | Use existing conflict resolution; preserve recoverable text instead of silent destructive overwrite |
| Account switched | Clear visible cards, cursors, note drafts, image buffers, and owner-scoped caches before rendering another owner |
| Index rebuilt | Same visible events, identity, hidden state, and source-based counts |

---

## 8. Profile, reflection, and visibility flows

### 8.1 Private profile editor

Reuse existing account/local-profile fields where their meaning and privacy match. Allow an optional display name, avatar, and explicit training-start date. No mandatory full name, birth date, sex, body weight, or social account is needed for Journey.

An already configured account avatar/name may be displayed as a fallback. Editing a private Journey identity must not silently change the public Crew identity. If the repository currently shares those fields, either add a private override or clearly route to a separately labeled public-profile editor; never promise private editing of a public field.

Select avatars through the existing user-mediated image-selection flow. Do not request access to the entire photo library merely to display a profile. Do not reuse a progress-body photo as an avatar automatically.

Handle save failure, duplicate submission, invalid/future training dates, long names, avatar removal, and offline edits. The header remains usable with no profile customization.

### 8.2 Reflection creation

```text
Timeline → Add note
  → optional date and optional source link
  → enter plain text
  → Save
  → persist once through the local source service
  → show one card at the chosen date
```

A note must contain non-whitespace text. Do not trim meaningful formatting beyond a documented normalization policy. Validate the same character/date constraints before persistence as in the editor.

Show unsaved changes before abandoning an edited note. Reuse existing draft recovery if available; protect owner isolation and do not transmit drafts in analytics. Cancellation must not create an empty timeline event.

After Save, show local persistence status accurately. Sync failure is distinct from local save failure. Repeated taps use an idempotent request ID or existing equivalent so they do not create duplicate reflections.

### 8.3 Linking notes to sources

Links are typed source references, not embedded copies of all source data. The user may link a reflection to a workout or supported review after explicitly choosing it.

If the linked source is deleted, preserve the independent reflection unless the user also deletes it. Remove cached linked titles/images and show a generic unavailable-link state. The user's own note text remains their content; do not silently rewrite it or infer that deleting a workout deletes every independent note mentioning it.

Account deletion removes both notes and other data according to the existing account-deletion policy.

### 8.4 Hide versus delete

| User action | Effect |
|---|---|
| `Hide from timeline` | Changes only Journey visibility; provide a local reversible acknowledgement |
| `Restore to timeline` | Shows the current source-derived entry again |
| `Edit record` | Opens the existing authoritative editor |
| `Delete workout/measurement/photo` | Uses the existing source-deletion flow and its consequences |
| `Delete note` | Deletes the actual reflection through its own explicit confirmation |

Do not put a generic `Delete` menu item on every card without identifying what will be deleted. Source deletion must not be confused with removing something from the feed.

Hidden entries belong in a separate management view reachable from Timeline options. The list reveals only the minimum current source summary needed to restore an item. Deleted sources are not restorable through this view.

---

## 9. Privacy and selective sharing

### 9.1 Boundary matrix

| Data | Private Journey | Ordinary cloud sync | Remote Coach / analytics | Public/Crew share |
|---|---|---|---|---|
| Existing workout data | Current permitted source projection | Existing opt-in/allowlist only | Existing approved context only; Journey adds no new access | Explicit eligible fields through existing preview |
| Private profile overrides | Yes | Only when specifically covered by existing consent/policy | No new inclusion | Never silently substituted into public identity |
| Reflections | Yes | Explicitly registered under existing permitted private sync | Excluded by default | Not supported in this release |
| Measurements | Yes, through existing source | Preserve existing approved storage/sync behavior | No new inclusion | Not supported from Journey |
| Progress photos | Existing viewer; hidden previews by default | Existing approved media policy only | No raw images or analysis | Not supported from Journey |
| Program-change details | Minimal private receipt projection | Existing approved training fields only | No raw private reasons from Journey | Not supported in this release |
| Health-derived reasons/inputs | Not a new standalone Journey category | Preserve on-device boundary | Excluded | Excluded |
| Journey index | Local-only, rebuildable | Excluded | Excluded | Excluded |
| View preferences | Device-local by default | Only explicitly permitted non-sensitive preferences | No raw settings/content dump | Excluded |

The previous roadmap already separates local/model/sync/analytics/public projections and preserves the Health-data boundary. Journey must use those boundaries, not serialize one universal "timeline event" object everywhere. [B1, Section 8.3]

### 9.2 Photo-preview behavior

Default to `hidePhotoPreviews = true` per device. A concealed card has no loaded thumbnail pixels behind an opaque overlay; avoid decoding the image until an allowed reveal/view action needs it.

`Reveal once` is an explicit temporary view state. Clear it when leaving the relevant view, switching accounts, or returning from background. Enabling previews is a separate persistent local preference with plain-language explanation.

Use the current approved image cache/storage service, bounded thumbnail sizes, and cache invalidation on photo deletion. Verify ownership of app-generated thumbnails and deletion behavior. Do not persist decoded images in generic event caches, logs, or crash attachments.

Use the existing app privacy-cover pattern for sensitive screens during background transitions where supported. Do not claim this prevents screenshots, screen recordings, or every OS-level copy.

### 9.3 Sharing flow

Initial Journey sharing scope is **eligible workout summaries and verified milestones only**. Body data, reflections, applied-change reasons, and reviews remain private from this feature.

```text
Card → Share
  → read current source and eligibility
  → select existing supported audience
  → choose allowed fields
  → show exact outgoing preview
  → confirm the preview and source revisions
  → publish through existing sharing service
  → show actual success / pending / failure state
```

Reuse existing Crew identity, authentication, and entitlement rules. A signed-out user may continue private training and Journey browsing; only actions requiring Crew identity use the current sign-in flow.

Build the share from a separate allowlisted DTO, never from a screenshot of the entire private timeline or serialization of the complete card. In particular, do not leak hidden body values, private nicknames, local gym identifiers, equipment notes, exact location, reflection text, or hidden metadata into share assets.

Default to the least revealing supported fields. Let the existing sharing feature handle deliberate opt-in to additional workout fields. Verify the actual rendered/exported asset, not only its visible on-screen preview.

At confirm, recheck source revisions, ownership, eligibility, and audience. A changed source or audience invalidates the preview. Retries must not create duplicate posts.

### 9.4 Existing posts versus source edits/deletion

A Journey hide action never deletes a Crew post. A source edit also must not silently change a post someone already approved.

Follow the existing publication lifecycle and disclose whether a share is a snapshot. Link to the existing manage/delete-post flow where available. During source deletion, explain separately whether published copies remain and how existing app-controlled posts can be removed.

Do not promise to erase downloaded, screenshotted, or externally shared copies. Any existing in-app post deletion must use the authorized publication record, not guess from the source ID.

### 9.5 Security controls

Resolve owner and permissions at query, route, edit, and share boundaries. Scope note drafts, caches, cursors, and indexes by owner. Treat stored free text as data, not instructions or markup.

No timeline data enters a model prompt merely because the Coach screen opens. Do not add broad "read entire journey" or generic write tools in this feature. Keep user text and private field values out of production logs and ordinary telemetry.

---

## 10. Visual design, accessibility, and copy

### 10.1 Design direction

Preserve ReguLift's current visual identity and existing shared components. The reference image is inspiration for date grouping and personal records, not a request to copy its purple marketing background or pet-app imagery.

Use the existing page/card/type tokens, restrained separators, and functional icons. Prefer concise text and real user content over stock gym photos. Reuse current light and dark variants.

Proposed project targets, to be validated in native builds:

| Element | Requirement |
|---|---|
| Hit areas | At least the project's 44 × 44 pt minimum; larger where existing primary actions require it |
| Typography | Scalable semantic styles; no fixed-height card that clips expanded text |
| Layout | One column; collapse the date rail at narrow/large-text sizes |
| Card hierarchy | Date, event title/status, one useful detail, source action |
| Color | Supplement status text/icons; never the sole indication of privacy or success |
| Photo area | Optional, bounded, no mandatory image download for scrolling |
| Long labels | Wrap naturally; do not split ordinary words into fragments |
| Loading | Stable placeholders without fake measurements or false completed-work counts |
| Motion | Respect reduced motion; no forced confetti or scroll-jumping celebrations |

These continue the audit's proposed design system rather than introducing another UI kit. [B1, Sections 5.1–5.4]

### 10.2 Accessibility requirements

Group a card's summary meaningfully for the screen reader, with separate accessible actions for opening, editing, hiding, or sharing. Read date, status, exercise, load convention, and units accurately; skip decorative rail elements.

Announce selected filters and hidden-photo state. Do not read sensitive photo descriptions automatically while previews are concealed. All actions need visible alternatives to swipe, long press, sound, or color alone.

Test the largest supported text sizes, keyboard navigation where supported, VoiceOver, reduced motion, increased contrast, and light/dark modes. No sticky filter/header may cover the last actionable card.

### 10.3 Localization

Use the app's existing localized strings, plural rules, unit formatters, decimal handling, and date service. Do not compose sentences from fragments whose word order changes between languages.

Test English, Japanese, Vietnamese, and a deliberately expanded pseudo-locale as design fixtures; only ship locales the app actually supports. Add right-to-left testing when it is part of the supported matrix. Keep user-entered names/notes intact.

### 10.4 Proposed microcopy

| Situation | Copy |
|---|---|
| Header derived date | `Training records since {month year}` |
| Explicit self-reported date | `Started training {month year}` |
| Saved partial | `Saved partial workout` |
| Calculation limitation | `Saved in your history. Some calculations exclude this session.` |
| Body photo | `Private photo · Preview hidden` |
| Hide item | `Hidden from your timeline. The original record is unchanged.` |
| Restore item | `Restored to your timeline.` |
| Missing linked source | `The linked record is no longer available.` |
| Program change pending effective date | `Change scheduled for {period}` |
| Change review limitation | `These results are not directly comparable.` |
| Experiment review | `Inconclusive — view the recorded limitations.` |
| No notes | `Add a note about something you want to remember.` |
| Local save with sync issue | `Saved on this device. Sync will retry.` |
| Stale share preview | `This record changed. Review the updated share before posting.` |

Only display statements that match actual source, sync, and policy state. Do not say `Private` as a substitute for implementing the stated data boundary.

---

## 11. Persistence, offline operation, and compatibility

### 11.1 Migration and storage

Keep the current SwiftData/offline-first architecture and its existing migration strategy. Map proposed entities to actual models before adding schemas. Do not assume every new model is excluded from sync automatically.

Prefer additive changes. Test real persisted stores from supported older app versions. Do not reset the user's source store after a Journey migration/index failure or attempt a destructive downgrade to roll back the feature. The prior audit already requires forward-compatible migration and source preservation. [B1, Sections 8.4–8.5]

A corrupt derived index can be discarded and rebuilt. Reflections, private profile overrides, and visibility settings are user data and must not be discarded with that index.

### 11.2 Offline behavior

Browsing locally available entries, viewing locally available source details, adding/editing notes, hiding/restoring items, and editing a local private profile must not require a new network dependency.

Handle unavailable synced media explicitly. No automatic cloud fallback that changes photo or Health privacy is introduced. Crew publication can require connectivity under its existing policy, but never block source saving or private browsing.

On foreground, reconcile recent source changes and incomplete builds. Background processing is an optimization, not the only path to correctness. Keep reconciliation cancellable and bound its work.

### 11.3 Sync and conflicts

Sync authoritative source changes through the existing allowed transport. Rebuild each device's index locally; do not synchronize index rows.

For reflections, use the existing conflict/version model and preserve both recoverable texts when automatic merging would lose intent. For source-linked privacy visibility, the specified hidden-first conflict rule prevents an offline device from accidentally resurfacing a hidden item.

Account linking/import deduplication must preserve canonical source identity, independent journal ownership, and the proper visibility overrides. Old clients must not erase new fields through partial writes. Unsupported fields/events fail safely without corrupting existing data.

### 11.4 Feature flags and entitlements

Use separate flags, or existing equivalent controls, for the main Journey surface, reflections/private profile editing, advanced change/review adapters, and share entry points. Flags are not billing policy.

Turning the main surface off must preserve existing History and all underlying sources. Provide a read/edit/delete/export management route for already-created reflections and private profile data even when the main feed is disabled. Preserve hidden preferences for later re-enable.

Use current paid/trial entitlements and existing access-expiry behavior. Do not place private history retrieval or data deletion behind a newly invented entitlement. If write access is restricted by existing product policy, display that clearly without destroying saved data.

### 11.5 Initial engineering budgets

These are proposed engineering targets, **not measurements or promises**. Benchmark on the oldest practical supported device with a synthetic production-sized store before freezing them.

| Path | Starting budget |
|---|---|
| First warm page of 30 local text cards | p95 under 500 ms |
| Warm filter/month query | p95 under 500 ms |
| Local source edit reflected in visible feed | Usually within 1 second after commit, with explicit updating state otherwise |
| History fixture | At least 10,000 mixed events without loading all content or full-size images at once |
| Workout save | No new synchronous full-history scan or dependency on timeline index success |
| Rebuild | Bounded batches, progress, cancellation, resumability/reconciliation; no main-thread freeze |
| Image memory | A bounded visible/nearby thumbnail cache; profile and measure actual limits |

If a target is not met, document the measured result and the mitigation. Do not claim performance from an unprofiled simulator screenshot.

---

## 12. Implementation milestones and task checklist

There are **54 implementation tasks across eight milestones**. Each checkbox starts unchecked. A task is complete only when its behavior is connected to real sources and its acceptance evidence is recorded.

Tests, accessibility, privacy checks, and compatibility apply in every milestone. J6 is the integrated hardening gate, not permission to postpone correctness until the end.

### 12.1 Release sequence

| Milestone | Deliverable | Required exit gate |
|---|---|---|
| J0 | Repository map, agreed semantics, privacy model, baseline fixtures | No unresolved source ownership/date/eligibility conflict in the core slice |
| J1 | Local projection, stable IDs, hydration, bounded querying | Edit/delete/rebuild/import fixtures produce the same correct private events |
| J2 | Progress shell and usable core timeline | User can find/open an old workout and body record without losing navigation context |
| J3 | Private profile, reflections, hiding/restoring | New user data persists safely; hiding never changes history or statistics |
| J4 | Program-change and review integrations | Every enabled advanced card is backed by a real source and truthful status |
| J5 | Privacy-complete selective sharing | No unauthorized fields or unintended publication; existing sharing controls respected |
| J6 | Migration, multi-device, performance, accessibility, deletion hardening | Required regression suite and physical-device checks pass |
| J7 | Usability validation, measurement, staged rollout, handoff | Release evidence, rollback path, and support documentation complete |

After J2, the basic private timeline can enter internal testing. Broad release requires the relevant J5/J6/J7 gates. Advanced adapters may be staged separately only when the unavailable capability is documented and not described as shipped.

### 12.2 J0 — Foundations

- [ ] **TJ-FND-01 — Map the real repository.** Locate Progress navigation, History, saved sessions, aggregate/eligibility/PR services, Body/media storage, program receipts, goals/reviews, Crew, local identity, SwiftData, sync, entitlements, and tests. Produce a path-and-owner map; do not create guessed duplicate services.
- [ ] **TJ-FND-02 — Record dependency status.** Map Section 2.2 to implemented/partial/missing code and the earlier audit task families. Identify correctness fixes that block this release. Record evidence for every claimed existing capability.
- [ ] **TJ-FND-03 — Agree dates and metrics.** Reconcile Timeline with shared History date semantics, date-only records, imports, partial completion, and eligibility. Add fixtures and document the chosen policy before building the feed.
- [ ] **TJ-FND-04 — Establish privacy and identity boundaries.** Document local-only index storage, private versus public profile fields, note sync policy, owner namespace, photo visibility, and permitted share fields. Verify actual exporters/stores, not labels alone.
- [ ] **TJ-FND-05 — Add baseline fixtures and flags.** Capture current source counts/formatting/navigation and create deterministic synthetic records for normal, partial, flagged, imported, and deleted sources. Add disabled exposure flags without changing billing.
- [ ] **TJ-FND-06 — Confirm UI routes and component reuse.** Map the proposed screen specification to real components and canonical source routes. Capture a baseline of first-viewport hierarchy and accessibility behavior.

**J0 acceptance:** The implementation note identifies real files, owners, commands, date policy, privacy projections, and blocked integrations. Current logging and Progress behavior still pass the baseline suite.

### 12.3 J1 — Projection and querying

- [ ] **TJ-DAT-01 — Implement stable identities.** Add canonical owner/source/facet IDs and alias handling where required. Verify edits, imports, app restarts, and locale changes do not create new event IDs.
- [ ] **TJ-DAT-02 — Implement the local index boundary.** Add minimal rebuildable index records using the existing persistence architecture. Assert their absence from sync/model/public/analytics payloads.
- [ ] **TJ-DAT-03 — Build core source adapters.** Project saved workouts, eligible achievements, measurements, and photos from existing sources. Group PRs into parent workouts and preserve partial/flagged record visibility.
- [ ] **TJ-DAT-04 — Implement batched hydration.** Resolve current source state, shared metric formatters, eligibility, comparison scope, source routes, and photo placeholders into immutable DTOs. Never render source text or image bytes from a stale generic cache.
- [ ] **TJ-DAT-05 — Implement incremental invalidation.** Observe committed source changes, re-read canonical records, and invalidate dependent badges/tags. Verify repeated and out-of-order signals cannot resurrect deleted records.
- [ ] **TJ-DAT-06 — Implement backfill and reconciliation.** Add bounded resumable history indexing, coverage reporting, lost-notification repair, and safe full rebuild. Keep workout saving independent of index success.
- [ ] **TJ-DAT-07 — Implement pages and month queries.** Add owner/query/revision-bound keyset cursors, OR filters, hidden-item exclusion, bounded hydration refill, and deterministic date-only tie-breaking.
- [ ] **TJ-DAT-08 — Add projection contract tests.** Test identity, source edits, source deletion, PR invalidation, paging during updates, import dates, and rebuild equivalence. Include injected index failure after a successful workout save.

**J1 acceptance:** A canonical source maps to one correct visible event/facet. Rebuilds preserve hidden state and user-authored data. Query failure cannot delete or invalidate the actual workout.

### 12.4 J2 — Core timeline UI

- [ ] **TJ-UI-01 — Extend the Progress shell.** Add the compact header and Overview/Timeline switch, preserving the existing Overview, tools, History route, and top-level tabs.
- [ ] **TJ-UI-02 — Build timeline grouping and cards.** Implement date groups, one-column cards, explicit source status, optional featured result, and responsive layouts. Keep decorative date rails nonessential.
- [ ] **TJ-UI-03 — Render truthful core states.** Display normal/partial/flagged workouts, eligible inline PRs, exact measurement values, and private photo placeholders using the existing source semantics.
- [ ] **TJ-UI-04 — Add filters and month navigation.** Implement the filter sheet, OR behavior, reset, coverage-aware month jump, and explicit no-match states. Verify a multi-tag workout appears once.
- [ ] **TJ-UI-05 — Connect canonical source routes.** Open original source details, handle unavailable sources, and restore filter/month/scroll anchors on return. Do not create a second workout editor.
- [ ] **TJ-UI-06 — Add photo discretion controls.** Default to concealed previews, implement reveal-once and a separate persistent local setting, and clear temporary reveals on view exit/background/account switch.
- [ ] **TJ-UI-07 — Add contextual entry points.** Connect successful workout receipts and suitable chart points to the correct timeline item or filtered period. Never link an aggregate point to a guessed record.
- [ ] **TJ-UI-08 — Complete UI states and tests.** Cover new-user, indexing, no-match, offline, unavailable source/media, error/retry, large text, and screen-reader flows. Keep History accessible in degraded states.

**J2 acceptance:** A user can locate a past workout, understand its saved/eligible status, open its original detail, and return to the same location. Concealed photos are not decoded merely to appear behind an overlay.

### 12.5 J3 — Private ownership features

- [ ] **TJ-OWN-01 — Implement the private header/editor.** Reuse or extend the local profile; support optional name/avatar and an explicit training-start date. Keep public Crew identity edits separate and display records-since honestly.
- [ ] **TJ-OWN-02 — Implement reflection storage and validation.** Add versioned source records, local persistence, allowed sync projection, nonblank/Unicode/length/date validation, and idempotent creation.
- [ ] **TJ-OWN-03 — Implement reflection editor and cards.** Add standalone/linked notes, save/failure feedback, edit/delete, unsaved-change handling, and bounded previews. Cancellation cannot create blank records.
- [ ] **TJ-OWN-04 — Implement linked-source lifecycle.** Keep independent notes when a linked source is deleted, remove cached linked metadata, and show a generic unavailable link. Test owner isolation and current source resolution.
- [ ] **TJ-OWN-05 — Implement hide/restore management.** Persist visibility separately from the index, provide reversible hiding and a Hidden items view, and distinguish source deletion. All filters must respect hidden state.
- [ ] **TJ-OWN-06 — Verify ownership/conflict behavior.** Test private/public profile separation, offline duplicate saves, concurrent note edits, hidden-first visibility conflicts, account linking, and feature-off data access.

**J3 acceptance:** Notes and private profile fields survive app restart and permitted sync without public exposure. Hiding a workout changes neither source counts nor PR calculations. No independent journal text is lost during an index rebuild.

### 12.6 J4 — Training context and review integrations

- [ ] **TJ-CTX-01 — Add reliable program/block start adapters.** Use actual activation/enrollment events and version references. Do not reconstruct unsupported historical starts from the current program.
- [ ] **TJ-CTX-02 — Add meaningful committed-change cards.** Map actual action receipts through a versioned display policy. Include authorization scope, before/after, effective period, and scheduled/applied/reverted status.
- [ ] **TJ-CTX-03 — Integrate approved evidence details.** Link to existing reason/outcome surfaces using privacy-aware projections. Keep raw Health reasons out of remote/public paths and avoid causal success wording.
- [ ] **TJ-CTX-04 — Add goal review cards.** Use real review/benchmark records, measured-versus-estimated labels, comparability, and superseded/invalidated-result handling.
- [ ] **TJ-CTX-05 — Add experiment review cards.** Surface actual completed/inconclusive reviews and their source limitations. Do not display creation-time zero change as a completed result.
- [ ] **TJ-CTX-06 — Test and document integration coverage.** Exercise missing receipts, future-effective changes, reversals, edited evidence, and disabled source features. Mark unimplemented adapters blocked, not complete; keep the core timeline usable.

**J4 acceptance:** Every enabled change/review card resolves to a real committed source and truthful status. No recommendation becomes an applied-change event merely because a model or UI suggested it.

### 12.7 J5 — Privacy and sharing

- [ ] **TJ-PRV-01 — Audit all projections.** Test local index, sync, model, analytics, diagnostics, and public serializers with sensitive sentinel values. Forbidden values must be absent from actual outgoing payloads.
- [ ] **TJ-PRV-02 — Verify photo/identity privacy lifecycle.** Test concealed previews, thumbnail creation/deletion, avatar selection/removal, background transitions, owner switches, and per-device privacy defaults.
- [ ] **TJ-PRV-03 — Implement the existing-share adapter.** Allow only eligible workout/milestone publication through the current Crew/share services. Add no automatic publication on save, import, milestone creation, or note creation.
- [ ] **TJ-PRV-04 — Bind and validate previews.** Generate separate allowlisted DTOs/assets, show the exact audience/fields, and recheck source revisions/eligibility at confirm. Reject stale previews and deduplicate retries.
- [ ] **TJ-PRV-05 — Connect publication management.** Reuse current manage/delete-post behavior. Explain that hide, source edits, source deletion, and publication deletion are different operations; avoid false external-copy erasure promises.
- [ ] **TJ-PRV-06 — Test sharing failure and access cases.** Cover signed-out, no Crew, revoked access, offline, source deletion, account switch, duplicate request, and forbidden-field injection without blocking private logging.

**J5 acceptance:** No private Journey object is directly serialized or screenshotted into a share. Every new publication has explicit valid authorization; ordinary saving, indexing, and browsing publish nothing.

### 12.8 J6 — Integrated hardening

- [ ] **TJ-QA-01 — Test persisted migrations and rebuild recovery.** Use supported older stores, interrupted migrations/backfills, corrupted index, low storage, and retry. Verify source records and notes remain intact.
- [ ] **TJ-QA-02 — Test offline and sync ordering.** Cover disconnected devices, repeated/out-of-order events, unavailable media, stale edits, hidden-first conflicts, and old-client field preservation.
- [ ] **TJ-QA-03 — Test account and namespace isolation.** Switch owners while pages, media, editors, and share previews are active. Verify no prior-owner content survives in visible state or executable actions.
- [ ] **TJ-QA-04 — Test all deletion paths.** Cover workout, photo, measurement, achievement, reflection, linked source, profile avatar, and account deletion; verify index, thumbnails, caches, references, and sync tombstones.
- [ ] **TJ-QA-05 — Profile performance and cancellation.** Use the mixed 10,000-event fixture; measure page queries, scrolling, image memory, source-change refresh, backfill, and workout-save impact. Record real device results.
- [ ] **TJ-QA-06 — Validate accessibility and localization.** Run screen-reader, largest text, narrow layout, long names/notes, units, dates, long translations, reduced motion, contrast, and supported right-to-left checks.
- [ ] **TJ-QA-07 — Test feature flags and entitlement transitions.** Disable features after data exists; expire/restore current access; interrupt publication. Preserve history, active workout saving, and note/profile data controls.
- [ ] **TJ-QA-08 — Execute the complete regression matrix.** Record fixture IDs from Section 13, test commands, actual outcomes, remaining defects, and physical-device checks. No privacy/data-loss defect is an acceptable known release issue.

**J6 acceptance:** The release candidate passes the required integrated fixtures. Measured results and limitations are documented; simulator-only work is not reported as physical-device validation.

### 12.9 J7 — Validation and release

- [ ] **TJ-REL-01 — Add consent-aware measurement.** Register only the allowed coarse events in Section 14; exclude content and sensitive categories. Verify offline deduplication, opt-out, and deletion behavior.
- [ ] **TJ-REL-02 — Run task-based usability checks.** Ask testers to find/edit an old workout, interpret a partial session, hide/restore a card, add a private note, and safely share an eligible result. Fix repeated confusion before broad rollout.
- [ ] **TJ-REL-03 — Prepare staged flags and rollback.** Start internally, then use an opt-in cohort, then expand after the gates pass. Exercise rollback after real notes, hidden entries, and posts exist.
- [ ] **TJ-REL-04 — Update truthful product/support copy.** Explain Overview versus Timeline, privacy defaults, hiding versus deletion, source corrections, and actual advanced-event coverage. Do not advertise adapters that remain blocked.
- [ ] **TJ-REL-05 — Verify production readiness.** Check privacy copy against actual behavior, current entitlement handling, support access, diagnostics minimization, and release evidence. No new price or permanent free tier is part of this task.
- [ ] **TJ-REL-06 — Deliver the final engineering handoff.** Record changed files, models/migrations, source adapters, flags, tests, measurements, supported limitations, operational recovery, and all task statuses.

**J7 acceptance:** The shipped scope is explicit; users retain control of their data; the team can disable new exposure without losing source history or reflections.

### 12.10 Parallel work

After J0 contracts are agreed, projection tests, UI components against synthetic DTOs, and reflection editor work can proceed in parallel. A UI-only prototype does not count as a finished integration.

Keep one owner for stable IDs, date semantics, privacy DTOs, and schema changes. Do not let separate branches invent conflicting source references or public/private identity rules. Run integrated source/edit/delete tests before merging parallel vertical slices.

---

## 13. Required regression fixtures

Use synthetic data only by default. Freeze clocks, owner identities, policy versions, and ordering inputs. Keep these tests connected to the existing source services rather than testing only hardcoded UI arrays.

| ID | Scenario | Expected result |
|---|---|---|
| TJ-T01 | No workouts, notes, or body records | Honest new-user state; no fake milestones, dates, or zero trend |
| TJ-T02 | First saved normal workout | One card with canonical source values; direct original-detail route |
| TJ-T03 | Partial and calculation-ineligible saved workouts | Both remain private history; completion and named eligibility are not conflated |
| TJ-T04 | Draft workout and discarded empty session | No saved-workout event is fabricated |
| TJ-T05 | Three PRs attached to one workout | One parent card; eligible inline summary; one result in combined filters |
| TJ-T06 | Edit load/date so a PR is invalidated | Same workout identity; corrected date/value; badge and filter membership update |
| TJ-T07 | Two machines with identical displayed loads | No cross-equipment PR or comparison is invented |
| TJ-T08 | Multiple records with equal/date-only timestamps | Stable order across paging, restart, rebuild, and locale changes |
| TJ-T09 | Import old workouts and rerun the import | Original training dates; importer/canonical-ID deduplication; no import-time event flood |
| TJ-T10 | Insert/edit/delete sources while loading later pages | Cursor restarts safely; no duplicates, skipped permanent records, or lost anchor crash |
| TJ-T11 | Filter union plus hidden parent workout | One card per event; hidden PR parent does not reappear through Milestones |
| TJ-T12 | Month with no matches during incomplete backfill | Correct no-match versus still-indexing states; older History remains available |
| TJ-T13 | Known-zone travel, midnight, daylight-saving, and date-only records | Agreed shared date policy applied consistently in History, Timeline, and month navigation |
| TJ-T14 | Exact decimal body value and a single measurement | Stored precision preserved; no fabricated trend or value judgment |
| TJ-T15 | Hidden photo, reveal once, leave/background/reopen | No hidden thumbnail decode before reveal; temporary reveal cleared appropriately |
| TJ-T16 | Photo deleted while decoded/cached/viewed | Owned thumbnail buffers/caches invalidated; no ghost preview or stale source route |
| TJ-T17 | Duplicate/refused/offline reflection save | One persisted valid note, or honest failure; no empty/cancelled event |
| TJ-T18 | Unicode note, long text, blank text, future date | Consistent validation; no corruption, clipping, or invalid source entry |
| TJ-T19 | Delete a workout linked from an independent note | Note remains; deleted source metadata disappears; generic unavailable link |
| TJ-T20 | Hidden entry followed by source edit/index rebuild | Remains hidden; source metrics remain unchanged |
| TJ-T21 | Explicit training-start date versus earlier imported record | Distinct provenance; no silent rewriting of self-reported start date |
| TJ-T22 | Public Crew identity plus private Journey nickname/avatar edit | No silent public change or private-field publication |
| TJ-T23 | Program suggestion, confirmed future change, active change, reversal | Only real committed events; truthful scheduled/applied/reverted states and version links |
| TJ-T24 | Missing historical change receipts | No reconstructed or fabricated past Coach actions |
| TJ-T25 | New experiment, inconclusive review, incompatible goal result | No creation-time success; actual review limitations and comparability preserved |
| TJ-T26 | Correct/delete evidence after a goal or experiment review | Current success claim invalidated/superseded through source rules |
| TJ-T27 | Cancel/stale/repeated share confirmation | No unintended or duplicate publication; changed source requires updated preview |
| TJ-T28 | Inject private notes/body/Health/gym data into share candidate | Allowlist excludes it from actual outbound DTO and rendered asset |
| TJ-T29 | Hide/delete source with a previously published snapshot | Separate operations explained; existing publication management used accurately |
| TJ-T30 | Index corruption, partial migration, low storage, lost notification | Sources preserved; repair/reconciliation works; no silent empty-store reset |
| TJ-T31 | Two offline devices edit note and visibility; old client syncs | Recoverable note intent; hidden-first conflict rule; no deletion resurrection/field loss |
| TJ-T32 | Switch accounts with pending page, image, note edit, and share | No cross-owner content or action; old callbacks invalidated |
| TJ-T33 | Disable feature or change entitlement after user data exists | History and note/profile data controls remain; active workout save unaffected |
| TJ-T34 | 10,000 mixed events and rapid filter/month changes | Bounded reads, image memory, and cancellable work; no full-history UI freeze |
| TJ-T35 | Largest text, VoiceOver, long translations, light/dark, reduced motion | Readable cards, usable controls, correct focus, no obscured actions |
| TJ-T36 | Analytics opt-out, source deletion, logging errors, and diagnostics | No raw source content or hidden sensitive values in telemetry; consent/deletion respected |

Add unit tests for projection policies and view-model formatting, integration tests for real persistence/source changes, UI tests for navigation/privacy flows, and physical-device tests for lifecycle/accessibility/performance. The precise tools/commands come from the real repository.

---

## 14. Measurement and usability validation

### 14.1 Questions to evaluate

The initial success test is usefulness, not the number of feed opens. Determine whether users can find a prior record, interpret its status, understand a program change, and preserve the intended privacy.

Use task-based checks with realistic synthetic history. Include a new lifter, an experienced importer, a user returning after a break, and a user browsing with large text where practical. This is a proposed research sample strategy, not a claim that testing has happened.

### 14.2 Allowed event examples

Use the existing analytics/consent system. Proposed events:

| Event | Permitted example properties |
|---|---|
| `journey_opened` | Entry-point enum, app/feature version, coarse index-availability state |
| `journey_source_opened` | Entry-point enum and success/unavailable status; no record ID or private content |
| `journey_query_completed` | Latency bucket, result-count bucket, failure class; not exact source dates |
| `journey_note_saved` | New/edit operation and success/failure; no text, date, linkage, or content length |
| `journey_visibility_changed` | Hide/restore and success/failure; no source ID or sensitive category |
| `journey_share_completed` | Allowed share type, success/failure, existing coarse audience class |
| `journey_index_reconciled` | Duration/count buckets, projection version, coarse error class |

Treat these as candidates for privacy review, not automatically safe just because they are enums. Omit events/properties that the current consent or data boundary does not permit. Keep body/Health categories, note text, exact loads, private dates, images, gym names, source IDs, and raw action reasons out of ordinary analytics.

### 14.3 Metric definitions

| Measure | Definition/use |
|---|---|
| Find-a-record task success | Testers who reach the specified original record without help / testers attempting that task |
| Meaning comprehension | Testers correctly distinguishing saved partial work from completed/eligible work in the fixture |
| Hide-versus-delete comprehension | Testers correctly predicting the effect before acting |
| Source-route reliability | Successful permitted source opens / attempts, with deleted/not-yet-synced sources reported separately |
| Duplicate/missing-event defects | Reproducible source-to-feed mismatches in fixtures or approved minimized diagnostics |
| Query responsiveness | Measured local page/filter latency distributions under documented fixture/device conditions |
| Retained training | Existing four-week training-retention definition, only with fully observed cohorts and recorded feature exposure |

Do not infer satisfaction solely from time spent scrolling, assume all nonuse is failure, or claim a retention improvement without suitable data. Opening a body photo or writing a private note is not an appropriate monetization signal by default.

Fix metric definitions before evaluating the release. Do not retrospectively change workout completion rules to make Journey appear more effective.

---

## 15. Release gates and definition of done

### 15.1 Release-blocking failures

Do not broadly release with a known source-data-loss defect, cross-owner leak, unauthorized publication, concealed-photo leak, incorrect milestone caused by the timeline, or a hidden-item preference that is silently ignored.

A timeline mismatch is not repaired by changing valid source data to fit the feed. Fix the projection/query/formatting policy or explain the source's real semantics.

### 15.2 Staged exposure

Start with internal builds and deterministic fixtures. Move to an opt-in cohort after core privacy, source correctness, and source-edit tests pass. Expand only after required device checks, usability findings, and rollback drills are addressed.

During a rollback, disable new entry/publication or the affected adapter rather than deleting source records. Preserve notes and user data controls. Rebuildable-index recovery must be clearly separate from a source-store migration.

### 15.3 Definition of done

A milestone is done when its data flow, source-backed UI, edit/delete behavior, offline state, permission boundaries, supported accessibility/localization, tests, and feature-off behavior are demonstrated.

The complete Journey scope is done when:

- The core private timeline, compact profile, reflections, filters/month navigation, visibility controls, and supported source routes work end to end.
- Enabled program/review integrations use real sources; any still-blocked integrations are explicitly labeled as outside the shipped subset rather than silently counted as complete.
- Share preview, publication, photo privacy, data deletion, migration, multi-device conflict, and owner-isolation tests pass.
- Actual commands/results, device checks, measurements, limitations, flags, and recovery instructions are recorded in the handoff.

No task is complete merely because a model type, mock screen, unchecked test file, or screenshot exists.

---

## 16. Coding-agent execution instructions

Copy the following block into the coding agent with this Markdown file and repository access:

```text
Implement ReguLift's My Training Journey according to this document.

Start with J0 and task TJ-FND-01. Inspect the actual repository before writing
code. Report the real paths, source models, existing services, test commands,
and dependency status. Do not assume proposed names in this plan already exist.

Scope: a private compact profile and timeline inside existing Progress, with
source-linked workouts/body/milestones, optional reflections, filters/month
navigation, meaningful committed-change/review cards, hiding/restoring, and
explicit eligible sharing through the existing Crew/share service.

Do not build another bottom tab, workout database, PR calculator, social feed,
public profile, image-analysis pipeline, AI journal, or new payment tier.
Do not implement the entire prior eight-feature roadmap as a side effect.
Use adapters for its real sources and report unimplemented dependencies.

Reuse existing metrics, completion/eligibility rules, date services, canonical
source routes, action confirmations, SwiftData patterns, sync, identity,
privacy projections, media storage, entitlements, and accessibility components.

Preserve stable event IDs, original source meaning, partial saved history,
source-based statistics, and comparison/PR validity. Hiding a card must not
change history or metrics. A cache rebuild must not erase notes/preferences.
Never generate missing historical actions or infer causality from a timeline.

Default Journey to private and body-photo previews to concealed. Keep the
index local-only in the actual transport/storage configuration. No new notes,
photos, Health-derived reasons, or private identity fields may enter model,
analytics, diagnostics, or public payloads without the document's explicit
allowed boundary. Saving or importing must not publish anything.

Implement one complete vertical slice or task group per pull request. Include
schema/migration work only when required and compatibility-tested. Keep core
workout saving independent from index work. Test edits, deletions, lost and
out-of-order notifications, owner changes, paging, and feature rollback.

Use synthetic fixtures. Run the repository's real available build/test/lint
commands and report only commands actually run, their exit results, and any
untested device cases. Do not equate a simulator run with physical-device QA.
Do not mark a blocked adapter or mock screen complete.

After each task group report:
- Task IDs completed and acceptance evidence.
- Files changed and existing components reused.
- Models/migrations, privacy projections, and compatibility impact.
- Commands run with actual results.
- Remaining risks, blocked dependencies, and the next unblocked task.

Do not introduce a new vendor, paid service, database, minimum OS requirement,
broad dependency, or changed pricing without a separate explicit decision.
Stop for a concrete source/privacy/schema conflict that cannot be resolved
from the repository; report the specific conflict rather than inventing data.
```

### First pull request

Complete TJ-FND-01 through TJ-FND-06 as repository-backed findings, fixtures, and disabled flags. Then implement the smallest J1/J2 workout-only slice with stable identity, original-detail navigation, and an edit/delete test.

Do not begin by adding a decorative profile screen disconnected from the actual workout lifecycle.

---

## 17. Pull-request handoff template

```markdown
## Scope
Task IDs:
User outcome:
Existing components/services reused:
Enabled event sources:
Blocked source integrations:

## Data and contracts
Canonical source(s):
Stable identity and date policy:
Source/eligibility/PR dependencies:
New authoritative user data:
Derived/cache-only data:
Migration and older-client behavior:

## User experience
Entry points and source routes:
Loading/empty/offline/failure states:
Accessibility/localization checks:
Hide versus delete behavior:
Navigation/scroll restoration:

## Privacy and compatibility
Actual local-only/sync projections checked:
Photo/private-profile behavior:
Public/share DTO and asset inspection:
Owner-switch and stale-action handling:
Feature-off and entitlement behavior:
Deletion/cache/tombstone behavior:

## Evidence
Test fixture IDs:
Build/test/lint commands actually run:
Actual results and failures:
Physical-device checks:
Performance measurements and fixture size:
Screenshots or recordings of implemented states:

## Release
Feature flags:
Known limitations:
Recovery/rollback instructions:
Next unblocked task:
```

---

## 18. Source basis and verification boundaries

### B1 — Existing video audit and implementation plan

`REGULIFT_VIDEO_AUDIT_AND_IMPLEMENTATION_PLAN.md`, supplied in this conversation, is the integration baseline. Relevant sections are 4 (correctness/metric semantics), 5 (design/navigation), 6.7–6.11 (Progress, body, reviews, Crew), and 8 (architecture, privacy, migration, and sync).

The source distinguishes recorded, partial, completed, analysis-eligible, achievement-eligible, and published training states. This plan preserves those distinctions. fileciteturn5file2L104-L118

The source requires common metric descriptors rather than independent per-screen calculations. This plan uses that contract for card values and any source-based header metrics. fileciteturn6file2L212-L230

The source keeps Progress, Crew, Settings, and Program detail as distinct responsibilities and avoids a new navigation migration for each feature. fileciteturn6file1L156-L168

The source separates model, sync, analytics, publication, and diagnostics projections, and preserves Health-specific privacy. fileciteturn6file0L51-L65

The source requires source preservation through offline operation, sync conflicts, migrations, and feature disablement. fileciteturn6file0L67-L79

### B2 — Earlier complete feature roadmap

`REGULIFT_IMPLEMENTATION_PLAN.md` defines Equipment Passport, recommendation evidence, Coach My Program, Week Designer, set-limiters, goals/benchmarks, conversational voice Coach, and program links. The supplied audit incorporates that earlier scope. Journey adds a read-oriented personal history layer; it does not independently reimplement those features.

### B3 — User-approved Journey concept

The current conversation establishes the desired direction: a private `My Training Journey` inside Progress; a compact personal identity header; dated workouts, milestones, body records, changes, reviews, and optional notes; hidden photo previews; and deliberate sharing through Crew. The reference image is visual inspiration only, not evidence of ReguLift's actual implementation.

### Verification limits

This document was written from the user's requirements and existing planning artifacts. No source repository, native build, backend configuration, production account, current SDK/API contract, or live entitlement configuration was inspected for this handoff. Proposed models, service signatures, character/page limits, performance budgets, and task sequences are design decisions—not claims that code exists or measured results have been achieved.

Before using a particular framework API, the coding agent must check the repository's actual SDK, deployment target, permissions, and supported-device matrix. No new OS version, vendor capability, or external API is assumed by this plan.

---

**Build order:** Existing correctness foundations → source-backed private timeline → profile/reflections/visibility → real training-change and review integrations → deliberate sharing → hardening and staged release.
