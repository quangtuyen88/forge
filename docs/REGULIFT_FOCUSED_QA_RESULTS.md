# Regulift — Focused QA results (SIM-DEV)

**Date:** 22 September 2026
**Plan:** `docs/REGULIFT_FOCUSED_QA_UX_GOAL.md`
**Candidate:** branch `redesign/lyfta-lungy` (commit recorded in the git log entry that adds this file), Debug, unsigned, simulator only.
**Evidence:** `docs/qa/2026-09-22/` (screenshots named in the tables, suite summaries).
**Profile:** SIM-DEV — iPhone 14 simulator, iOS 26.4, default text size (large-text checks at the app's Dynamic Type cap, `.xxLarge`). No physical device, no signed build, no configured backend, billing, accounts or Watch. Everything that needs those is **Blocked**, not passed.

## Gates

| Gate | Result |
|---|---|
| `scripts/check-localization.py` | placeholder parity ok (1,808 localizations with specifiers) |
| String Catalog coverage vs Xcode `-exportLocalizations` | 0 keys missing ja, ko or vi in the app, ForgeCore and Watch catalogs (was 324 ja/ko + 490 all three) |
| `swift test --package-path ForgeCore` | 711 / 711 |
| `pnpm --dir server test` | 204 / 204 |
| App unit tests (`ForgeTests`, iPhone 14) | 50 / 50 |
| `e2e/onboarding-profile.yaml`, fresh install, iPhone 14 | pass |
| Maestro, all `.maestro/[0-9][0-9]-*.yaml` in order, one install, shared state | 22 / 22 on the final build (`suite-final-summary.txt`). Earlier runs of this wave: 17 failed on every suite run until the Timeline fix; 14 failed 2 of 4 runs under load until it waited for the Active version row; 24 failed on the pre-fix build at its new bad-entry assertion, as it should. |

## Open observations from the Q1 report

| ID | Reproduced on this candidate | Now |
|---|---|---|
| OBS-005 — safe exit on Finish/Discard has no name | Yes. The dialogs rendered as an anchored popover that drops the cancel-role button; only an unnamed "dismiss popup" was exposed, and `23-finish-empty` asserted that defect. | Fixed. Both confirmations are alerts with a visible, labelled **Keep going** next to **Finish workout** / **Discard workout**. `23` now asserts Keep going and that it keeps the session. VoiceOver audio: Blocked (device). |
| OBS-006 — History edits write through, no Cancel | No — already fixed in `9ce1052` (draft + Cancel/Done). | Verified by `22`. New FQ-12 defects in the same editor were found and fixed (below). |
| OBS-007 — voice-unavailable layout hides the typed fallback | Could not reach the state: the simulator recognizer keeps listening with permissions denied. | Added a DEBUG-only switch (`voiceUnavailable`) that puts voice into its permission-denied failure. New `24-voice-unavailable` shows the failure capsule, asserts no set was created, reaches **Type a set** fully, and logs a typed set. Physical microphone/model states: Blocked (device). |

## Defects found and fixed in this run

| Objective | Defect (evidence) | Fix |
|---|---|---|
| FQ-12 | Saving any History edit rewrote the load of every set from 1-decimal display text: a stored 62.56 kg became 62.6; a lb user's 60 kg (shown 132.3 lb) was written back as 60.01 kg. | Only a changed field is written; loads seed and display with up to 2 decimals. |
| FQ-12 | While editing, Back / edge-swipe popped the view and silently dropped the draft. | Back is hidden while editing; an edit ends only through Cancel or Done. |
| FQ-16 | A blank or garbled load logged as 0 kg (`Double(text) ?? 0`); `-5`, `inf`, `nan` and 0 reps were accepted. | One validator (`LoadEntry.parse`, ForgeCore, unit-tested) gates the logger (button disabled, inline message) and History. |
| FQ-16 | A session containing a bodyweight (0 kg) set could never be saved after an edit. | Zero is valid for bodyweight and band movements. |
| FQ-13 | `finish()` had no guard: a fast second tap (all sets logged, no alert) advanced the block calendar twice and saved two Health workouts. | `finish()` returns if the session is already completed. |
| FQ-11 | No test proved a redelivered sync change stays one record. | Server test: same change twice → one record; identical data under a new id → two. |
| FQ-29/30 | History edit rows were wider than an iPhone 14 at every text size (fields at x = −1; at max text the whole page clipped). | `ViewThatFits` two-line fallback; verified at max text. |
| FQ-29 | The new Today week bar surfaced to VoiceOver and UI tests as a bare "Progress, 3 %" and captured taps meant for the Progress tab. | Drawn bar with no accessibility element; the card keeps its combined label. |
| FQ-29 | "Hide an item" entries read "Full C · Sep 22" with no verb. | Accessibility label "Hide Full C · Sep 22". |
| FQ-30 | Program import: both text fields are multi-line and had no way to dismiss the keyboard except a drag. | Keyboard **Done**. |
| OBS-007 / FQ-15 | With voice unavailable, one state held both the voice reason and the typed-entry hint: a bad typed entry put "Try: deadlift 132.5×8 @8" inside the red voice capsule and removed "Microphone or speech permission is off. Enable it in Settings."; any typed submit replaced it with a generic "Voice unavailable". The hint was a plain string, never localized. (`24` on the previous build: `obs007-before-typed-error-in-voice-capsule.png`.) | The capsule reads the voice reason directly; the hint shows with the typed field, is localized, and scrolls into view above the keyboard. The failure message wraps up to 3 lines instead of truncating to "…permission is off. E…". `24` asserts both messages after a bad entry. (`obs007-after-typed-error.png`) |
| FQ-30 | 324 app strings had English and Vietnamese but no Japanese or Korean (since the Coach/Whisper and training waves). | Japanese and Korean added. |
| FQ-30 | Xcode's own extraction (`-exportLocalizations`) found 490 strings the code localizes that were in no String Catalog, so they were English in ja, ko **and** vi ("Plan tools", "Log", "Not entered", "RPE not recorded", VoiceOver labels, 18 ForgeCore voice prompts, 4 Watch strings). | Catalog entries in ja, ko and vi. |
| FQ-30 | Plurals were built as `item\(n == 1 ? "" : "s")`; in 18 localized strings the English "s" leaked into ja/ko/vi (vi already showed e.g. "…tuần nàys"). | `L10n.pluralSuffix` returns "s" only in English. Plain English strings keep their inline plural. |
| FQ-30 | Siri / Shortcuts phrases: the catalog keyed them `Start my workout in \(.applicationName)` while the App Intents metadata looks up `… ${applicationName}`, so the ja/ko/vi phrases never matched. | Re-keyed to the placeholder form. |
| FQ-30 | Program import: "Version 1 · 1 days · 1 exercises". | Singular/plural. |
| FQ-30 | Minutes read "min" in 14 ja/ko/vi values while the rest of the catalog uses 分 / 분 / phút (Timeline "1 min · 第2週"). | Normalized to 分 / 분 / phút. |
| FQ-30 | Walk in ja/ko/vi (below): the Progress hub rows (History, Plan audit, Recovery, Experiments, PR board, …) stayed English because the row component took plain `String`s; the "Analysis eligible" scope label and caption came from ForgeCore as English literals; Timeline cards read "Full B", "Starting load", "Load changed", "1 working set · Week 2", and its error banners were English; the week-plan mode on Today read "Standard"; the first Coach chip asked "なぜDumbbell Lateral Raiseが変わったのですか？". | Row titles and subtitles, the scope labels, the Timeline card text and errors, and the week-plan mode go through the catalogs; Timeline workout titles use the localized day name; Coach chip titles use the localized exercise name while the message sent to the coach keeps the English name the engine matches on. |
| FQ-19/29 | Timeline: after scrolling the All list, a filter or month change kept the old scroll offset, so the new list opened clamped at its bottom. Only the oldest workout showed; newer ones sat hidden under the pinned header, and `17` tapped a hidden card (fails in suite order on every run). (`fq19-before-filter-opens-at-bottom.png`) | A new month or filter is a new list and opens at its top; load more, hide, restore and note edits keep their offset. `17` no longer walks back up after a filter change. (`fq19-after-filter-opens-at-top.png`) |

Translations added in this run are machine translations checked against the app's existing ja/ko/vi terminology, with placeholder parity enforced (`scripts/check-localization.py`, merge scripts refuse a mismatched specifier). They need a native-speaker pass before release.

Flow-only fixes (no behavior change): `14` dismisses the keyboard with `hideKeyboard`, then waits for the Active version row (it lands after the SwiftData save and pushed "Review redacted copy" down under a pending tap: 2 failures in 4 suite runs) before aiming at the button; `18` drags the conversation to dismiss the multi-line composer (`hideKeyboard` does not dismiss it on iOS 26, and the toolbar Done reports a stale frame); `17` taps the first "View workout" below the pinned header; `20` and `22` select Overview first (the segment is remembered per device), assert set rows through their VoiceOver labels (the visual strings stay covered by `SessionClaimsTests`), scroll to the rated row, and tap the trailing edge of a field before `eraseText`.

## Locale walk (FQ-30), iPhone 14, mature data

Today, Settings, Coach, Progress (Overview and Timeline) and Crew in Japanese, Korean and Vietnamese, launched with `-appLanguage` (argument domain only; the stored language is untouched). Before the fixes each of those screens had English rows, labels or card text; after them, the walked screens read in the chosen language apart from the items listed below. Screenshots: `docs/qa/2026-09-22/` (`fq30-walk-after-ja.png`, `-ko`, `-vi`). Numbers follow the device region, not the app language (for example "4.749 kg"), which is the platform's rule and was left as is.

Still English after this run, not fixed here:
- Text built as plain `String` values that never reaches a catalog: Program import "On this device" rows, Recommendation effectiveness lines, Week designer sentences, goal reasons from ForgeCore `PlanningFeatures`, and similar. Needs a per-screen pass.
- The gym name stored at onboarding ("Commercial gym") is saved as English data on the profile.
- Some Vietnamese exercise names in the existing ForgeCore catalog are English loanwords (for example "Deadlift"); left as the catalog has them.

## Objective status (SIM-DEV)

| FQ | Status | Evidence / blocker |
|---|---|---|
| 01 | Blocked | Needs signed candidate, physical phone, configured backend and store. |
| 02 | Not run | Process reconciliation; this file is the SIM-DEV input. |
| 03 | Blocked | No previous-store fixture; no `VersionedSchema` migration plan in `Models.swift`. |
| 04 | Partial | Pass: `01-onboarding` in the suite and `e2e/onboarding-profile.yaml` on a fresh install. The paid route uses the DEBUG bypass, so the purchase-required variant is Blocked (StoreKit sandbox). |
| 05 | Not run | Back/kill/interrupt not scripted. |
| 06 | Partial | `ImportTests`, `14` analyse/activate. Returning user Blocked (accounts). |
| 07 | Partial | Ready/resume/rest covered by `02`, `10`, `15`; unconfigured/missed/unavailable fixtures not built. |
| 08 | Not run | No clock/timezone injection. |
| 09 | Partial | Pass: `20-effort-rpe` after relaunch; `SessionClaimsTests`, `EffortDivergenceTests`. Export variant Not run. |
| 10 | Pass (SIM-DEV) | `12`, `21` (typed Deadlift log from another exercise; plate sheet receipt), `PlatesTests`. |
| 11 | Pass (server) | New redelivery test. Policy note: sync is id-keyed last-writer-wins, so "same id, different content" is an edit when newer, rejected when older — not "rejected without mutation" as FQ-11 phrases it. Needs a policy decision. |
| 12 | Pass (SIM-DEV) | `22`, `LoadSemanticsTests`; defects above fixed. |
| 13 | Partial | Pass: `23`, `03`; double-finish guard. VoiceOver audio Blocked (device). |
| 14 | Partial | `12` enters/exits Focus Mode; a full Focus Mode session is not scripted. |
| 15 | Partial | Pass: `24` (DEBUG permission-denied state); physical mic/model states Blocked (device). |
| 16 | Partial | Pass: `LoadSemanticsTests`, `22`; unit-switch round trip not scripted. |
| 17 | Partial | `10` kill/relaunch resume; airplane mode + outbox Blocked (backend). |
| 18 | Not run | No fault-injection point between save and adaptation. |
| 19 | Partial | Timeline filter/month fix above (`17`); cross-screen equality otherwise unit tests only. |
| 20 | Partial | `14`, `15`, `PlanningFeaturesTests`. |
| 21–27 | Blocked | Live Coach backend, accounts, StoreKit sandbox, sharing/Crew backend, egress capture. |
| 28 | Blocked | Physical paired Watch. |
| 29 | Partial | Fixes above; VoiceOver audio and measured hit areas need a device. Observation: 11 other destructive confirmations use the iOS popover (tap-outside exit, exposed as "dismiss popup"); consistent with the platform, left as is. |
| 30 | Partial | Catalog gaps above fixed; iPhone 14 walk in ja/ko/vi above; History edit at default and max text. Open: text built as plain `String` values never reaches a catalog and stays English in every language (e.g. Program import "In your library" / "Active version" rows, Recommendation effectiveness lines, goal reasons from ForgeCore `PlanningFeatures`); needs a per-screen pass. Native review of the new translations. |
| 31 | Blocked | Needs device traces and agreed budgets. |
| 32 | Blocked | Needs five unassisted participants. |
