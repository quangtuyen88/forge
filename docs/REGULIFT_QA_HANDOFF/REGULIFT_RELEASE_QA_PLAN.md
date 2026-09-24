# Regulift — Release QA handoff

**Prepared:** 20 September 2026  
**Status:** All tests NOT RUN. The user reports the preceding implementation goals are complete.  
**Purpose:** Validate the actual release candidate, reveal remaining UI friction, and return evidence for a defensible launch decision. This is not a new feature roadmap.

## 1. Start here

This pack contains **216 test cases**, **263 proposed case/profile execution rows**, **17 UI workflows**, and a **33-case first-pass smoke subset**. Matrix rows are planned runs, not completed tests. Some multi-variant cases need extra rows; the numbers are not an exhaustive Cartesian product or a claim of total system coverage.

Read this file, complete `release_manifest.json`, run the smoke subset, then execute the applicable full suite. Use `REGULIFT_TEST_CASES.md` for steps and acceptance, `REGULIFT_UI_WORKFLOWS.md` for recordings, and `REGULIFT_QA_TRACKER.xlsx` for results. Finish `REGULIFT_QA_RESULTS_TEMPLATE.md` and return the evidence folder structure below.

**Do not write “all features passed” because all screens opened.** A Pass needs the expected UI outcome and the required data/network/payment assertion. A programmer checking a goal checkbox is implementation evidence, not a replacement for executing the release tests.

### What changed from the earlier handoff

All 62 audit acceptance cases are retained as AU-01–AU-62. All 46 Share Cards cases are retained as SC-01–SC-46, and all 28 Jev cases as JV-01–JV-28. Remaining cases are proposed coverage extensions for already shipped capabilities, releases, failure paths and UI evaluation. Every source case has a direct ID mapping; no original case is silently dropped.

## 2. Freeze scope before QA starts

Fill the manifest with actual app/build/commit, backend/rules/schema/flag versions, supported OS/hardware, offered products/prices, and account/cloud permissions. Do not assume an iOS/watchOS version, live provider, paid SKU or launch flag from an older roadmap. Record which features are reachable, advertised, disabled, shadow-only or locale-limited.

| Applicability | Meaning |
|---|---|
| Required | Feature/variant is shipped or advertised in this release; execute all assigned profiles. |
| Review | Scope unresolved; this prevents a final readiness decision. |
| N/A | Not shipped/supported, with reason, owner approval and evidence of disabled entry point/advertising. A failing or untestable feature is NOT N/A. |

CORE and PAID are required for the described paid launch. Other gates start at Review until the release owner maps them to the real flags. Do not hide a failed user-visible feature by changing a workbook cell. An actual scope change needs a new candidate/config review, user-facing metadata consistency and regression tests of the disabled path.

| Gate | Scope rule |
| --- | --- |
| CORE | Required core workflow, data correctness, accessibility, privacy or release control; never N/A merely because a bug blocks it. |
| PAID | Required for the paid launch described by the user. Freeze actual products, storefronts, access and offline/expiry policy; do not reuse old draft prices. |
| COACH | Required whenever the Coach is reachable/advertised; cloud-disabled variants still need local/fallback tests. |
| VOICE | Required for each advertised voice capture/parser route; map local and cloud paths separately. |
| APPLE_SURFACES | Resolve per advertised widget/Live Activity/Siri/notification surface. Split variants; do not waive all because one surface is unsupported. |
| SPOKEN_COACH | Conditional on shipped event narration or spoken Coach; no assumption that dictation includes audio output. |
| WATCH | Required if Watch is included/advertised; otherwise N/A only with owner-approved exclusion and listing/build evidence. |
| SYNC | Required for enabled account sync, including guest merge and account isolation. |
| AUTH | Required for every offered sign-in provider and account-owned endpoint. |
| CREW | Required if reachable/advertised; include actual audience and content-safety operations. |
| SHARING | Required for existing workout/program sharing when shipped, independently of Share Cards v2. |
| SHARE_V2 | Conditional on v2 core and individual template flags. Preserve ordinary sharing tests even when off. |
| SHARE_NEXT | Conditional on reviewed next-target export flag; no pressure to turn it on for launch. |
| SHARE_PHOTO | Conditional on Photo look; local/external tests only unless Photo-to-Crew is separately enabled. |
| SHARE_CREW | Conditional on card attachment to Crew; authenticated publication/media authorization required. |
| SHARE_PHOTO_CREW | Conditional on Photo-to-Crew, independent from ordinary auto-post and local Photo export. |
| JEV | Conditional on off/shadow/enabled by locale. Shadow cannot mutate; live locale evaluation required only for enabled routes. |
| JEV_FOLLOWUP | Conditional on the single shorter-session follow-through loop; not an assumed shipped feature. |
| FUEL | Required for enabled nutrition surfaces; test current formulas, not invent a new nutrition policy. |
| PROGRESS_PHOTOS | Required for enabled private photos; separate from selected share backgrounds. |
| GOALS | Required for enabled goal types; map actual supported types. |
| EXPERIMENTS | Required for enabled experiments; outcomes use their approved evidence rules. |
| TIMELINE | Required for shipped timeline, notes and hide/restore. |
| PROGRAM_IMPORT | Required for offered plan import/activation/redacted sharing; not the same as workout-history import. |
| HISTORY_IMPORT | Required for advertised Strong/Hevy/CSV formats; enumerate real supported versions. |
| EXPORTS | Required for offered CSV/PDF reports; inspect actual exported files. |
| ADVANCED_SETS | Required for each offered drop/rest-pause/myo-reps mode; split and document any not shipped. |
| CUSTOM_EXERCISES | Required when custom exercise creation is offered. |
| GROWTH | Only actually shipped milestones, challenges and referral features; not a demand to build new ones. |

An aggregate case covering several surfaces (e.g. AU-59) must get one execution row per materially different surface when outcomes differ. A locale/model feature can be off while app-language support remains on. Enabled subpaths are required; unsupported subpaths need explicit evidence, not a blanket skip.

## 3. Test environments and roles

**Manual/device QA** owns screen flows, permissions, actual exports, audio, accessibility and usability. **iOS/engine QA** owns snapshot/receipt/provenance assertions, migrations, replay and fault injection. **Backend/security QA** owns staging authorization, token expiry, owned media, deletion and decoded payload/log inspection. **Billing QA** owns configured StoreKit/RevenueCat integration. Product/release owners resolve the behavior oracle before a test, not after a failure.

Use a release-like distribution build for visual and end-to-end flows. Test-only fixture/fault adapters may exist in an internal build; record that difference and separately prove the production archive excludes those controls. Use dedicated synthetic accounts and safe staging endpoints. Never run destructive, load, purchase or security tests on real customer data without separate authorization.

### Profiles

| ID | Required setup |
|---|---|
| BASE | Representative supported real iPhone; release-candidate distribution build; English; kg; normal text; dark; stable network. Repeat smoke in light appearance. |
| SMALL | Smallest supported iPhone layout on the minimum supported OS; physical device for critical workflow. Record exact model/OS; screenshot-only simulator checks supplement, not replace. |
| LARGE_TEXT | Smallest supported layout at largest supported accessibility text; native keyboard; test essentials in light/dark. Record exact text-size setting. |
| JA | Japanese app language with a fluent reviewer; Japanese region/date input; supported real phone; applicable provider-locale flag recorded. |
| KO | Korean app language with a fluent reviewer; Korean region/date input; supported real phone; applicable provider-locale flag recorded. |
| REGION | English app language with decimal-comma region and lb, plus EN-US comparison; use test timezone boundaries including DST without assuming user location. |
| OFFLINE | Real device in airplane mode; test fresh permissions and documented cached entitlement; begin without cloud model/network and reconcile when restored. |
| VOICEOVER | Real iPhone, VoiceOver enabled and audio captured; test reading/interaction order, adjustable controls, status announcements and Reduce Motion. |
| WATCH | Supported paired phone and real Watch; record exact OS/model; connected, disconnected and later sync; include supported standalone behavior. |
| BILLING | Dedicated StoreKit/sandbox/TestFlight test identities with exact environment recorded; real device integration plus local StoreKit fault simulation. |
| PRIVACY | Synthetic staging accounts; approved decoded-payload inspection/local adapter assertions; sanitized app/backend/provider diagnostics; no real Health or personal data. |
| SLOW_DEVICE | Oldest/slowest supported real iPhone with minimum supported OS and large-history fixture; profile memory, energy, rendering and network failures. |
| USER_STUDY | Five consenting target lifters; isolated synthetic or voluntarily created test data; their familiar supported device where practical; no physical lifting required. |

### Matrix application

Run full applicable behavior on BASE. Run the core first-to-second-workout flow on minimum supported OS/smallest layout and newest supported stable OS/largest supported layout. Repeat critical UI in light and dark appearances. For every advertised locale, run onboarding → log/edit → save → History → Coach → paywall and all localized qualifiers; assigned rows plus workflow coverage are the minimum.

Keep separate rows for actual devices/variants; copy an execution row with a unique run ID and record environment in evidence. A BASE Pass does not automatically pass SMALL, WATCH, offline or another locale. At least one actual device is required for audio/Watch/system permission/payment-integration claims. Simulator or mocked results must be labeled as such.

## 4. Fixtures and independent oracles

The following are **synthetic test values, not training or nutrition advice**. No need to lift the stated loads. UI tests can be performed stationary. Engineer-provided seeded stores and mock responses are not production data.

| Fixture | Setup and independent expectation |
|---|---|
| F0 — Fresh / empty | Isolated fresh install, no workouts, optional account absent, no week configured. Permissions reset; explicit release-entitlement route. Preserve separate fixture for app upgrade, not uninstall it. |
| F1 — Controlled workout | Current session Upper A with barbell Bench, target 60 kg x 8 for two working sets, target RPE 8; include other planned work for partial finish. Reported effort initially null. Rest/completion times injected only in harness variants; real-device timing tested separately. |
| F2 — Cross-exercise regression | Full C with active Lunge bodyweight / zero added load; Deadlift not current. Typed command deadlift 60x8 @8. Deadlift bar 20 kg; plates per side available 20,10,5,2.5,1.25 kg. Freeze extra-set-versus-new-prescription policy. |
| F3 — Eligibility boundaries | Engineer supplies versioned eligible/ineligible/unknown fixtures immediately below/at/above CURRENT plausibility caps, intervals and verification rules. Approved expected selector output saved before test; no fabricated universal thresholds. |
| F4 — History and week | Synthetic zero/one/mature history, one saved 60 kg x 8 set, actual versus eligible ledger, explicit completed and planned commitments. Include rest, missed, empty week, two distinct same-day sessions, starting targets and real changes. Preserve source revisions. |
| F5 — Food and measurement | Body measurement 82.5 kg. Custom food 100 g and 380 kcal; nutrition fields defined in fixture JSON by product owner. Day target 2,752 kcal, so after this sole entry 2,372 remain. This is test arithmetic, not a recommended calorie target. |
| F6 — Equipment and variants | Barbell with explicit total load/bar inventory; per-dumbbell pair, machine stack A/B, bodyweight and assisted variants. Distinct identity/convention. Freeze supported supersets/drop/rest-pause/myo-reps and approved counting/comparator policies. |
| F7 — Program/history imports | Actual supported-format synthetic one-day plan, zero/missing/old source timestamps per schema, malformed files, unsupported versions, Strong/Hevy CSV inputs, overlapping rows, unmapped exercises and unit variants. Source checksums and expected row-mapping ledger required. |
| F8 — Card/photo sources | Saved eligible normal session, multiple PRs, first best, e1RM, missing RPE, invalidated comparator, week with/without denominator, committed/pending/restricted next target. Synthetic local and cloud-only photos with distinct A/B visuals and known EXIF/GPS canaries. |
| F9 — Coach/Jev | Synthetic known ProgramDecision with reviewed workout-only projection; separate Health-dependent local reason; unknown birthday; ambiguous weight question. Mock provider responses, deadlines, malformed answers and labeled routing corpus. Model access never assumed. |
| F10 — Voice/audio | Consented test recordings with exact expected transcript/slots per supported locale; silence, noise, interruptions and rapid cancel. No need to lift real weights; commands tested while stationary. Record local/cloud provider and actual permissions. |
| F11 — Accounts/social/sync | Staging identities A owner, B follower, C outsider; guest has separate local data. Existing audience/merge/transfer policy frozen. Separate expired tokens and pending upload/delete states; no real users or production destructive requests. |
| F12 — Payments | Dedicated Store sandbox accounts and local StoreKit simulations; exact actual product IDs, currencies, offers, groups, grace and expiry/cached-access policy. Never share passwords, store receipts, private keys or production payment identifiers in review package. |
| F13 — UI/accessibility | All important states, long EN/JA/KO names, max plausible numeric labels, normal and accessibility text, keyboard, light/dark, VoiceOver and Reduce Motion. Capture both semantic controls and final exported images. |
| F14 — Watch/system | Actual supported phone/Watch pair, cached session, connected/disconnected events, two different events plus a repeated ID, old widget/activity/action context. Freeze canonical merge/authority policy before testing. |
| F15 — Privacy/security | Unique synthetic canaries e.g. QA_PRIVATE_HEALTH_C42 and QA_PRIVATE_NOTE_N17 in source fields, derived/control-flow decisions, nested error metadata, captions, caches and diagnostics. Instrument test adapters and authorized staging requests; never real medical records. |
| F16 — Performance | Fresh and representative mature/high-volume synthetic stores. Record dataset sizes, repeats, network condition and preapproved p50/p95/memory/energy budgets on slowest supported real hardware. No post-hoc threshold changes. |
| F17 — Follow-through | Confirmed shorter-session receipt linked to exactly one workout; canceled receipt, duplicate completion, dismissed/expired/deleted issues, structured and free-text feedback. No inferred satisfaction or permanent preference. |
| F18 — Engine oracle | Versioned expected snapshots/output vectors signed off by engine owner before QA. Include progression, missing effort, volume, deload, lock, plateau, no-change, unavailable and idempotent replay. QA must not derive expected values solely by rerunning the same production function. |
| F19 — Migration/recovery | Sanitized real previous-schema store copies with active session, null/legacy RPE provenance, pending outbox/receipts and private data markers. Backup and restore procedures; deliberately broken copies only in isolated test container/device. |
| F20 — User study | Five consenting target lifters; record training/app familiarity, device and language without unnecessary identity. Give scenario U1 only. Use safe seated/stationary input rather than an actual maximum-effort workout. |

### Fixed arithmetic spot checks

- `60 kg × 8 = 480 kg` contribution for one ordinary barbell set; editing to 9 gives `540 kg`. Whole-workout aggregates can differ by declared inclusion policy; do not compare unlike scopes.
- Target RPE 8 with no reported effort must preserve reported `null`. One explicit report of 8 plus one missing report means mean 8 over **one** report, coverage 1/2—not two reports.
- Total barbell target 60 kg, bar 20 kg: `(60 − 20) / 2 = 20 kg per side`. Bodyweight Lunge has no default 20 kg bar.
- Fixture calorie total: `380 + 2,372 = 2,752`. This validates display arithmetic only.

For training, nutrition, completeness, comparability, period boundaries, entitlement/grace, and migration policy, obtain a signed expected-output fixture from the owner. Never invent load changes, fatigue windows, RPE defaults or exact trial durations. Do not simply compare one UI to another UI powered by the same potentially wrong selector. Missing oracle → **Blocked** and specify what is needed.

Use realistic/timestamped fixture logs when testing eligible metrics. Keep deliberately rapid synthetic sets in F3 separate; they should hit plausibility policy, not mysteriously fail a PR test. Any injected-clock run is labeled, and real timer/background behavior has separate device evidence.

## 5. Run order

### A — Scope and smoke

Execute this subset first; it locates stop-ship problems without asking QA to record every advanced tool before a valid workout exists:

AU-01, AU-03, AU-05, AU-06, AU-07, AU-08, AU-09, AU-12, AU-14, AU-16, AU-17, AU-19, AU-23, AU-24, AU-25, AU-28, AU-46, AU-47, AU-49, AU-50, AU-53, AU-55, AU-60, AU-61, WK-10, PY-01, PY-03, SA-03, SA-05, RC-01, RC-02, RC-03, UX-08

Stop release promotion on data loss, cross-exercise values, fabricated effort, unauthorized access/upload, incorrect billing access, duplicate committed action, or an unusable essential control. Preserve evidence and fix/retest; continue unrelated low-risk tests only when the environment remains trustworthy.

### B — Main product flows

Record W01–W05, W07 and W12. Run applicable data/engine/workout tests, not only their visible happy paths. W03 and W14 must demonstrate force-kill/resume and at least one failed adaptation after a successful save.

### C — Advertised integrations

Record W06, W08–W11 and W13 where enabled. Run each purchased product and real restoration path. Inspect actual share/CSV/PDF bytes. Use actual Watch/audio surfaces; opening settings is not evidence of their operation.

### D — Conditional model and card enhancements

Run the enabled SC/JV cases. Leave Jev off/shadow if its evaluation or pre-upload privacy gate is unresolved. Do not delay the reliable core app merely to enable optional features; do not label an enabled unsafe feature optional to evade testing.

### E — Release evidence and visual review

Finish W14–W16, screen-state inventory and U1/W17 usability review. Recheck the exact final distribution build. A later binary/backend/rules/flag change invalidates affected results until impact-based regression and the mandatory smoke are rerun.

## 6. Result rules: keep uncertainty visible

- **Not run:** No execution evidence yet.
- **Pass:** Required assertions match on the identified candidate/profile, with evidence; all required variants complete.
- **Fail:** An expected result differs; record actual result and defect ID even when the screen looks acceptable.
- **Blocked:** Missing environment, fixture, permission, oracle, provider access or prerequisite; no claim of Pass.
- **Waived:** A documented noncritical failure deferred by release owner with reason/workaround/expiry. Not a pass. Never waive P0 data/privacy/auth/payment correctness or inaccessible essentials.
- **N/A is applicability, not a pass status.** Use reason and reviewer; preserve past failed attempts in run history.

Test priority is not observed defect severity. **P0** tests protect release-critical invariants, **P1** validates shipped capability/usability, **P2** is cosmetic. Severity: **S0** privacy/security exposure or widespread destructive loss; **S1** wrong data/payment/action, core task blocked or deterministic crash; **S2** meaningful but recoverable usability/function failure; **S3** minor cosmetic issue. One severe failure is not diluted by many passing rows.

## 7. Evidence contract

Each test/run must identify case ID, profile, exact build/config, fixture version/reset behavior, steps, expected versus actual, tester/time, attachments and defect/retest links. Keep final attempts and prior failures; never overwrite the only evidence of a failure.

### Recording instructions

Start with a short slate (run/workflow ID, build, device/OS, locale/units, account/permissions). Record normal speed with legible UI. Use touch indicators only if available; do not obscure content. Pause briefly at important states. Keep each scenario uninterrupted; explicitly mark every reset, seeded scenario, intentional kill and injected fault. A long feature montage without labeled boundaries is insufficient.

Capture original audio for voice/narration/VoiceOver; attach a human observation for haptics and hardware behaviors recording cannot capture. When sound is unavailable, mark audio assertions Blocked instead of claiming success. Do not require QA to physically perform heavy exercise.

### Screenshots needed for visual review

For Today: empty, ready, resume, rest, missed and complete. For logger: untouched effort, explicit effort, corrected set, rest, cross-exercise receipt and correct plate sheet. For result: normal, partial and pending adaptation. For Progress/Timeline: fresh, one-session, mature, grouped change, edit and hide/restore. For Coach: initial, keyboard, grounded reply, clarification, preview and timeout. Include paywall, restore, important permission disclosures, Fuel validation, key settings, plus each enabled share template/look/format. Repeat critical first viewports in light/dark and small/large text; include JA/KO when advertised.

### Evidence beyond video

Attach unit/integration/UI test result summaries and relevant `.xcresult` or equivalent privately as appropriate; synthetic exported PNG/JPEG/CSV/PDF; sanitized request/assertion logs; receipt/metric ledgers; migration and performance reports. A TLS packet listing or empty console alone cannot prove no sensitive export. Inspect approved decoded test requests plus server/provider logging and state what was not observable. Keep credentials, access tokens, raw receipts, full production database dumps and real Health/private photo data out of the return bundle.

## 8. Return package

```text
REGULIFT_QA_RESULTS_<build>_<date>/
  release_manifest.json                 filled, including flags and supported matrix
  REGULIFT_QA_TRACKER.xlsx               results, evidence paths, defects, scope approvals
  REGULIFT_QA_RESULTS_TEMPLATE.md        renamed/filled executive result
  videos/W01_BASE_<build>.mp4            separate named workflows/variants
  screenshots/<case>_<profile>_<state>.png
  exports/<case>_<profile>_<artifact>    actual synthetic assets, not just previews
  assertions/<suite>_<build>.txt         expected/actual counts and test output
  diagnostics/                         sanitized traces and limitations
  defects/DEFECT-001.md                  reproducible issue with links
  usability/participant-P01.md           anonymous, consented study notes
  retests/                              previous defect -> fixed build -> new evidence
```

Use ordinary relative evidence paths so files resolve after ZIP extraction. Videos may be separate uploads when the archive is too large; keep the same manifest names. Return one short highlight clip only as an addition, not instead of case evidence.

## 9. Go/no-go

The tracker is a coverage assistant, **not an automatic release certificate**. No release while scope is unresolved, a required P0 case is Not run/Blocked/Fail, a required variant is missing, or a confirmed S0/S1 is open. Required enabled-feature P1 cases must Pass or have an explicit noncritical signed waiver; an unknown result is not waivable evidence. Optional features may be disabled through a reviewed actual configuration and their disabled paths tested.

A Pass for functional test counts does not prove visual usability. Review the W12 screen set and five-user formative notes. Repeated confusion over target versus logged values, inability to correct a set, or inability to find Start/Save/Restore needs triage before promotion. Cosmetic spacing or optional animation can be deferred with an owner; no new design system is required.

Release owner signs a final decision after QA, engine/data, privacy/backend and billing owners review their evidence. App Review approval, training efficacy and medical safety are separate matters and are not established by this pack.

## 9A. Conditional source-specific release checks

These preserve the prior feature specifications, not new requirements to enable optional work. When the implemented product deliberately differs, record the approved contract change before testing instead of silently changing the expected result.

### Share Cards v2 (S2), only for enabled formats/looks

The source spec proposes Square 1080 × 1080 and Story 1080 × 1920; opaque sRGB PNG for Clean and JPEG for Photo. Inspect dimensions, MIME/extension agreement, actual encoded pixels and absence of private metadata. Essential labels such as Estimated 1RM, Planned — not completed, units and load convention remain legible in each enabled locale. Final reviewed asset must match delivered content. Next-target disclosure, Photo and Photo-to-Crew each have separate consent/feature gates.

S2's proposed measurement budgets: Clean render p95 under 1 second; Photo under 2 seconds after the selected asset is locally available; start with an 8 MiB output ceiling subject to existing Crew limits and incremental render memory target under 64 MiB. These are product targets, not platform guarantees. Record the actual preapproved budget and any written revision before testing. Cloud-photo retrieval time is measured separately, not hidden in render latency.

### Jev (S3), only for enabled routing locales

Keep off/shadow when the data-flow gate or evaluation is unresolved. Structured follow-up buttons need no model call. Retain the current parser for complete known commands. One inference at most per eligible unresolved user turn; no inference on timer ticks or every logged set. The exact actual provider model, question-set and policy versions are part of the candidate identity.

S3 proposes at least 150 calibration and 300 held-out examples per enabled locale, with paraphrase groups kept on one side of the split. Score the actual approved wire projection, not only original text. Its proposed launch gates are: no unauthorized mutation or prohibited export in tests plus architecture review; at least 98% routed-interpretation point precision, 95% Wilson lower bound at least 95%, and at least 100 routed held-out examples per locale; at least 40% useful coverage of cloud-eligible previously unresolved requests; and at least five percentage points better correct-next-step selection than the existing route. Report denominator, confidence interval, abstention/fallback and errors separately. These are acceptance targets from S3, not measured performance or proof of universal privacy.

The source's initial timing targets are a 1.5-second Worker inference deadline and 2.5-second end-to-end wait budget. Record the configured measured budgets rather than promising them as vendor SLAs. A locale that does not pass retains its existing route; it does not lose app-language support. A timeout, unknown model version or missing provider access is not a reason to upload blocked information elsewhere.

## Source and requirement provenance

- **S1 — REGULIFT_E2E_VIDEO_REVIEW_GOAL.md**, 20 September 2026: G00–G18, acceptance T01–T62 and release definition. AU cases preserve every original expected outcome. The user now reports this goal completed; the earlier video is not evidence of the new build.
- **S2 — REGULIFT_SHARE_CARDS_V2_GOAL.md**, 20 September 2026: §13 T01–T46, selected-field/privacy policy, feature flags and staged rollout. SC cases preserve the outcomes; enable only the shipped subset.
- **S3 — REGULIFT_JEV_GOAL.md**, 20 September 2026: §13 AT-01–AT-28, §12 per-locale evaluation and §14 flags. JV cases preserve outcomes; planned work is not presumed enabled.
- **S4 — FORGECORE_INTEGRATION.md**, 20 September 2026: local engine boundary, real decision evidence, exact-preview consent, idempotency, Health export policy and migration. Repository names remain unverified.
- **S5 — OVERVIEW(1).md**, 17 September 2026: documented product surfaces. Old free-launch/pricing details are superseded by the release manifest; do not freeze draft prices from that file.
- **Q — Proposed release-coverage additions** in this handoff: expanded steps, fixture data, priorities, matrix selection, workflow scripts, qualitative UI checks, additional cases and evidence/go-no-go process. These are not claims of newly found bugs or newly required features. Thresholds/budgets must be agreed before testing.

### External platform references checked 20 September 2026

These references inform the listed platform checks only. The user-provided specifications remain the source of product behavior. This is not an App Review or legal-compliance certification.

- **A1 — App Review Guidelines**, especially completeness, truthful metadata, UGC and privacy/third-party AI disclosures. Use for release review, not invented training requirements. `https://developer.apple.com/app-store/review/guidelines/`
- **A2 — Auto-renewable Subscriptions**: clear billed price/period and access to restoration. `https://developer.apple.com/app-store/subscriptions/`
- **A3 — StoreKit sandbox testing**: distinguish local simulations from account/backend integration and label the test environment. `https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox`
- **A4 — RevenueCat Sandbox Testing**: use the actual configured test environment and record differences from production rather than treating a simulated purchase as production proof. `https://www.revenuecat.com/docs/test-and-launch/sandbox`
- **A5 — Offering account deletion**: distinguish deleting app data/account from ending a store subscription. `https://developer.apple.com/support/offering-account-deletion-in-your-app/`
- **A6 — Apple accessibility guidance**: verify usable controls, adaptive text and assistive interaction on actual targets. Proposed quantitative UI targets in Q are not a certification. `https://developer.apple.com/design/human-interface-guidelines/accessibility`
- **A7 — HealthKit authorization**: missing samples are not a trustworthy indicator that read access was granted or denied; test both without inventing data. `https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data`

