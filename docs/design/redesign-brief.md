# Regulift redesign brief

Every screen, what it is for, what is wrong with it today, and a prompt you can hand to a
designer or a generative UI tool.

Observations below come from the running app on 2026-09-18, not from memory.

---

## 1. Who this is for, and where they are standing

A lifter, mid-set, phone face-up on a bench or on the floor. Chalky hands. Forty seconds
of rest. Headphones in, gym loud. They are not reading; they are glancing.

Everything in this brief follows from that one sentence. The current design was drawn for
someone sitting down with the app. That is the root problem, and it shows up on every
screen as the same three symptoms: too much grey, too much prose, and numbers that are
the same size whether they matter or not.

## 2. Design goals

Six goals, in priority order. When two conflict, the higher one wins.

**1. Readable at arm's length.** The one number that matters on a screen should be legible
with the phone flat on the floor and the lifter standing. Today the biggest number on
Progress is 22pt. It should be closer to 44pt, and everything competing with it should
get smaller, not bigger.

**2. One decision per screen.** Each screen should ask exactly one question and make its
answer a single obvious target. Today asks "check in or start or read the review or open
adjustments". Pick one, demote the rest.

**3. Explanations collapse.** Every explanation is one line by default, with the rest
behind a tap. The Settings Voice group currently has four toggles carrying four
paragraphs; each caption is longer than its label. That is a legal page, not a control
panel.

**4. Voice is a mode, not a button.** Voice control persists for a whole session, but it
is drawn as a 44pt microphone wedged between a text field and a tick. It needs its own
presence, its own states, and a place where the live transcript can appear without
shoving the set editor down the screen.

**5. Colour carries meaning, grey does not.** The metric hue system is good and worth
keeping: yellow time, purple load, mint sets, orange effort, red heart, pink energy, lime
done. The failure is grey doing semantic work — errors, captions, disabled states and
"nothing here yet" all look identical.

**6. Big targets, few of them.** In the logger, nothing interactive should be under 56pt.
Elsewhere 44pt. Where that forces fewer controls on screen, that is the point.

### One accessibility fix that is not optional

`Theme.textTertiary` (`#636366`) on `Theme.card` (`#1C1C1E`) measures about **2.85:1**.
WCAG AA wants 4.5:1 for body text and 3:1 for large text. It fails both. That colour
carries most of the captions in the app. Raising it to roughly `#8E8E93` gets you to
about 4.6:1 and costs nothing. Do this before anything else in this document.

## 3. What stays

Do not redesign these. They were chosen deliberately, match Apple Fitness, and work.

| Token | Value |
|---|---|
| Accent (lime) | `#B4FF00` dark, `#5C9E00` light |
| Value (purple) | `#A48DE2` dark, `#6E4FD0` light |
| Surfaces | page `#000000`, card `#1C1C1E`, inner `#2C2C2E` |
| Metric hues | time `#FFD60A`, load purple, sets `#2DDFCC`, effort `#FF9F0A`, heart `#FF3B30`, energy `#FF0049` |
| Radii | card 24, control 14, row 12, chip 10 |
| Spacing | page margin 20, group gap 12, inner 10, bottom bar 36 |
| Type | greeting 26 bold, title 22 bold, section 18 semibold, number 22 bold mono, body 15, label 13, caption 12, overline 10 |

**What changes in the type scale:** add a display size, 44 bold monospaced digits, for the
one number that owns a screen. `forgeNumber` at 22 is currently doing both "hero number"
and "number in a row", which is why nothing reads as more important than anything else.

## 4. How to use the prompts

Each prompt is written to be pasted whole into a generative UI tool or handed to a
designer. They assume iPhone 17, 402×874pt, dark mode first, and the tokens above. Name
every element explicitly; generative tools drift on tab bars and icon sets if you do not.

Every prompt ends with the same closing line, so add it if you split them up:

> Dark background `#000000`, cards `#1C1C1E` at 24pt radius, 20pt page margins, 12pt
> between cards. Lime `#B4FF00` only for the primary action and completed state. Bottom
> tab bar: Today (flame), Coach (chat bubbles), Progress (chart line), Crew (two people),
> active tab lime. No drop shadows, no gradients, no stock photography.

---

# The screens

## Tab 1 — Today

**Job.** Answer one question: what am I doing today, and am I ready for it.

**Wrong now.** Four things compete: a ring card with three stat pairs, a Week 1 review
card with a four-line paragraph, a week strip, and an adjustments card cut off at the
fold. The primary button changes label between Check in, Start Full C · ≈60 min, and
Resume Full C · 0 sets logged, which is good, but it sits under a scroll of material the
lifter has already read.

**Goal.** The workout name, readiness, and the button are one glance. Everything
explanatory moves below the fold or behind a tap. A returning lifter should be able to
start training without scrolling.

**Prompt.**
> Design a fitness home screen. Top: greeting "Good morning" 26pt bold with "Week 2 of 6 ·
> Friday, Sep 18" beneath in 13pt grey; right side a circular coach avatar and a gear
> button, both 44pt. Below: one hero card, full width, containing the workout name "Full
> C" as a 22pt title, a large readiness number "84" at 44pt in lime with the word READY in
> 10pt letterspaced grey above it, and two smaller stats to its right — SESSIONS 3/3 in
> mint, SETS 4/72 in mint — at 22pt. A single line of coach copy underneath: "All clear.
> Let's lift." Below the hero, a horizontal week strip of seven rings, S M T W T F S,
> completed days filled lime, today marked with a filled lime dot under the letter. Then a
> single collapsed row "Nova's adjustments · 3 changes" with a chevron. Fixed at the
> bottom above the tab bar: one full-width lime capsule button, 50pt tall, 14pt radius,
> "Start Full C · ≈60 min" in 16pt semibold black.

## Tab 2 — Coach

**Job.** Ask a question about your own training and get a checkable answer.

**Wrong now.** It is a generic chat transcript. Every reply is the same grey bubble in the
same width, so "Today's date is 2026-09-17" looks exactly as important as a plan change.
The coach avatar repeats beside every single message, eating 40pt of width on each. Three
suggestion chips sit above the input and scroll off the right edge mid-word.

**Goal.** Answers that change the plan look different from answers that do not. The
suggestion chips are the fastest path for a lifter who does not know what to ask, so they
should be readable and complete.

**Prompt.**
> Design a coaching chat screen. Header: "Coach" centred 18pt semibold, coach avatar and a
> 44pt more-options circle on the right. Messages: the lifter's own messages are right
> aligned grey `#2C2C2E` bubbles at 14pt radius, no avatar. Coach replies are left aligned
> with the avatar shown only on the first message of a run, not every message. A coach
> reply that changes the training plan renders instead as a card with a lime left edge, a
> 13pt lime overline "PLAN CHANGE", the change in 18pt semibold, one line of reason in
> 15pt, and a row of two buttons, "Apply" lime capsule and "Not now" plain. Above the
> input, suggestion chips wrap onto two lines rather than scrolling: "Why did my weight
> drop?", "Swap an exercise", "Explain my deload". Input row: rounded field "Ask your
> coach", a 44pt microphone circle, and a 44pt lime send circle.

## Tab 3 — Progress

**Job.** Show whether the last month beat the month before it.

**Wrong now.** A 2×2 grid of four cards, each about 150pt tall and 80% empty, holding a
22pt number. Then a Trends list where every row reads "Log 8 more weeks to compare" — the
screen's whole job, comparison, is unavailable, and it says so four times in identical
grey.

**Goal.** Stop wasting the top third on four numbers that could be one row. Say the
"not enough data yet" thing once, warmly, and show what there is.

**Prompt.**
> Design a training progress screen. Title "Progress" 26pt bold, share button top right.
> Replace a 2×2 stat grid with one horizontal strip of four compact stats separated by
> hairlines: streak 1 wk in yellow, workouts 2 in mint, volume 1.6 t in purple, best e1RM
> 85 kg in purple, each number 22pt bold monospaced with a 10pt letterspaced grey label
> above. Below it the hero: a large line chart card, full width, 260pt tall, titled
> "Tonnage per week", lime line, purple dots, x-axis in weeks. Under the chart a Trends
> list: each row has the metric name 15pt, its value 22pt bold in its metric colour, and a
> trend arrow. When there is not enough history, show one single card instead of repeating
> per row: "Eight more weeks and I can compare. Three logged so far." with a small
> progress bar 3/8. Bottom tab bar with Progress active.

## Tab 4 — Crew

**Job.** Compare your week with people you train with.

**Wrong now.** Signed out it is one card in the top eighth of the screen and 700pt of pure
black below it. It reads as a broken screen, not an invitation.

**Goal.** The signed-out state should show what the lifter is missing, not a bare button.

**Prompt.**
> Design a signed-out state for a training social screen. Centre a preview of the real
> feature rather than an empty page: three stacked crew member rows, blurred or at 40%
> opacity, each with a circular avatar, a name, and a small ring showing their week's
> completion. Over them, a card: lime two-person icon in a 56pt circle, "Train with your
> crew" 22pt bold, "See everyone's week as rings, give kudos, climb the board." 15pt grey,
> and a lime capsule "Sign in" 50pt tall. Beneath the card one 13pt grey line: "Your
> training stays private until you join a crew." Full-height layout, nothing floating in
> empty black.

---

## Workout logger — the most important screen in the app

**Job.** Log a set in under three seconds without looking away from the bar.

**Wrong now.** The screen is a stack: a header with a layout toggle and Finish workout, a
metrics strip, a quick-log text row with a microphone, then the exercise card with the set
editor, then remaining sets, then the next exercise. The set editor's Log set button is
roughly 900pt down from the top of the screen. The weight and rep steppers are 44pt
circles sized for a seated thumb. Errors render as raw text under the quick-log row and do
not clear when voice is switched off.

**Goal.** The active set editor owns the screen. Everything else is either a thin strip or
scrolled away. Logging a set is one target, and it is huge.

**Prompt.**
> Design a workout set-logging screen for use mid-set in a gym. Top strip, 44pt tall only:
> workout name "Full C" centred, a 44pt close button left, "Finish" text button right.
> Under it a single thin line of session metrics, 13pt: 0:33 elapsed in yellow, 0/24 sets
> in mint, 0 kg tonnage in purple. The rest of the screen is one card, the active set:
> exercise name "Bulgarian Split Squat" 22pt bold with "Set 1 of 4 · RPE 8 · rest 3:00"
> 13pt grey beneath. Then two enormous steppers side by side, each 120pt tall: minus and
> plus circles 56pt, the value between them at 44pt bold monospaced — 25 kg in purple, 8
> reps in mint. An RPE row of seven chips 6 to 9, 44pt tall, selected chip filled lime. A
> full width lime capsule "Log set", 64pt tall, 18pt semibold black, with a tick icon.
> Below the fold only: remaining sets as compact rows, and the next exercise collapsed to
> one line. Dark, high contrast, nothing decorative.

### Voice states in the logger

Voice needs four drawn states. Only the first two exist today, and the error state is a
raw `NSError` dump.

**Prompt.**
> Design four states of a hands-free voice control for a gym workout screen, as a bar
> pinned directly above the primary action button.
> **Idle:** a 56pt outlined microphone circle on the right of a slim bar reading "Tap to
> talk" in 13pt grey.
> **Listening:** the circle fills lime and a soft pulse ring animates outward; the bar
> shows a live waveform of five lime bars and, to its left, the partial transcript in 15pt
> white, truncating from the head so the newest words stay visible.
> **Understood:** the bar turns into a card, lime left edge, showing the parsed command in
> 18pt semibold — "Bulgarian Split Squat · 25 kg × 8 @ 8" — with a countdown ring and two
> buttons, "Confirm" lime capsule and "Cancel" plain.
> **Not understood:** the same bar in red `#FF3B30` at 12% opacity, one line only: "Didn't
> catch that — take two minutes" in 15pt, no buttons, fading after two seconds.
> Never show raw error text. Unavailable voice shows one sentence and a link to Settings.

---

## Daily check-in

**Job.** Four numbers and a sleep figure in fifteen seconds.

**Wrong now.** It is honest and close to right, but four identical 1-to-5 segmented rows
read as a form. The sore-muscle body map is the only interesting control and it is at the
bottom, below the fold.

**Goal.** Make it feel like fifteen seconds, not a questionnaire.

**Prompt.**
> Design a daily readiness check-in. Title "Daily check-in" 26pt bold, subtitle "Fifteen
> seconds. Sleep and soreness set today's plan." 15pt grey. Four rating rows — Sleep,
> Soreness, Energy, Motivation — each a label on the left and five 44pt circular targets
> numbered 1 to 5 on the right; the selected circle fills with that metric's colour rather
> than grey, and the unselected ones are outlines only. Then a sleep card: "SLEPT" 10pt
> overline, a 44pt bold "7" with "HOURS" beside it, minus and plus 56pt lime circles. Then
> the sore-muscle body map, front and back silhouettes side by side, tappable regions
> filling orange by soreness. Bottom: full width lime capsule "Save check-in" 50pt tall.

## Session summary

**Job.** Close the loop: what you did, what changed, what is next.

**Goal.** One number owns it — tonnage or PR count — and the coach's read of the session
is one line, not a paragraph. Sharing should be a first-class target here, since this is
the only moment a lifter wants to post.

**Prompt.**
> Design a post-workout summary. Hero: "Full C · done" 22pt bold, and the session's headline
> number at 44pt bold monospaced with its unit beside it — total tonnage in purple. A row
> of three compact stats: duration in yellow, sets in mint, PRs in lime. One line of coach
> copy in 15pt with the coach avatar. Then any personal records as lime-edged cards, one
> per PR, "Back Squat · 85 kg e1RM · +2.5". Then "What changes next week" as a maximum of
> three single-line rows with a chevron each. Bottom: two buttons side by side, a lime
> capsule "Share" and a plain "Done".

## Onboarding

**Job.** Get to a first workout in under two minutes without asking anything the app can
infer.

**Goal.** One question per screen, a visible progress indicator, and every question
answerable with a tap rather than typing.

**Prompt.**
> Design a fitness onboarding flow, one question per screen, dark. Top: a thin lime
> progress bar showing step 3 of 7 and a "Back" text button. The question as a 26pt bold
> line, at most eight words, e.g. "How many days can you train?". Answers as large
> selectable cards, 72pt tall, 14pt radius, stacked with 12pt gaps; selected card gets a
> 2pt lime border and a lime tick on the right. At most five options. Bottom: full width
> lime capsule "Continue" 50pt tall, disabled until an answer is chosen. No keyboard input
> anywhere in the flow. No illustrations.

## Paywall

**Job.** Sell a 14-day trial honestly.

**Goal.** One price, one button, the trial terms in plain words above the fold, and the
value shown as three concrete product moments rather than a feature list.

**Prompt.**
> Design a subscription paywall for a strength training app. Top: "Regulift" wordmark and a
> close button. Headline 26pt bold, at most six words: "Your program, adjusted weekly."
> Three benefit rows, each an icon in a 44pt lime-tinted circle, a 15pt semibold line and a
> 13pt grey line under it — no bullet lists of features. Then a single price card, 2pt lime
> border: "14 days free, then $9.99/month" 18pt semibold, with "Cancel anytime in Settings"
> 13pt grey beneath. Bottom: full width lime capsule "Start free trial" 50pt tall, a plain
> "Restore purchases" text button beneath, and the legally required terms in 10pt grey.
> One price only, no three-column comparison, no countdown timer, no crossed-out prices.

## Fuel (nutrition)

**Job.** How much is left to eat today.

**Goal.** This screen was already tightened once; the remaining problem is that kcal and
macros compete. Give kcal the display size and demote macros to bars.

**Prompt.**
> Design a daily nutrition screen. Hero: one enormous number, 44pt bold monospaced, the
> kcal remaining, in pink `#FF0049`, with "LEFT TODAY" as a 10pt letterspaced grey overline
> and "of 2,400" 13pt grey beneath. Under it three horizontal macro bars, full width, 32pt
> row height: protein, carbs, fat, each with the gram figure right-aligned at 15pt
> medium and the bar filled in its own hue. Then one "Today's meals" card listing entries
> as single rows, name left, kcal right, with a 44pt lime plus button to add. Bottom tab
> bar. No pie charts, no rings, no four-column macro grids.

## Settings

**Job.** Change a setting and leave.

**Wrong now.** Grouped cards where several toggles carry two- and three-line grey
explanations, and the Voice group alone now has four toggles with four paragraphs. The
groups are long and unlabelled until you scroll into them.

**Goal.** Label on the left, control on the right, one short line of help only where a
setting is genuinely surprising. Anything needing a paragraph gets a detail screen.

**Prompt.**
> Design a settings screen for an iOS fitness app, dark, grouped cards on black. Each group
> has an 18pt semibold heading inside the card. Rows are 56pt tall: label 15pt on the left,
> control on the right — a lime switch, a value with a chevron, or a segmented control. Help
> text appears on at most one row per group, a single 12pt line, never a paragraph. Any
> setting needing more explanation becomes a row with a chevron leading to its own screen.
> Show a "Voice" group with four rows: Require "Coach" before a command, Fast logging, Use
> Apple's speech service, Understand unusual phrasing — plus one status line at the bottom
> of the group, "Listening in English", with a chevron. Sticky "Done" button top right.

## Plan audit

**Job.** Show what the engine changed in the lifter's imported plan and why.

**Goal.** Each change is one readable row: what it was, what it is, one reason. This is the
screen where the "every decision has a readable reason" principle is most visible, so it
should look like a diff, not a report.

**Prompt.**
> Design a plan review screen showing what a training engine changed. Header "Plan audit"
> 26pt bold with "7 changes" 13pt grey. Each change is a card: the exercise name 15pt
> semibold, then the change as a before-and-after on one line — "3 × 8" struck through in
> grey, an arrow, "4 × 6" in lime 18pt semibold. Under it one 13pt grey line of reason:
> "Closer to your MEV for quads." A chevron opens the full reasoning. Bottom: full width
> lime capsule "Apply all" and a plain "Review one by one" beneath.

## History and session detail

**Job.** Find a past session and see what you lifted.

**Goal.** Sessions as a scannable list where the eye lands on the date and the headline
number; the detail screen mirrors the session summary so the two feel like one thing.

**Prompt.**
> Design a workout history list. A month heading 18pt semibold with the month's total
> tonnage right-aligned in purple. Each session is a 72pt row: the weekday and date stacked
> on the left in 15pt and 13pt grey, the workout name 15pt semibold in the middle, and the
> tonnage 22pt bold monospaced purple on the right, with a chevron. A calendar heat grid
> sits above the list, seven columns, squares filled in a lime ramp by volume. No avatars,
> no thumbnails.

## Exercise detail

**Job.** Show the lifter's own history with one movement.

**Goal.** Their e1RM curve is the hero. Everything else — instructions, muscles, equipment
— is reference material below it.

**Prompt.**
> Design an exercise detail screen. Title: exercise name 26pt bold with equipment and
> primary muscle as two small chips beneath. Hero: an e1RM line chart card, 240pt tall,
> lime line, purple points, with the current best called out as a 44pt bold monospaced
> number in purple over the top left of the chart. Below: a compact "Best sets" list, three
> rows, weight × reps @ RPE with the date right-aligned. Then a muscle map showing primary
> in lime and secondary in a dimmer lime. Reference text last, collapsed to a single row
> with a chevron.

## PR board and awards

**Job.** A wall of things the lifter has earned.

**Goal.** This is the one place where decoration is correct. It should feel like a trophy
cabinet and look different from every other screen.

**Prompt.**
> Design a personal records board. A 2-column grid of medallion cards, each 1:1, with a
> metallic circular badge, the lift name 15pt semibold, the record 22pt bold monospaced in
> lime, and the date 12pt grey. Earned badges are full colour with a subtle lime rim glow;
> unearned ones are outline only at 30% opacity with the requirement as one 12pt line.
> Above the grid a single line: "6 of 24 earned". This screen may use more visual weight
> than the rest of the app; it is a reward, not a tool.

## Measurements and progress photos

**Job.** Track body change over months.

**Goal.** Photos are the emotional payload; the numbers support them. The current
separation of the two into unrelated screens wastes both.

**Prompt.**
> Design a body progress screen. Top: a side-by-side photo comparison, two portrait tiles
> with dates beneath, and a small "Compare" control to change which two. Below: a weight
> line chart card, 200pt tall, purple line, with the current weight as a 44pt bold
> monospaced number. Then measurement rows — chest, waist, arms, thighs — each 56pt, label
> left, value 22pt bold monospaced right, with the change since last entry as a small
> coloured delta. A lime capsule "Add entry" pinned at the bottom.

## Import

**Job.** Get an existing program into the app from a screenshot or pasted text.

**Goal.** The lifter should see the parse happening and be able to fix it inline; a wall of
text they must proofread is the failure mode.

**Prompt.**
> Design a program import screen. Two large choice cards at the top, 100pt tall: "Paste
> text" with a document icon and "From screenshot" with a camera icon, both 14pt radius
> with lime icons. Below, once parsed, show the result as editable rows grouped by day:
> day name 18pt semibold, then one row per exercise with the name 15pt on the left and
> "4 × 8" in lime 15pt semibold on the right, each row tappable to correct. Anything the
> parser was unsure about gets an orange left edge and the label "Check this". Bottom: a
> lime capsule "Use this program".

---

## Priority order

If this is built in waves rather than all at once:

1. The contrast fix on `textTertiary`. One line, fixes every screen, unblocks accessibility.
2. Workout logger and its four voice states. It is where lifters spend their time and it is the weakest screen.
3. Today. It is the first thing anyone sees.
4. Settings. Cheapest large win — it is mostly deletion.
5. Progress and Coach.
6. Crew, Paywall, Onboarding.
7. Everything else.
