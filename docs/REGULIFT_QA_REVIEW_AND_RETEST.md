# Regulift — Independent QA Evidence Review and Retest Handoff

**Reviewed:** 21 September 2026  
**Candidate described by QA:** 1.0 (1), commit `f1c9cac458f31d6f9f20926f8aeb40b769c4c477`  
**Verdict:** **HOLD paid public launch.** Preserve the useful simulator results; fix the identified editing/presentation/accessibility problems, reconcile conflicting evidence, and test a configured release candidate. This is not a request for more features.

## 1. What this review actually checked

The supplied `REGULIFT_QA_RESULTS(1).md`, all 263 execution rows and associated scope/profile/workflow definitions in `REGULIFT_QA_TRACKER(2).xlsx`, and all 15 uploaded videos were reviewed. The videos total **20 minutes 29.76 seconds**. The uploaded files are **332 × 720 pixels and silent**. Visual coverage used regular samples across each complete timeline plus closer half-second inspection of critical editing, logging, calculator and confirmation sequences. This is not frame-by-frame playback certification.

The accompanying 19 stills are unmodified frame extractions. References such as `[V22 00:40; E05]` identify the video and position, not a new app test. Their exact source names, positions and hashes are in the evidence/source manifests.

**No application tests were executed by this reviewer.** The repository, original Maestro scripts, assertion logs, accessibility trees, backend traces, signed application, billing receipts, and real-device runs were not supplied for independent inspection. File paths mentioned inside the QA report are not themselves inspected evidence. No source code or original tracker has been modified.

Evidence terminology used here:

- **QA-reported:** stated in the supplied report/tracker, without independent execution.
- **Visually supported:** the uploaded pixels show the stated outcome, within their limits.
- **Evidence conflict:** the supplied video/definitions do not establish the written Pass claim.
- **Recommendation:** a proposed fix, release rule or retest—not a finding about unseen source code.

## 2. Release verdict and what has improved

The current bundle supports an engineering progress review, **not approval of a paid distribution build**. QA describes a Debug simulator build with code signing disabled, no configured RevenueCat integration, no reachable configured Coach/sync/auth path, and no frozen backend deployment. It explicitly reports no device-level privacy capture, no real Watch/audio results, no billing lifecycle run, no human usability study, and no release sign-off. [S1 §§1–2, 8, 10]

Useful improvements are visible:

1. The RPE recording now shows an aggregate average based on **one reported set out of two**, rather than silently including both. The row-level presentation still conflicts with it; see R01.
2. After a cross-exercise Deadlift log, the plate sheet uses **Lunge / 0.0 kg**, not the previous unrelated 60 kg. Its bodyweight/barbell presentation still needs correction; see R04.
3. A saved set is visibly resumable after leaving and returning to the app. QA separately reports a force-kill assertion; the video alone does not prove the exact termination mechanism or offline recovery.
4. Custom food appears in the meal list, timeline hide/restore is exercised, and an experiment appropriately waits for follow-up evidence.

Do not interpret “21/21 Maestro flows green” as 263 case/profile executions passing. A flow may exercise only one branch of a broader case, and script assertions can be weaker than the acceptance criterion. [S1 §§3–5]

## 3. Recomputed tracker coverage

These are **the tracker’s recorded statuses**, not newly approved reviewer results.

| Execution population | Total | Pass | Fail | Blocked | Not run |
|---|---:|---:|---:|---:|---:|
| All planned rows | 263 | 10 | 1 | 139 | 113 |
| All planned P0 rows | 170 | 9 | 1 | 96 | 64 |
| P0 rows explicitly marked Required | 85 | 8 | 1 | 54 | 22 |
| P0 rows whose applicability is Review | 85 | 1 | 0 | 42 | 42 |

There are **134 distinct P0 case IDs**; profile repetitions account for 170 P0 execution rows. The report’s “161 of 170 P0 rows not passed” matches the all-planned population, but calling all 170 “required” is inconsistent with the tracker’s applicability column. The explicitly Required P0 population has **77 of 85 not passed**; another 85 P0 rows still need scope resolution. This does not authorize silently dropping them. [S2 Execution]

The report’s earlier statement that only **2** cases passed is stale after its revision-2 table reports **10**. Its smoke summary reports **6 of 33** cases fully passed. Keep case counts, profile-run counts and smoke counts separate. [S1 §§2–3]

### Required evidence-administration corrections

| ID | Current inconsistency | Correction |
|---|---|---|
| Q01 | `Profiles` defines BASE as a real iPhone/distribution candidate, but actual BASE is a Debug simulator. | Record the actual run as a distinct simulator profile; retain its useful assertions. Do not use it to close hardware/distribution requirements. Execute the promised BASE profile separately. |
| Q02 | `Scope!C5:C33` uses strings such as `unresolved`, `reachable in build` and `target exists`, while `Dashboard!D15` only counts exact `Review`. | Use the approved canonical status enum; keep explanatory text in another field. Unknown/missing states must count as unresolved. Verify dashboard totals against the underlying rows. |
| Q03 | W02 is `Pass` in the workbook but `Partial` in the report, with constituent context/correction checks incomplete. | Reconcile W02 with the defined workflow assertions. Keep it Partial until all required outcomes are evidenced. |
| Q04 | AU-12’s written one-observation result conflicts with the attached two-log video. | Hold approval; attach the exact operation-ID replay fixture and assertion log. See R03. |
| Q05 | AU-19 describes different values/action from the video and the case’s original rep-edit specification. | Re-run the exact case; distinguish a separate weight-edit scenario. See R02. |
| Q06 | Report says RPE coverage 2/4; attached RPE/History sequence shows 1/2. | Correct source mapping or attach the matching run. Do not silently substitute a different fixture while retaining its old expected values. |
| Q07 | Workflow notes say imports/hide/restore were not recorded, but current adaptive/timeline clips show some of those operations. | Update coverage precisely: an import activation preview is visible; final exported artifacts and cross-surface propagation still need assertions. |

**Do not rewrite previous attempts into success.** Keep original run IDs, results and defect history. Add reviewer holds/retest attempts with build/config/fixture IDs, source hashes, timestamps and assertion paths. The original tracker in this upload remains untouched.

## 4. Findings requiring action or a focused retest

### R01 — Missing RPE is still rendered as a reported value in individual History rows

**Disposition:** fix before release; extend AU-05/AU-06 and cross-surface checks.  
**Evidence:** [V20 ~01:02; E01], [V22 ~00:43–00:48; E06].

The History header shows average **8.5**, covering **1 of 2 sets**, and says only self-rated sets count. Yet both read-only set rows carry effort values: the first displays `@8`, the second `@8.5`. The aggregate improvement is real, but the same screen still gives two different impressions of what the user reported.

This is a visible **presentation/provenance inconsistency**. It does not prove the missing RPE was written into storage or used by the engine.

**Implementation requirement:** show the first row as effort not recorded, or display a clearly labeled target separately from any reported effort. In the editor, a suggested target must not look like an already entered report. Preserve nullable provenance through logging, editing, history, summaries and sharing.

**Retest:**

- [ ] Two untouched RPE fields: no reported average, no per-set `@N`, no “RPE on target” claim.
- [ ] One explicitly reported 8.5 and one missing: average 8.5, coverage 1/2; only the reported row displays `@8.5`.
- [ ] Open and close Edit without changing effort: missing stays missing after reopen/relaunch.
- [ ] Export/share and Coach projections preserve the same distinction.

### R02 — History editing lacks a safe draft/cancel boundary; numeric evidence is mismatched

**Disposition:** release fix for accidental historical edits; retest AU-19/AU-20 and decimal formatting.  
**Existing QA issue:** OBS-006 (reported S3). This review recommends higher release priority without silently changing the QA severity.  
**Evidence:** [V22 00:23–00:48; E04–E06], S1 §6 and S2 AU-19/AU-20.

Only **Done** is visible; there is no explicit Cancel/Undo. As the automated input briefly reads **664**, the screen immediately changes to tonnage **5,824 kg** and e1RM **841.1 kg**. The following edit field visibly reads **62.564**; afterward the read-only row renders **63 × 8 @8** and the session displays approximately **1,013 kg** of tonnage.

The report instead describes tonnage **2,016 → 2,036 kg** and e1RM **76 → 79.2 kg**. The tracker case’s expected scenario is a **60 kg × 8 → 60 kg × 9 rep edit**; the current video edits a weight field in a different session. These are not interchangeable test fixtures.

The transient number may result from automation failing to replace/select the existing value. That is not proof of bad arithmetic. What is established is that intermediate input immediately drives displayed historical metrics, and the attached recording does not prove the claimed final result. Persisted intermediate writes and actual engine side effects require instrumentation.

**Implementation requirement:** use an isolated edit draft with explicit Save and Cancel. Keep invalid/incomplete text out of committed historical projections. On Save, validate, commit once and refresh dependent displays. Retain the app’s existing policy for unusual loads; do not invent new training rules for this test. Use sufficient load precision in read-only rows so the same saved value is not misleadingly rounded.

**Retest:**

- [ ] Exact AU-19: one known 60 kg × 8 set becomes 60 kg × 9; the set contribution becomes 540 kg from 480 kg everywhere that counts it.
- [ ] Exact AU-20: perform the same draft change, Cancel, reopen; original values and projections remain unchanged.
- [ ] Separate weight case: replace 64 with 62.5 using actual keyboard input; save/reopen and display **62.5**, with the appropriate locale separator.
- [ ] Temporary text such as blank, `6`, `62.` or a mistyped 664 cannot mutate the committed plan, PRs, awards or historical metrics before Save.
- [ ] Missing effort remains missing when only weight/reps are edited.
- [ ] Dismiss/back/force-kill while editing follows a defined, tested draft-discard or draft-resume policy.

### R03 — The duplicate-log Pass is not established by the supplied video

**Disposition:** evidence hold / re-run, **not automatically a product duplicate bug**.  
**Case:** AU-12; inspect the overly broad WK-11 evidence mapping as well.  
**Evidence:** [V21 ~00:24–00:31 and 00:46–00:51; E02/E03].

The same text `deadlift 60x8 @8` is entered twice. After the first entry, Deadlift has 1/3 sets. After the second, it has **2/3**, a fresh rest countdown, and “Next: Deadlift · set 3 of 3.” This does not match the report’s “one observation” claim.

**Crucial distinction:** two intentional sets with identical weight/reps/RPE are valid. Idempotency must identify a replay of the **same operation**, not reject a second workout set merely because its text matches. The recording exposes no operation IDs, so it cannot resolve that distinction.

**Retest two separate fixtures:**

- [ ] Replay/double-deliver one operation ID with the same fingerprint: exactly one saved set, one receipt, no second rest-start/progression side effect.
- [ ] Submit the same values as two deliberate operations with different IDs: exactly two sets. Never suppress the second legitimate set by text similarity.
- [ ] Reuse an operation ID with different content: explicit conflict and no mutation.
- [ ] Include before/after database counts and event/receipt IDs. A toast or “flow passed” line is not the numeric oracle.

### R04 — Cross-exercise load isolation improved, but bodyweight still opens a barbell calculator

**Disposition:** narrow improvement supported; finish equipment-state UI and formally close AU-07/08/09.  
**Evidence:** [V12 ~00:42–00:44 and 00:59.5–01:00.5; E08].

After a typed Deadlift log while Lunge is visible, the plate sheet identifies **Lunge / 0.0 kg / Bodyweight · Commercial gym**. This no longer borrows the other exercise’s 60 kg target. However, it still shows **“Per side,” “bar 20,” and “Not loadable with these plates.”**

**Requirement:** a bodyweight exercise with no external load should show “No plates needed” or the appropriate existing added-load UI—not an impossible 20 kg barbell target. Open the Deadlift calculator separately and verify its correct bar, plates, units and load convention.

**Retest:** keep the cross-exercise receipt test, then test Bodyweight, weighted bodyweight, barbell and per-dumbbell variants using the same explicit exercise-context boundary. An improvement visible in the video is not a substitute for the missing storage/context assertions in the report.

### R05 — Destructive confirmation omits an explicit safe action

**Disposition:** release accessibility/usability fix.  
**Existing issue:** OBS-005, reported S2.  
**Evidence:** [V23 ~00:24.5–00:25.5; E07], S1 §6/§9.

“Nothing logged yet” visibly offers **Discard workout**, without a visible **Keep going** action. A subsequent dismissal returns to the logger, but an implicit dismissal is not a clearly named choice.

QA separately reports that the safe dismissal has no accessible label. The silent recording does **not** independently verify its accessibility-tree or VoiceOver behavior.

**Requirement:** explicitly expose Keep going and Discard workout, with meaningful accessibility names and the appropriate destructive emphasis. Apply the same rule to partial-workout finish confirmation.

**Retest:** touch, keyboard/switch access where supported, and real VoiceOver; dismissal/back-out preserves the session; discard removes only the intended empty draft and does not create a completion, PR, award or adaptation. A no-set workout is different from a no-plan week—test both.

### R06 — “Coach server: Connected” needs to agree with service usability

**Disposition:** reconcile configuration and status presentation before release.  
**Evidence:** [V09 ~00:58; E09], [V08 ~00:22; E17], S1 §1.

Settings reports **Coach server: Connected**, while QA states this build cannot make Coach/sync/auth requests because its configuration is absent. The sign-in sheet explicitly says Google sign-in is not configured.

This may be a difference between public endpoint reachability, cached status and authenticated readiness; the video does not establish the cause. Whatever the cause, “Connected” should not imply a working Coach when the actual user request cannot succeed.

**Requirement:** distinguish Not configured, Checking, Available, Authentication required and Unavailable using actual state. Preserve local/manual features. Verify normal answer, ambiguity, timeout and confirmed-action paths against the configured backend; the injection-refusal response is not proof of those paths.

### R07 — Typed fallback accessibility remains a reported, unresolved risk

**Disposition:** reproduce on the smallest supported physical layout; do not close merely because automation learned to scroll.  
**Evidence:** QA OBS-007/DEFECT-001 in S1 §§6, 9. The original diagnostic failure image is referenced but not supplied in this bundle.

QA reports that the voice-unavailable explanation pushes “Type a set” out of view. Changing an automation coordinate/scroll closes a script failure, not the underlying usability issue.

**Requirement:** keep manual/typed input straightforward when voice is unavailable. Use a compact, dismissible status and task-first layout. Test keyboard open, large text, denied voice permission and model-not-downloaded states on the actual supported device.

## 5. UI polish still visible in the supplied build

These are focused refinements—not reasons to restart the design or add new modules. Original report §6 said it had not applied a visual review to the remaining screenshots; this section adds a visual pass over the uploaded clips.

| Surface | Visible behavior | Recommended finish | Priority |
|---|---|---|---|
| Today | A generic “Your plan changed for next week” message; readiness and other status information compete with the workout task. | Lead with Start/Resume and the actual changed exercise/next session when available. Do not invent a reason; hide unhelpful generic cards. | After correctness fixes |
| Coach | Large portrait plus repeated large suggestion cards and bottom chips. [V13; E15] | Keep one compact identity and one set of contextual prompts; prioritize input, response and action preview. | Polish |
| Progress | A long, equally weighted tool directory and charts with insufficient data. [V11; E16] | One meaningful current summary; History/Timeline first; group advanced analysis and collapse empty charts. | Polish |
| Timeline | Initial targets are repeatedly called “Load changed.” A global menu repeats indistinguishable “Hide Load changed.” [V17; E10/E11] | Group starting prescriptions; reserve before/after language for real changes; attach Hide to the selected event, retaining Undo/Restore. | Focused usability fix |
| Fuel | A new, untouched food form shows a red missing-nutrition warning while Save looks prominent. [V07 ~00:38; E12] | Neutral initial guidance; specific field errors after interaction/submission; Save readiness matches validation. Saved custom food itself is visibly working. | Polish |
| Equipment | Long comparison-rule prose precedes the actionable equipment list. [V14] | Active gym and review-needed items first; keep explanatory rules behind help. | Polish |
| History list | At V20 ~01:00, the delete/trash affordance visibly collides with the date/set text. [E19] | Keep content and destructive actions in separate bounds throughout swipe/edit states; test large text and the native keyboard. | Focused usability fix |
| History | Rounded load and effort labels do not consistently communicate source/precision. [V22] | Fix as part of R01/R02 rather than treating it as merely decorative. | Release fix |

The 332-pixel-wide recordings do not support formal font-size, contrast or large-text compliance measurements. Native screenshots and actual device/accessibility interaction are still needed.

## 6. Clip-by-clip coverage ledger

A visible operation does not close every case listed beside a video in the tracker.

| Clip | Independent visual observation | Still not established |
|---|---|---|
| V07 `07-fuel_BASE.mp4` | Custom food enters Breakfast with visible nutrition totals; early error-state styling. | Full input matrix, persist/reopen/deletion and region cases. |
| V08 `08-crew_BASE.mp4` | Signed-out Crew and sign-in options; Google unavailable in this build. | Actual authentication, audience/ownership, guest merge, posting and deletion. |
| V09 `09-settings_BASE.mp4` | Settings groups and provider controls; “Connected” status. | Real effective processing path, persistent configuration, production-only behavior. |
| V10 `10-abandoned-session_BASE.mp4` | Load-plausibility prompt and later Resume with one saved set. | Exact force-kill assertions, offline state, failed adaptation, duplicate delivery. |
| V11 `11-progress-tools_BASE.mp4` | Tool navigation, evidence-limited analytics, measurement entry UI. | Full metric equivalence, measurement persistence across controlled boundaries, exported reports. |
| V12 `12-workout-tools_BASE.mp4` | Cross-exercise typed receipt, context-isolated Lunge load, irrelevant bodyweight plate formula; workout utilities. | Full calculator assertions, complete Focus Mode workout, actual audio recognition. |
| V13 `13-coach-security_BASE.mp4` | Consent and one instruction-extraction refusal. | Normal connected Coach grounding, action approval, real privacy/security suite. |
| V14 `14-adaptive-features_BASE.mp4` | Equipment, goal UI, import analysis/activation, share review entry and experiment waiting. | Cross-surface active-plan propagation, actual exports, qualifying experiment outcome. |
| V15 `15-plan-fuel_BASE.mp4` | Week/block review, muscle-emphasis explanation and Fuel navigation. | Seeded empty/rest/missed weeks and validated rescheduling outcomes. |
| V17 `17-journey_BASE.mp4` | Timeline filtering, note/history navigation, hide and restore. | Correctness of every underlying record and absence of side effects; remaining event-label/menu issues. |
| V18 `18-coach-clarify_BASE.mp4` | Composer interaction and voice/settings controls. | A completed ambiguous-question clarification conversation. |
| V20 `20-effort-rpe_BASE.mp4` | One missing and one explicitly rated set; average covers 1/2. | The separately specified two-unrated fixture and complete row/export provenance. |
| V21 `21-log-integrity_BASE.mp4` | Two identical-text entries lead to 2/3 Deadlift sets. | Same-operation replay identity; does not support the written one-observation claim. |
| V22 `22-history-edit_BASE.mp4` | Immediate metric changes during weight typing; no cancel; read-only rounding/RPE inconsistency. | Claimed AU-19 values or the exact 60×8→60×9 case; persistence side effects during typing. |
| V23 `23-finish-empty_BASE.mp4` | Empty-finish prompt, dismissal and return to Today. | Named safe accessibility action; database assertions excluding completion/award/plan side effects. |

Do not call Home Screen transitions or blank transition frames crashes without logs. This automated sequence may deliberately relaunch/reset. Do not assume records persist continuously across all 15 videos unless the fixture/run manifest establishes that.

## 7. Smallest useful next QA run

Run these as **targeted retests**, then finish the existing applicable release suite. These are not substitutes for required billing, privacy and platform verification.

| Order | Work item | Existing case/workflow anchors | Required result/evidence |
|---|---|---|---|
| 1 | Freeze actual candidate and scope | RC controls, Profiles, Scope, W16 | Signed build identity, backend/rules version, flags, storefront/products, physical devices, supported locales, owner. No credentials in the returned evidence. |
| 2 | Repair evidence mapping and summary formulas | Q01–Q07 | Consistent report/workbook, canonical statuses, separate simulator results, retained previous attempts, matching file hashes. |
| 3 | RPE provenance end to end | AU-05/06, cross-surface metrics | Independent two-missing and one-reported fixtures; UI + persisted values; no fake per-set effort. |
| 4 | Safe historical editing | AU-19/20 | Exact rep-edit and cancel oracles, decimal weight test, no committed side effects during typing. |
| 5 | Replay versus intentional identical sets | AU-12 | Stable operation/receipt IDs, two distinct fixtures and persisted counts. |
| 6 | Exercise/equipment context | AU-07/08/09 | Lunge bodyweight and Deadlift barbell paths both correct after cross-exercise logging. |
| 7 | Named safe confirmation and fallback | AU-57, UX-07, VS-03, WK-10 | Real accessibility output and native keyboard/large-text recordings; no data-loss on dismissal. |
| 8 | Week state and active plan | AU-24–30, W04 | Explicit empty/rest/missed/resume/complete seeds; import remains authoritative without reseeding. |
| 9 | Connected Coach and account flows | AU-46/47/49/50, W05/W10 | Normal answer, clarification, missing fact, preview/reject/approve/stale action, auth/guest merge/Crew boundaries. |
| 10 | Paid lifecycle on actual platform integration | AU-55, W11 | Purchase, cancel, restore, expiry and access behavior; platform sandbox evidence and release configuration checks. |
| 11 | Offline/privacy/migrations | AU-16/17/58/60/61, W14 | Physical interruption, denied/failed network, retries, previous-store fixtures, export/telemetry canaries and deletion. |
| 12 | Actual sharing artifacts | AU-53, W09 | PNGs from the editor, selected fields, cancel leaves training intact, temp-file/metadata handling, optional Crew publish. |
| 13 | Enabled Apple/language/accessibility surfaces | W06/W12/W13 | Watch and supported Apple surfaces; audio recordings; native keyboard/VoiceOver; all shipped locales, including vi if enabled. |
| 14 | Human comprehension and sign-off | W17/W16 | Unassisted users explain the next-session change; named release owner, open-risk disposition and monitoring/rollback owner. |

**Scope discipline:** Jev is reported off, and follow-through is reported unbuilt. Do not implement them merely to close a QA row. An owner may exclude genuinely disabled/unadvertised optional features with build/listing evidence. A visible or advertised feature that cannot be tested remains Blocked; missing infrastructure is not an N/A reason. Core logging, data integrity, paid access for a paid launch, and required privacy checks cannot be waived by relabeling a flag.

### External documentation correction: RevenueCat Test Store is not Apple sandbox proof

The QA report’s proposed Test Store key plus sandbox-account shortcut needs to be separated into two testing paths. RevenueCat documents Test Store as a simulated purchase environment; it does not exercise StoreKit/platform-specific behavior. Use the platform-specific iOS API key and Apple’s platform sandbox for the actual pre-launch store integration, and do not ship a Test Store key. Test Store results remain useful development evidence, not replacement W11 sign-off. [S3/S4]

Keep secrets in the team’s secure configuration system. Return redacted environment status, not API secrets, user tokens or real personal records.

## 8. Evidence bundle to return after retesting

Return the updated report/tracker with:

- Exact candidate build/commit/config and scope approvals; separate actual device and simulator profiles.
- One independent fixture per critical correctness case, with expected values fixed before running it.
- Raw assertion excerpts showing before/after records and operation IDs where those are the oracle.
- Matching video names, timestamps and hashes; native screenshots for UI/accessibility review.
- Completed export files, redacted billing state evidence, real connected Coach traces, and privacy/failure assertions for the enabled release.
- Failure and retest attempts preserved, with reviewer names; no “Pass” created solely because a screen opened or a script reached its end.

The next review should answer two independent questions: **does the product behave correctly, and is the evidence sufficient to authorize this release configuration?** A small number of unresolved implementation issues plus many unexecuted environments is not “hundreds of bugs,” but it is still not a release approval.

## 9. Source references and artifact integrity

**S1:** supplied `REGULIFT_QA_RESULTS(1).md`, revision 2. Section/line references: candidate lines 9–15; verdict 19–23; counts 29–41; first-priority results 47–56; UI findings 86–92; unverified integrations 100–105; open issues 111–119; unsigned release 123–135.

**S2:** supplied `REGULIFT_QA_TRACKER(2).xlsx`. Independently read Execution, Case Index, Profiles, Scope, Workflows and Dashboard formulas. Useful row anchors: Execution AU-05 row12, AU-06 row15, AU-12 row25, AU-15 row33, AU-19 row41, AU-20 row42, AU-43 row67, AU-48 row74, WK-10 row187, WK-11 row188. Header is row4. Original workbook not edited.

**S3:** RevenueCat, Sandbox Testing, accessed 21 September 2026. External implementation clarification only; not evidence about this build.  
`https://www.revenuecat.com/docs/test-and-launch/sandbox`

**S4:** RevenueCat, Test Store, accessed 21 September 2026.  
`https://www.revenuecat.com/docs/test-and-launch/sandbox/test-store`

**V07–V23:** the 15 source recordings listed in §6. Exact metadata/hashes are in `source_manifest.json`; selected frames in `evidence_manifest.json`.

## 10. Selected visual evidence

The stills retain the source’s low resolution; they are not redesigned screens or proof of hidden database state. Open the corresponding full video for interactions.

| ID | Source / position | Extracted frame |
|---|---|---|
| E01 | `20-effort-rpe_BASE.mp4` · 01:02.00 | [reported rpe coverage](evidence/E01_20-effort-rpe_BASE_062.00_reported_rpe_coverage.png) |
| E02 | `21-log-integrity_BASE.mp4` · 00:30.00 | [first deadlift log](evidence/E02_21-log-integrity_BASE_030.00_first_deadlift_log.png) |
| E03 | `21-log-integrity_BASE.mp4` · 00:50.00 | [second deadlift log](evidence/E03_21-log-integrity_BASE_050.00_second_deadlift_log.png) |
| E04 | `22-history-edit_BASE.mp4` · 00:38.00 | [history intermediate edit](evidence/E04_22-history-edit_BASE_038.00_history_intermediate_edit.png) |
| E05 | `22-history-edit_BASE.mp4` · 00:40.00 | [history decimal edit](evidence/E05_22-history-edit_BASE_040.00_history_decimal_edit.png) |
| E06 | `22-history-edit_BASE.mp4` · 00:45.00 | [history readonly rpe rounding](evidence/E06_22-history-edit_BASE_045.00_history_readonly_rpe_rounding.png) |
| E07 | `23-finish-empty_BASE.mp4` · 00:25.00 | [empty finish dialog](evidence/E07_23-finish-empty_BASE_025.00_empty_finish_dialog.png) |
| E08 | `12-workout-tools_BASE.mp4` · 01:00.00 | [bodyweight plate context](evidence/E08_12-workout-tools_BASE_060.00_bodyweight_plate_context.png) |
| E09 | `09-settings_BASE.mp4` · 00:58.00 | [coach connected status](evidence/E09_09-settings_BASE_058.00_coach_connected_status.png) |
| E10 | `17-journey_BASE.mp4` · 02:06.00 | [timeline hide menu](evidence/E10_17-journey_BASE_126.00_timeline_hide_menu.png) |
| E11 | `17-journey_BASE.mp4` · 00:34.00 | [timeline initial targets](evidence/E11_17-journey_BASE_034.00_timeline_initial_targets.png) |
| E12 | `07-fuel_BASE.mp4` · 00:38.00 | [new food validation](evidence/E12_07-fuel_BASE_038.00_new_food_validation.png) |
| E13 | `07-fuel_BASE.mp4` · 00:54.00 | [saved food](evidence/E13_07-fuel_BASE_054.00_saved_food.png) |
| E14 | `10-abandoned-session_BASE.mp4` · 00:39.00 | [resume saved set](evidence/E14_10-abandoned-session_BASE_039.00_resume_saved_set.png) |
| E15 | `13-coach-security_BASE.mp4` · 00:18.00 | [coach suggestions](evidence/E15_13-coach-security_BASE_018.00_coach_suggestions.png) |
| E16 | `11-progress-tools_BASE.mp4` · 00:24.00 | [progress hierarchy](evidence/E16_11-progress-tools_BASE_024.00_progress_hierarchy.png) |
| E17 | `08-crew_BASE.mp4` · 00:22.00 | [auth not configured](evidence/E17_08-crew_BASE_022.00_auth_not_configured.png) |
| E18 | `14-adaptive-features_BASE.mp4` · 03:11.00 | [experiment waiting](evidence/E18_14-adaptive-features_BASE_191.00_experiment_waiting.png) |
| E19 | `20-effort-rpe_BASE.mp4` · 01:00.00 | [history row overlap](evidence/E19_20-effort-rpe_BASE_060.00_history_row_overlap.png) |
