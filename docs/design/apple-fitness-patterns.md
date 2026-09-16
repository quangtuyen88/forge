# Apple Fitness patterns → Forge

Source: Apple Fitness, iOS 26, March 2026 capture (ui-pocket.com, 121 screens read at full size). This sheet records what Apple does, what Forge copies, and what Forge deliberately skips. It is the brief for the design refresh in `GOAL.md` and for the Stitch screens in project "forge".

Forge keeps its own tokens throughout (`Theme.swift`: cobalt accent, Inter Tight, 20 pt cards, light and dark pairs). Apple's lime accent, per-metric rainbow and SF Rounded are not adopted. The product voice stays "They log. We program." Coach copy stays specific and checkable, never medical.

## 1. What Apple does

**Numbers are the content.** Every screen leads with a value, not a picture or a paragraph. Values are 30–110 pt bold; the unit sits beside the value in small caps at roughly 60 % of the size and in the same colour (`855/120 KCAL`, `1.25 KM`, `15'32"/KM`). Labels are quiet nouns in grey. There is never a sentence where a number would do.

**One object per screen.** The Move goal page is a 400 pt ring and nothing else above the fold. The badge page is one medallion, one name, one sentence. The countdown is one ring with one digit. Empty space is left empty.

**Rings as the daily object.** The ring is the unit of "did I do it today". It appears at every scale: the hero (400 pt), the summary card (200 pt), the friend row (110 pt), the week strip (36 pt). The week strip of seven mini rings sits under the nav bar of every detail screen and stays pinned while the hero scrolls away. Today's weekday letter sits in a coloured pill; future days are dimmed.

**Metric grid.** Detail cards are a two-column grid: caption in grey 17 pt, value in 30 pt bold, hairline between rows, an odd cell spanning the full width. Value colour encodes metric identity (time yellow, distance blue, energy pink, pace cyan, elevation green) and that colour is consistent on every screen.

**List rows put the value first.** A session row is a 20 pt card: tinted circle with the activity glyph, activity name in grey 17 pt, the headline value in 30 pt bold colour with a small-caps unit, the date in grey at the trailing edge. Every row is the same height. Grouping is by month with a 28 pt month header; with a filter active each month gets a plain-text totals table (count, time, energy; total and average).

**Metric detail page.** Large title, full-width segmented period control (D/W/M/Y), a stat header (caption, big number, period caption), one tall bar chart with dotted gridlines and right-side y labels, then one grey pill CTA. Scrubbing a bar shows a coloured callout pill (label, value, date) with a vertical line while the other bars dim. Empty charts keep their axes and month labels.

**Trends.** A 2 × 2 card of arrow circles: chevron-up in the metric colour, a flat dash in lavender when there is no data or the trend is locked. The trends page opens with a three-line headline in the user's name voice, then locked trends list the exact unlock rule ("at least one walking workout per week for six months"). The metric trend page compares the last 90 days (coloured bars) against the previous 275 (grey bars) with dotted average lines and pill labels.

**Set-a-number sheets.** Full-height dark sheet, circular X, title and a three-line explainer, then one giant numeral (about 90 pt) with the unit under it and two coloured circular − / + buttons, and a single pill CTA at the bottom. The per-day schedule variant uses full-width pill rows: label left, big value with small-caps unit centred, − / + circles flanking it, plus a live preview chart above. No wheels, no text fields, no toast on confirm: the hero re-renders with the new value and that is the feedback.

**Awards.** The badge hub leads with "Keep going": the next badge as a dim outline, its name, `470 / 500`, a thin progress bar. Categories are cards with one large 3-D medallion (name, date), a fanned stack of small medallions at the bottom-left and "+8 more · Show all" at the bottom-right. Grids are three columns; earned badges are full colour with a count pill, locked badges are grey line art with a progress bar. The detail page is silent: one medallion, the name, one sentence stating the exact rule and progress, a share button. Tapping flips the medallion to a gold back face engraved with the earned date. Rewards arrive as a system banner, never a modal.

**Live workout.** Pure black, no cards. Three numeral sizes stacked left-aligned: primary 110 pt, secondary 90 pt with a two-line grey label beside it, tertiary 60 pt in a row with caps labels. A dark rounded control panel is anchored to the bottom: activity glyph, elapsed time 56 pt yellow monospaced, live ring; then a row of circles with a 180 pt pause circle in the centre. Paused: time turns grey and the centre becomes a yellow-tinted resume circle. Pulling the panel up reveals three stacked pills: a red-tinted destructive "End workout", then two grey ones. Ending a workout lands directly on the session detail; a banner announces any badge.

**Sharing.** Friend rows are cards: avatar and name, percent 34 pt and `0/120 KCAL` in the ring colour, a 110 pt ring at the right. A sort menu (name, move, steps, workouts) sits at the section header. Suggestions are avatar cards with a dismiss X and a small pill that becomes "✓ Pending". The person page is a 180 pt avatar, name, a today grid (label/value rows with hairlines beside a 210 pt ring), seven mini rings for the week, recent activity rows and three recent badges.

**Chrome.** Circular 56 pt glass buttons for nav actions, a floating glass tab bar with the active tab in a raised pill, cards 20–24 pt on near-black, section headers that are themselves tappable ("Workout details >"). Grey pills with an accent-coloured label are the secondary CTA; solid accent pills are reserved for the one primary action. Explainers are one grey sentence; CTAs are verbs.

## 2. What Forge copies

| Apple pattern | Forge adoption | Where |
|---|---|---|
| Value + small-caps unit | `MetricValue` component: bold numeral, unit at 55 % in the same colour, monospaced digits, numeric transition | Every stat on Today, History, Summary, Progress, Crew |
| Ring at every scale | `RingView` (single) and `RingsView` (nested, up to three); readiness ring keeps its spring | Today hero, Crew rows, profile, week strip |
| Week strip of mini rings | `WeekRingStrip` replaces the check circles: ring = sets logged that day over the planned session budget, today's letter in an accent pill, future days dim | Today, History header, Crew profile |
| Metric grid | `MetricGrid` card: two columns, hairlines, odd cell spans | Session summary, session detail, Crew profile "This week" |
| Value-first list rows | `SessionRow`: glyph circle, day name grey, tonnage 24 pt accent with `KG`, date trailing; one-set sessions show sets instead of "—" | History, Crew profile recent sessions |
| Month totals | `MonthTotalsRow` under each month header: sessions, time, sets, tonnage | History |
| Chart grammar | `forgeChart()` style: bars for counts, dotted gridlines, right-side y labels, weekday/month x labels; `ChartScrubCallout` pill with value and date; empty charts keep axes and show the unlock sentence | Progress e1RM, weekly sets, volume load |
| Trend arrows | `TrendRow`: 40 pt circle with chevron up/down or a dash, label, value with delta; a Trends card on Progress with e1RM per main lift, sessions per week, sets per week, readiness average, this block versus last | Progress |
| Set-a-number sheet | Check-in sheet: explainer line, 1–5 rows as full-width pill rows with a segmented control, sleep hours as a giant numeral with − / + circles, one CTA "Save check-in"; readiness ring re-renders on save, no toast | Check-in |
| Keep going + medallions | `NextBadgeRow` (outline glyph, name, `7 / 10`, progress bar) at the top of the awards area; `Medallion` (accent gradient ring, dark disc, white symbol; locked = outline) replaces the 4-column symbol grid; `BadgeDetail` = one medallion, one sentence with the exact rule and progress, share | Progress (moved below the charts), Awards page |
| Live control panel | Logger rest state: bottom panel with countdown 56 pt accent, −30 / Skip / +30 circles, heart rate at the right; logger header stats as bare numerals with caps labels | Logger |
| Friend rings | Crew leaderboard rows become ring cards (avatar, name, `3/4 SESSIONS`, tonnage, 96 pt ring with sets inside) with a sort menu (sessions, tonnage, name); profile page with today grid, week rings, recent sessions, badges; empty state as one card with icon, title, one sentence, one pill | Crew |
| Tappable section headers | "Workout details >" style headers that navigate to History, PR board, Trends | Progress, Summary |
| Silent rewards | Badge unlock stays a top banner (already a toast); no modal, no confetti | Progress |

Colour rule: Forge does not adopt per-metric hues. Values default to `Theme.text`. The volume family (sets, tonnage, e1RM) uses `Theme.accentValue` (cobalt in light, `#6E93F0` in dark so numerals clear 6:1 on cards). Records and upward trends use `Theme.positive`; downward trends, fatigue and heart rate use `Theme.negative`. Time is `Theme.text`. Units and captions are `Theme.textSecondary`. One accent-coloured value per row or cell, never two.

Type rule: hero values 44–56 pt (`forge(48, .bold)` with tracking −1.5), card values 24–28 pt, row values 22 pt, all with `monospacedDigit()`. Units small caps 55 % of the value, `.semibold`, tracking 0.5.

## 3. What Forge skips, and why

- **Per-metric rainbow.** Forge is one cobalt accent with green and red semantics. Five hues would dilute the brand and fight the fatigue red.
- **Photo-free Today.** Apple has no persona; Forge's coach is the product's voice. The coach photo leaves the Today hero (numbers first) but the avatar stays in the header and on the adjustments card, and the session summary keeps its photo hero as the payoff moment.
- **Countdown ring before a workout.** Lifting starts at the rack, not on a timer.
- **Arrival check-in, Fitness+, plans, media.** Not strength features.
- **Three nested rings for Move/Exercise/Stand.** Forge nests at most three: sessions this week, sets this week, readiness. The inner readiness ring is coloured by the fatigue action (positive on proceed, accent on a trimmed or light day, negative on forced rest).
- **Wheel pickers and inline steppers for logging.** The set editor stays as is (one-thumb speed); only the header numerals and the rest panel change in this refresh.
- **Gold back face and 3-D renders.** `Medallion` is a layered vector; no art assets.
- **Sort by "name" as the default.** Forge sorts the Crew week by sessions (the north star), then tonnage.
- **Coach headline in the user's name.** Kept out: Forge coach lines must be checkable and the name adds nothing a lifter can verify.

## 4. Screen-by-screen

**Today.** Header: greeting, week line, coach avatar, gear. Hero card: three nested rings (sessions, sets, readiness) on the left, three `MetricValue` rows on the right (`2/3 SESSIONS`, `38/48 SETS`, `86 READY`), coach line under. `WeekRingStrip` directly under the hero. Adjustments card unchanged in content, rows tappable. Two stat tiles (streak, tonnage this week with delta chip). Next-session card with the start button. Check-in and Ask-coach tiles. Bottom bar unchanged.

**Check-in.** As in section 2. Sore map stays.

**Logger.** Header numerals without tile chrome (elapsed, sets, tonnage). Rest state: bottom control panel replaces the rest bar. Set editor untouched.

**Session summary.** Photo hero stays. Then `MetricGrid` (duration, sets, tonnage, average RPE, heart rate when present, PRs), per-exercise table (exercise, best set, e1RM, delta), muscles worked as bars, streak card, share and done.

**Session detail (History).** `SessionHeader` (glyph circle, day name, time range, week), the same `MetricGrid` and per-exercise table, notes, edit mode unchanged.

**History.** Month header, `MonthTotalsRow`, `SessionRow`s. `WeekRingStrip` pinned under the nav for the current week.

**Progress.** Order: period control (This block / 12 weeks / Year), Trends card, sets per muscle versus landmarks, e1RM chart with lift picker and scrub callout, volume load, calendar heat map, `NextBadgeRow` + earned medallion strip, links (History, PR board, Body stats, Photos). Awards page and badge detail as in section 2.

**Crew.** Rings segment as the default when signed in; feed and Me stay. Profile page redesigned. Empty state redesigned.

## 5. Copy retained from Apple's grammar

- Labels are nouns: SESSIONS, SETS, TONNAGE, READY.
- Explainers are one sentence: "Fifteen seconds. Sleep and soreness set today's plan."
- Unlock rules are exact: "Log Back Squat in three sessions to see a trend."
- CTAs are verbs: "Save check-in", "Start Full C", "Show all".
- Rewards state the rule: "Log at least one session every week for four weeks in a row."
