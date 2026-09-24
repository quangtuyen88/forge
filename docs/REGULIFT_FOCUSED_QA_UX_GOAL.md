# Regulift — Focused QA and UI/UX Goals

**Prepared:** 22 September 2026  
**Purpose:** Select the next high-value tests and design improvements; do not start another feature-expansion sprint.  
**Audience:** QA lead, native iOS/frontend engineer, training-data owner, backend/privacy owner, billing owner, product designer.  
**Status:** Proposed execution plan. **All tests below are Not run by this reviewer.** This is not an Apple-authored certification or a fresh inspection of your latest build.

> **Goal: A lifter can find the right workout, log and correct what happened, keep the data through interruptions, and understand the next session—without learning the whole app.**

## Read this first

This is an **ordered focus slice of the existing 216-case / 263-row QA pack**, not its replacement. It defines **32 focused test objectives**, seven recording routes, and seven implementation goals. An objective may contain several variants; expand each required variant into a separate execution row before running it. Do not call this “32 executions” or close a whole family because one variant passed.

Use the original case IDs and steps when closing original tracker rows. New `FQ-xx` IDs are focus-group identifiers, not retroactive replacements for an `AU`, `WK`, `UX` or other case. Tests for other enabled features remain required according to release scope.

Do not add a new theme, model, mascot, chart, Health importer, shader, subscription tier or navigation structure in this pass. First validate the existing product, then simplify its dominant workflows.

## 1. Evidence basis and what it does not establish

### Q1 — Submitted revision-2 QA report

The supplied **“Regulift — QA result and launch decision”**, revision 2 dated 21 September 2026, reports:

- Build `1.0 (1)` at `f1c9cac458f31d6f9f20926f8aeb40b769c4c477`, unsigned Debug simulator. Backend/billing/auth configuration was absent; Jev routing was off (§1).
- 708 ForgeCore, 203 server and 41 app test assertions reported green, plus 21/21 Maestro flows. Its coverage table records 10 Pass, 1 Fail, 139 Blocked and 113 Not run (§3). These are **source-reported outcomes**, not newly verified passes.
- Open observations: unnamed accessible cancel action (OBS-005, source severity S2); write-through History edits without Cancel (OBS-006, S3); voice-unavailable layout pushes the typed fallback off-screen (OBS-007, S3) (§6/§9).
- No completed hardware, billing, outbound-privacy capture, Watch/audio, migration, performance or human usability evidence (§7/§8).
- The report is unsigned and explicitly says it is evidence, not release approval (§10).

Treat this as a dated baseline. Your latest code may already fix some observations; close them with candidate-specific evidence rather than assuming they remain or are resolved.

**Source inconsistencies remain explicit.** Q1 §2’s “134 P0 / 2 Pass” sentence does not agree with §3’s revised P0 summary; reconcile the original tracker and actual scope rather than silently adopting either count. A green automation sequence does not establish unasserted saves, permissions, billing or user comprehension. Retain the original source unchanged.

### S1 — Supplied interface-polish skill

“Details that make interfaces feel better” asks reviewers to use the existing styling system, inspect states, preserve readable dynamic numbers, size hit targets, use consistent icons, and restrain repetitive motion. Its CSS/React-specific prescriptions are **not automatically native SwiftUI implementation requirements**. Section 5 below records the adaptation and the review boundaries.

### External verification, separated from the source report

Q1 §10 item 1 suggests a RevenueCat Test Store key plus an Apple sandbox account. That combination is **not sufficient evidence of the real StoreKit integration**. RevenueCat distinguishes Test Store from platform sandboxes and directs pre-launch testing to the platform-specific API key and Apple sandbox. Test Store remains useful for early development but does not test StoreKit-specific behavior. [A4]

No test execution, repository change, network capture, physical-device inspection or fresh screenshot review was performed to create this plan. The proposed priorities and usability targets below are tailored recommendations, not measured findings or Apple rules.

## 2. The next seven goals

| Goal | Priority | Owner | Deliverable | Exit condition |
|---|---|---|---|---|
| **G0 — Make the candidate testable** | P0 | Release + backend + billing + QA | Signed candidate, manifest, real test services, clear release scope | Required paths can actually execute; simulator-only evidence remains labeled. |
| **G1 — Make logging and corrections trustworthy** | P0 | iOS + training-data | Explicit exercise context; missing-effort integrity; draft-based editing; named safe actions | FQ-09–16 pass on applicable profiles, with stored-value assertions. |
| **G2 — Prove save → recover → next session** | P0 | Engine + data/sync | Durable observations; idempotent updates; truthful state and metric presentation | FQ-03, 07–08, 17–20 pass; no lost set, duplicate update or fake success. |
| **G3 — Make first use obvious** | P1, P0 for blocked tasks | Design + iOS | Simplified setup and Today using current components | FQ-04–06 and relevant accessibility pass; user study validates comprehension. |
| **G4 — Verify the paid and connected experience** | P0 when shipped | Billing + backend/privacy | Real purchase lifecycle, normal Coach, authorized actions, safe sync and export | FQ-21–28 pass for shipped capabilities, not only mocked or disabled paths. |
| **G5 — Reduce UI clutter without hiding important data** | P1; P0 for correctness/access | iOS/design + QA | Task-first result/Progress/Coach/settings; accessible shared components | Runtime states reviewed across the five skill categories; no repeated critical obstacle. |
| **G6 — Collect usable release evidence** | P0 sign-off | QA lead + release owner | Focus results, old-suite mapping, recordings, assertions and scope decision | All applicable release blockers resolved and remaining original required tests closed. |

**Priority is independent of source defect severity.** Preserve Q1's S2/S3 labels in the defect register. This plan treats inability to cancel a harmful edit, loss of data, privacy leakage, inaccurate entitlement and inaccessible essential controls as release-gate outcomes even when the original observation had a lower severity.

### Work in this order

1. **Unblock G0 immediately.** Do not spend another run proving a Coach composer renders when the backend is unavailable.
2. In parallel, fix/retest **G1** against deterministic local fixtures; environment gaps need not stop local data-contract work.
3. Run **G2 and the real billing/privacy paths in G4** before claiming launch readiness.
4. Prototype and review **onboarding + Today**, then **logger/edit + result**. Do not redesign all screens in one pull request.
5. Finish G5/G6 and remaining applicable original cases; run unassisted participants before signing off.

## 3. Candidate, fixtures and execution profiles

### Required manifest fields

```text
candidate_id / app version / build / commit / dirty-tree diff hash
signing and distribution type / installed-artifact identity
backend deployment / rules and schema versions
feature gates and effective runtime routes (including Jev)
store environment / product and entitlement IDs / API-key TYPE only
account state / permissions / supported locales and appearance modes
device model / OS / physical versus simulator / text size / locale / region / units
fixture ID / seed or prior-store provenance / clock / timezone / reset boundaries
QA owner / privacy owner / billing owner / release owner
```

Do not include credentials, private receipts, production prompts or personal Health samples. Use disposable test accounts and synthetic fixtures.

### Fixtures to prepare once

| Fixture | Contents and oracle |
|---|---|
| **NEW** | No workouts, no measurements, no Health access; actual supported setup and access path. |
| **EFFORT** | Two same-scope sets at a known valid load/reps; all missing versus one explicitly rated 8.5; separate target RPE. |
| **CONTEXT** | Lunge/bodyweight currently visible; Deadlift command target with known bar/plates. |
| **EDIT** | Saved 60 kg × 8; expected set-volume 480 kg, becoming 540 kg only after saving ×9. Use actual domain eligibility separately. |
| **DECISION** | Existing engine fixture with a real captured change and another with no change; compare to the rule outputs, not chat example numbers. |
| **WEEK** | Explicit unconfigured/rest/ready/resume/missed/complete/unavailable variants; separate imported active source. |
| **MATURE** | Representative long history and a previous persisted-schema fixture; counts, units and optional fields documented. |
| **CONNECTED** | Accounts A/B, guest merge data, actual test offerings, configured backend, approved cloud projection and private-data canaries. |

### Profile matrix

- **SIM-DEV:** deterministic/unit/UI automation for rapid iteration; never describe it as a physical distribution run.
- **RC-PHONE:** signed candidate on at least one actual supported phone for the complete core flow, network paths and store sandbox.
- **SMALL/SLOW:** actual smallest layout and slowest supported class where they differ; minimum supported OS plus current supported OS. Record actual devices; do not invent a hardware model.
- **A11Y:** large and accessibility text, VoiceOver with sound, Reduce Motion, keyboard, supported dark/light and increased-contrast settings.
- **LOCALE:** every shipped locale. Q1 identifies English/Japanese/Korean evidence and Vietnamese present in code; explicitly confirm or exclude Vietnamese in the release manifest. Test language separately from decimal-region/unit settings.
- **FAILURE:** airplane mode, timeout, 401/expired auth, disconnected services, kill/relaunch, pending commit, retry and migration faults.
- **WATCH:** actual paired hardware when Watch is shipped/advertised; simulator is supplementary.

Do not form an arbitrary full Cartesian product. Run the core loop on both size/OS boundaries, every primary action in A11Y, all exposed copy/input paths in each locale, and each relevant failure at the data/commit boundary. Expand further where a change affects that dimension. Required variants must be listed before execution.

## 4. Focused acceptance tests

**Execution status for every objective: Not run.** Video proves what is visible; a record/receipt assertion proves the corresponding data outcome. Neither replaces the other.


### FQ-01 — Freeze and exercise the actual release candidate

**Priority:** P0  
**Owner:** Release + backend + QA  
**Basis:** Q1 §1 and §8; existing W16. Reported environment gap, not a new UI finding.

**Fixture / prerequisite:** A signed distribution candidate on a physical supported iPhone, with a dedicated test account and reachable intended backend.

**Run:** Record commit/build, signing/distribution method, OS/device, backend deployment, rules/schema versions, enabled flags, product/entitlement IDs and locale scope. Open an authenticated, read-only service request. Fetch store offerings using the intended iOS integration. Inspect release-only screens for development bypasses.

**Pass only when:** The recorded environment matches what was actually tested. Authentication, Coach connectivity and billing readiness are distinguished; endpoint reachability alone is not “Coach ready.” No debug purchase bypass ships. Missing configuration is Blocked, not a simulated Pass. Keep secret values out of the manifest.

**Evidence:** Redacted manifest, app/system build identity, service request/result IDs, configuration-presence assertions and runtime screenshots.


### FQ-02 — Reconcile scope, assertions and reported passes

**Priority:** P0  
**Owner:** QA lead + release owner  
**Basis:** Q1 §2/§3 contain different P0 summaries; §5 reports partial workflows despite green automation.

**Fixture / prerequisite:** Submitted revision-2 results plus the existing 216-case catalog/tracker and candidate manifest.

**Run:** Preserve the old report. Assign each shipped/reachable gate Required or explicitly Excluded with an owner and evidence. Separate Debug simulator from physical distribution profiles. Bind each claimed pass to the exact fixture, action, expected result and artifact; retain failed attempts and retests.

**Pass only when:** One internally consistent release coverage summary. A green script is not a blanket pass for unasserted outcomes. An enabled feature with unavailable infrastructure is Blocked. Optional disabled Jev or narration is not silently treated as passed or forced into implementation. No unknown scope disappears from the denominator.

**Evidence:** Reconciled coverage sheet/change log and a case-to-artifact map. Do not overwrite the source report to conceal its inconsistencies.


### FQ-03 — Upgrade and store-migration preservation

**Priority:** P0  
**Owner:** iOS/data + QA  
**Basis:** Q1 §8: previous-store fixtures absent; migration unverified.

**Fixture / prerequisite:** A real previous app-store schema fixture or the actual previous distributed build’s test store; never a newly seeded database labeled as an upgrade.

**Run:** Populate workouts, nullable effort, a pending session, preferences and applicable outbox items. Install the candidate without clearing data. Open History, Resume and the plan. Inject or reproduce a migration failure using a safe fixture.

**Pass only when:** Facts, identifiers, units and missing values survive. A migration failure cannot silently reset or delete the user’s data. A supported fallback/recovery is visible. If this is genuinely the first distributed store, document that scope decision and still test the current persisted schema across candidate updates.

**Evidence:** Old/new schema and build IDs, synthetic record manifest, migration assertions and restart recording.


### FQ-04 — Fresh onboarding reaches a truthful first plan

**Priority:** P1; P0 for invalid plan or blocked primary action  
**Owner:** iOS/design + QA  
**Basis:** Q1 W01: eight steps and paywall bypass recorded; new simplification is a proposal, not proven current behavior.

**Fixture / prerequisite:** Fresh local profile, optional permissions denied, no observed training history; separate entitled and purchase-required variants.

**Run:** Complete the minimum supported setup, skipping optional photos/measurements/import. Inspect the actual starting plan and the next action. Continue through the applicable access route to the first exercise. Repeat with uncalibrated starting loads.

**Pass only when:** Required engine inputs and constraints are preserved. No guessed load is presented as a measured PR; unsupported configurations are not offered as valid plans. No optional download/permission blocks manual training. The button says where it goes, including purchase when required. Do not change the business model just to shorten the flow.

**Evidence:** Uninterrupted runtime recording, actual input-to-plan assertions and first-set state; no fabricated success chart.


### FQ-05 — Onboarding Back, interruption and preview invalidation

**Priority:** P0  
**Owner:** iOS/state + QA  
**Basis:** Proposed regression protection for the new onboarding design.

**Fixture / prerequisite:** Partially completed setup and an existing generated preview.

**Run:** Go back; change frequency/equipment; interrupt with keyboard, background and force-kill; resume. Cancel a purchase and return to the preview. Rapidly press Continue/Preview on supported controls.

**Pass only when:** Draft choices survive as designed; a changed dependency regenerates or invalidates the old preview. Exactly one intentional activation occurs. Returning never overwrites an unrelated active plan. Payment cancellation preserves setup. No loading animation is a dependency of data saving.

**Evidence:** Before/after draft and plan IDs/revisions, interruption recording and activation-count assertion.


### FQ-06 — Returning user and training-history import route

**Priority:** P0 when import/returning-user routes ship  
**Owner:** iOS/data + QA  
**Basis:** Q1 W08: imports/exports not executed. Reuse existing import and account tests.

**Fixture / prerequisite:** An entitled returning user, a small valid supported Strong/Hevy file, and a malformed/unsupported file.

**Run:** Restore/continue as the returning user without rebuilding their plan. Separately import the valid file through preview; cancel once and activate once. Submit the malformed file. Ask only for genuinely missing setup information.

**Pass only when:** Restore does not create a new plan or duplicate observations. Preview/cancel does not activate; actual activation updates the intended authoritative source once. Missing source RPE stays missing. Malformed import leaves the existing plan untouched. Complete the original import suite for every shipped format.

**Evidence:** Sanitized source file, import mappings, row counts/IDs, active-source revision and UI recording.


### FQ-07 — Today distinguishes every weekly state

**Priority:** P0  
**Owner:** Planning + iOS/QA  
**Basis:** Q1 §4 and W04: empty/rest/missed-week fixtures not seeded.

**Fixture / prerequisite:** Separate fixtures: unconfigured week; scheduled rest; ready workout; in progress; missed workout; planned commitments complete; unavailable plan.

**Run:** Open Today for each fixture. Use its main action and return. Include an imported active plan and a manually adjusted week without resetting data between the checks of that variant.

**Pass only when:** Unconfigured is not green “0 of 0 complete.” Start/Resume/Review schedule/Plan week matches state. Calendar week and block week are distinct. The visible session, logger and Coach-eligible projection reference the same active source. No extra workout is prescribed merely to fill an empty screen.

**Evidence:** One labeled screenshot and state assertion per variant plus one continuous cross-screen route.


### FQ-08 — Dates, rest deadlines and schedule boundaries

**Priority:** P0  
**Owner:** Planning + QA  
**Basis:** New targeted boundary test for a time-dependent product; not a defect asserted by Q1.

**Fixture / prerequisite:** Injected clock and documented local timezone; week-boundary, midnight, timezone-change and applicable DST variants.

**Run:** Start/rest/log around a date boundary; reopen Today; shift timezone while keeping the same records. Move an upcoming session, then open the weekly view, History and reminders.

**Pass only when:** One defined local-date/week policy is used. Completed observations are not duplicated or moved by formatting changes. The rest timer follows its deadline policy, not the number of rendered ticks. Timezone changes do not silently double-run progression or schedule duplicate reminders.

**Evidence:** Clock/timezone manifest, stable IDs, deadline/event assertions and boundary screenshots. Record supported policy before execution.


### FQ-09 — Reported effort stays separate from the target

**Priority:** P0  
**Owner:** Training-data + iOS/QA  
**Basis:** Q1 AU-05/AU-06 claim Pass; retain the claim as reported and re-establish it on the candidate.

**Fixture / prerequisite:** Fixture A: two unrated sets with target RPE 8. Fixture B: one explicitly rated 8.5 plus one unrated set. Use the same valid load/reps for easy comparison.

**Run:** Log each fixture; finish; view individual History rows, average/coverage, summary and an available export. Open Edit on the unrated set and Cancel. Reopen after restart.

**Pass only when:** A has no reported average. B counts exactly one rating at 8.5. A row must not show an unlabeled @8 as if reported when that is only the target. Cancel does not create a rating. Inspect serialized observations as well as text. Existing missing-effort engine policy stays intact.

**Evidence:** Observation values/provenance, rendered rows/coverage, before/after cancel records and relevant export.


### FQ-10 — Exercise identity and plate conventions never mix

**Priority:** P0  
**Owner:** Logger/equipment + QA  
**Basis:** Q1 AU-07/08/09 remain Blocked; prior cross-exercise issue requires explicit verification.

**Fixture / prerequisite:** Lunge selected with Bodyweight/zero added load, Deadlift available, known bar/plate inventory and explicit units.

**Run:** While viewing Lunge, submit “deadlift 60x8 @8.” Inspect the receipt and current-view identity. Open Plates without navigating; then go explicitly to Deadlift and open Plates. Check the rest owner.

**Pass only when:** A single explicit exercise/equipment identity owns each utility. Bodyweight does not display a failed bar-20 calculation; use no-plates/applicable added-load UI. Deadlift uses the actual bar/inventory. The typed destination and visible selection are not silently conflated. Preserve the existing intentional extra-exercise policy.

**Evidence:** Receipt/set/exercise IDs, equipment/loading convention and utility screenshots for both contexts.


### FQ-11 — Transport retry is not a second intentional set

**Priority:** P0  
**Owner:** Data/backend + QA  
**Basis:** Q1 AU-12 reports deduplication of identical typed text; explicit operation identity is required to prove the intended guarantee.

**Fixture / prerequisite:** One fixed logging operation ID and payload fingerprint, plus a second deliberately distinct operation ID with identical set values.

**Run:** Deliver the same operation twice, including a delayed retry after acknowledgement loss. Then log the same values using the new operation ID. Also replay the first ID with altered content and rapidly double-tap the submission control.

**Pass only when:** Same ID/same content returns one observation and original receipt. New intentional ID allows a second legitimate identical set. Same ID/different content is rejected without mutation. Two fast UI submissions follow a documented intent policy. Do not deduplicate by text, timestamp proximity or weight alone.

**Evidence:** Operation IDs/fingerprints, exact before/after stored counts, receipts/conflict result and pending-UI recording.


### FQ-12 — History edits are reversible drafts with accurate precision

**Priority:** P0  
**Owner:** History/data + QA  
**Basis:** Q1 OBS-006, AU-20 Fail; AU-19 reports changing totals but does not close cancellation.

**Fixture / prerequisite:** A saved 60 kg × 8 set (480 kg set volume), a decimal-load example supported by the equipment, and unrelated historical records.

**Run:** Edit reps to 9; Cancel. Repeat and Save. During another edit temporarily enter an incomplete/large number, then dismiss/back. Edit a supported decimal value and reopen. Interrupt before commit.

**Pass only when:** Cancel preserves 480 kg; a committed 60 × 9 contributes 540 kg under the same metric definition. Intermediate keystrokes cannot mutate committed history, PRs or future plans. Unsaved dismissal has a recoverable choice. Accepted precision is shown faithfully and validated by loading convention; no silent destructive rounding.

**Evidence:** Draft versus committed snapshots, edited record ID, cancel/save assertions, downstream invalidation and keyboard recording.


### FQ-13 — Finish, Keep going and Discard have explicit meanings

**Priority:** P0  
**Owner:** Logger/accessibility + QA  
**Basis:** Q1 OBS-005: safe action has no accessible label; WK-10 alone does not establish accessibility.

**Fixture / prerequisite:** One empty session and one partial session, both normal and VoiceOver variants.

**Run:** Tap Finish. Choose Keep going. Reopen and choose the applicable Discard/Finish action. Repeat under VoiceOver and cancel with system dismissal. Deliver a repeated finish event.

**Pass only when:** Safe and destructive actions are separately named and reachable. Keep going retains the session. Empty discard deletes only the empty draft; partial finish preserves logged facts once. No unnamed dismiss target is the only safe option. Finishing below prescribed volume is allowed without coercive language.

**Evidence:** Video with VoiceOver audio, accessibility labels/tree, saved/deleted record assertions and duplicate-finish receipt.


### FQ-14 — A complete Focus Mode workout, not just its first screen

**Priority:** P0  
**Owner:** Logger + QA  
**Basis:** Q1 W02 is Partial despite green flow. Expand the actual workout interaction.

**Fixture / prerequisite:** A short fixture with warm-up/work sets, two exercises, an existing supported superset and applicable substitution.

**Run:** Complete the entire session in Focus Mode. Correct a set; skip rest; open an exercise tool and return; swap/reorder through supported controls. Background during rest. Finish and reopen History.

**Pass only when:** Targets and reports remain distinct; warm-ups do not silently become working sets. Focus/standard logger use one state owner. Returning preserves position. Superset/rest ownership follows the real sequence. No phantom set or progression is triggered by navigation/animation. Complete extra advanced-technique variants in the original suite when shipped.

**Evidence:** Full session recording, per-set IDs/type/order, rest deadlines and finished record comparison.


### FQ-15 — Voice failure never hides manual/typed logging

**Priority:** P0 for fallback; conditional voice-path checks  
**Owner:** Voice/iOS + QA  
**Basis:** Q1 OBS-007 and W06: fallback visibility concern; supplied recordings were silent.

**Fixture / prerequisite:** No speech model, denied mic, unavailable network, silence/noise; additionally one known spoken command if voice ships.

**Run:** Enter every unavailable state on the smallest supported phone with keyboard and large text. Reach Type a set and manual logging. Where enabled, speak a known command, cancel/retry and trigger a timeout; record sound.

**Pass only when:** Fallback controls remain fully reachable, not hidden beneath the home indicator or an explainer. A failure creates no set. Successful voice uses the same observation contract as manual input. No unexpected cloud fallback without consent. Narration, if shipped, never speaks a stale or uncommitted target.

**Evidence:** Real audio/video for spoken variants, interpreted intent/record assertions with synthetic data, permission/network route evidence.


### FQ-16 — Units, equipment increments and numeric entry

**Priority:** P0  
**Owner:** Logger/data + QA  
**Basis:** Targeted protection for dense number-heavy screens; no new arithmetic policy is proposed.

**Fixture / prerequisite:** kg/lb, regional decimal separators, barbell, per-dumbbell, machine-stack, bodyweight and assisted-load examples supported by the app.

**Run:** Enter/log/edit a set in each convention, switch display units and reopen History/Plates. Attempt blank, negative, nonfinite, out-of-range and incomplete input where applicable.

**Pass only when:** One correct conversion, explicit load convention and consistent precision. Blank is not zero. Bodyweight and assistance are not interpreted as ordinary barbell load. Invalid values cannot be committed; supported negative/assistance semantics follow the actual domain contract rather than a blanket ban.

**Evidence:** Input/stored/display triples, unit/convention assertions, validation screenshots and conversion round trip.


### FQ-17 — Offline logging and durable resume

**Priority:** P0  
**Owner:** iOS/sync + QA  
**Basis:** Q1 AU-16 reports force-kill Pass; offline remains Blocked. Do not conflate these results.

**Fixture / prerequisite:** Entitled local session with an approved offline-access policy; no dependency on a cloud Coach.

**Run:** Enable airplane mode; log several sets; background, force-kill and restart the app/device as applicable; resume; finish offline; reconnect and retry queued delivery.

**Pass only when:** The same observed sets and pending session survive. No duplicate observation/progression after reconnection. Offline entitlement behavior follows the documented policy; an in-progress workout is not destroyed by a network failure. App kill/relaunch is not recorded as an OS crash.

**Evidence:** Physical-device recording, event/outbox IDs, before/after persistence and server acknowledgement counts.


### FQ-18 — Workout save succeeds independently of adaptation

**Priority:** P0  
**Owner:** Engine/iOS + QA  
**Basis:** Q1 §4: failed-adaptation paths Blocked.

**Fixture / prerequisite:** Fault injection after durable observation save but before adaptation/commit, with exact failure point recorded.

**Run:** Finish the workout; fail the next-session evaluation/update step; open the summary and History. Restart; retry once and repeatedly; later allow success.

**Pass only when:** Facts remain saved. UI distinguishes “saved; update pending” from committed next-session changes. Retry applies at most one canonical update for the event/revision. Sharing, animation and Coach availability are not save dependencies. Existing automatic progression policy is unchanged.

**Evidence:** Fault marker, durable save and update receipts, event/revision counts and pending-to-success recording.


### FQ-19 — Summary, History, Progress and next target agree

**Priority:** P0  
**Owner:** Metrics/engine + QA  
**Basis:** Q1 AU-23 equality remains unasserted; AU-19 alone is insufficient.

**Fixture / prerequisite:** One uninterrupted known fixture with eligible, ineligible, partial and missing-effort records; engine test fixture for one real change and one no-change decision.

**Run:** Inspect saved result, History, Progress, Why, Timeline and card export where available. Edit one fact, cancel another, and reopen after restart. Follow the actual next session.

**Pass only when:** Same-scope values match; intentional recorded/eligible/planned differences are labeled. Estimated strength is not a completed lift. Initial targets are not improvements. Reasons come from the actual engine branch; no-change is valid. Target changes require the correct result revision, not a decorative sample number.

**Evidence:** Metric oracle by scope/window, observation and decision IDs/revisions, before/after outputs and linked screenshots.


### FQ-20 — Week adjustments and constraints preserve intent

**Priority:** P0  
**Owner:** Planning/engine + QA  
**Basis:** Q1 W04 is Partial; exposed control does not establish applied behavior.

**Fixture / prerequisite:** A missed workout, a shorter-session request, an unavailable-equipment constraint and a locked/preferred exercise, using supported engine configurations.

**Run:** Preview and cancel an adjustment; preview and approve; modify context before approving an old preview; use a temporary constraint and later restore the ordinary plan.

**Pass only when:** Cancel changes nothing. Accepted changes fit the current constraints or show a truthful tradeoff. Stale previews cannot apply silently. Temporary changes do not become permanent preferences. Completed records remain intact. Reuse existing engine rules and their deterministic fixtures; do not invent universal recovery thresholds.

**Evidence:** Exact plan diffs, approvals, context revisions and evidence of restoration/no-mutation on cancel.


### FQ-21 — Normal Coach grounding and ambiguity with live services

**Priority:** P0 when cloud Coach ships  
**Owner:** Coach/backend + QA  
**Basis:** Q1 AU-48 injection refusal Pass; normal question/clarification still Blocked.

**Fixture / prerequisite:** Working authenticated backend; one permitted engine decision, one withheld/private reason and ambiguous body-weight/exercise-load context.

**Run:** Ask a normal program question; “Why did my weight drop?”; an unknown birthday; a stale or missing decision. Trigger timeout/retry. Exercise enabled routing paths separately.

**Pass only when:** Answers match authorized facts; ambiguous meaning is clarified; unknown data is not invented or met with irrelevant medical copy. Withheld Health causes stay local. Draft survives failure. An instruction-refusal example does not substitute for these ordinary answers. A connected label reflects the actual effective capability.

**Evidence:** Synthetic prompt/expected-fact fixture, allowed projection, response/tool IDs, UI/error recording and backend success/failure assertions.


### FQ-22 — Coach actions preserve authorization and consent

**Priority:** P0 when Coach actions ship  
**Owner:** Coach/engine/backend + QA  
**Basis:** Q1 W05 action preview not established; retain existing proposal/approval boundary.

**Fixture / prerequisite:** One supported action, an unsupported request, a stale proposal, two test account identities and adversarial content.

**Run:** Request the action; reject; approve a fresh preview; change the plan then try the old approval. Ask the model to skip confirmation or use another account’s resource; retry the approved operation.

**Pass only when:** The model can propose, not commit arbitrary changes. Approval binds the exact current diff. Rejection/unsupported/foreign-resource/stale requests do not mutate state. Matching replay returns the original receipt. No instruction in retrieved/user text supplies trusted confirmation. Jev confidence never grants permission.

**Evidence:** Proposal/digest/revision and operation IDs, authorization and mutation-count assertions, previews and final receipt.


### FQ-23 — Real iOS product purchase and clear offer

**Priority:** P0 for paid launch  
**Owner:** Billing + QA  
**Basis:** Q1 PAID/W11 untested. Outside-source correction: Q1 §10 item 1 is insufficient for platform verification; see A4.

**Fixture / prerequisite:** Signed candidate, configured App Store products, RevenueCat iOS platform-specific key and Apple sandbox test account; no Test Store key for this platform test.

**Run:** Fetch actual offerings; inspect price/period and eligible offers; purchase the supported monthly and annual products using separate variants. Verify entitlement from the actual transaction path. Test unavailable products and repeated taps.

**Pass only when:** Correct access unlocks from verified transactions, not a debug bypass. Actual billed amount and period are clear; restore and terms/privacy are reachable. No unconfigured trial is advertised. Record sandbox metadata discrepancies separately and reconcile catalog/paywall mapping; sandbox success does not prove every production storefront price.

**Evidence:** Store/product/entitlement IDs, redacted transaction and CustomerInfo results, offering mapping, recording and configuration proof without secret values. [A4][A5]


### FQ-24 — Payment cancellation, restore and lifecycle

**Priority:** P0 for paid launch  
**Owner:** Billing/iOS + QA  
**Basis:** Q1 §8: no purchase/restore/expiry evidence.

**Fixture / prerequisite:** Entitled, new, expired and pending test states; actual supported grace/retry configuration.

**Run:** Cancel a purchase; interrupt a pending purchase; restore after reinstall/sign-in using supported ownership rules; run renewal/expiry/revocation and configured grace/retry variants. Let entitlement refresh occur during an active workout.

**Pass only when:** No accidental unlock or double charge request; pending is distinct from failed. Restore resolves actual ownership. Expiry does not erase history or discard an active set. Known cached/offline access behavior is declared. An unsupported production lifecycle branch is explicitly scoped, not given a fabricated pass.

**Evidence:** Timestamped state-transition assertions, redacted store events, access results and recordings. Keep platform-sandbox and mocked tests labeled separately.


### FQ-25 — Account sync, isolation and deletion

**Priority:** P0 when account/sync ships  
**Owner:** Backend/iOS + QA  
**Basis:** Q1 W10/W14 blocked by unconfigured services.

**Fixture / prerequisite:** Two disposable accounts, a guest dataset, two clients/devices where supported, and pending offline work.

**Run:** Authenticate, merge guest data using the supported flow, expire auth, sign out/in and attempt cross-owner reads/writes. Create a conflict with pending edits. Delete the test account/data then reconnect an old outbox.

**Pass only when:** No cross-account record or receipt access; guest merge is explicit and deduplicated. Conflicts preserve observed facts and follow a documented policy. Deletion revokes/cancels old work so removed data cannot reappear. Sign-out does not expose the previous account’s state to the next one.

**Evidence:** Owner/resource assertions, sync/conflict receipts and deletion/no-resurrection evidence. Never attach production credentials or private user data.


### FQ-26 — Privacy under active outbound processing

**Priority:** P0  
**Owner:** Privacy/backend/iOS + QA  
**Basis:** Q1 §8 explicitly does not claim privacy; no reachable backend is not a privacy pass.

**Fixture / prerequisite:** Synthetic distinctive canaries in Health-derived fields, private notes, photos metadata and forbidden nested evidence; active intended cloud routes.

**Run:** Run cloud Coach, enabled routing, analytics/crash diagnostics, sync and sharing. Inspect client requests and server/provider-bound payloads and approved logs. Revoke the relevant consent and repeat; test error/retry routes.

**Pass only when:** Forbidden raw and derived data do not leave through any disallowed path. Explicit allowed projections follow the reviewed policy; hashing is not automatic permission. No private prompt is exported merely to debug. Denial is enforced before network processing. A proxy that cannot inspect encrypted traffic is not a complete negative proof; close the gap with instrumented test assertions.

**Evidence:** Sanitized request/egress inventory, canary scan plus positive-control result, lineage/export assertions, consent transitions and stated visibility limits.


### FQ-27 — Share-card pixels and Crew audience

**Priority:** P0 when sharing/Crew ships  
**Owner:** Sharing/backend + QA  
**Basis:** Q1 W09 Not run; exports empty; Crew only signed out.

**Fixture / prerequisite:** A real synthetic saved session, one eligible PR, one missing RPE, a committed future target and a stale target; two audience test accounts.

**Run:** Preview, cancel, export and inspect the actual image. Change source data and preview again. Post an explicitly selected card to Crew; retry upload and inspect from allowed and disallowed viewers. Test a photo variant only when shipped.

**Pass only when:** Exported pixels match approved fields and saved facts; no hidden notes/Health values or original-photo metadata. Future target labeled planned, not completed; stale preview is rebuilt or rejected. Cancel leaves training intact. No-account external sharing follows existing policy; Crew requires actual authorization. One intended post, with enforced audience—not an assumed private group.

**Evidence:** Image file, metadata inspection, selected-field fixture, source revision, upload/post IDs and audience assertions.


### FQ-28 — Watch and advertised Apple surfaces

**Priority:** P0 for shipped/advertised functions  
**Owner:** watchOS/iOS + QA  
**Basis:** Q1 W13 and §8: no Watch/audio/system evidence.

**Fixture / prerequisite:** A physical paired Watch/iPhone for shipped Watch behavior; actual Lock Screen/widget/Siri surfaces; configured permissions.

**Run:** Log offline on Watch; log concurrently on phone; reconnect and replay events. Background the app during rest; inspect Live Activity/widget state and end cleanup. Invoke supported shortcuts/reminders and interrupt audio where enabled.

**Pass only when:** One observation per intended event and one canonical adaptation. Cached/provisional Watch targets are not mistaken for confirmed updates. No stale timer/notification or lingering finished Live Activity. Manual/offline core remains available under denied permissions. Record nonapplicable capabilities individually; simulator evidence alone does not close hardware requirements.

**Evidence:** Physical-device video with sound where relevant, event identities, widget/activity snapshots and deduplication/deadline assertions.


### FQ-29 — Accessible primary actions and safe exits

**Priority:** P0  
**Owner:** iOS/accessibility + QA  
**Basis:** Q1 OBS-005 and AU-57; S1 minimum-hit-area/state principles, adapted to native iOS.

**Fixture / prerequisite:** Smallest supported physical layout, default and accessibility Dynamic Type sizes, VoiceOver and Reduce Motion.

**Run:** Complete setup, one set, correction, Keep going, finish, History Save/Cancel and paywall restore using VoiceOver. Repeat with keyboard and large text. Measure touch bounds; inspect selected/disabled/error focus and announcement.

**Pass only when:** Every essential action and safe exit is labeled and reachable; no color-only selection, overlapping hit regions or clipped load/price. Use at least 44 × 44 pt hit areas as this project’s touch target, with space between actions—not a claim that all Apple controls require that absolute minimum. No fixed-height truncation or shrink-to-fit workaround. [A1]

**Evidence:** VoiceOver audio, accessibility tree, measured hit areas, real screenshots and automated accessibility audit findings where supported; manual navigation still required.


### FQ-30 — Locales, keyboard and meaningful visual states

**Priority:** P0 for correctness/reachability; P1 for isolated polish  
**Owner:** Localization/design + QA  
**Basis:** Q1 W12 is Today-only; vi exists in code but scope is unconfirmed.

**Fixture / prerequisite:** Every shipped locale verified from the candidate, explicitly deciding en/ja/ko/vi; supported appearances, units and numeric regions.

**Run:** Walk onboarding, logger/editor, summary, Coach, Progress, settings and paid offer with long labels, actual keyboards and empty/loading/failure/selected states. Include fresh and mature data. Recheck small-screen footer overlap.

**Pass only when:** No critical clipping, unlocalized action, incorrect numeric interpretation or obscured fallback. Preserve drafts and scroll position where expected. Text and selection meet measured contrast/accessibility requirements. A single Today screenshot or key-count parity is not a whole-locale pass. Cosmetic deviations are recorded separately from broken tasks.

**Evidence:** Per-locale route screenshots, keyboard recordings, numeric round-trip assertions and specific strings/issues.


### FQ-31 — Performance and motion do not obstruct the workout

**Priority:** P1; P0 for hangs/data loss/unusable actions  
**Owner:** iOS/performance + QA  
**Basis:** Q1 §8: no approved performance budgets or measurements; S1 typography/motion/performance principles.

**Fixture / prerequisite:** Smallest/slowest supported physical device, fresh and long-history fixtures, existing animations/Rive only when actually shipped.

**Run:** Record cold launch, Today readiness, Log acknowledgement, History scrolling, chart navigation, export and a sustained representative workout. Repeat under permitted offline/error and Reduce Motion states. Interrupt existing animations and replay captured motion slowly.

**Pass only when:** No animation delays persistence or approval; no custom celebration on every frequent log. Changing timer digits stay aligned. No memory growth, prolonged main-thread freeze or repeated image/model initialization. Agree measured device-specific budgets before scoring; do not label an arbitrary FPS or duration as an Apple mandate. Compare candidate to a recorded baseline.

**Evidence:** Instruments/performance traces, device/fixture/run conditions, predeclared budgets and repeated-run results, slow playback plus normal-speed video.


### FQ-32 — Five unassisted users understand the whole loop

**Priority:** P1 discovery; P0 for repeated critical blockage  
**Owner:** Product/design + QA  
**Basis:** Q1 §7 and W17: no human study completed.

**Fixture / prerequisite:** Five target lifters who did not build the app; consented recordings and synthetic data; include varied familiarity and language, with separate accessibility expertise where available.

**Run:** Without pointing at controls, ask each participant to create a plan, find today’s session, log/correct a set, finish, explain the next session, find History and one voice/privacy setting. Ask them to read the actual paid offer and explain the charge; do not require real payment or disclosure of health facts.

**Pass only when:** Record completion, hesitations, wrong turns, assistance and misunderstanding task by task. Proposed small-study acceptance: all five finish/save or safely cancel without critical error; at least four explain the next-session state correctly; everyone who sees the offer explains charge/period accurately. One misleading price or lost record is not averaged away. This is usability discovery, not statistical conversion proof.

**Evidence:** Anonymized participant task matrix, exact questions/answers, videos and ranked recurring obstacles with owner/retest plan.


## 5. UI/UX work: improve these surfaces in this order

**Review scope:** planned full review of onboarding, Today, logger/History, result, Progress, Coach and Settings. Expected framework is native SwiftUI; verify the repository's actual tokens/components first. **Inspected evidence in this handoff:** Q1 text and S1 skill. Current view source, accessibility tree, measured contrast, runtime motion and new screenshots: **Not reviewed**. Thus this is an improvement specification, not new design approval.

### 5.1 Source-backed concerns first

| Source severity / proposed priority | Location | Before, as reported in Q1 | Proposed after | Why |
|---|---|---|---|---|
| S2 / P0 | Empty/partial Finish dialogs | Cancel has no accessible label; only destructive action and unnamed dismissal exposed | Explicit, accessible **Keep going** plus distinct Finish/Discard; correct focus | A safe exit must be understandable without sight. Recheck real VoiceOver, not a renamed screenshot. |
| S3 / P0 | History set editor | Every keystroke writes through; no Cancel/Undo | Isolated validated draft; **Save / Cancel**; dismissal protection | Error prevention and recovery outrank a cleaner-looking form. |
| S3 / P0 fallback access | Logger, voice unavailable | Explanation pushes typed fallback off-screen | Compact status; manual/typed entry remains reachable above safe area and keyboard | A fallback cannot become hardest to use when its main path fails. |

Do not claim these still exist in the current candidate without reproducing them. Preserve Q1's original severities; the right-hand priorities are this plan's proposed release policy.

### 5.2 Hierarchy goals — proposed, not new defect observations

| Order | Screen | Keep prominent | Collapse/move, not delete | Acceptance task |
|---|---|---|---|---|
| **1** | Onboarding + plan preview | A focused question, supported choices, Back/Continue; actual generated week and first workout | Optional body/nutrition/profile/model configuration; long methodology | User chooses a valid setup and explains the plan without a tutorial or false fitness score. |
| **2** | Today | Correct workout/rest/resume state, one dominant action, compact week, at most one immediately relevant change | Duplicate readiness/metric presentations, feature directory, large portraits | “What do I do now?” is answered without opening Settings. |
| **3** | Logger + History editing | Exercise identity, units, target versus entered result, Log, correction and safe exit | Detailed cues and uncommon tools in contextual sheets; never hide the fallback | User logs and corrects a mistake without changing unrelated data or losing place. |
| **4** | Workout result | Saved facts, actual next-session status, Done; optional Share | Detailed analysis and secondary numbers | User explains saved versus pending, and planned versus completed. |
| **5** | Progress + Timeline | One meaningful trend, clear period/scope, History; related events grouped | Empty graph stacks, repeated initial “change” entries, full advanced-tool directory | User finds a prior workout and understands the chart without learning internal eligibility terminology. |
| **6** | Coach | Composer, relevant answer, factual context and explicit action preview | Large portrait, duplicate suggested questions, provider configuration | One normal question succeeds; an error preserves the draft and next action. |
| **7** | Settings | Training; Coach & privacy; Voice & audio; Appearance & language; Account & data | Task-specific one-off controls move into the task; diagnostics stay development-only | User locates voice processing and account/data controls without searching unrelated groups. |

These are content-placement changes. Keep current tabs, engine logic, payment policy and expert access unless a separate tested decision approves a change. Do not create an “Advanced mode” just to relocate clutter.

For onboarding, the proposed question sequence remains goal → available week → experience → equipment → actual plan preview, subject to genuine engine dependencies. Import and returning-user routes remain available. Ask private-resource permission when the applicable function needs it; do not hide required consent. [A2]

For Settings, classify each control as global preference, task-specific option, sensitive permission, or development diagnostic. A privacy control or restore route is not expendable decoration. [A3]

### 5.3 Apply the supplied polish skill in the actual native stack

S1 says to use the existing styling system. Do not introduce Tailwind, React, web CSS or an animation library into this native task just to reproduce its examples.

| Required review category | Source principle | Native review/action | Current verification |
|---|---|---|---|
| **Typography** | Readable wrapping; stable updating numbers | Semantic/scalable text; avoid critical truncation; use existing tabular/monospaced digit support for rest/count values where needed; keep labels and units readable | Not reviewed in latest candidate; FQ-29–31 provide evidence. |
| **Surfaces** | Coherent corners, optical alignment, hit areas; distinguish structure from elevation | Reuse one shared spacing/surface family; align label/icon/control; 44 × 44 pt project touch target with nonoverlapping hit areas; use the native component's actual shape/insets rather than mechanically applying web geometry | Not reviewed; report has a concrete fallback/confirmation issue to reproduce. |
| **Animations** | Interruptibility, quiet exits, restraint on repeated interactions | Use existing native state transitions; user input and saving never wait for motion; static feedback remains; test Reduce Motion; replay existing transitions slowly plus normally | No new motion recording inspected. |
| **Icons** | Consistent weight and selection treatment | Reuse existing SF Symbols/icon family; retain tab/action labels; selected state includes an accessible label/mark, not color alone | Not reviewed. |
| **Performance** | Animate only what helps; avoid speculative optimization | Measure actual main-thread work, scrolling and resource lifetime; do not add web `will-change` or preemptively rewrite the renderer | Q1 reports no performance measurements. |

Apple's accessibility guidance supports adaptable text, sufficiently sized/spaced controls, screen-reader labels and alternatives to color/gestures. This project uses a **44 × 44 pt minimum target for touch controls** as its own ergonomic acceptance criterion; points are not web pixels. Check actual geometry, contrast and accessibility output, not the mockup alone. [A1]

S1 contains literal web recipes such as `scale(0.96)`, CSS keyframes and blurred icon transitions. Do **not** transplant those automatically. Frequent Log/edit actions should retain native feedback, and Reduce Motion must work. Apple recommends purposeful, brief motion that does not obstruct tasks. [A6]

### 5.4 Content budget without deleting meaning

For an ordinary setup screen, try one question, one optional helper sentence, labeled options, Back and one dominant next action. For Today, try one dominant workout/rest/resume object. For Progress, start with the useful data actually available, not a mandatory count of charts.

These are design starting points, not hard word or card limits. Keep billing terms, consent, missing-value explanations, safety exits and units legible. Do not replace clear labels with unlabeled icons or make text smaller to make a screenshot look less crowded.

A visual agent must deliver a **keep / collapse / move / remove-duplicate map**, actual before/after runtime screenshots, state-coverage results and tests—not just a concept board. Review two representative screens at a time; approve their components before expanding.

### 5.5 Considered but deliberately deferred

| Candidate | Decision | Reason |
|---|---|---|
| New Rive/mascot animation | No new implementation in this pass | It does not close missing billing, privacy, cancellation or data-integrity evidence. Test existing animation only when shipped. |
| Replace Apple-like UI with an entirely new theme | Defer | It expands regression risk before hierarchy and state correctness are established. Keep the chosen shared visual direction. |
| Replace numbers with decorative gauges/images | Reject for primary logging/analysis | Real loads, units, periods and missing values must stay readable; a graphic cannot conceal missing evidence. |
| Full Settings/nav rewrite or more tabs | Defer | Move task-specific options and group existing controls first; preserve discoverability and explicit permissions. |
| Jev as a remedy for failed Coach/data behavior | Defer new routing | Q1 says Jev is off. Fix/read/test the actual service and data contracts; only enable a new model under its separate evaluated scope. |

**Design verdict for this handoff:** **Not verified**. QA should use S1's eventual `Block / Needs changes / Approve` verdict only after inspecting the candidate. `Approve` for a polish review is not release approval for billing, privacy or persistence.

## 6. Seven recordings to return

Record the candidate identity at the beginning or in a sidecar manifest. Avoid hidden reseeds between assertions. Reproduction fixtures must be visibly labeled synthetic. Do not crop away dialogs, keyboard, safe areas or failed attempts.

| Route | Script | Primary objectives | Additional evidence |
|---|---|---|---|
| **R1 — First plan** | Fresh launch → supported setup → Back/edit → actual plan preview → applicable paid route → first Today | FQ-04–07 | Input/plan/entitlement state and first-use task results. |
| **R2 — Log and correct** | Missing effort + one rating → cross-exercise typed log → correct plate context → Focus Mode → History draft Cancel then Save | FQ-09–16 | Set/context/operation IDs, stored values, precision and cancellation assertions. |
| **R3 — Save and recover** | Offline session → force-kill → resume → partial finish → injected adaptation failure → retry → next session → cross-screen comparison | FQ-17–20 | Fault location, save/update receipts, counts and exact plan revision. |
| **R4 — Connected Coach** | Normal answer → ambiguity → missing data → preview reject/approve → stale approval → timeout/retry | FQ-21–22, 26 | Allowed request/response projection, ownership/consent and mutation assertions. |
| **R5 — Paid + share + account** | Real sandbox purchase/cancel/restore lifecycle variants → actual card export → intended Crew audience → sign-out/deletion variant | FQ-23–27 | Separate store-state variants, exported pixels, audience checks, sanitized deletion proof. |
| **R6 — Accessibility + Apple surfaces** | Core route at large text/VoiceOver → keyboard and unavailable voice → applicable Watch/widget/activity/shortcut flows | FQ-15, 28–31 | Sound, actual hardware and accessibility tree; use separate clips where devices differ. |
| **R7 — Unassisted participants** | Five independent first-plan → first-workout → correction → saved result → next-session explanation tasks | FQ-32 | Per-task completion, help, hesitations, exact price/next-session interpretations. |

No fixed video duration is required. Preserve the full relevant transaction, waiting/error states and recovery. A concise index with timestamps is more useful than a long unlabelled montage. Videos alone cannot close privacy, transaction, migration or idempotency assertions.

## 7. Keep the rest of the shipped surface in scope

The focus list sets the order; it does not waive the original QA pack. Before release, map these areas to their existing required cases:

| Shipped area | Minimum attention beyond the focus slice |
|---|---|
| Adaptive engine | Existing rule/parity tests for progression, missing effort, volume adjustments, early/scheduled deload, plateau handling, substitutions and edits. Add a real app-to-engine output check for each changed path. Do not change training thresholds to satisfy a demo. |
| Fuel/body measurements | Known versus missing values; serving/decimal/zero validation; consumed/remaining consistency; save/edit/delete/restart; source provenance. Nutrition formulas are not redesigned here. |
| Photos/body tracking | Pick/cancel/store/compare/delete; local ownership; explicit permitted export only; originals/metadata not uploaded inadvertently. |
| Program/history import and CSV/PDF export | Each shipped format, supported version, invalid input, mapping, duplicate delivery, preview/activation and actual redacted artifact—not just an entry button. |
| Goals/experiments/equipment | Goal-save/update, comparable-evidence eligibility, insufficient-data state, opt-in/cancel, temporary versus permanent constraints and equipment identity. |
| Crew | Each shipped authentication method, ownership/audience, retries, deletion, and applicable moderation/report/block behavior from the actual product scope. No invented “private group” promise. |
| Jev / follow-through | Document off/not shipped if that is true; remove the claim from the release offer. If enabled, use its separate routing/privacy/quality/authorization suite. Confidence never bypasses approval. |
| Spoken coaching/Rive/photo-card variations | Only enabled variants require their extra media/privacy/performance tests; existing basic fallback still works when disabled. |

**Unresolved scope is not N/A.** A feature may be excluded only when it is demonstrably not reachable, advertised or required by another shipped path, with a named release-owner decision. Do not remove tests solely because setup is inconvenient.

## 8. Reporting and acceptance rules

### Test result semantics

- **Pass:** every assertion for the specified case/profile/variant is evidenced on the identified candidate.
- **Fail:** actual result violates an expected assertion; retain evidence before fixes.
- **Blocked:** a required prerequisite or observation channel is unavailable.
- **Not run:** no valid execution occurred.
- **Excluded:** release owner approves a genuine scope exclusion with proof; not a pass.
- A **noncritical waiver** records accepted residual risk and a follow-up owner; it does not turn failure into Pass or waive privacy/data/payment/accessibility blockers.

Do not report a combined “Pass” when one variant only renders a screen and another lacks storage assertions. Retests get a new row linked to the original attempt. Preserve observed values rather than editing them to match prose.

### Required evidence per execution

```text
FQ objective + original case ID(s) + variant + profile
candidate/build/commit/backend/config identity
fixture/reset policy and relevant state revisions
exact steps + expected assertions + actual values
status + tester + timestamp
video/screenshot path + timestamps
record/request/receipt IDs (sanitized)
assertion logs + actual export when applicable
limitations + defect ID + retest linkage
```

Store capture secrets separately; never put reusable account tokens, secret keys, private Health samples or unredacted purchase receipts in the shared handoff.

### Proposed release conditions

- G0's actual candidate/configuration and scope are approved; no simulator/distribution substitution.
- No applicable P0 is Fail, Blocked or Not run in this slice **or the remaining original required scope**.
- No unresolved data loss, duplicate commit, wrong exercise/load, fabricated reported effort, unauthorized action/export, broken paid entitlement or inaccessible essential action.
- Every open Q1 observation is reproduced/resolved or explicitly shown absent on the candidate with equivalent assertions; a script scroll fix alone does not close the UX issue.
- Runtime UI state review is complete on supported boundary profiles/locales; visual approval is independent of functional approval.
- Human tasks are recorded and recurrent critical obstacles resolved. The small study does not prove retention or conversion.
- Release, iOS/data, billing, backend/privacy and QA owners sign; support/monitoring/rollback ownership is declared.

Do not demand a new feature, a new theme or perfect animation as a launch gate. Do not waive a trustworthy core flow just because the screenshots look polished.

## 9. Agent / engineer start instruction

```text
Work only on Regulift's focused QA and UI/UX goals in this document.
Read the existing source and QA evidence before changing code.

First return:
1. Candidate/configuration and release-scope inventory.
2. Mapping of FQ objectives to existing tests/components.
3. Reproduction status for OBS-005, OBS-006 and OBS-007.
4. A keep/collapse/move map for onboarding, Today, logger and result.

Prioritize data-safe logging, explicit correction/cancel, durable saves,
real billing/backend/privacy evidence and accessible fallback controls.
Use the existing native SwiftUI/tokens/engine boundaries.
Do not rewrite training rules, add a model, alter pricing/free access,
or introduce a second styling/navigation system.

For UI: build and show two representative runtime screens at a time.
Use the actual state data or a clearly labeled synthetic fixture.
Include small-screen, large-text, keyboard and error states.
Do not call a mockup, a green automation flow, or an unconfigured service
an end-to-end pass.

After a fix: run its deterministic assertions and the affected original
regression cases, attach evidence, and preserve failed attempt history.
Stop for review before broadening the redesign.
```

## 10. Source notes and verification record

**Q1 — User-provided QA report:** `REGULIFT_QA_RESULTS(1).md`, “Regulift — QA result and launch decision,” revision 2, 21 September 2026. Relevant sections: §1 candidate identity; §2/§3 scope and counts; §4 first-priority regressions; §5 coverage; §6/§9 observations; §7/§8 evidence gaps; §10 unsigned report and proposed setup. The report's terminology and recorded statuses are retained; explicit limitations/corrections are identified above.

**S1 — User-provided skill:** `make-interfaces-feel-better`, “Details that make interfaces feel better.” Relevant principles: existing styling system (line 9); state inspection (line 11); typography/tabular numbers (57–63); minimum hit areas and icons (85–95); motion restraint (97–99); review coverage/verification (120–187). Web-specific examples are not falsely presented as native API requirements.

The following are external primary references consulted **22 September 2026**. They support only the indicated platform/tool guidance, not any claim that Regulift passed a test:

- **[A1] Apple HIG — Accessibility:** adaptable text, contrast, labels, control size/spacing, Reduce Motion. `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/accessibility.json`
- **[A2] Apple HIG — Onboarding:** brief/contextual setup and timing of optional permission/configuration. `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/onboarding.json`
- **[A3] Apple HIG — Settings:** task-specific options versus general preferences. `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/settings.json`
- **[A4] RevenueCat — Sandbox Testing:** Test Store/platform sandbox distinction, pre-launch platform key, sandbox metadata caveats. `https://www.revenuecat.com/docs/test-and-launch/sandbox`
- **[A5] Apple — Auto-renewable subscriptions:** clear renewal price/period, restore/sign-in and terms/privacy. `https://developer.apple.com/app-store/subscriptions/`
- **[A6] Apple HIG — Motion:** purposeful, brief feedback that does not block routine actions. `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/motion.json`

**Deliverable checks performed:** objective count/unique IDs, section references, result-template rows, and file creation were checked locally. **App code, UI automation, device behavior, billing, privacy and usability tests: not executed for this handoff.**

**First two assignments:** release owner provides the real configured candidate; iOS/QA reproduces and closes History draft cancellation and the safe/fallback accessibility issues with visible and stored-state evidence.
