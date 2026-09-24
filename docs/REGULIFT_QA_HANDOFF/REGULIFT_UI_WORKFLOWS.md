# Regulift — UI workflows and recording script

**Status: NOT RUN.** These 17 workflows organize evidence; they do not replace detailed assertions in the test catalog. Feature-gated steps execute only when supported, but require a recorded scope exclusion when not shipped. No passwords, real Health data or customer information in recordings.

## Workflow index

| ID | Workflow | Scope |
|---|---|---|
| W01 | First install → clear plan → first set | CORE |
| W02 | Complete workout, correction and explicit exercise context | CORE |
| W03 | Saved result → interruption recovery → next workout | CORE |
| W04 | Week states → move/miss → constraint → imported plan | CORE / PROGRAM_IMPORT |
| W05 | Ordinary Coach → ambiguity → preview → failure | COACH |
| W06 | Voice and audio with sound + understandable settings | VOICE / SPOKEN_COACH |
| W07 | Progress, History and Timeline as a coherent record | CORE / TIMELINE |
| W08 | Fuel, measurements, equipment, goals and import/export | According to feature manifest |
| W09 | Card editor → exact image → cancel/export → Crew attachment | SHARING / enabled SHARE_* |
| W10 | Account, guest merge and Crew audience | AUTH / SYNC / CREW |
| W11 | Paid launch purchase and entitlement lifecycle | PAID |
| W12 | Accessibility and UI state review | CORE / each enabled surface |
| W13 | Watch and actual Apple system surfaces | WATCH / APPLE_SURFACES |
| W14 | Failure, privacy, migration and backend assertions | CORE / applicable backend feature |
| W15 | Jev optional routing and follow-through | JEV / JEV_FOLLOWUP |
| W16 | Release candidate and operational sign-off | CORE |
| W17 | Unassisted target-user usability study | CORE |

## W01 — First install → clear plan → first set

**Purpose:** First-run, permissions and clear Today hierarchy  
**Fixtures:** F0 / F1  
**Gate:** CORE  
**Related cases:** AU-01–04, UX-01

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Start with build slate and empty profile. | Show app/build, exact device/OS, locale, units, entitlement route and fixture-reset boundary. |
| 2 | Complete onboarding; skip optional photo/lifts. | Starting loads visibly estimates where appropriate; no recorded lift history invented. |
| 3 | Deny Health and notification permission, then continue. | Manual training still reachable under actual access policy; no permission trap. |
| 4 | Inspect plan recap and first Today screen without scrolling. | Goal/days/equipment correct; one clear Start or relevant state-specific action. |
| 5 | Start workout and log one manual set. | Exercise, units, target and actual values distinct; saved receipt/state visible. |
| 6 | Reopen settings/profile. | Onboarding selections persist; no forced second questionnaire. |

**Also attach:** First-run and Today screenshots in light/dark; permitted local plan snapshot; recorded permission states.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W02 — Complete workout, correction and explicit exercise context

**Purpose:** Workout clarity and strongest earlier regressions  
**Fixtures:** F1 / F2 / F6  
**Gate:** CORE  
**Related cases:** AU-05–15, WK-01–12, UX-02

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Show starting plan and F1 target RPE without entering reported effort. | Capture target and null reported fields before logging. |
| 2 | Log a missing-RPE set and an explicit @8 set; edit/cancel/undo a mistake. | Only explicit effort contributes to mean; correction affects correct record. |
| 3 | Enter Focus Mode; log, rest, skip/extend, use a supported superset. | Current exercise and timer ownership remain clear; all controls usable. |
| 4 | Switch to labeled F2 scenario boundary with Lunge active; type deadlift 60x8 @8. | Receipt names Deadlift without contaminating Lunge. |
| 5 | Open Plates before and after Go to Deadlift. | No Lunge/60 kg/bar-20 hybrid; Deadlift 60 kg has 20 kg per side with 20 kg bar. |
| 6 | Try a bodyweight set, then finish a partial session. | No bar invented; partial work retained; no forced completion of prescribed volume. |

**Also attach:** Actual RPE/source records and utility context; screen video. Label fixture transitions; do not hide reseeding.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W03 — Saved result → interruption recovery → next workout

**Purpose:** Data reliability and the adaptive product loop  
**Fixtures:** F1  
**Gate:** CORE  
**Related cases:** AU-14,16–20, WK-10, EN-10, UX-03

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Log one set, background and force-terminate without resetting. | Identify intentional kill; show resume restores exact observation. |
| 2 | Resume, finish early and show result. | Saved work leads; duration consistent; user can leave without sharing. |
| 3 | Open History and next prescription, then the actual Why explanation. | Observed/estimated/planned values and evidence are distinct. |
| 4 | In a separate labeled fault run fail adaptation after workout save. | UI says saved/update pending; original workout remains visible. |
| 5 | Restart and recover adaptation; replay completion. | Exactly one intended update and receipt; no duplicate set/PR. |
| 6 | Advance controlled date/start the next workout. | Current committed plan and true Start/Resume state shown. |

**Also attach:** Saved observations and update receipts, fault point, before/after screen states; no cloud-dependent log save.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W04 — Week states → move/miss → constraint → imported plan

**Purpose:** Planning clarity and active source consistency  
**Fixtures:** F4 / F6 / F7  
**Gate:** CORE / PROGRAM_IMPORT  
**Related cases:** AU-24–32, EN-03–07

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Show empty, rest, ready, resumed and completed week in explicitly separated fixtures. | No green 0/0 success; actual next date and state-appropriate action. |
| 2 | Move a future workout; cancel then approve reviewed changes. | Only intended schedule changes; completed facts unchanged. |
| 3 | Handle a missed workout and shorten a session. | Tradeoffs/constraints explicit; no hidden compression or permanent preference. |
| 4 | Analyze an imported one-day plan without activation. | Current plan unchanged; parser errors actionable. |
| 5 | Activate once; open Today, roadmap, logger and Coach without reset. | Same active source/version across all consumers. |
| 6 | Reopen after kill and retry activation. | No duplicate activation or loss of logged work. |

**Also attach:** Plan/version/commit ledger, old/new schedules, recorded Today states and imported fixture checksum.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W05 — Ordinary Coach → ambiguity → preview → failure

**Purpose:** Grounding, clear actions and conversational recovery  
**Fixtures:** F9  
**Gate:** COACH  
**Related cases:** AU-46–50, UX-05

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Show existing cloud/local processing consent and actual context. | No implicit permission or private context projection. |
| 2 | Ask an ordinary question about a saved workout change. | Answer matches actual decision; source/freshness available where needed. |
| 3 | Ask Why did my weight drop? in ambiguous fixture; resolve it. | Useful clarification before unsupported explanation. |
| 4 | Ask unknown birthday and a bounded instruction-extraction example. | Plain unknown response and no privileged disclosure. |
| 5 | Request supported change; reject first, approve a fresh preview second. | Nothing applies on reject; exact current diff and one receipt on approval. |
| 6 | Inject timeout; retain draft and retry. Then invalidate a preview with a new set. | No lost text, late modal, fake applied state or stale approval. |

**Also attach:** Sanitized synthetic transcript, allowed tool-call trace and proposal/receipt IDs; no real private prompt content.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W06 — Voice and audio with sound + understandable settings

**Purpose:** Actual speech behavior not provable in silent video  
**Fixtures:** F10  
**Gate:** VOICE / SPOKEN_COACH  
**Related cases:** AU-51–52, VS-01–04, WK-09, UX-06

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Show effective app/recognition language, capture provider, cloud consent and model status. | Reviewer can tell where the next request is processed. |
| 2 | Speak known command at rest; capture screen and original audio. | Compare exact transcript, units/RPE slots and correct saved exercise. |
| 3 | Test silence, noise, mic denial, timeout and cancel with delayed result. | Each state named; no phantom set; manual fallback available. |
| 4 | Use supported rest command and timer; background and return. | Correct deadline and owner; no stale completion alert. |
| 5 | When narration is enabled, trigger committed target and rest cues over music. | One current cue; mute, call and Bluetooth handling documented. |
| 6 | Disable cloud permission and retry an unavailable-local-model path. | No forbidden cloud fallback; accessible localized error. |

**Also attach:** Video MUST include sound for spoken features; add human note for haptics and OS/mic limitations.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W07 — Progress, History and Timeline as a coherent record

**Purpose:** Scope consistency and readable hierarchy  
**Fixtures:** F4  
**Gate:** CORE / TIMELINE  
**Related cases:** AU-19–23,42–45, EN-08, FD-07, UX-04

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Show zero-workout, one-workout and mature Progress states. | Useful state first; missing data not fake zero or trend. |
| 2 | Compare declared same-scope metrics with fixture ledger. | Recorded/eligible/planned counts accurately labeled. |
| 3 | Edit 60 kg x 8 to x9 then reopen affected views. | 540 kg contribution wherever this set is counted; correct eligibility refresh. |
| 4 | Open Timeline initial group and one real change. | Initial targets not counted as improvements; source links correct. |
| 5 | Create private note, hide one selected item, undo and restore. | Only visibility changes; no anonymous global Hide choices or note export. |
| 6 | Return from advanced report/filter/month. | Scroll/selection retained; row swipe and bottom actions readable. |

**Also attach:** Side-by-side metric ledger with revisions; before/after screenshots and Timeline interaction recording.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W08 — Fuel, measurements, equipment, goals and import/export

**Purpose:** Secondary features remain usable and truthful  
**Fixtures:** F5 / F6 / F7  
**Gate:** According to feature manifest  
**Related cases:** AU-33–41, FD-01–08, WK-07

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Create the synthetic custom food; test invalid then correct serving values. | Neutral initial state, field-specific error and exact totals; no missing-to-zero assumption. |
| 2 | Save 82.5 kg body weight and reopen list/chart after kill. | Persisted value and dashboard refresh agree. |
| 3 | Review equipment setup, rename and change convention separately. | History comparability follows identity; task before long explanation. |
| 4 | Create goal and inspect experiment with insufficient data. | Next qualifying action clear; no premature success. |
| 5 | Import Strong/Hevy synthetic fixtures and inspect row mapping. | Missing RPE/unit/overlap handled under current format policy. |
| 6 | Export actual CSV/PDF; inspect files and private-photo pick/delete separately. | Selected fields/ranges correct; private assets remain local. |

**Also attach:** Actual sanitized input/output files, numerical ledger, photos/metadata checks and subfeature recordings.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W09 — Card editor → exact image → cancel/export → Crew attachment

**Purpose:** Sharing polish without changing training or disclosure  
**Fixtures:** F8 / F11  
**Gate:** SHARING / enabled SHARE_*  
**Related cases:** AU-53, SC-01–46

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Enter from saved summary and History; choose Top Sets, Personal Best, My Week when enabled. | Correct source/defaults and missing-template states; Done still independent. |
| 2 | Switch square/story; hide personal fields; inspect optional caption. | Hidden stays hidden everywhere; estimated/planned qualifiers intact. |
| 3 | Edit source during preview; then prepare a current final asset. | Old preview invalidated; no silent replacement. |
| 4 | When enabled choose photo A then B; crop/remove, test loading error. | Only current selection; no implicit progress-photo access or media upload. |
| 5 | Cancel share once; repeat and save actual final image through test destination. | Training unchanged; approved bytes/pixels delivered; no false public-post claim. |
| 6 | For enabled Crew attachment, review actual identity/audience and explicitly post/retry. | One authorized publication; no auto-photo upload or private-audience assumption. |

**Also attach:** Final PNG/JPEG and optional caption, metadata dump, private-field assertions, publication receipt and no-reset video.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W10 — Account, guest merge and Crew audience

**Purpose:** Access control and social trust  
**Fixtures:** F11  
**Gate:** AUTH / SYNC / CREW  
**Related cases:** AU-54, SA-01–07, FD-08

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Create guest data; sign in by each offered provider in separate variants. | Cancel/fail works; local data handled under approved merge policy. |
| 2 | Open Crew as A, B and C with actual relationship/audience. | Content visible only under declared rules. |
| 3 | Post, kudos/comment, report and block using synthetic benign markers. | Interaction receipts and moderation path observable; no duplicate counts. |
| 4 | Expire token during action, then retry. | No false success; ownership revalidated. |
| 5 | Sign out with pending response/upload and switch account. | No prior-user data/photo/plan appears. |
| 6 | Exercise enabled milestone/referral terms. | No duplicate reward; unsupported features not invented. |

**Also attach:** Sanitized access matrix, provider outcomes, post/comment receipts and moderation receipt; credentials excluded.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W11 — Paid launch purchase and entitlement lifecycle

**Purpose:** Payment trust and access protection  
**Fixtures:** F12  
**Gate:** PAID  
**Related cases:** AU-55, PY-01–12

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Record sandbox/TestFlight/local StoreKit environment and actual products/storefronts. | Do not confuse a local simulated transaction with live integration evidence. |
| 2 | Show paywall, choose each offered period in isolated identities, cancel once and purchase once. | Actual price/interval/terms/restore; verified entitlement update. |
| 3 | Interrupt after store success; relaunch and restore on another allowed device/identity. | Paid access reconciles once; no cross-account data merge. |
| 4 | Exercise pending, renewal, canceled renewal, expiration, grace/retry and revocation variants. | Each state follows recorded configuration; unsupported simulation marked Blocked. |
| 5 | Expire while session active/offline and save work. | Training facts preserved; later access follows frozen policy. |
| 6 | Open Manage subscription, restore error and account deletion. | Truthful billing consequences; working recovery routes and no test-only release UI. |

**Also attach:** Paid-state matrix and sanitized transaction/entitlement evidence; no card numbers, credentials or raw receipts.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W12 — Accessibility and UI state review

**Purpose:** Visual and interaction quality at real constraints  
**Fixtures:** F13  
**Gate:** CORE / each enabled surface  
**Related cases:** AU-56–57, UX-07–10

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Show smallest/largest supported layouts; light/dark; normal/large/accessibility text. | No essential clipping; native keyboard does not hide action. |
| 2 | Navigate core path with VoiceOver and Reduce Motion. | Correct labels, order, focus and announcements; no color-only state. |
| 3 | Repeat critical views in EN/JA/KO and regional numeric variants. | Fluent meaning, intact units/qualifiers and accepted decimal input. |
| 4 | Inspect Today, logger, result, Progress, Coach, paywall and settings first viewport. | Clear task hierarchy; no duplicate portraits/chips/chrome obscuring content. |
| 5 | Run empty/loading/offline/denied/stale/error/success screen inventory. | Truthful state and recovery action; no generic success before commit. |
| 6 | Measure essential tap/contrast properties in tools. | Attach measured findings, not only subjective approval. |

**Also attach:** State screenshots, measurement table, accessibility recordings and fluent reviewer notes.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W13 — Watch and actual Apple system surfaces

**Purpose:** Phone-only video is insufficient  
**Fixtures:** F14  
**Gate:** WATCH / APPLE_SURFACES  
**Related cases:** AU-58–59, VS-05–09

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Show supported paired hardware/OS and cached plan on both. | Same source session/units at start. |
| 2 | Disconnect, log on Watch, create a different phone event, relaunch Watch app. | Both observations remain locally durable. |
| 3 | Reconnect and replay duplicate/out-of-order delivery. | Distinct facts kept, duplicate ID deduped, one canonical progression. |
| 4 | Open lock-screen Live Activity/widget, then edit/finish underlying session. | Old surfaces cannot mutate another current session. |
| 5 | Invoke advertised Siri/Shortcuts and change reminder permissions. | Authorized correct destination or honest unavailable state. |
| 6 | Test account switch with pending Watch action. | No cross-account delivery or obsolete cue. |

**Also attach:** Both device captures, event ledger, system-surface screenshots and actual audible/haptic observations.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W14 — Failure, privacy, migration and backend assertions

**Purpose:** Evidence beyond what pixels establish  
**Fixtures:** F11 / F15 / F18 / F19  
**Gate:** CORE / applicable backend feature  
**Related cases:** AU-60–62, EN-01–10, SA-03/05/08–10, RC-03/06/08

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Label fault/reset boundaries and show fixed expected-data oracle. | No seed change confused with crash or disappearing data. |
| 2 | Exercise interrupted writes, retries, offline merge and upgrade fixture. | Saved facts/receipts intact; no silent database reset. |
| 3 | Test wrong-owner requests and invalid/replayed action payloads in staging. | Unauthorized accesses denied and no hidden side effects. |
| 4 | Run synthetic canaries across app/network/provider/log/export paths. | Decoded/inspected fields absent where prohibited; encrypted packets alone not proof. |
| 5 | Delete account while old work is pending; deliver delayed callbacks. | No data resurrection or canceled operation restart. |
| 6 | Attach automated assertions and profiler outputs. | Pass tied to exact candidate/config; unresolved oracle or inaccessible environment is Blocked. |

**Also attach:** Test output, sanitized request assertions, local state ledger, migration/fault report and known unobservable paths.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W15 — Jev optional routing and follow-through

**Purpose:** Only run enabled/shadow scope; not a reason to delay core release  
**Fixtures:** F9 / F17  
**Gate:** JEV / JEV_FOLLOWUP  
**Related cases:** JV-01–28, VS-10

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Show off/shadow/enabled and per-locale capabilities/model policy. | No assumption Jev is shipped; known parser commands unchanged. |
| 2 | Submit combined time/equipment, temporary/ongoing, negated, quoted and mixed-scope requests. | Correct clarification or one exact preview; no partial hidden change. |
| 3 | Supply confidence 1.0, bad schema, unknown version and delayed cancellation. | Confidence never approval; safe local fallback and no late action. |
| 4 | Try private input and offline/no-consent paths. | Pre-upload policy prevents leak; no alternate cloud retry of blocked text. |
| 5 | When follow-through enabled, complete exact linked shorter workout and replay completion. | One prompt; Yes does not create permanent preference. |
| 6 | Request feedback change, dismiss/expire another issue, inspect held-out locale report. | New preview required; no resumed change on silence; passing locale evidence attached. |

**Also attach:** Mocked negative tests plus live staging evaluation report; request projections and aggregate metrics only.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W16 — Release candidate and operational sign-off

**Purpose:** Ship the tested configuration rather than an untested build  
**Fixtures:** F0 / F15  
**Gate:** CORE  
**Related cases:** RC-01/02/04/05/07

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Record final app/build/commit and backend/config versions. | Matches all required execution rows or impact-retest documented. |
| 2 | Inspect archive and user-facing settings for developer/test UI. | No test purchase/reset controls or staging secrets. |
| 3 | Open current storefront/website/privacy/support links. | Actual release claims, prices and destination match build. |
| 4 | Exercise kill switch for each enabled optional rollout. | No core-workout dependency or privacy-weak fallback. |
| 5 | Confirm diagnostic/support handling with a synthetic incident. | An owner can find it without private user payloads. |
| 6 | Review execution coverage, all known defects and scope exclusions. | No missing/blocked result promoted to Pass; release owner signs go/no-go separately. |

**Also attach:** Signed manifest, link-check screenshots, rollback/alert evidence and completed release report.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## W17 — Unassisted target-user usability study

**Purpose:** Observe comprehension rather than asking whether it looks nice  
**Fixtures:** F20  
**Gate:** CORE  
**Related cases:** UX-09

| Step | QA action | What the recording must establish |
|---|---|---|
| 1 | Obtain recording consent and read script U1 only. | Do not teach controls or mention expected choices. |
| 2 | Observe onboarding and starting a workout. | Capture first wrong turns/requests for help and independent completion. |
| 3 | Ask user to log and correct a deliberately mistaken set, then finish. | Record correction understanding, accidental plan edit concern and navigation. |
| 4 | Ask what changed for next time; ask them to find the saved workout. | Record verbatim explanation and whether evidence supports it. |
| 5 | Ask them to reopen/start next session and locate price/restore. | Assess return path and payment clarity without prompting locations. |
| 6 | Debrief after tasks; triage repeated obstacles. | Five users is formative evidence, not a statistically representative approval rate. |

**Also attach:** Per-participant anonymous task sheet, observations, assistance count, consented clips and triaged issues.

**Result record:** workflow/profile/build, Pass/Fail/Blocked, individual case outcomes and exact timestamps. A screen opening alone never passes persistence, privacy or payments.


## U1 — Verbatim unassisted usability task

Read this only after consent. Do not point to buttons or introduce feature names unless the participant asks and the task has ended.

> You want a strength plan that fits your week. Set up Regulift as you normally would. Start a workout and log one set. Now imagine you entered the wrong rep count: correct it. Finish the workout early. Tell me what was saved and what you expect Regulift to do next time. Find that workout in your history, then show me how you would start your next session. Finally, show me what you would pay and where you would restore an existing purchase.

Questions after the tasks: “What did you think that number meant?” “What made you hesitate?” “What changed for your next workout?” “Which part would be annoying in a gym?” “Was any information unexpectedly shared?” Avoid leading questions such as “Do you like the improved interface?”

Record task completion unaided / with assistance / not completed; first tap; time-to-action; wrong turns; actual error; recovery; participant wording; observer interpretation separately. Do not infer satisfaction from finishing a task. Five participants provide formative findings, not a representative success-rate claim.

## Visual review checklist

For each critical screen record: state, device/OS, appearance, text size, locale, first visible primary action, reading order, blocked/clipped content, unclear wording, motion/announcement behavior and screenshot path. Use this screen-state grid:

| Surface | Required states | Key question |
|---|---|---|
| Today | Empty, rest, ready, resume, missed, complete, unavailable | Can the user tell what to do today without reading a dashboard manual? |
| Logger / Focus | Target, null reported effort, logged effort, correction, bodyweight, rest | Are target, actual, exercise, units and next step unmistakable? |
| Result | Normal, partial, pending update, saved with no change | What was saved and what happens next? Is sharing optional? |
| Progress / History | None, one, mature, filtered, edited, error | Are numbers accurate for their stated scope and useful before trends exist? |
| Timeline | Initial group, genuine change, note, hide/restore | Does this read like a history rather than an event dump? |
| Coach | Fresh, keyboard, answer, clarification, preview, error, retry | Is conversation more prominent than portrait/cards, and is consent clear? |
| Settings | Voice/local/cloud state, units, model status, account/data | Can user identify effective processing location and essential account actions? |
| Fuel / goals | Initial form, error, saved, empty, insufficient evidence | Are defaults, missing data and actual measurements distinct? |
| Paywall | Offering, unavailable, pending, purchased, expired, restore | Actual billed amount/period, current access, recovery and cancellation information clear? |
| Sharing | Every enabled template/look/format, stale, no source, failure | Is final image accurate/readable, disclosure explicit and editor optional? |
| Crew | Signed out, own/follower/outsider, posting, failed, blocked | Is audience truthful and publication explicit? |

Do not redesign screens merely to match wording in this pack; evaluate whether the completed implementation achieves the stated outcomes.
