# Regulift: Apple HIG audit, all screens

Date: 2026-09-30. Code: `main` at `1f321d7`. Guidance: Apple HIG snapshot of 2026-09-12 (apple-hig skill, release 2026-09-27).

## Method and limits

- Walked the app on an iPhone 14 simulator (iOS 26.4) as a new user (onboarding, check-in, first workout, summary). Then walked it again with the demo data (`--seed-demo`). Took screenshots in light mode, in dark mode, and at the AX3 text size (`accessibility-extra-large`). Key screenshots are in `shots/`.
- Six read-only code passes covered every view file in `App/Forge`. I also read `App/ForgeWatch` and `App/ForgeWidgets`. The contrast values are measured from screenshot pixels or computed from `Theme.swift` hex values with the WCAG formula.
- Coach ran against the local stub (`e2e/coach-stub.mjs`) because this worktree has no coach secret. Crew was checked signed out only.
- Not done: a VoiceOver run on device, visual checks with Increase Contrast or Reduce Transparency on, a run of the watch app, and widget rendering. The watch and widget findings come from the code only.
- Rules are paraphrased from the HIG with the section name. "Team call" marks my own recommendations that are not Apple rules.

Priority: **P1** blocks some people, or Apple's guidance explicitly says to avoid it. **P2** breaks a platform convention or causes friction. **P3** is polish.

## What already works

- The tab bar is the system `TabView` (`ForgeApp.swift:136`). Dark Mode adapts on every screen I checked.
- Text colors pass: secondary text `#5F6672` measures 5.8:1 on white, and orange text (`accentText` `#C2460C`) measures 5.0:1.
- The History delete flow is the model to copy. It has a confirmation dialog with `role: .destructive`, a context-menu delete, and a VoiceOver "Delete session" action (`HistoryView.swift:163-177, 361-366`).
- Program roadmap, Adjustments, Timeline and Coach voice mode check Reduce Motion.
- The paywall shows the price, the date of the first charge, Restore, Terms and Privacy. You can delete your account inside the app. The lift-detail chart gives each point a VoiceOver label.

## P1: fix first

### P1-1 Text does not grow past xxLarge

- **Evidence**: `ForgeApp.swift:109` sets `.dynamicTypeSize(...DynamicTypeSize.xxLarge)` for the whole app. At the AX3 text size, Today looks almost the same as at the default size (`shots/01` vs `shots/02`).
  - UIKit appearance proxies fix the navigation title, tab label and segmented-control fonts at 30, 17, 11 and 13 pt (`ForgeApp.swift:39-51`).
  - 197 `.system(size:)` calls fix the size of symbols and some text.
  - The watch app uses `.custom(name, size:)` with no `relativeTo:` (`WatchTheme.swift:11-19`), so it has no Dynamic Type.
  - The widgets use fixed `.system(size:)` fonts.
- **Rule**:
  - HIG › Typography › Supporting Dynamic Type: layouts must adapt to every text size, including the larger accessibility sizes, and custom fonts must support Dynamic Type and Bold Text the way system fonts do.
  - HIG › Accessibility › Vision: aim for at least 200% text enlargement (140% on watchOS).
- **Fix**:
  1. Remove the cap at `ForgeApp.swift:109`.
  2. Scale the proxy fonts with `UIFontMetrics(forTextStyle:).scaledFont(for:)`.
  3. Give symbols text-style fonts or `@ScaledMetric` sizes.
  4. Change fixed heights to `minHeight`: tiles 180 pt `TodayTiles.swift:362, 529`, next-up card 172 pt `TodayComponents.swift:242`, pills 34 pt.
  5. At `dynamicTypeSize.isAccessibilitySize`, stack horizontal rows vertically (use `ViewThatFits` or `AnyLayout`).
  6. On the watch, use `.custom(name, size:, relativeTo:)`.
  7. Check every tab at AX5.

### P1-2 White text on orange buttons fails contrast in Dark Mode

- **Evidence**: The filled buttons (Start, Continue, Send code, Save) put white bold text on `accent`.
  - Light mode, `#F5621C`: 3.16:1.
  - Dark mode, `#FF7A33`: **2.60:1** (`shots/03`, `shots/04`).
  - No custom color has an Increase Contrast variant (`Theme.swift:6-9`).
- **Rule**:
  - HIG › Accessibility › Vision: bold text needs at least 3:1, other text up to 17 pt needs 4.5:1. Check both appearances.
  - HIG › Color: give custom colors light, dark and increased-contrast variants.
  - HIG › Dark Mode: aim for 7:1 with custom colors.
- **Fix**: Fill buttons with `accentStrong` `#C2460C` in both modes (white text 5.03:1). Or keep the bright orange and use black text (6.65:1 light, 8.08:1 dark). Move the colors into an asset catalog with High Contrast variants.

### P1-3 The Sign in with Apple button disappears in Dark Mode

- **Evidence**: `AccountView.swift:26` sets `.signInWithAppleButtonStyle(.black)` in every appearance. On the black page in Dark Mode the button shape is gone and only the logo and text show (`shots/04`). The button is a rounded rectangle 52 pt high, next to 50–56 pt capsules.
- **Rule**: HIG › Sign in with Apple › Buttons: never use the black style on a dark background (use white), and match the corner radius of the other buttons.
- **Fix**: `.signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)`. Clip it to a `Capsule()` at the same height as the other buttons.

### P1-4 Permission prompts appear without context, and purpose strings do not match what the app does

- **Evidence**:
  - **Apple Health**: the request fires as soon as the check-in sheet opens, before any tap (`TodayView.swift:1963-1966`). It asks to read sleep, HRV, resting heart rate and heart rate, and to write workouts (`Health.swift:14-18`). The purpose string mentions sleep only.
  - **Notifications**: the request fires when the workout logger opens (`WorkoutView.swift:850`). The system alert covers the first workout with no reason given (`shots/05`).
  - **Microphone**: the purpose string says the app listens "only while you hold the mic button in the coach chat". In fact the coach uses tap-to-start, and the logger listens continuously.
  - **Camera** (from code, not run): if access is denied, the barcode scanner shows a blank view with no message and no Settings link (`BarcodeScannerView.swift:14, 46`).
  - **Cloud dictation**: audio is uploaded before the coach consent check (`SpeechInput.swift:666` vs `CoachView.swift:1601`).
- **Rule**:
  - HIG › Privacy › Requesting permission: ask only when a feature clearly needs access, ideally when the person starts using it. Purpose strings describe the real use in one specific sentence.
  - HIG › HealthKit: ask for each data type in context, and explain briefly why it is needed and how it helps.
  - HIG › Generative AI: ask before you use personal data.
- **Fix**:
  - Remove the request in `.task`. Add a "Use Apple Health for sleep" button to the check-in, and read only the types you use.
  - Ask for notification permission the first time a rest timer starts, with one line of explanation ("Get a banner when rest ends").
  - Rewrite the mic and speech purpose strings to match both coach and workout use.
  - Handle a denied camera with an explanation, an Open Settings button and manual entry.
  - Check the coach consent before recording starts.

### P1-5 Destructive actions with no confirmation and no undo, and no way to delete a progress photo

- **Evidence**:
  - A swipe deletes a body measurement (`MeasurementsView.swift:393`) or a meal (`NutritionView.swift:706`) at once. Neither has an accessibility action.
  - A swipe deletes a custom exercise at once (`CustomExercisesView.swift:31-39`).
  - A long press deletes a saved routine at once (`RoutineAdaptationView.swift:973-979`).
  - "Remove exercise" in the logger works immediately, with no confirmation or undo (`WorkoutView.swift:2755`).
  - Coach "Clear conversation" works immediately, with no confirmation or undo (`CoachView.swift:412, 2010-2024`).
  - A coach "Restart the block" action has no Undo (`CoachView.swift:2381, 2799`).
  - On Today, "Drop the next session" and "Start this week over" apply in one tap (`TodayView.swift:403-421, 475`).
  - On the watch, "End workout" works in one tap.
  - Progress photos have no delete path: `ProgressPhoto.deleteFile()` has no callers.
- **Rule**:
  - HIG › Alerts: skip alerts for common actions people can undo, but confirm uncommon destructive actions that cannot be undone.
  - HIG › Design principles › Agency: build in ways to reverse actions.
  - HIG › Generative AI: confirm significant actions and do not automate destructive ones.
- **Fix**:
  - Use the History pattern: a system `List` with `.swipeActions { Button(role: .destructive) }`, a `.contextMenu` equivalent, and `.accessibilityAction(named:)`.
  - Add Undo, or a confirmation dialog where the action cannot be undone. Clear conversation and restart block need a dialog; restart block also needs an Undo receipt.
  - Add a photo delete action with confirmation. It must remove both the file and the row.

### P1-6 Undo buttons and messages that disappear on a timer

- **Evidence**:
  - The only Undo for an approved volume increase is in a 4 s pill (`TodayView.swift:968-972`).
  - A voice toast shows a "Go to …" action for 2 s (`WorkoutView.swift:1638`).
  - The new-badge toast lasts 3 s and covers the Overview/Timeline control (`ProgressView.swift:113-129`, `shots/10`).
  - The Timeline toast lasts 2.4 s.
  - None of these messages is announced to VoiceOver.
  - The rest panel removes itself at 0:00. There is no haptic, and speech is off by default (`WorkoutView.swift:391-399`).
- **Rule**:
  - HIG › Accessibility › Cognitive: minimize UI that dismisses itself on a timer, and prefer explicit dismissal.
  - HIG › Accessibility › Hearing and HIG › Feedback: send feedback through several channels, and pair audio cues with haptics.
- **Fix**:
  - Keep undo pills until the person's next action or an explicit close. Post `AccessibilityNotification.Announcement`.
  - Move the badge toast off the segmented control (for example, above the tab bar) and make it open Awards.
  - When rest ends, keep a "Rest over · Log set N" state until the next tap, and add `.sensoryFeedback(.warning, trigger:)`.

### P1-7 Tap targets below Apple's 28 pt minimum

- **Evidence**:
  - Rep pills: each value gets about 26 pt of width (12 values in the row, `SetEditorControls.swift:133-157`).
  - Crew kudos and comment buttons are about 14–19 pt high (`PostCardView.swift:52-69`).
  - The Today dismiss X is a 13 pt glyph with no frame (`TodayView.swift:514, 1053`).
  - Override chips are about 25–26 pt (`TodayView.swift:1690`, `WorkoutView.swift:3826`, `CoachView.swift:1560`).
  - The paywall Restore, Privacy and Terms links are about 15 pt high (`PaywallView.swift:120-131`).
  - The grams capsule is about 18 pt (`FoodSearchView.swift:189-203`).
  - The training-report close button is 32 pt.
  - At 11 sites in Settings, `.frame(minHeight: 44)` sits outside the Button, so the hit area is only the text (for example "Sign out" `SettingsView.swift:134`, "Delete account" `:141`).
- **Rule**: HIG › Accessibility › Mobility and HIG › Buttons: on iOS the default target is 44×44 pt and the minimum is 28×28 pt. Leave about 12 pt between controls.
- **Fix**:
  - Put `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())` inside each button label.
  - Reps: show about 7 values around the target (about 48 pt each), with − and + to shift the range.

### P1-8 VoiceOver gaps

- **Evidence**:
  - **Icon-only buttons with no label**: the onboarding name clear button (`OnboardingView.swift:603`), the referral share button (`ReferralView.swift:39`), the Crew week chevrons (`CrewView.swift:278`), the PR share menu (`PRSheet.swift:33`), kudos and comment (`PostCardView.swift`), and the watch ± buttons (`WatchExerciseView.swift:140`).
  - **Silent chart**: `V3WeekBars` sets `.accessibilityElement(children: .ignore)` with no label (Fuel protein, Recovery sleep).
  - **Wrong label**: the hero chart label always says "up", even when the percentage is negative (`ProgressOverviewCards.swift:69-73`).
  - **Selection by color only**: selected chips have no `.isSelected` trait (Today time-box chips, onboarding day buttons, grams presets, kudos, coach picker).
  - **Missing header trait**: section headers lack `.isHeader` (`V3SectionHeader`, `InsightsSectionHeader`, `SettingsView.section()`).
  - **Gestures with no action**: swipe-to-log (`WorkoutView.swift:3742`) and the long press on a coach bubble have no accessibility action.
- **Rule**:
  - HIG › Accessibility: describe the interface for VoiceOver.
  - HIG › Icons: give custom icons alternative text.
  - HIG › Color and HIG › Toggles: never show state with color alone.
  - HIG › Charts: make every chart accessible.
- **Fix**:
  - Add the missing labels.
  - Add `.accessibilityAddTraits(.isHeader)` in the three header components.
  - Add `.isSelected` and a checkmark or shape to selected chips.
  - Fix the sign in the hero label.
  - Add `.accessibilityChartDescriptor` to the custom charts, or at least a summary label.
  - Add `.accessibilityAction(named:)` for the swipe and long-press gestures.

## P2: platform conventions

| ID | Finding (evidence) | HIG basis (paraphrased) | Fix |
|---|---|---|---|
| P2-1 | **Sheets with no close button**: check-in (`shots/09`), volume approval, explain sheet, badge detail, new record, Crew invite and handle setup, and the PR board and body stats opened from Today. **Done with no Cancel**: many toolbars place Done trailing and offer no Cancel. **Edits lost on swipe-down**: reflection note, private profile, custom exercise, custom food, fuel targets, session edit mode and set feedback lose unsaved edits with no warning. | Sheets: put Cancel on the leading side and Done on the trailing side, and always pair Done with Cancel or Back. If swipe-down would lose unsaved changes, confirm first. Modality: always offer an obvious dismissal. Accessibility: offer a button as well as swipe-to-dismiss. | Wrap each sheet in a `NavigationStack` with `.cancellationAction` and `.confirmationAction` items. Add `.interactiveDismissDisabled(isDirty)` plus a confirmation dialog. Show the grabber on resizable sheets. |
| P2-2 | **Sheets stacked on sheets**: logger → summary → record, share or coach. Settings → feedback, import, account or custom exercise. Today → PR board → PR sheet. Food search → scanner or grams. Adjustments → explain. | Sheets and Modality: show one sheet at a time, and close a modal before you present another. | Push inside the sheet's `NavigationStack` (`navigationDestination`). Close the logger first, then present the summary. |
| P2-3 | **Custom navigation chrome**: Today has its own header, and when you scroll the compact bar shows only Ask, not Settings (`TodayComponents.swift:897-915`, `shots/11`). A floating ▶ button covers content and has no text (`TodayView.swift:2085-2107`). Progress pages hide the system title and draw a 30 pt title in the content. Lift collection and Awards hide the bar background. The Timeline pinned bar is an opaque fill. | Branding: express the brand through familiar components, and keep standard sizes, placement and behavior. Layout: prefer scroll-edge effects to solid backgrounds under controls. | Use a system `NavigationStack` title plus `.toolbar` for Ask and Settings, so both stay visible while you scroll. Replace the floating button with the labeled Start button, or a bottom `.safeAreaBar` whose label names the session. Use `.scrollEdgeEffectStyle` instead of opaque bars. |
| P2-4 | **Color meanings clash**: the non-interactive "First time" flag uses the same orange as the "Details ›" link beside it (`shots/06`). Tonnage and loads are red (`shots/08`), and red also means Delete. "Send feedback" (orange) and "Delete all training data" (red) look alike (`shots/20`). Toggles use two tints, orange and brown (`shots/17`, `18`). A blue pill and blue rest time add a third accent color. | Color: do not use one color for two meanings, especially interactive versus plain text. Buttons: red is for destructive roles. Toggles: change the tint only when needed, and keep it consistent. | Use orange text only for things you can tap. Show stats in the label color. Keep red for destructive and negative states. Use one toggle tint. |
| P2-5 | **Duplicated system settings**: Settings has an app Appearance picker (System, Light, Dark; `SettingsView.swift:623-630`, `ForgeApp.swift:110`). It also has an in-app Language picker that writes `AppleLanguages` next to "Open in iOS Settings" (`shots/19`). | Dark Mode: avoid an app-specific appearance setting. It makes people manage two settings, and the app can look broken when it ignores the system choice. Settings: System Settings owns language. The HIG does not name in-app language pickers, so removing it is a team call. | Remove the Appearance picker. Keep only the "Open in iOS Settings" row for language. |
| P2-6 | **Settings is one long scroll of 15 cards**. Several controls have no label: Hypertrophy/Strength/Both, the experience picker, "Auto", "Off/Minimal/Standard", "Cloud (most accurate)" and "Follow app language" (`shots/17`, `18`, `19`). The injury toggles sit under the equipment toggles with no heading. Destructive rows are red text without `role`. | Settings: keep settings few and easy to find. Writing: settings labels must be clear, with a line that explains what the setting does. Layout: use progressive disclosure. | Use a `Form` with sections and pushed subpages (Training, Coach, Voice, Plates, Notifications, Data, Subscription, About). Name every picker with `LabeledContent`. Add an "Injuries to work around" section. Note: branch `claude/settings-page-mock-design-fb6362` is already redesigning Settings, so check these points there. |
| P2-7 | **Onboarding**: 15 steps before the app, including a photo step and a fixed 2.5 s "building" screen (`OnboardingView.swift:1265-1275`). The keyboard's Done pill overlaps Continue, and page content shows through under the pinned Continue button (`shots/12`). The "work around" step uses square checkboxes (`shots/13`). | Onboarding: keep it brief, postpone setup that is not essential, and let people experience the app before a purchase prompt. Loading: the best loading ends before people notice it. Layout: respect safe areas. Toggles: on iOS, use switches in list rows and toggle-like buttons elsewhere. The HIG describes checkboxes only for macOS. | Move the photo, current lifts and injuries steps to after the first workout. Remove the artificial wait. Use `.submitLabel(.continue)` and `.onSubmit` instead of the floating Done. Give the bottom bar a scroll-edge effect or a solid background. Use the same selectable rows as the goal step. |
| P2-8 | **Paywall**: the only way past the paywall is DEBUG-only, so a release build is a hard paywall right after onboarding (`PaywallView.swift:132-138`). "14 days" is hard-coded, with no eligibility check. Restore gives no result (`Store.swift:109-113`). Settings has no subscription summary and no way to manage the subscription. | In-App Purchase: let people use the app before asking for payment, and consider limited free access. Show the introductory offer's price, length and the regular price after it. Show the renewal date, and let people manage or cancel in the app. Feedback: when something fails, say so and why. | Show trial text only when the person is eligible (RevenueCat `checkTrialOrIntroDiscountEligibility`, or StoreKit `isEligibleForIntroOffer`). Show a result after Restore. In Settings, add a renewal-date row and `.manageSubscriptionsSheet`. Team call: consider a limited free first week. |
| P2-9 | **Coach (AI)**: no reply has a feedback or report control. No reply carries an AI marker: only on-device answers get an "On-device answer" note, and server replies look like messages from a person with a photo. A failed send puts the question back in the composer with no Retry. The thinking dots have no label. | Generative AI: say where AI is used, and never make AI output look human-written. Let people report problems with output. Put Retry or Undo near generated content. Explain failures and give a next step. | Add an "AI" tag beside the coach name in the header and on each reply, a thumbs up/down and Report menu on each reply, and an inline Retry. Label the thinking state "{coach} is thinking". |
| P2-10 | **Motion that ignores Reduce Motion**: Today parallax (`TodayView.swift:610-618`), the badge toast slide-in, the swipe row, the looping pulse while listening (`WorkoutView.swift:1443`), the looping thinking dots (`CoachView.swift:571`), and fixed `.snappy` animations in Settings, Fuel and Paywall. Exercise detail autoplays a looping video with no stop control (`ExerciseDetailView.swift:277-280`). | Accessibility › Cognitive: with Reduce Motion on, cut automatic, repeating, scaling and zooming motion, and use fades instead of slides. Give video a start and stop control, and respect the autoplay setting. | Read `accessibilityReduceMotion` in these places. Check `UIAccessibility.isVideoAutoplayEnabled`, and add a play/pause button. |
| P2-11 | **Charts**: the custom charts (hero line, trends dot plot, weight chart, lane Canvas) are hidden from VoiceOver. The Balance bar tells segments apart by shade only. The lift chart's selected-point popup is not announced. | Charts: make every chart accessible (Audio Graphs or a descriptor with a summary), and do not rely on color alone. Separate adjacent color areas. | Add `AXChartDescriptor`. Label each Balance segment in place, or add swatches and separators. Post an announcement when a point is selected. |
| P2-12 | **Workout logger**: two lists of exercises ("Up next" and the full list, `shots/06`). The weight-ruler numbers measure 1.77:1. The partial-finish alert labels its cancel button "Keep going". The typed-weight field is capped at `.large` (`WorkoutView.swift:3085`). | Design principles › Simplicity: include only what is needed. Accessibility contrast: 4.5:1 for small text. Alerts: title the button that cancels "Cancel". | Keep one list. Darken the tick labels near the value. Use `Button("Cancel", role: .cancel)`. Team call: set `isIdleTimerDisabled` during a workout (not set today) so the screen stays on. |
| P2-13 | **Crew**: the tab is a sign-in card with no title and no preview (`shots/16`). Failures are silent: the feed looks empty on error, and the Rings spinner never stops. Posts have no report or block option. | Managing accounts: explain what an account brings, and delay sign-in. Writing: give a next step on blank screens. Feedback: say when something fails. (Report and block for user content is an App Review rule, not HIG.) | Show a sample crew and a title. Add error states with Retry. Add report, block and mute. |
| P2-14 | **Text input**: many fields have a placeholder and no label (Crew handle, comment, referral, barcode, custom food, email, code). Email lacks `.textContentType(.emailAddress)` and the code field lacks `.oneTimeCode`. Custom-food numbers are parsed with `Double(String)`, which rejects a comma decimal separator (Vietnamese). `String(format: "%.1f")` is used in plates, PR and exercise detail. | Text fields: show a hint of purpose, add a separate label, show the right keyboard, and use a number formatter because formats vary by locale. Inclusion: support local number formats. | Add labels. Use `TextField(value:format:)` with `.number`. Add content types. |
| P2-15 | **Silent failures and dev text**: Feedback "Send" always shows success (`FeedbackSheet.swift:10-45`). Referral counts read 0 after an error. Comment posts fail silently. Barcode lookup errors are hidden. "Google sign-in is not configured in this build" and dev-code autofill are not gated to DEBUG (`AccountView.swift:35-66`). | Feedback: say when something cannot be done, and why. Writing: error messages say how to fix the problem. | Show real error states. Gate dev strings with `#if DEBUG`. |
| P2-16 | **Watch app**: text is 11 pt in 4 places, below the watchOS 12 pt minimum (`WatchRootView.swift:30, 111`, `WatchExerciseView.swift:65, 92`). There is no Dynamic Type. The ± buttons are 38 and 30 pt and have no labels. "End workout" has no confirmation. | Accessibility and Typography: on watchOS, 12 pt minimum, 44×44 pt default target, 140% text enlargement. | Use 12 pt or larger with `relativeTo:`, 44 pt buttons, and labels such as "Decrease weight". Confirm End workout. |
| P2-17 | **Widgets**: the system widgets use a fixed dark `#1C1C1E` background in light mode as well (`WidgetTheme.swift:7`). Fonts are fixed sizes. No `widgetAccentable` groups. | Widgets: support light and dark appearances, prefer system text styles (Dynamic Type from Large to AX5), and group content into accented and primary groups. | Use adaptive backgrounds and text styles. Mark the key number with `.widgetAccentable()`. |

## P3: polish

- **Jargon**: RPE, e1RM, tonnage, deload, block and meso appear without definitions. The check-in's 1–5 scales have no end labels, and it is unclear whether a 5 for soreness is good or bad (`shots/09`). Inclusion and Writing: define specialized terms, and use plain language. Add "Poor … Great" end labels.
- **Copy**:
  - "1 sets" (`shots/08`): use `^[\(n) set](inflect: true)`.
  - Several screens show English strings outside the catalog: Goal roadmap, Week designer, Program import, Routine adaptation, and Coach errors.
  - HealthKit: in user copy, write "Apple Health", not "Health" (the check-in says "from Health").
  - Remove "Tap – / + to set".
- **Icons**: the Today shortcuts use 3D clay illustrations while the rest of the app uses SF Symbols (Icons: keep icons consistent in style and weight). The Photos camera glyph opens the photo library. `chevron.right` is used 43 times and `arrow.right` 8 times; use `chevron.forward` so they flip in right-to-left languages. This only matters if you add Arabic or Hebrew.
- **Summary**: stat numbers are colored blue, amber and red with no meaning (`shots/08`). The new-record sheet opens by itself 850 ms after the summary appears, which stacks a sheet on a sheet.

## Screen index

| Area | Screens | Findings |
|---|---|---|
| Onboarding | Welcome, coach, name, science, goal, experience, loop, days, length, equipment, numbers, workarounds, photo, building, summary | P1-1, P1-8 (name clear button), P2-7, P3 jargon |
| Paywall and account | Paywall, Account sign-in, Referral | P1-2, P1-3, P1-7, P2-8, P2-14, P2-15 |
| Today | Today, check-in, adjustments, explain, volume approval, collapsed header | P1-1, P1-4, P1-5, P1-6, P1-7, P2-1, P2-3, P2-4, P2-10 |
| Workout | Logger, rest panel, voice card, plates, swap, add exercise, note, why, set feedback, summary, new record, PR, exercise detail, share composer, training report | P1-4, P1-5, P1-6, P1-7, P1-8, P2-1, P2-2, P2-10, P2-12, P3 summary |
| Coach | Chat, voice mode, consent | P1-4 (mic, cloud audio), P1-5, P1-8, P2-9, P2-10 |
| Progress | Overview, trends, lift detail, lift collection, awards, PR board, muscles, balance, body stats, photos | P1-5 (photos, measurements), P1-6 (badge toast), P1-8, P2-3, P2-11 |
| Timeline and history | Timeline, note editor, hidden items, private profile, about, history, workout detail, blocks, recovery | P1-6, P1-8 (sleep bars), P2-1, P2-3 (opaque pinned bar) |
| Fuel | Day, targets, guidance, food search, grams, custom food, scanner | P1-4 (camera), P1-5, P1-7, P2-1, P2-2, P2-14 |
| Crew | Root, post and comments, handle setup, profile, invite | P1-7, P1-8, P2-1, P2-13 |
| Settings and plan tools | Settings, training setup, gym editor, exercise rules, experiments, equipment passport and editor, goal roadmap and editor, program roadmap, muscle emphasis, adjustments and detail, week designer, move session, plan audit, program import, copy routine, adapt to me, routine library, feedback, import, custom exercises | P1-5, P1-7 (11 sites), P2-1, P2-5, P2-6, P3 copy |
| Watch | Root, exercise, rest, coach | P1-1, P1-5, P2-16 |
| Widgets | Home (small and medium), Lock Screen (circular and rectangular), rest Live Activity | P1-1, P2-17 |

## How to verify the fixes

1. `xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`, then walk every tab. No text may be clipped and no controls may overlap.
2. Run the Accessibility Inspector audit on Today, Logger, Progress, Coach and Settings, in light and dark mode.
3. Walk the same five screens with VoiceOver: every control has a name, and selected states are read out.
4. Turn on Reduce Motion and Increase Contrast, and check the items in P2-10 and P1-2.
5. Start from a fresh install (`xcrun simctl erase`) and confirm the permission order: nothing asks at check-in or at logger open, only when the related feature is first used.

## Status after the fixes (2026-09-30)

All P1, P2 and P3 items were implemented on branch `claude/apple-hig-skill-check-93ce9c`. Exceptions and deliberate choices:

- **Text size (P1-1)**: text follows Dynamic Type up to AX3 (about 235 %, above Apple's 200 % target), not AX5. Glyphs grow up to 1.6×. The workout's 58 pt weight × reps numbers keep their size.
- **Primary buttons (P1-2)**: the fill is `#F5621C` in both appearances (white bold label 3.16:1, above the 3:1 minimum for bold text; dark mode was 2.60:1) and `#C2460C` with Increase Contrast (5.03:1).
- **Kept because DESIGN.md requires it (owner-approved)**: the floating round Start button on Today, the clay icons in Today's shortcut row, and the in-content 30 pt titles on Progress pages. The hard paywall after onboarding stays (business decision); its debug-only bypass is unchanged. The partial-finish alert keeps "Keep going" (QA decision FQ-13), now with the cancel role.
- **Restart the block from Coach**: this action has no undo in the app's undo system, so it now asks for confirmation instead.
- **Correction to P2-4**: the orange "First time" tag in the logger is a button (it opens "Why this weight?"), so the link color is right; it was left as is.
- **Comment reports**: the comments API returns no author handle, so Block is offered on a comment only when the post's author wrote it.
- **E2E flows**: eight small flow edits are needed for removed or moved UI (onboarding photo step, Settings Appearance row, the onboarding keyboard Done button, the coach consent step before voice, history edit discard, Import and Feedback now pushed inside Settings). They are applied in the same pull request; the E2E suite has not been run against them yet.
