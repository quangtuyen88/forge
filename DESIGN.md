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
- Workout numbers 44–56 pt bold, tabular digits. Value first, unit smaller and quieter.
- Sentence case. Onboarding and paywall headlines are centered and bold; at most one phrase in the accent color.

## 5. Option rows and buttons

- Option row: pale row fill, leading symbol, title, optional subtitle. Selected = solid accent strong fill (#C2460C), white text, white check. No border in either state.
- Onboarding goal and equipment rows lead with an art tile instead of a symbol: the illustration on a 56 pt card-colored tile with 8 pt corners and a 1 pt image outline, identical on plain and selected rows; a gym preset's tile shows its equipment.
- Primary button: orange accent capsule, white 19 pt bold label, 56 pt. One per screen.
- Secondary button: row-fill capsule, text color label.
- Destructive: red text, never a filled red button next to a primary.
- Icon badge: the symbol in its category color on a 14 % fill of the same color; circles on tiles, 8 pt rounded squares on list rows. Neutral rows use the accent.

## 6. Flow grammar (Lungy pattern)

- Welcome: brand, one line, one button.
- One question per page. The chosen answer explains what it changes, inline, under the option.
- A short statement page sits between question groups. It says one true thing about the product.
- The lifter tries the core loop (log a set, rate effort, see the next load) inside onboarding, guided by the coach bubble, before any paywall.
- A brief "building your plan" moment precedes the plan reveal. It names real steps.
- Paywall states the trial timeline with real dates and prices.
- Today opens with the greeting, the "Today" title, an **Ask <coach>** voice button (waveform + "Ask Nova") and settings. The button opens voice mode listening at once; when the header scrolls away the inline title keeps the waveform button.
- The **week rings card**: open rings for Sessions / Sets / Time (`ArcRings`); stat columns of a colored dot + label, the number, and "/target unit" on its own line; a streak badge; a "Protein today" pill (the Log food action).
- The **session card** leads Today: the coach's flat scene of the lead lift on its scene panel, with the day name, "≈ N min · M sets", the readiness word and the week on the calm left side of the art, and "View plan"; below it a strip of the next lifts as coach scenes (a tap opens the muscle preview), then the one main action in the order Resume, Check in, Train anyway, Start. Order on a training day: header, session card, readiness pills, week rings card, shortcut row, tiles, the conditional cards, and last the Ask grid.
- A **readiness pill**: "Checked in · slept N h", or a check-in prompt when the next session is offered without a check-in. When the next session repeats a muscle trained today, a second pill says so.
- A **shortcut row** of orange clay icons: Plan, Readiness (the check-in), Weigh-in, Records. The shortcut never reads "Check in": that label belongs to the main action. Asking the coach lives in the header button and the Ask grid.
- **2-column tiles**, always an even count (4 when possible): Nova's call, lift trend, Sleep, Resting HR — Body weight takes the fourth place when only one of lift trend and Resting HR has data. Tiles stay white; each carries one metric color, shown only by a filled SF Symbol in the top-right corner (where the coach tile has its avatar) and by its chart: lift dumbbell.fill in metricLoad over the route line, Sleep moon.fill in metricSleep over bars on a 0–9 h scale, taller when a night ran longer (Health's nights, or without Health the last check-in of each day), Resting HR heart.fill in metricHeart, Body weight scalemass.fill in metricBody over a blue line. Only a tile that needs the lifter is tinted: Sleep before today's check-in (without Health sleep) and Body weight before the first weigh-in sit on their wash (sleepWash, bodyWash) with a hairline ring in their metric color, a muted "—", their clay object (art-sleep, art-numbers) cropped into the bottom-right corner and an orange link with a chevron ("Check in ›", "Weigh-in ›"; "Not logged yet ›" when today's check-in has no sleep hours); a single weigh-in shows a flat track. With Health on, Sleep reads a plain "—" and the fourth tile waits until Health has loaded, so the check-in prompt never flashes and Body weight never swaps for Resting HR. After a check-in the filled Sleep tile fades in while the sheet closes (the empty one leaves at once) and its bars grow in one after another as the sheet clears (Reduce Motion: the fade only). A first-time lift on the coach's tile reads "First" and the lift's own name ("First Deadlift") over an outlined, empty Last bar. The **Nova's call** tile shows one decision — the exercise art, the new value, the change vs last time — and opens its "Why this weight?" explanation; "N changes" opens every change in a sheet, where Easier / Keep / Harder live. "This week's plan" and the other conditional cards stay under the tiles.
- The **Ask <coach> grid**: four illustrated questions in 2 columns — "What's my plan today?", "Show my last workout", "Why this weight?", "Am I recovered?" — each a coach scene over a label band. A tap opens voice mode with that question asked; the plan and last-workout answers carry their card.
- When the main action scrolls away, a **floating round Start button** replaces the Start bar.
- Today has one main action per state, in this order: Resume, Check in, Train anyway, Start. On a plan rest day the task card reads "Next up · <date>" and "Nothing is scheduled today.", and Start is the secondary pill. An empty week shows only the "Plan this week" card. The adjustment summary sits directly under the task card.

## 7. Active workout

- White page; the session name on the left, "Finish" in orange text on the right.
- Exercise-name tabs with an orange underline on the active tab.
- Centered Elapsed / Load / Sets stats; 8 pt grey bands separate sections.
- The set section: the anatomy art (128 pt, orange = the working muscles), name, equipment, "Set n of N" with one pip per set (logged green, current accent, the rest track); a plain line "Target RPE · Rest" with the decision link and Details; the big weight × reps numbers; a ruler with an orange indicator; amber rep capsules; mic + Log set.
- Every exercise inside Workout is drawn with the anatomy art (ExerciseArt), never a coach scene: the muscles are the information there.
- "Effort by set" chart in RPE zone colors with a dashed target line.
- Up next rows: 56 pt anatomy art, name and prescription; no tags.
- The rest panel: the coach's flat rest scene on the blue scene panel carries the blue open-ring countdown; the next set with its anatomy art; "How hard was set n?" as the headline with the target in plain text; RPE chips 6–10 with zone bars — the selected chip takes the zone gradient, with dark text on the yellow zone; −30 s, Skip rest, +30 s.
- After a save, a receipt above the editor names the set ("Set n · saved on this device") with the recorded load, reps, reported effort and the feedback entry. A failed save shows an inline error under the steppers, keeps the numbers and starts no rest.
- The chip says "Target RPE"; the stepper row says "Your RPE". An untouched stepper is never saved or announced as a reported effort.
- While a field has the keyboard, `Log set` also sits in the keyboard toolbar. The rest panel previews the next set and its target, and its controls ignore taps for 0.6 s after a rest starts.
- `Log set` is the single accent capsule. Active set editor and the primary action stay visible without scrolling.

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
- Changes that wait for the lifter ("Needs your OK") show where the lifter already looks: a pill next to the check-in on Today, the Kai's call tile, and a tinted row at the top of the roadmap's This week. All three open the same review sheet: the change as numbers (3 → 4 sets), one reason, Approve and a decline that names what stays. Approve on Today leaves a 4 s "Added · Undo" pill.

## 9. Voice

- Voice stays inline with the active set.
- Idle: quiet microphone. Listening: accent orb with waveform. Failure: red mic-slash capsule with one short message.
- Coach voice mode covers the chat. The live transcript is the display text, with words still being recognized in secondary. The accent disc with its waveform sits in the thumb zone and is the send control; one flat ring follows the voice level. Close and keyboard flank it and never move between states. When the coach has answered, the disc settles into the quiet microphone ("Tap to talk") and the exchange stays in the chat.
- From Today, voice mode opens full screen over Today and closes back to it. Before the first word it offers "Try asking" chips. "What's my plan today?" answers with a plan card (a row per lift: coach scene, name over sets × reps · load; Start, or Resume while a workout is open), "Show my last workout" with a report card (duration, sets, load, the record if one landed, a row per lift, Open workout). Spoken questions reach those cards through TodayAskIntent, which matches English, Japanese, Korean and Vietnamese phrasing; the tiles and chips pass the kind directly.
- Workout chat: the debrief card's questions open a chat about that one workout (zoom from the card). The title is the workout, the first message is the debrief, coach answers carry a 2 pt flat accent rule on the left and, when they name a lift, its next-load token or an effort-by-set chart (a dashed target line, sets over target in the effort color); the Coach tab uses the same answer style, with evidence only under answers given in the current conversation (next load from the next planned session, effort from the lift's latest workout). Only that workout leaves the device, and the chat says so. Voice mode keeps its layout and adds the workout under the coach's name.

## 10. Imagery

Three art families. **Clay objects** stay for tool headers and empty states: friendly soft-3D, matte clay, rounded chunky shapes, soft light from the upper left, one soft contact shadow, transparent background, no text, no people (the goal symbols' clay arm is a symbol, not a person). Art palette: the orange family (Huawei-style orange 3D) — deep orange `#F0412B`, brand `#F5621C`, amber `#FFA10A`, peach `#FFC09A`, cream highlights, charcoal details. Muscle highlights are orange: primary deep orange-red, secondary peach. Every illustration and equipment thumbnail is generated with the GPT image model through Codex from one style sheet (`docs/design/illustration-style.md`), so the family stays consistent; `scripts/recolor-art.py` keeps art in the palette; art colors live only inside the images, never in UI chrome. Coach photos stay for the Coach tab portrait and the Settings coach picker; everywhere else the coach is drawn flat. Functional visuals: muscle maps, plate graphics, mini charts, PR cards. No stock athlete photography, no emoji in chrome.

**Flat people illustrations** (Daylio-like; style rules in `docs/design/illustration-style.md`): `art-group-legs|pull|push|core` as 36 pt group thumbnails in Trends headers, `art-exp-addset|reps` as experiment tile pictures — only ever small thumbnails or tile pictures, never a large hero, always decorative. Body metrics and tool rows use filled SF Symbols in the metric colors (Apple-Health style), no icon containers.

**Flat coach scenes** (style in docs/design/illustration-style.md, "Flat coach scenes"): Nova and Kai drawn flat with the builds of real strength coaches, from the app's coach photos — 9 lift families (deadlift, overhead press, pull-up, curl, calf raise, squat, bench, row, lateral raise, plus leg raise) and 8 story scenes (plan, last workout, why this weight, recovered, rest, record, hello, strong), each on one pastel scene panel. Assets `<coach>-scene-<name>` and the flat avatar `<coach>-face` in Assets.xcassets/CoachScene. CoachScene.forExercise maps any exercise to its lift family (mood art, not form instruction). Used on Today (session card, strip, Today's plan card, Ask grid), in voice-mode cards and on the rest panel, always the chosen coach. Scene panels (Theme.scenePeach/Amber/Blue/Lavender/Green) are light in both appearances, so text on them uses Theme.sceneInk / sceneInkSecondary / sceneTimeInk.

Clay art carries a Progress tool screen's header (`ProgressLargeTitle(art:)`), 68 pt, never tinted icon squares — art-schedule, art-blocks, art-audit, art-flask, art-balance, art-numbers, art-camera, art-sleep, art-bowl, art-pro, art-goal, art-equipment, art-empty-progress, goal-hypertrophy.

## 11. Implementation rules

- Use tokens from `App/Forge/Theme.swift`; never hard-code palette colors in feature views.
- Support light and dark, Dynamic Type, VoiceOver, 44 pt minimum targets, Reduce Motion.
- Simulator verification covers light, dark, Dynamic Type XL and the rest timer.
- The rules a machine can check — no gradient, glow or drop shadow, no uppercase display text, no hard-coded palette color, no "sparkles" symbol — live as ast-grep rules in `lint/design/` and run as `make check-design` (part of `make test`). Add a one-line `// ast-grep-ignore: <rule id>` only where the exception is real, with the reason in the same commit.

## 12. Huawei flat pages: Today and Progress (scoped exception)

Today and Adjustments sit on the flat grey page (`Theme.pageGrey`) with flat white 16 pt cards — no sky gradient, no border, no shadow in light; dark keeps the soft card ring. All gradient and shadow code lives in `App/Forge/TodayStyle.swift`, the only file exempt from `design-no-gradient` and `design-no-shadow`. Approved by the owner on 2026-09-25 (Today: A3 v3; Progress: the lift-collection redesign). Lift trends (approved 2026-09-26) add the per-lift lines of §8; on Trends, v6 replaces them with the dot plot. In dark appearance a lift token shows the figure without the art's white background on a `Theme.track` disc (`ArtCutout`). Adjustments (approved 2026-09-28) shows the block as one canvas: a lane per lift with its load steps, the current week tinted orange, a hollow ring for a planned or waiting change; the detail page opens on a flat accent-tint hero with before and after rep bars. Every other screen keeps §1–§11.

Progress v6 (approved 2026-09-29: Trends "v10 B+C", Overview, lift page, Experiments) puts those four screens on the white page with the peach field behind the top block and the nav bar, and hairline lists below — no cards. Shared helpers in `App/Forge/ProgressSurfaces.swift`: `FieldSection` (the top block on the field), `.progressFieldPage(title:)` (the page chrome), `ArtThumb` (a rounded decorative thumbnail). The Overview carries one message: the mean % hero on the field, then "Your lifts", "Your body" and "More" hairline lists (tool rows as SF Symbols). Trends opens with "N of your M lifts got stronger since <month>." over the §8 dot plot. The lift page makes the graph the hero on the field with a "Recent" list below. Experiments states "Test one change" over illustrated tiles. The Timeline (v5.1, approved 2026-09-29) joins them. On the field: the week button (the month outside the current month) that opens the month menu, a round "…" menu, and one summary sentence ("This week you trained 1 of 3 days and set 3 records. Full B is next: Deadlift 140 kg × 8."). On the page: text filter chips and a 1 pt rail with a 7 pt dot per entry. Entries are compact 10 pt rows on `Theme.timelineRow` with a 32 pt SF Symbol tile (`Theme.timelineTile`) or the coach avatar, one gold record line on workouts, and the coach's pending change on the accent tint with the only solid orange button in the list. A centred label with the week's sessions and records separates weeks. While scrolled, a floating glass week pill (`floatingGlass` in TodayStyle.swift) and the chips pin under the segment control. Long press opens the system context menu (Open workout, Add a note, Hide from timeline; hiding is reversible, so it is not red). "Add a note about today" lives in the "…" menu and an empty month offers "Add a note". Only today's check-in shows. Parts live in `App/Forge/TimelineV5Parts.swift`. Tool screens keep their v3 look until redesigned; Lift collection and Awards keep the grey page with white cards. Screen names follow the v3 renames: Mesocycles → Training blocks; Recommendation effectiveness → Adjustments; Measurements → Body stats; "Muscles this week" → "Muscles, last 7 days".
