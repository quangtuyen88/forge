# Regulift Design System

## Apple Fitness color harmony and OLED dark theme

This file is the canonical visual contract for Regulift. Product UI must optimize for rapid glanceability, arm’s-length legibility, and high-contrast use during active training.

## 1. Tri-metric activity palette

Every vivid hue has one stable meaning. Never reuse a metric color for an unrelated role.

| Role | OLED color | Apple system companion | Usage |
|---|---:|---:|---|
| Time / rest / voice | `#00F0FF` Electric Cyan | `#0A84FF` | Elapsed time, rest countdowns, voice orb, waveform, listening status |
| Sets / exercise / active reps | `#00F076` Workout Neon Green | `#30D158` | Set counts, exercise adherence, active reps, `Log set`, workout completion |
| Tonnage / intensity / end workout | `#FF2D55` Move Electric Red | `#FF375F` | Load, tonnage, RPE/intensity, finish/end workout, high-impact values |
| Plate 15 kg / supporting gold | `#FFD60A` Fitness Gold | — | Plate inventory and exceptional supporting highlights only |
| Critical error | `#FF3B30` System Red | — | Destructive errors and critical warnings, not normal tonnage |

Accessible light-mode variants may darken these hues when required for WCAG AA. Their semantic role must not change.

## 2. OLED surfaces

| Token | Dark value | Purpose |
|---|---:|---|
| Page | `#000000` | True OLED background |
| Card | `#1C1C1E` | Primary container |
| Recessed control | `#151518` | Inputs, compact rows, status capsules |
| Track | `#3A3A3C` | Inactive controls and progress tracks |
| Primary text | `#FFFFFF` | Main labels and values |
| Secondary text | `#8E8E93` | Supporting labels; never dimmer on dark cards |

Use flat surfaces, continuous corners, and subtle hairline borders. Do not add decorative gradients, broad glows, or drop shadows.

## 3. Typography and glanceability

- Primary workout numbers: 44–56 pt, heavy condensed sans serif, tabular digits.
- Metric values appear before labels. Units remain smaller and quieter.
- Use sentence case. Avoid all-caps labels except external standards or abbreviations.
- A lifter must read weight, reps, rest time, and the primary action from 3–5 feet away.
- Secondary copy must meet WCAG AA against its surface.

## 4. Progress charts

- Follow Apple Fitness metric cards: metric title, one large color-coded current value, compact range control, then the plot.
- Use vertical bars for discrete weekly totals such as sets and tonnage; reserve lines for continuous strength trends such as e1RM.
- Keep axes sparse, labels quiet, grid lines low-contrast, and the current period at full opacity while prior periods remain muted.
- Use the semantic metric color for both the headline value and chart marks. Do not add decorative area gradients.
- Place charts on one dark rounded card with a subtly recessed plot surface; never split one metric across multiple cards.

## 5. Active workout HUD

- Top HUD contains radial set progress plus three compact telemetry cells: Time in cyan, Sets in green, Tonnage in electric red.
- Separate telemetry cells with subtle hairlines.
- Keep the active set editor and primary action visible without scrolling.
- `Log set` is a 56–64 pt neon-green pill with a bold checkmark.
- `Finish workout` uses electric red and never competes with `Log set`.
- Prescription is visual: `Last → Target` plus one short adaptation signal.

## 6. Voice and hands-free states

- Voice stays inline with the active set; never cover workout numbers with a routine modal.
- Idle: quiet microphone orb.
- Listening: cyan orb with waveform glyph and restrained pulse.
- Feedback: one-line cyan waveform capsule.
- Failure: red mic-slash capsule with one short actionable message.
- Typed quick logging stays collapsed unless requested.

## 7. Voice and gym settings

- Use native iOS switches with neon-green active tint.
- Put one compact status badge above voice settings, such as `Listening · English`.
- Keep descriptions to one line where possible.
- Plate inventory uses rounded color pills:
  - 25 kg / 45 lb: electric red
  - 20 kg / 35 lb: electric cyan
  - 15 kg / 25 lb: fitness gold
  - 10 kg / 10 lb: workout green
  - Smaller change plates: neutral track gray

## 8. Navigation and interaction

- Bottom navigation uses high-legibility SF Symbols and restrained active-state color.
- Voice affordances may glow only while actively listening.
- Touch targets are at least 44 pt; primary workout actions are 56–64 pt.
- Motion communicates state, remains interruptible, and respects Reduce Motion.

## 9. Imagery

Use functional visuals only: muscle maps, exercise glyphs, radial progress, mini charts, adaptation arrows, plate graphics, and PR cards. Avoid decorative fitness photography and generic athlete imagery.

## 10. Implementation rules

- Use semantic tokens from `App/Forge/Theme.swift`; do not hard-code palette colors in feature views.
- Preserve the 1:1 metric allocation across every screen and widget.
- New components must support dark and light appearance, Dynamic Type, VoiceOver, and 44 pt minimum targets.
- Simulator verification must cover dark mode, light mode, Dynamic Type XL, voice active/error states, and the rest timer.
