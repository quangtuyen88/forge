# Regulift — goal and features (1.0, 17 September 2026)

Detailed checklist with status: `GOAL.md`. Original requirements: `product.md`.

## Goal

An iOS strength coach that programs the next session from what you actually did.

- Tagline: **They log. We program.**
- User: lifters with one to four years of training who have outgrown static programs and will not pay a human coach.
- Loop: log a workout → the engine adjusts the next session → visible progress → keep coming back.
- Business: 1.0 ships free during launch. Pro subscription (RevenueCat, $12.99 / month or $79.99 / year) is built and switched off behind `Features.pro`.
- Platforms: iPhone, Apple Watch, widgets and Live Activity. No Android.
- Languages: English, 日本語, 한국어, switchable inside the app without relaunch.

## Features

### Program engine (ForgeCore)
- 314 exercises with muscle, pattern, equipment, compound flag, injury-aware substitutions, names in three languages.
- Templates for 3 to 6 days a week: full body, upper/lower, push/pull/legs, push/pull, Arnold. Custom exercises.
- 6-week mesocycle: minimum effective volume start, weekly progression, deload week, per-muscle auto-regulation, early deload after two red days.
- Load rules: RPE-based ±2.5–5 %, double progression for isolation, e1RM (Epley) trends, plateau detection with variant rotation.
- Fatigue score from check-ins, HRV and resting heart rate; light-session conversion and forced rest.
- Plausibility guard: loads that jump more than 20 % over the best ask for confirmation, sets under 20 s apart and sessions with 4+ sets in under 5 minutes are unverified and feed no PRs, badges or Crew.

### Today
- Rings hero: sessions, sets, readiness. Week strip, coach adjustments card, weekly review.
- Quick actions: start workout, check-in, ask the coach, log food.
- Daily check-in: sleep, soreness, energy, motivation, hours slept, sore-muscle map. Apple Health fills sleep and heart data when allowed.

### Logger
- Prescribed sets with ghost values, one-tap log, swipe to complete, quick log by text or voice ("deadlift 132.5x8 @8").
- Rest timer with panel, Live Activity and Dynamic Island, adjustable, haptics.
- Swap, add, remove, reorder, supersets, warm-up ramp, drop sets, rest-pause, myo-reps, plate calculator, notes.
- Pause and resume across app kills. Finishing with nothing logged offers Discard.
- Summary with PRs, tonnage, muscles worked, three-line debrief, share as story or square card.

### Coach
- Chat backed by a Cloudflare Worker (training-only guardrails, rate limits, no medical advice), on-device answers on iOS 26 when available.
- Actions applied from chat with confirmation: swap, early deload, restart block, remember a note.
- Replies, chips and weekly review follow the app language. Dictation on device or via Whisper on Workers AI.

### Progress
- 2×2 stat cards, trends (sessions, sets, tonnage, top lift), e1RM charts, volume load, weekly sets per muscle, consistency heat map, awards.
- Tiles: Fuel, History (edit or swipe-delete sessions), PR board, body stats, progress photos with compare, muscle balance, mesocycle history, recovery report, PDF report. CSV export, Strong and Hevy import.

### Fuel
- Calorie and macro targets from goal and training volume, phase chip (cut / recomp / bulk).
- Food in three taps: favourites first, Open Food Facts search and barcode, grams shortcut. Protein per meal, weight-vs-intake chart.

### Crew
- Handle, display name, bio, follow, feed, kudos, comments, weekly rings leaderboard. Auto-post workouts and PRs (toggles). Referral give-a-month / get-a-month.

### Apple Watch
- Plan list, set logging with RPE, rest ring with haptics, live heart rate into the phone, standalone workouts synced later, ask the coach from the wrist.

### Platform
- Sign in with Apple, Google or email; sync of profile, sessions, sets and check-ins through the Worker and D1. Works fully offline without an account.
- Widgets (today, streak, weekly sets), Siri and Shortcuts, notifications for rest and reminders.
- Privacy: training data on device unless signed in, Health data never uploaded, no ads, delete all data and delete account in Settings.
- Design: Apple Fitness palette (lime accent, one colour per metric), capsule buttons, four tabs.

### Website
- regulift.app: landing page with demo video, feature tour, FAQ, free lifting tools (1RM, plates, RPE chart), privacy and terms. Deployed on Cloudflare.

## Not in 1.0
- Exercise demo clips (player built, no clips).
- Watch complications, remote push notifications, MetricKit crash reports.
- Pro subscription switched off. Direct "Share to Instagram Stories" button.
- Japanese and Korean App Store listings and screenshots.
