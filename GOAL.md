# Forge — Complete Build Checklist (No Deferrals)

Status legend: `[x]` done · `[~]` partial (gap named) · `[ ]` to do · `[?]` needs an owner decision (new dependency or third-party account)

## 1. Program Engine
- [~] Exercise database — 314 exercises with primary muscle, synergists, equipment, movement pattern, compound/isolation. Gap: difficulty + video URL fields done; clips pending a content source.
- [ ] Exercise video/GIF demos — looped clips per exercise, cached locally. Needs a clip source (owner: licensed library or own recordings).
- [x] Substitution map — injury flags (shoulder/knee/back) + equipment-based swaps
- [x] Volume landmark tables — MV/MEV/MAV/MRV per muscle group
- [x] Set counting logic — 0–4 RIR validity, 0.5 synergist credit
- [x] Mesocycle generator — MEV start, weekly progression, deload week, session set budget, per-muscle auto-regulation, early deload
- [x] Load progression rules — RPE-based ±2.5–5% adjustments
- [x] Double progression logic — rep-range-based increases for isolation
- [x] Fatigue score — ACVR + soreness + sleep + RPE penalty (+ HRV/RHR when available)
- [x] Fatigue interventions — light session conversion, forced rest, early deload after two red days
- [x] e1RM engine — Epley, 12-week trends, plateau detection + variant rotation trigger
- [x] Starting weight calibration — reported lifts or bodyweight estimates
- [x] Program templates — 3/4/5/6-day splits (full body, upper/lower, PPL, push/pull, Arnold), user-selectable in Settings
- [~] Program regeneration — plan is recomputed from the profile on every change (Settings edits goal/equipment/schedule). Gap: explicit "restart block" option and goal editing in Settings.

## 2. Workout Logger
- [x] Today's workout view — prescribed sets/reps/load/RPE target
- [x] Set logging — weight, reps, RPE, one-tap log, swipe-to-complete
- [x] Ghost values — previous session per set
- [x] Rest timer — auto-start, 3 min compound / 90 s isolation, adjustable, notification, Live Activity
- [x] Plate calculator — kg/lb, bar weight config, available-plates config
- [x] Mid-workout exercise swap — substitution map integration
- [x] Add/remove/reorder sets and exercises on the fly
- [x] Superset/circuit support
- [x] Warm-up set calculator — auto-generated ramp to working weight
- [x] Notes per exercise + per workout
- [~] Offline-first — local SwiftData. Gap: cloud sync, conflict resolution (needs backend decision).
- [x] Workout summary — PRs, duration, tonnage, volume per muscle, share session
- [x] kg/lb toggle — global + per-lift
- [x] Workout pause/resume across app kills
- [x] Drop sets, rest-pause, myo-reps logging variants

## 3. Check-in & Recovery
- [x] Daily check-in — sleep/soreness/energy (1–5), motivation slider
- [x] Check-in → fatigue model wiring
- [x] Soreness per-muscle map (body diagram tap)
- [x] HealthKit sleep auto-import
- [x] Readiness score display pre-workout
- [x] Weekly recovery report

## 4. AI Coach Chat
- [x] LLM integration — scoped system prompt, training-only guardrails (Cloudflare Worker proxy, no key in app)
- [x] Context injection — program, recent logs, PRs, volume auto-regulation (fatigue score kept out of the request by design)
- [x] Pre-built quick prompts
- [x] Action execution from chat — apply program edits with user confirmation
- [x] Conversation history per user (persisted)
- [x] Medical/injury deflection — safe redirect responses
- [~] Rate limiting per IP. Gap: per subscription tier (needs auth).

## 5. Analytics
- [x] e1RM trend charts per lift (12-week rolling)
- [x] Weekly sets per muscle vs landmark bands
- [x] Volume load charts (sets × reps × weight over time)
- [x] PR detection + shareable card — Instagram/TikTok story format
- [x] Consistency streak + calendar heatmap
- [x] Muscle balance radar — push/pull, upper/lower ratios
- [x] Mesocycle history + comparison
- [x] Workout history list + full detail view
- [x] Body measurements tracking — weight, body fat %, tape measurements
- [x] Progress photo vault — private, date-stamped, side-by-side compare
- [x] CSV + PDF export
- [x] Personal records board — all lifts, filterable

## 6. Social & Gamification
- [?] User profiles — avatar, stats, PRs (needs backend)
- [?] Follow/followers system (needs backend)
- [?] Workout feed — friends' completed sessions (needs backend)
- [?] Kudos/comments on workouts (needs backend)
- [?] PR auto-post to feed (needs backend)
- [x] Streaks + badges — engine + Progress card with unlock toast
- [?] Weekly leaderboards among friends (needs backend)
- [x] Share workout summary to external socials

## 7. Apple Watch App
- [x] Companion logging — set completion, RPE from wrist
- [x] Rest timer — auto-start, adjustable, haptic tap when rest ends
- [x] Heart rate display during workout
- [x] Standalone mode — workout without phone nearby, sync later
- [ ] Complications — streak, today's workout status
- [x] watchOS workout session — HealthKit write

## 8. Nutrition Module
- [x] Calorie/macro targets — computed from goal (cut/bulk/recomp) + training volume
- [x] Food logging — barcode scanner + database (Open Food Facts, no key)
- [x] Quick-add frequent meals
- [x] Protein-per-meal distribution view
- [x] Weight trend ↔ calorie adherence correlation chart
- [x] Auto-adjust targets on bulk/cut phase change

## 9. Onboarding & Paywall
- [x] Onboarding flow — goal, experience, days/week, session length, equipment, lifts, injury flags, photos step
- [x] First program generation + preview ("Built for you")
- [x] Paywall — post-onboarding, pre-first-workout, personalised
- [?] RevenueCat — currently StoreKit 2 with the same products and 7-day trial. Owner decides: keep StoreKit 2 or add RevenueCat.
- [x] Trial handling — restore purchases, expiry/grace display, win-back offers
- [?] Promo code system — influencer attribution (needs backend + App Store offer codes)
- [?] Referral program — give month/get month (needs backend)

## 10. Platform Infrastructure
- [?] Auth — Sign in with Apple, Google, email (needs backend decision: Supabase/Firebase/own Worker)
- [?] Cloud backend — profiles, program state, sync
- [~] Push notifications — rest-timer local notification, workout reminders, deload explanations, PR celebrations, re-engagement (local first; remote needs backend)
- [x] Live Activities / Dynamic Island — rest timer
- [x] Widgets — today's workout, streak, weekly volume
- [?] Crash + event analytics — Crashlytics, Amplitude (new dependencies). Own event pipeline via the Worker is the no-dependency path.
- [x] Onboarding funnel tracking — install → trial → paid
- [x] A/B testing framework — paywall copy, pricing
- [x] Settings — units, rest, training, coach, data delete, notifications, theme
- [~] Data privacy — file protection entitlement, CSV export, delete all, privacy policy draft (web/privacy.html). Gap: legal review, real policy URL in Theme.privacyPolicyURL, GDPR/CCPA request flow.
- [?] Android app — full feature parity (separate project; engine port)
- [~] Localization — EN first, ES/DE/PT/FR structure-ready. Gap: catalog present, translations pending.

## 11. Launch & Marketing Ops
- [~] App Store assets — screenshots, preview video, ASO keywords. Gap: copy + screenshot plan done, captures pending.
- [x] Product Hunt launch kit
- [x] Landing page — waitlist → referral loop
- [x] In-app feedback button + beta survey system
- [x] Support channel — in-app chat or email triage
- [x] Content engine setup — TikTok/Shorts pipeline, progress-timelapse templates

## Execution order
1. Engine + logger + analytics + coach actions (local, no accounts)
2. Settings/infra, check-in map, nutrition, widgets, watch, onboarding photos, trial status
3. Backend-dependent items after the owner decides: auth/sync provider, RevenueCat, analytics SDKs, Android
4. Launch ops: landing page, App Store copy, Product Hunt kit, content templates
