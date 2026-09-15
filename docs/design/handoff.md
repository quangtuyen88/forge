# Forge — Design Handoff

As built today; anything not marked "must keep" is negotiable.

## 1. What Forge is

Forge is an auto-regulated strength coach for intermediate lifters (1–4 years in) who outgrew static programs (5/3/1, PPL spreadsheets) but can't afford $150–300/month coaching. It reads lifts, sleep, and soreness, then reprograms the next session. Voice: "They log. We program." Anti-persona: casual gym-goers wanting quick workouts — high churn, never design for them. North star: 3 logged workouts per week per active user. What must not change: the coaching loop (check-in → plan → log → adjustments); coach copy that is specific and checkable ("half the sets, RPE ≤ 6", not "take it easy"); and no medical, injury-rehab, or outcome claims anywhere.

## 2. Screen inventory

| Screen | Purpose | Entry | Key elements | May change / must keep |
|---|---|---|---|---|
| Onboarding (8 steps) | Build profile + first program | First launch | Progress bar, coach pick, goal/schedule/gym cards, numbers step (units, bodyweight, lifts, promo), injury flags, photo, "Week 1 is ready" summary | Step order and visuals may change; every input must survive — coach pick, goal, experience, days/week, session length, equipment, bodyweight, lifts, injury flags, promo code, photo |
| Paywall | Convert trial | After onboarding; whenever subscription lapses | Coach hero photo, headline (A/B tested), "Built for you" personalization lines, two benefit rows, annual/monthly select cards (annual default), sticky CTA "Start free trial", restore/privacy/terms | Layout may change; keep personalization lines, real prices, trial terms, restore |
| Today | Daily home | Tab 1 (flame) | Greeting + week header, readiness ring, coach adjustments card, early-deload card, quick actions, week strip, check-in gate, today's plan list, gear button → Settings | Card order may change; the adjustments card is the product — keep it prominent |
| Check-in sheet | 15-second daily read | Today, when not checked in | Sleep, soreness 1–5, energy 1–5, sore-muscle map tap, Health opt-in note | Questions must stay (they feed the fatigue model); presentation may change |
| Logger | Log a workout | Today → session | Exercise list, superset chips, warm-up ramp, ghost values, set editor (weight × reps + RPE chips), swipe-to-complete rows, rest bar with skip | One-thumb speed is sacred: <3 taps per set, rest timer auto-starts. Set editor may be redesigned denser/clearer |
| Rest Live Activity | Rest countdown off-app | Auto with rest timer | Dynamic Island / lock screen: countdown, exercise name, live heart rate, Skip, Go | Style may change; countdown, Skip, and heart rate must stay |
| Session summary | Post-workout payoff | Finishing a logger session | "SESSION COMPLETE" header, count-up stats (duration, sets, tonnage), new-PR rows, notes, next-session line, muscles worked, navy share card (square + story) | This is the delight screen — motion welcome here |
| Coach | Chat with AI coach | Tab 2 (bubbles) | Consent screen (first ask only), quick prompts, chat bubbles, apply-action confirmation, on-device answer chip | Consent copy and the training-only/no-medical guardrail are fixed |
| Progress | Proof it works | Tab 3 (chart) | Stat tiles, badges row + unlock toast, streak + calendar heat map, e1RM trend (12 weeks), PRs, weekly sets vs landmarks, volume load, this-week per-muscle, plus: history list, PR board, measurements, progress photos, mesocycle history, balance radar | Charts and layout fully negotiable; keep the data stories (e1RM, weekly sets vs landmarks, streak) |
| Fuel (Nutrition) | Calories/macros | Tab 4 (fork) | Targets setup sheet, today kcal-left header, macro rings, meal sections, food search, barcode scanner, protein-by-meal split, weight-vs-intake chart | Rings may be restyled; barcode + search must stay reachable |
| Crew | Social layer | Tab 5 (people) | Invite card, Feed / Leaderboard / Me tabs, handle setup, kudos/comments, profile pages, auto-post toggles | Empty states are a known weakness — redesign welcome |
| Settings | Everything else | Gear on Today | Sections: Account (sign-in, sync, delete), Invite (referral), Crew (auto-post), Units (kg/lb), Rest timer, Training (goal, split, days, length, equipment, injuries, restart block, custom exercises), Coach (pick, consent, server), Plates (bar + available plates), Appearance (system/light/dark), Notifications (reminder), Data (import, CSV export, feedback, support, delete all), Subscription, About | Section grouping may change; no setting may disappear |
| Import sheet | Bring Strong/Hevy history | Settings → Data | File picker, unit check, preview counts, unmatched-exercise warning, confirm | Flow may change; CSV import must survive |
| Custom exercise form | Add own lifts | Settings → Training → Custom exercises | Name, primary muscle, up to two synergists, equipment | All four fields must stay |
| Watch app | Wrist logging | ForgeWatch app | Plan list (sets × reps), set logging (reps, RPE), rest timer with haptic, heart rate, standalone sync state | Layout is watch-constrained; interactions stay |
| Widgets | Glanceable | Home/lock screen | Home: today's workout, week sets vs target, streak, est. minutes. Lock screen + accessory: week sets | Content and sizes may change; keep today's-workout and week-sets widgets |

## 3. Design tokens as built

All from `Theme.swift`. Every colour is a light/dark pair; dark mode is first-class, plus a System/Light/Dark override in Settings.

| Colour | Light | Dark | Role |
|---|---|---|---|
| accent | #3866D6 | #3866D6 | Primary actions, selection, chart highlight |
| page | #F3F4F8 | #0B0C10 | App background |
| card | #FFFFFF | #16181F | Card surfaces |
| innerSurface | #F1F3F8 | #1F222B | Recessed rows, chips, secondary buttons |
| track | #E3E7F0 | #2A2E3A | Progress tracks, heat zero |
| text | #111318 | #F4F5F8 | Primary text |
| textSecondary | #5C6270 | #A3A8B5 | Labels |
| textTertiary | #9096A4 | #6B7180 | Captions |
| onAccent | #FFFFFF | #FFFFFF | Text on accent |
| positive | #2FA36B | #2FA36B | Gains, success |
| negative | #D9534F | #D9534F | Destructive, fatigue red |
| ring | black 6% | white 8% | 1 pt borders |
| highlight | white 90% | white 7% | Inset top-light on cards |
| shadow | #1B2B5A 8% | black 45% | Card shadows |
| ramp (1–4) | #C5D3F5 #8FAAEC #5A82E0 #2B54C4 | #2B3D6E #3A5AA8 #3866D6 #6E93F0 | 5-step chart/heat ramp |

Radii (all continuous): card 20 (components live 18–22), row/inner 12 (8–14), chip 10, button 14.

Spacing: page margin 26, gap between card groups 18, inside components 10. Card padding defaults 16, inner 14.

Type is Inter Tight throughout, scaling with Dynamic Type. Modifiers:

| Modifier | Size / weight | Tracking | Use |
|---|---|---|---|
| forgeGreeting | 26 bold | −0.9 | Paywall hero, greeting |
| forgeTitle | 22 bold | −0.8 | Screen titles |
| forgeSection | 18 semibold | −0.7 | Card headers |
| forgeNumber | 22 bold, monospaced | −0.7 | Big stats |
| forgeBody | 15 regular | — | Default body (app default 16) |
| forgeBodyStrong | 15 medium | — | Row titles |
| forgeLabel | 13 medium | — | Secondary labels |
| forgeCaption | 12 medium | — | Captions, fine print |

Nav large title: Inter Tight Bold 30 (−0.9); nav title 17 semibold; tab labels 11 medium; segmented 13 medium.

Button styles: **Pill primary** — full width, min height 52, radius 14, accent fill, white 18%→clear top stroke, label 16 semibold, press scales to 0.97 over 0.12 s. **Pill secondary** — same geometry, innerSurface fill + 1 pt ring, normal text colour. **Icon button** — 40 pt circle, card fill, ring, shadow. **Row press** — scale 0.98 + opacity 0.85. **Card press** — scale 0.97. All press transitions 0.12 s easeOut.

Cards: fill + continuous 20 radius + soft shadow (radius 16, y 6) + 1 pt ring + inset top highlight fading by mid-height. Inner surface: recessed fill, 12 radius, no shadow, no ring.

## 4. Motion as built

| Interaction | Motion |
|---|---|
| Any press | scale 0.97, easeOut 0.12 s |
| Chips / RPE selection | easeOut 0.15 s |
| Content appearing | fade + 8 pt rise, easeOut 0.25 s, 40 ms stagger per element |
| Readiness ring | spring 0.55 s, no bounce |
| State changes (log a set, select card) | `.snappy` spring |
| Summary stats | numericText count-up, easeInOut 0.6 s |
| PR card reveal | spring 0.45 s, bounce 0.2 |
| Badge toast | spring 0.3 s |

Reduce Motion: appear-offset disappears (fade only), count-up skipped. Rule: core-loop motion stays under 300 ms; rare payoff screens (summary, PR reveal) may delight.

## 5. Copy and accessibility rules

Launch copy rules apply to all surface copy: headline ≤ 6 words; sublines ≤ 60 characters, one line; no outcome promises, absolutes, or guarantees; no medical or injury claims; numbers on screen must be real (seeded data, never invented); social proof only when true and sourced. Coach copy is specific and checkable — numbers, sets, RPE caps — never vague encouragement. Accessibility as built: VoiceOver labels across the core loop (check-in, set rows, select cards), Dynamic Type supported but capped at xxLarge, and 44 pt minimum tap targets. Keep or exceed all three.

## 6. Known rough edges the designer should solve

- Badges sit above the actionable charts in Progress; the charts are why people open the tab.
- The logger set editor is dense — weight, reps, RPE chips, ghost values, and controls compete.
- Onboarding opens on coach pick before any value statement; users choose a face before knowing what Forge does.
- Crew empty states are bare one-liners.
- Fuel rings render before anything is logged — no graceful zero state.
- Onboarding numbers step: the keyboard accessory bar overlaps content.
- History rows show "—" for one-set sessions (warm-ups, singles).

## 7. Deliverables we need back

- One Figma file; pages named exactly as the inventory above.
- Components: card, pill button (primary + secondary), chip, stat tile, adjustment row, set row, rest bar.
- Light and dark variants of every screen.
- Exported tokens (colours, type, spacing, radii) as JSON or a table.
- A short rationale per changed screen.
- Frame naming: `Screen / State` — e.g. `Today / Ready`, `Logger / Resting`, `Progress / Empty`. Engineering pulls designs through the Figma MCP, so frame names are an API.

## 8. How to run it

TestFlight build from the owner. Or Xcode: open `App/Forge.xcodeproj`, scheme Forge, any iPhone simulator. The coach chat needs `App/Secrets.local.xcconfig` (gitignored) — ask the owner; everything else works without it.
