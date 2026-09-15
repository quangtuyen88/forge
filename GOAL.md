# Forge — Complete Build Checklist (No Deferrals)

Status legend: `[x]` done · `[~]` partial (gap named) · `[ ]` to do · `[?]` needs an owner decision (new dependency or third-party account)

## 1. Program Engine
- [~] Exercise database — 314 exercises with primary muscle, synergists, equipment, movement pattern, compound/isolation. Gap: difficulty + video URL fields done; clips pending a content source.
- [~] Exercise video/GIF demos — player + cache done; clips to be recorded by the owner
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
- [x] Program regeneration — plan recomputed from the profile on every change; Settings has goal/split editing and "Restart training block".
- [x] Custom exercises — user-defined lifts with muscle and equipment, usable in swaps and added sets, synced

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
- [x] Offline-first — local SwiftData + Worker sync, last-writer-wins
- [x] Workout summary — PRs, duration, tonnage, volume per muscle, share session
- [x] kg/lb toggle — global + per-lift
- [x] Workout pause/resume across app kills
- [x] Drop sets, rest-pause, myo-reps logging variants
- [x] Siri and Shortcuts — start today's workout, log a set, skip rest; Skip button in the rest Live Activity
- [x] Import history from Strong and Hevy CSV — sessions, sets, RPE; exercise names matched to the catalogue
- [x] Edit past sessions — change or delete sets, delete a session (synced as tombstones)

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
- [x] Rate limiting — per IP + per-user daily cap (free 5 / pro 60) behind auth
- [x] On-device explanations — Foundation Models on iOS 26 explain each adjustment and answer offline; Worker remains the default

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
- [x] User profiles — handle, display name, bio, stats, top PRs (own Worker backend)
- [x] Follow/followers system — follow/unfollow, crew feed
- [x] Workout feed — followed + self, cursor paging, pull-to-refresh
- [x] Kudos/comments on workouts
- [x] PR auto-post to feed — toggles in Settings
- [x] Streaks + badges — engine + Progress card with unlock toast
- [x] Weekly leaderboards among friends — sessions + tonnage, week picker
- [x] Share workout summary to external socials

## 7. Apple Watch App
- [x] Companion logging — set completion, RPE from wrist
- [x] Rest timer — auto-start, adjustable, haptic tap when rest ends
- [x] Heart rate display during workout
- [x] Live heart rate — Watch streams bpm into the logger and the rest Live Activity (advisory only, no automatic rest changes)
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
- [x] RevenueCat — webhooks, entitlement mapping, give/get month promo grants via the Worker
- [x] Trial handling — restore purchases, expiry/grace display, win-back offers
- [x] Promo code system — influencer attribution + revshare dashboard via the Worker
- [x] Referral program — give month/get month, code + deep link

## 10. Platform Infrastructure
- [x] Auth — Sign in with Apple, Google, email (own Cloudflare Worker)
- [x] Cloud backend — own Worker + D1: profiles, sync, social, billing
- [~] Push notifications — rest-timer local notification, workout reminders, deload explanations, PR celebrations, re-engagement (local first; remote needs backend)
- [x] Live Activities / Dynamic Island — rest timer
- [x] Widgets — today's workout, streak, weekly volume
- [~] Crash + event analytics — own event pipeline via the Worker. Gap: crash reports (MetricKit summaries pending).
- [x] Onboarding funnel tracking — install → trial → paid
- [x] A/B testing framework — paywall copy, pricing
- [x] Settings — units, rest, training, coach, data delete, notifications, theme
- [~] Data privacy — file protection entitlement, CSV export, delete all, privacy policy draft (web/privacy.html). Gap: legal review, real policy URL in Theme.privacyPolicyURL, GDPR/CCPA request flow.
- [-] Android app — dropped by decision (iOS only)
- [~] Localization — EN first, ES/DE/PT/FR structure-ready. Gap: catalog present, translations pending.
- [x] Accessibility — VoiceOver labels across the core loop, Dynamic Type capped at xxLarge

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
