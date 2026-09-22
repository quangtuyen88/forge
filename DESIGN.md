# Regulift Design System

## Clean light-first system, one blue accent

This file is the canonical visual contract for Regulift. References studied on Appllama: Lyfta (visual language) and Lungy (flow grammar). Product UI must stay glanceable at arm's length during training.

## 1. Color

One accent. Every other hue has one fixed meaning.

| Role | Light | Dark | Usage |
|---|---:|---:|---|
| Accent | `#0062E6` | `#0A84FF` | Primary action, selection, active tab, links, progress, live numerals, chart marks |
| Done | `#1E8E3E` | `#30D158` | Logged sets, completed sessions, records |
| Effort | `#C2410C` | `#FF9F0A` | RPE, streaks, energy |
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
- Primary button: accent capsule, white label, 56 pt. One per screen.
- Secondary button: row-fill capsule, text color label.
- Destructive: red text, never a filled red button next to a primary.

## 6. Flow grammar (Lungy pattern)

- Welcome: brand, one line, one button.
- One question per page. The chosen answer explains what it changes, inline, under the option.
- A short statement page sits between question groups. It says one true thing about the product.
- The lifter tries the core loop (log a set, rate effort, see the next load) inside onboarding, guided by the coach bubble, before any paywall.
- A brief "building your plan" moment precedes the plan reveal. It names real steps.
- Paywall states the trial timeline with real dates and prices.
- Today leads with one card: today's session and its start button. Everything else follows.

## 7. Active workout

- Stats bar card: Duration, Volume, Sets. Duration in accent.
- Set table columns: Set, Previous, Weight, Reps. A logged row turns done-green tint with a green check.
- `Log set` is the single accent capsule. `Finish workout` is a secondary capsule until every set is logged.
- Active set editor and the primary action stay visible without scrolling.

## 8. Charts

- Metric title, one large accent value, compact range control, then the plot.
- Bars for weekly totals, lines for e1RM. Sparse axes, quiet grid, current period full opacity, earlier periods muted.
- One metric per card.

## 9. Voice

- Voice stays inline with the active set.
- Idle: quiet microphone. Listening: accent orb with waveform. Failure: red mic-slash capsule with one short message.

## 10. Imagery

Blue isometric illustrations and the coach photos already in the asset catalog. Functional visuals: muscle maps, plate graphics, mini charts, PR cards. No stock athlete photography, no emoji in chrome.

## 11. Implementation rules

- Use tokens from `App/Forge/Theme.swift`; never hard-code palette colors in feature views.
- Support light and dark, Dynamic Type, VoiceOver, 44 pt minimum targets, Reduce Motion.
- Simulator verification covers light, dark, Dynamic Type XL and the rest timer.
- The rules a machine can check — no gradient, glow or drop shadow, no uppercase display text, no hard-coded palette color, no "sparkles" symbol — live as ast-grep rules in `lint/design/` and run as `make check-design` (part of `make test`). Add a one-line `// ast-grep-ignore: <rule id>` only where the exception is real, with the reason in the same commit.
