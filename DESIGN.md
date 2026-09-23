# Regulift Design System

## Clean light-first system, one blue accent

This file is the canonical visual contract for Regulift. References studied on Appllama: Lyfta (visual language) and Lungy (flow grammar). Product UI must stay glanceable at arm's length during training.

## 1. Color

One action accent. Every other hue has one fixed meaning and appears as values, 14 % icon badges and chart marks, never on buttons.

| Role | Light | Dark | Usage |
|---|---:|---:|---|
| Accent | `#0062E6` | `#0A84FF` | Primary action, selection, active tab, links, progress, live numerals, chart marks |
| Time | `#0E7490` | `#22D3EE` | Elapsed time, rest countdowns, schedule |
| Done | `#1E8E3E` | `#30D158` | Logged sets, completed sessions, records |
| Effort | `#C2410C` | `#FF9F0A` | RPE, streaks, energy |
| Record | `#B45309` | `#FFD60A` | Records, PRs, trophies |
| Heart / destructive | `#D70015` | `#FF453A` | Heart rate, delete, critical errors |
| Plate gold | `#FFD60A` | `#FFD60A` | 15 kg / 25 lb plate only |

Never add a second accent. Never use a gradient, glow or drop shadow.

## 2. Surfaces

| Token | Light | Dark | Purpose |
|---|---:|---:|---|
| Page | `#FFFFFF` | `#000000` | Background |
| Card | `#FFFFFF` | `#1C1C1E` | Grouped content, 1 pt hairline border |
| Row | `#EEF2F4` | `#2C2C2E` | Option rows, inputs, secondary buttons |
| Track | `#E1E6EA` | `#3A3A3C` | Inactive progress and controls |
| Text | `#0F0F12` | `#FFFFFF` | Labels and values |
| Secondary text | `#5F6672` | `#98989F` | Supporting copy, WCAG AA on every surface |

## 3. Shape

Actions are capsules. Cards are 16 pt. Rows and inputs are 10 pt. Chips are 8 pt. All corners continuous. No other radius.

## 4. Typography

- Inter Tight everywhere. One display size per screen.
- Workout numbers 44–56 pt bold, tabular digits. Value first, unit smaller and quieter.
- Sentence case. Onboarding and paywall headlines are centered and bold; at most one phrase in the accent color.

## 5. Option rows and buttons

- Option row: pale row fill, leading symbol, title, optional subtitle. Selected = solid accent fill, white text, white check. No border in either state.
- Onboarding goal and equipment rows lead with an art tile instead of a symbol: the illustration on a 56 pt card-colored tile with 8 pt corners and a 1 pt image outline, identical on plain and selected rows; a gym preset's tile shows its equipment.
- Primary button: accent capsule, white label, 56 pt. One per screen.
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
- Today leads with one card: today's session and its start button. Everything else follows.
- Today has one main action per state, in this order: Resume, Check in, Train anyway, Start. On a plan rest day the task card reads "Next up · <date>" and "Nothing is scheduled today.", and Start is the secondary pill. An empty week shows only the "Plan this week" card. The adjustment summary sits directly under the task card.

## 7. Active workout

- Stats bar pinned under the navigation bar: Elapsed (time teal), Load (blue), Sets (done green), each with its icon badge. It never scrolls away.
- Active set card: exercise thumbnail and name, "Set n of N" with target RPE and rest chips in their colors, and a full-width segmented set bar under it (done green, current accent, upcoming track).
- After a save, a receipt above the editor names the set ("Set n · saved on this device") with the recorded load, reps, reported effort and the feedback entry. A failed save shows an inline error under the steppers, keeps the numbers and starts no rest.
- The chip says "Target RPE"; the stepper row says "Your RPE". An untouched stepper is never saved or announced as a reported effort.
- While a field has the keyboard, `Log set` also sits in the keyboard toolbar. The rest panel previews the next set and its target, and its controls ignore taps for 0.6 s after a rest starts.
- Weight is a blue tile, reps a green tile, RPE an orange row; tiles are fills without borders, 10 pt corners, 44–56 pt tabular numerals.
- Exercise list rows: thumbnail, name, one-line prescription with a teal rest time, and a green progress ring showing done/planned sets.
- `Log set` is the single accent capsule. `Finish workout` stays in the navigation bar.
- Active set editor and the primary action stay visible without scrolling.

## 8. Charts

- Metric title, one large accent value, compact range control, then the plot.
- Bars for weekly totals, lines for e1RM. Sparse axes, quiet grid, current period full opacity, earlier periods muted.
- One metric per card.

## 9. Voice

- Voice stays inline with the active set.
- Idle: quiet microphone. Listening: accent orb with waveform. Failure: red mic-slash capsule with one short message.

## 10. Imagery

Friendly soft-3D illustrations: matte clay objects, rounded chunky shapes, soft light from the upper left, one soft contact shadow, transparent background, no text, no people (the goal symbols' blue clay arm is a symbol, not a person). Art palette: Regulift blue `#2F7BFF`, coral `#FF7A59`, sunny yellow `#FFC83D`, mint `#3CCB8A`, sky `#8CC8FF`, charcoal details. Every illustration and equipment thumbnail is generated with the GPT image model through Codex from one style sheet (`docs/design/illustration-style.md`), so the family stays consistent; art colors live only inside the images, never in UI chrome. Coach photos stay as they are. Functional visuals: muscle maps, plate graphics, mini charts, PR cards. No stock athlete photography, no emoji in chrome.

## 11. Implementation rules

- Use tokens from `App/Forge/Theme.swift`; never hard-code palette colors in feature views.
- Support light and dark, Dynamic Type, VoiceOver, 44 pt minimum targets, Reduce Motion.
- Simulator verification covers light, dark, Dynamic Type XL and the rest timer.
- The rules a machine can check — no gradient, glow or drop shadow, no uppercase display text, no hard-coded palette color, no "sparkles" symbol — live as ast-grep rules in `lint/design/` and run as `make check-design` (part of `make test`). Add a one-line `// ast-grep-ignore: <rule id>` only where the exception is real, with the reason in the same commit.
