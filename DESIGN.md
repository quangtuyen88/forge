# Regulift Design System

## Clean light-first system, one orange accent

This file is the canonical visual contract for Regulift. References studied on Appllama: Lyfta (visual language) and Lungy (flow grammar). Product UI must stay glanceable at arm's length during training.

## 1. Color

One action accent: Huawei brand orange. Metric roles follow Huawei's rings; gradients live on data marks only.

| Role | Light | Dark | Usage |
|---|---:|---:|---|
| Accent | `#F5621C` | `#FF7A33` | Fills, tint, icons, selection, progress, rings |
| Accent text | `#C2460C` | `#FF9F5A` | Orange text on page and card surfaces |
| Accent strong | `#C2460C` | `#C2460C` | Fill behind small white text: selected rows, badges, chips |
| Accent fill | `#F5621C` | `#F5621C` | Primary buttons: fill behind the white label |
| Move (red-orange) | `#C8331B` | `#FF6B4A` | Sessions, load, tonnage, e1RM, effort, energy, streaks |
| Exercise (amber) | `#9A5B00` | `#FFC23D` | Sets, reps |
| Stand (blue) | `#1C63E0` | `#5AA9FF` | Elapsed time, rest countdowns, schedule |
| Sleep | `#6A4BDD` | `#B39DFF` | Sleep |
| Heart | `#C9214A` | `#FF5C7A` | Heart rate |
| Body (blue) | `#1C63E0` | `#5AA9FF` | Body weight (the Stand blue) |
| Done | `#1E8E3E` | `#30D158` | Logged sets, completed sessions, gains |
| Done text | `#15703A` | `#30D158` | Gains as text (+2.5 kg) |
| Record | `#B45309` | `#FFD60A` | Records, PRs, trophies |
| Destructive | `#D70015` | `#FF3B30` | Delete, critical errors |
| Plate gold | `#FFD60A` | `#FFD60A` | 15 kg / 25 lb plate only |
| Field | `#FFF1E8` | `#1E1612` | Warm peach field behind a Progress screen's top block and nav bar (`Theme.field`) |

- White text on orange only at ≥ 19 pt bold (WCAG AA large text); smaller white text sits on accent strong.
- With Increase Contrast, accent fill deepens to `#C2460C`; `accent`, `accentText`, `textSecondary` and `textTertiary` each take an Increase Contrast variant.
- RPE zones run blue → red for RPE 6–10 (`Theme.zones`).
- Gradients are allowed on data marks only — rings, bars, capsules, dots, chart lines and areas — deep → bright in the direction of progress (`Theme.grad*`); text, buttons and icons stay flat.
- Numbers stay in the text color; a colored dot names the metric.
- The peach field is a surface, not a metric color: numbers on it stay ink, and each block carries at most one orange focal mark.

Never add a second accent.

## 2. Surfaces

| Token | Light | Dark | Purpose |
|---|---:|---:|---|
| Page | `#FFFFFF` | `#000000` | Detail screens |
| Page grey | `#F2F4F6` | `#000000` | Today pages |
| Card | `#FFFFFF` | `#1C1C1E` | Grouped content, flat white (no border, no shadow) |
| Row | `#EEF2F4` | `#2C2C2E` | Option rows, inputs, secondary buttons |
| Track | `#E1E6EA` | `#3A3A3C` | Inactive progress and controls |
| Sleep wash | `#F5F3FF` | `#2A2735` | Today tile that needs a check-in |
| Body wash | `#F2F6FE` | `#232B38` | Today tile that needs a weigh-in |
| Timeline row | `#F2F4F6` | `#1C1C1E` | Progress Timeline entries and idle filter chips |
| Timeline tile | `#FFFFFF` | `#3A3A3C` | 32 pt glyph tile inside a Timeline entry |
| Text | `#0F0F12` | `#FFFFFF` | Labels and values |
| Secondary text | `#5F6672` | `#98989F` | Supporting copy, WCAG AA on every surface |

Today sits on the grey page with flat white cards; the v6 Progress screens use the white page with the peach field on top and hairline lists below (§12). Detail screens keep the white page and separate sections with 8 pt grey bands.

## 3. Shape

Actions are capsules. Cards are 16 pt, Today included. Rows and inputs are 10 pt. Chips are 8 pt. All corners continuous. No other radius.

## 4. Typography

- Inter Tight everywhere. One display size per screen.
- Text follows Dynamic Type up to AX3 (about 235 %); nothing is smaller than 11 pt. At accessibility sizes, rows stack their trailing value under the title instead of breaking words. The workout's big weight × reps numbers stay at their size (they are already larger than any body text).
- System glyphs use `scaledSystemFont(_:)`, so they scale with Dynamic Type, up to 1.6×.
- The app follows the system appearance; there is no in-app Light/Dark setting.
- Workout numbers 44–56 pt bold, tabular digits. Value first, unit smaller and quieter.
- Sentence case. Onboarding and paywall headlines are centered and bold; at most one phrase in the accent color.

## 5. Option rows and buttons

- Option row: pale row fill, leading symbol, title, optional subtitle. Selected = solid accent strong fill (#C2460C), white text, white check. No border in either state.
- Onboarding goal and equipment rows lead with a 56 pt photo tile (8 pt corners, 1 pt image outline), identical on plain and selected rows: the chosen coach training for that goal; a real training place for each gym preset.
- Primary button: orange accent capsule, white 19 pt bold label, 56 pt. One per screen.
- Secondary button: row-fill capsule, text color label.
- Destructive: red text, never a filled red button next to a primary.
- Icon badge: the symbol in its category color on a 14 % fill of the same color; circles on tiles, 8 pt rounded squares on list rows. Neutral rows use the accent.
- Settings rows are the exception: their glyphs use the secondary text color, so the plan chips stay the only orange above the fold (owner's pick B, 2026-09-30).

## 6. Flow grammar (Lungy pattern)

- Welcome: a photo of Nova and Kai fills the top of the screen (no status bar on this page); a white sheet with 16 pt top corners carries the brand, one line, "Build my plan" and the text button "I already have an account" (sign-in).
- The coach is the first choice. From then on the chosen coach's face (a 56 pt photo) anchors every question at the same place, over a three-stage bar (About you, Your week, Your plan); the lifter's name comes next and the coach uses it ("Nice to meet you, Alex.", "Week 1 is ready, Alex").
- One question per page. The chosen answer explains what it changes, inline, under the option. The workaround question uses option rows, like every other question.
- A short statement page sits between question groups. It says one true thing about the product. It leads with a 16 pt photo card of the coach or the lifter and says "Got it"; questions say "Continue".
- The core loop is shown, not tried: "You log. <coach> programs." pairs the lifter's own view of logging a set with the real next load (64 kg × 8 at RPE 7 → 67.5 kg next session) and what RPE 8 means.
- No progress photo is taken in onboarding; photos are added in Progress.
- A brief "building your plan" moment precedes the plan reveal; it lasts about a second. It names real steps. The ring holds a photo of the coach writing the plan.
- Paywall states the trial timeline with real dates and prices.
- Today opens with the greeting, the "Today" title, an **Ask <coach>** voice button (waveform + "Ask Nova") and settings. The button opens voice mode listening at once; when the header scrolls away the inline title keeps the waveform button and the settings gear.
- The **week rings card**: open rings for Sessions / Sets / Time (`ArcRings`); stat columns of a colored dot + label, the number, and "/target unit" on its own line; a streak badge; a "Protein today" pill (the Log food action).
- The **session card** leads Today: the coach's photo of the lead lift as a square on the card's trailing edge, with the day name, "≈ N min · M sets", the readiness word and the week on the card beside it, and "View plan"; below it a strip of the next lifts as coach photos (a tap opens the muscle preview), then the one main action in the order Resume, Check in, Train anyway, Start. Order on a training day: header, session card, readiness pills, week rings card, shortcut row, tiles, the conditional cards, and last the Ask grid.
- A **readiness pill**: "Checked in · slept N h", or a check-in prompt when the next session is offered without a check-in. When the next session repeats a muscle trained today, a second pill says so.
- The **check-in sheet** has Cancel, end labels under each 1–5 scale, and asks for Apple Health only from its "Use Apple Health for sleep" button.
- A **shortcut row** of orange clay icons: Plan, Readiness (the check-in), Weigh-in, Records. The shortcut never reads "Check in": that label belongs to the main action. Asking the coach lives in the header button and the Ask grid.
- **2-column tiles**, always an even count (4 when possible): Nova's call, lift trend, Sleep, Resting HR — Body weight takes the fourth place when only one of lift trend and Resting HR has data. Tiles stay white; each carries one metric color, shown only by a filled SF Symbol in the top-right corner (where the coach tile has its avatar) and by its chart: lift dumbbell.fill in metricLoad over the route line, Sleep moon.fill in metricSleep over bars on a 0–9 h scale, taller when a night ran longer (Health's nights, or without Health the last check-in of each day), Resting HR heart.fill in metricHeart, Body weight scalemass.fill in metricBody over a blue line. Only a tile that needs the lifter is tinted: Sleep before today's check-in (without Health sleep) and Body weight before the first weigh-in sit on their wash (sleepWash, bodyWash) with a hairline ring in their metric color, a muted "—", their clay object (art-sleep, art-numbers) cropped into the bottom-right corner and an orange link with a chevron ("Check in ›", "Weigh-in ›"; "Not logged yet ›" when today's check-in has no sleep hours); a single weigh-in shows a flat track. With Health on, Sleep reads a plain "—" and the fourth tile waits until Health has loaded, so the check-in prompt never flashes and Body weight never swaps for Resting HR. After a check-in the filled Sleep tile fades in while the sheet closes (the empty one leaves at once) and its bars grow in one after another as the sheet clears (Reduce Motion: the fade only). A first-time lift on the coach's tile reads "First" and the lift's own name ("First Deadlift") over an outlined, empty Last bar. The **Nova's call** tile shows one decision — the exercise art, the new value, the change vs last time — and opens its "Why this weight?" explanation; "N changes" opens every change in a sheet, where Easier / Keep / Harder live. "This week's plan" and the other conditional cards stay under the tiles.
- The **Ask <coach> grid**: four illustrated questions in 2 columns — "What's my plan today?", "Show my last workout", "Why this weight?", "Am I recovered?" — each a coach photo over a label band. A tap opens voice mode with that question asked; the plan and last-workout answers carry their card.
- When the main action scrolls away, a **floating round Start button** replaces the Start bar.
- Today has one main action per state, in this order: Resume, Check in, Train anyway, Start. On a plan rest day the task card reads "Next up · <date>" and "Nothing is scheduled today.", and Start is the secondary pill. An empty week shows only the "Plan this week" card. The adjustment summary sits directly under the task card.

## 7. Active workout

- White page; the session name on the left, "Finish" in orange text on the right.
- Exercise-name tabs with an orange underline on the active tab.
- Centered Elapsed / Load / Sets stats; 8 pt grey bands separate sections.
- The set section: the anatomy art (128 pt, orange = the working muscles), name, equipment, "Set n of N" with one pip per set (logged green, current accent, the rest track); a plain line "Target RPE · Rest" with the decision link and Details; the big weight × reps numbers; a ruler with an orange indicator; amber rep capsules between − and + buttons (44 pt; a tap on the capsules still sets the count); mic + Log set.
- Every exercise inside Workout is drawn with the anatomy art (ExerciseArt), never a coach photo: the muscles are the information there.
- "Effort by set" chart in RPE zone colors with a dashed target line.
- One exercise list: a card per exercise in the queue (anatomy art, name, prescription) and "Add exercise" at the end; there is no "Up next" list.
- The rest panel: the open-ring countdown sits on a neutral band beside the coach's rest photo; the next set with its anatomy art; "How hard was set n?" as the headline with the target in plain text; RPE chips 6–10 with zone bars — the selected chip takes the zone gradient, with dark text on the yellow zone; −30 s, Skip rest, +30 s; "Get a banner when rest ends" until notifications are decided.
- A "Rest over" banner stays until the next set.
- After a save, a receipt above the editor names the set ("Set n · saved on this device") with the recorded load, reps, reported effort and the feedback entry. A failed save shows an inline error under the steppers, keeps the numbers and starts no rest.
- The chip says "Target RPE"; the stepper row says "Your RPE". An untouched stepper is never saved or announced as a reported effort.
- While a field has the keyboard, `Log set` also sits in the keyboard toolbar. The rest panel previews the next set and its target, and its controls ignore taps for 0.6 s after a rest starts.
- `Log set` is the single accent capsule. Active set editor and the primary action stay visible without scrolling.
- Finishing shows the new records and the summary in the same sheet.

## 8. Charts

- Metric title, one large accent value, compact range control, then the plot.
- Charts may use the RPE zone colors and the data-mark gradients of §1.
- Bars for weekly totals, lines for e1RM. Sparse axes, quiet grid, current period full opacity, earlier periods muted.
- One metric per card.
- Trends dot plot: every lift shares one % scale per screen — open circle at the start of the range, orange dot at now, grey for a dip, dashed tick gridlines; ticks every 5 % up to a 20-point span, every 10 % up to 50, else every 20 %, with both ends rounded to the step so 0 % is always a tick, and the scale row pins under the nav bar while the list scrolls.
- Overview strength line: the weekly mean % change as an accent line with a flat area fill, no axes; the end dot turns gold when a record landed in the last 7 days.
- Lift trends: the Today lift tile is the one route-gradient (green → red) line with a hollow start dot and a filled end dot. The change reads as plain text (`+19 kg` in green, `Holding`, `−2 kg`); a dip is never red.
- A lift page plots one dot per workout joined by a thin line, directly on the peach field: the current training block at full strength, earlier blocks muted, record workouts gold, and a dashed orange "Today's target" line for the planned session. Press and hold, then drag, to read a workout (date, estimated max, set) with a selection haptic on each snap; a swipe that starts on the chart still scrolls the page. Ranges are training blocks (`Block 1 / Block 2 / All`), never weeks.
- Records are a staircase: one step per record.
- Week bars (Recovery sleep, Nutrition protein): 7 bars with dashed outlines on missing days, protein against a dashed goal line.
- The consistency week strip: one column per program week, rows of planned sessions — done as filled accent dots, missed as a small × in secondary, still-planned as track dots, today's planned session with an accent ring; the current week sits on a row-fill background, block labels run under a 2 pt top rule.
- Program roadmap: a road strip of blocks (previous complete, current with its sessions, next with its start date) above a sets-per-week chart that is also the week picker. Done weeks are solid `gradExercise` bars, this week is an outline that fills as sets are logged, planned weeks are dashed amber; labels under the dates read Now, Peak and Deload. The selected week's sessions sit directly under the chart; plan tools live in the toolbar menu and Week designer is the one link under the week.
- Changes that wait for the lifter ("Needs your OK") show where the lifter already looks: a pill next to the check-in on Today, the Kai's call tile, and a tinted row at the top of the roadmap's This week. All three open the same review sheet: the change as numbers (3 → 4 sets), one reason, Approve and a decline that names what stays. Approve on Today leaves an "Added · Undo" pill that stays until Undo, dismiss, a new change or leaving Today.

## 9. Voice

- The header names the coach and says "AI coach". Coach replies are attributed "<coach> · AI" and carry a Helpful / Not helpful / Report row.
- Voice stays inline with the active set.
- Idle: quiet microphone. Listening: accent orb with waveform. Failure: red mic-slash capsule with one short message.
- Coach voice mode covers the chat. The live transcript is the display text, with words still being recognized in secondary. The accent disc with its waveform sits in the thumb zone and is the send control; one flat ring follows the voice level. Close and keyboard flank it and never move between states. When the coach has answered, the disc settles into the quiet microphone ("Tap to talk") and the exchange stays in the chat.
- From Today, voice mode opens full screen over Today and closes back to it. Before the first word it offers "Try asking" chips. "What's my plan today?" answers with a plan card (a row per lift: coach photo, name over sets × reps · load; Start, or Resume while a workout is open), "Show my last workout" with a report card (duration, sets, load, the record if one landed, a row per lift, Open workout). Spoken questions reach those cards through TodayAskIntent, which matches English, Japanese, Korean and Vietnamese phrasing; the tiles and chips pass the kind directly.
- Workout chat: the debrief card's questions open a chat about that one workout (zoom from the card). The title is the workout, the first message is the debrief, coach answers carry a 2 pt flat accent rule on the left and, when they name a lift, its next-load token or an effort-by-set chart (a dashed target line, sets over target in the effort color); the Coach tab uses the same answer style, with evidence only under answers given in the current conversation (next load from the next planned session, effort from the lift's latest workout). Only that workout leaves the device, and the chat says so. Voice mode keeps its layout and adds the workout under the coach's name.

## 10. Imagery

**Coach photographs** are the only people in the app. One shoot, one gym: Nova and Kai (identity from the Coach tab photos) in the charcoal gym with steel racks and orange bumper plates, a soft key light from the front left, one grade; the rules and prompts are in `docs/design/illustration-style.md` ("Coach photographs"). Scenes `<coach>-scene-<name>` (10 lift families: deadlift, overhead press, pull-up, curl, calf raise, squat, bench, row, lateral raise, leg raise; 8 story scenes: plan, last workout, why this weight, recovered, rest, record, wave, flex) are square photos in Assets.xcassets/CoachScene; `<coach>-face` is a crop of the coach's avatar photo; the onboarding photos live in Assets.xcassets/Onboarding. CoachScene.forExercise maps any exercise to its lift family (mood, not form instruction). Always the chosen coach. Used on Today (session card, strip, the Ask grid), in voice-mode cards, on the rest panel, on the Experiments choice tiles, as the Trends group thumbnails (legs: squat, push: bench, pull: row, core: leg raise), in the coach avatar everywhere, in the Coach tab, the paywall and onboarding. Every photo is decorative (`accessibilityHidden`, `allowsHitTesting(false)`), fills its frame (`scaledToFill`, clipped) and never carries text: text sits beside or below it on a Theme surface. No stock photography: every photo comes from the coach shoot, and photos show no text or logos (a phone screen may show digits-only app UI).

**Clay objects** stay for tool headers and empty states: friendly soft-3D, matte clay, rounded chunky shapes, soft light from the upper left, one soft contact shadow, transparent background, no text, no people (the goal symbols' clay arm is a symbol, not a person). Art palette: the orange family (Huawei-style orange 3D) — deep orange `#F0412B`, brand `#F5621C`, amber `#FFA10A`, peach `#FFC09A`, cream highlights, charcoal details. Muscle highlights are orange: primary deep orange-red, secondary peach. Every clay illustration and equipment thumbnail is generated with the GPT image model through Codex from one style sheet (`docs/design/illustration-style.md`), so the family stays consistent; `scripts/recolor-art.py` keeps art in the palette; art colors live only inside the images, never in UI chrome. Body metrics and tool rows use filled SF Symbols in the metric colors (Apple-Health style), no icon containers. Functional visuals: muscle maps, plate graphics, mini charts, PR cards. No emoji in chrome.

Clay art carries a Progress tool screen's header (`ProgressLargeTitle(art:)`), 68 pt, never tinted icon squares — art-schedule, art-blocks, art-audit, art-flask, art-balance, art-numbers, art-camera, art-sleep, art-bowl, art-pro, art-goal, art-equipment, art-empty-progress, goal-hypertrophy.

## 11. Implementation rules

- Use tokens from `App/Forge/Theme.swift`; never hard-code palette colors in feature views.
- Support light and dark, Dynamic Type, VoiceOver, 44 pt minimum targets, Reduce Motion.
- Simulator verification covers light, dark, Dynamic Type XL and the rest timer.
- The rules a machine can check — no gradient, glow or drop shadow, no uppercase display text, no hard-coded palette color, no "sparkles" symbol — live as ast-grep rules in `lint/design/` and run as `make check-design` (part of `make test`). Add a one-line `// ast-grep-ignore: <rule id>` only where the exception is real, with the reason in the same commit.

## 12. Huawei flat pages: Today and Progress (scoped exception)

Today and Adjustments sit on the flat grey page (`Theme.pageGrey`) with flat white 16 pt cards — no sky gradient, no border, no shadow in light; dark keeps the soft card ring. All gradient and shadow code lives in `App/Forge/TodayStyle.swift`, the only file exempt from `design-no-gradient` and `design-no-shadow`. Approved by the owner on 2026-09-25 (Today: A3 v3; Progress: the lift-collection redesign). Lift trends (approved 2026-09-26) add the per-lift lines of §8; on Trends, v6 replaces them with the dot plot. In dark appearance a lift token shows the figure without the art's white background on a `Theme.track` disc (`ArtCutout`). Adjustments (approved 2026-09-28) shows the block as one canvas: a lane per lift with its load steps, the current week tinted orange, a hollow ring for a planned or waiting change; the detail page opens on a flat accent-tint hero with before and after rep bars. Every other screen keeps §1–§11.

Progress v6 (approved 2026-09-29: Trends "v10 B+C", Overview, lift page, Experiments) puts those four screens on the white page with the peach field behind the top block and the nav bar, and hairline lists below — no cards. Shared helpers in `App/Forge/ProgressSurfaces.swift`: `FieldSection` (the top block on the field), `.progressFieldPage(title:)` (the page chrome), `ArtThumb` (a rounded decorative thumbnail). The Overview carries one message: the mean % hero on the field, then "Your lifts", "Your body" and "More" hairline lists (tool rows as SF Symbols). Trends opens with "N of your M lifts got stronger since <month>." over the §8 dot plot. The lift page makes the graph the hero on the field with a "Recent" list below. Experiments states "Test one change" over photo tiles. The Timeline (v5.1, approved 2026-09-29) joins them. On the field: the week button (the month outside the current month) that opens the month menu, a round "…" menu, and one summary sentence ("This week you trained 1 of 3 days and set 3 records. Full B is next: Deadlift 140 kg × 8."). On the page: text filter chips and a 1 pt rail with a 7 pt dot per entry. Entries are compact 10 pt rows on `Theme.timelineRow` with a 32 pt SF Symbol tile (`Theme.timelineTile`) or the coach avatar, one gold record line on workouts, and the coach's pending change on the accent tint with the only solid orange button in the list. A centred label with the week's sessions and records separates weeks. While scrolled, a floating glass week pill (`floatingGlass` in TodayStyle.swift) and the chips pin under the segment control. Long press opens the system context menu (Open workout, Add a note, Hide from timeline; hiding is reversible, so it is not red). "Add a note about today" lives in the "…" menu and an empty month offers "Add a note". Only today's check-in shows. Parts live in `App/Forge/TimelineV5Parts.swift`. The lift page adds a Next time block for every lift (the next planned session, its load × reps, and a record or holding line), a next-target ring and legend on the graph, the coach's pending change for that lift, and Records in the stats. Muscles, Plan audit, Adjustments, Balance and the Experiments picked state (approved 2026-09-29) use the same field hero: one sentence with clay art, then hairline lists with 44 pt muscle thumbnails (`MuscleRegionThumb`) and one Review pill per pending ask. "Last 7 days" means today and the six days before. Lift collection and Awards keep the grey page with white cards. Screen names follow the v3 renames: Mesocycles → Training blocks; Recommendation effectiveness → Adjustments; Measurements → Body stats; "Muscles this week" → "Muscles, last 7 days".

Settings (approved 2026-09-30, mock v7 with option B) uses the same field grammar. The field states the plan as one sentence with chips ("Kai plans 3 days a week, 60 min each, to build muscle"); each chip opens a sheet whose options show their split and weekly sets, a "Now" tag on the current option and the change on the picked one, and the round accent-strong check applies it. The note under the sentence turns into "Plan updated · Undo", which stays until Undo, another change or leaving Settings. Below: Training, Coach, App and Account as hairline lists with grey glyphs (§5) — there is no Appearance row (the app follows the system) and Language opens the iOS per-app language page — then Send feedback, the legal links and the version. Every row pushes a field page with a one-sentence 28 pt hero (clay art where it helps) over hairline lists; deleting training data sits last on Your data with an action sheet that offers "Export CSV first". Parts live in `App/Forge/SettingsParts.swift`.

## 13. Crew

- The tab is titled "Crew".
- Signed out, it shows the sign-in card over a labelled example of the week rings.
- Posts and comments offer Report and Block.
- A Blocked people list names the blocked handles, each with Unblock.
