# Regulift (code name Forge) — Complete Build Checklist (No Deferrals)

Status legend: `[x]` done · `[~]` partial (gap named) · `[ ]` to do · `[?]` needs an owner decision (new dependency or third-party account)

## Product goal

**Import an old log → explain what Regulift learned → program the next session → explain every change → adapt when real life breaks the plan.**

The first-wave order is:
1. Explain why the program changed.
2. Smart Import Analysis.
3. Coach Context API + guardrails + ambiguity and action validation.
4. Smart missed-workout recovery.
5. Workout Focus Mode.

Plateau Rescue and Training Experiments follow after enough clean history exists.

## Existing feature baseline

- Adaptive program engine: volume landmarks, load/double progression, fatigue interventions, deloads, plateau detection, substitutions and custom exercises.
- Trust layer: structured decision ledger, reason codes, why-this-changed surfaces, user overrides and weekly review.
- Workout system: offline logger, quick/voice logging, rest timer + Live Activity, warm-ups, supersets, variants, notes, swaps, resume and session debrief.
- Coach platform: privacy-filtered context packet, curated RAG, on-device/server routing, ambiguity and missing-fact handling, prompt-injection guards, output validation, confirmed actions and coach memory.
- Activation: onboarding, generated first plan, Strong/Hevy CSV import, plan audit, paywall, referrals and subscription handling.
- Recovery: daily check-in, muscle soreness map, HealthKit sleep, readiness, recovery reports and missed-workout repair choices.
- Progress: e1RM, volume/sets charts, PRs, history editing, body measurements, photos, awards, mesocycles and exports.
- Supporting modules: Crew/social, nutrition, widgets, Siri/Shortcuts and Apple Watch workout logging.

## Success metrics

Track why-change views, prescription accept/revert rate, import → first workout conversion, first → second workout retention, missed-recovery acceptance, Coach helpful rate, hallucination/wrong-data rate, and paywall conversion after plan explanation.

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
- [x] Constraint system — named Gym Profiles, Travel/Crowd modes, Exercise Lock/exclusion, persistent session time budget and Minimum Effective Workout share one synced profile model
- [x] Program roadmap — six-week progression/deload timeline with current-week expansion, workout counts, decision proof and per-session muscle emphasis

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
- [x] Debrief — three checkable lines after every workout (result, effort, next loads), also on past sessions in History.
- [x] kg/lb toggle — global + per-lift
- [x] Per-exercise unit — kg/lb override honoured in Today adjustments, History, Progress, PRs and the exercise sheet.
- [x] Workout pause/resume across app kills
- [x] Drop sets, rest-pause, myo-reps logging variants
- [x] Siri and Shortcuts — start today's workout, log a set, skip rest; Skip button in the rest Live Activity
- [x] Quick log — "deadlift 132.5x8 @8" typed or dictated in the logger; Shortcuts/Siri "Log a set" with text; "Ask coach" and "Check in" shortcuts; "Log set" button on the rest Live Activity.
- [x] Import history from Strong and Hevy CSV — sessions, sets, RPE; exercise names matched to the catalogue
- [x] Edit past sessions — change or delete sets, delete a session (synced as tombstones)
- [x] Workout Focus Mode — one-set-at-a-time surface with minimal chrome, persisted default, rest takeover and resume
- [x] Minimum Effective Workout — preserves locked/main work, trims low-value exercises and caps working sets

## 3. Check-in & Recovery
- [x] Daily check-in — sleep/soreness/energy (1–5), motivation slider
- [x] Check-in → fatigue model wiring
- [x] Soreness per-muscle map (body diagram tap)
- [x] HealthKit sleep auto-import
- [x] Readiness score display pre-workout
- [x] Weekly recovery report
- [x] Weekly review — Today card when the week's sessions are done, plus a notification; plan-aware daily reminder body.

## 4. AI Coach Chat
- [x] LLM integration — scoped system prompt plus direct/indirect prompt-injection detection, quarantined history/context, escaped data boundaries and output leak validation (Cloudflare Worker proxy, no key in app)
- [x] Coach Context API — read-only privacy-filtered packet for program, recent logs, PRs, decisions and volume auto-regulation; Apple Health fields withheld by construction
- [x] Pre-built quick prompts
- [x] Action execution from chat — strict action/ID validation, planned-exercise and valid-replacement checks, then explicit user confirmation before any mutation
- [x] Conversation history per user (persisted)
- [x] Medical/injury deflection — safe redirect responses
- [x] Rate limiting — per IP + per-user daily cap (free 5 / pro 60) behind auth
- [x] On-device explanations — Foundation Models on iOS 26 explain each adjustment and answer offline; Worker remains the default
- [x] On-device answers — Apple Intelligence (iOS 26) answers when available and may propose validated plan actions; every mutation still requires explicit in-app confirmation; toggle in Settings.
- [x] Voice — dictation into the coach chat and the logger quick-log field (on-device speech when supported).
- [x] Structured Coach memory — confirmed typed facts with kind, provenance, confirmation date, optional expiry and supersession metadata; active memories are listed/deletable in Settings and sent with every question.

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
- [x] Training Experiments — one four-week lift intervention at a time with baseline/current e1RM and keep/revert review

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
- [x] Apple Watch — plan list with heart rate and set dots, big colored numerals, tinted steppers, rest ring that takes over after Log set, "Ask coach" from the wrist.
- [x] Rest timer — auto-start, adjustable, haptic tap when rest ends
- [x] Heart rate display during workout
- [x] Live heart rate — Watch streams bpm into the logger and the rest Live Activity (advisory only, no automatic rest changes)
- [x] Standalone mode — workout without phone nearby, sync later
- [ ] Complications — streak, today's workout status
- [x] watchOS workout session — HealthKit write

## 8. Nutrition Module
- [x] Calorie/macro targets — computed from goal (cut/bulk/recomp) + training volume
- [x] Food logging — barcode scanner + database (Open Food Facts, no key)
- [x] Quick-add frequent meals, Recently Logged shortcuts, Repeat Yesterday with duplicate protection and Undo
- [x] Training/rest/deload daily fuel guidance — optional carbohydrate/calorie adjustment while base targets and protein remain stable
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
- [x] Localization — EN, JA, KO in the app, widgets, watch and ForgeCore catalogs; in-app picker applies live with a confirm alert; exercise names, day names, coach chips and dates localized. Watch and widgets follow the system language.
- [x] Accessibility — VoiceOver labels across the core loop, Dynamic Type capped at xxLarge

## 11. Launch & Marketing Ops
- [~] App Store assets — screenshots, preview video, ASO keywords. Gap: copy + screenshot plan done, captures pending.
- [x] Product Hunt launch kit
- [x] Landing page — waitlist → referral loop
- [x] In-app feedback button + beta survey system
- [x] Support channel — in-app chat or email triage
- [x] Content engine setup — TikTok/Shorts pipeline, progress-timelapse templates

## 12. Design Refresh (Apple Fitness patterns)
Brief: `docs/design/apple-fitness-patterns.md`. Stitch project "forge": Today / Rings, Check-in / Sheet v2, Logger / Rest Panel, Session Summary / Detail v3, History / Sessions, Progress / Trends, Awards / Hub, Badge / Detail, Crew / Rings.
- [x] Shared components — MetricValue, RingView/RingsView, WeekStrip mini rings, MetricGrid, TrendRow, Medallion + NextBadgeRow, SessionRow/MonthTotalsRow/SessionHeader, forgeChart + ChartCallout
- [x] Metric colors — time yellow, load blue, sets mint, effort orange, heart red, energy pink, shared by phone and watch.
- [x] Today — rings hero (sessions, sets, readiness) with MetricValue rows, week ring strip, stat tiles with delta, next-session card
- [x] Check-in — pill rows, sleep hours as a giant numeral with − / +, one CTA, readiness ring re-renders on save
- [x] Logger — bare header numerals, rest control panel (countdown, −30 / Skip / +30, heart rate)
- [x] Session summary and detail — SessionHeader, MetricGrid, per-exercise table, muscles as bars
- [x] History — month totals row, value-first session rows, week ring strip
- [x] Progress — charts first, Trends card, forgeChart grammar + scrub callout + unlock sentences, NextBadgeRow + medallions, Awards page, badge detail
- [x] Crew — Rings segment with sort, profile page (today grid, week rings, recent sessions, badges), empty-state card
- [ ] Not adopted this round — period control on Progress (This block / 12 weeks / Year), set-editor redesign, Crew profile week rings (server has no per-day data yet)

## 13. Redesign (Lyfta look, Lungy flow)
References studied on Appllama: Lyfta: Gym Workout Tracker Log (80 screens) and Lungy: Breathing & Anxiety (81 screens). Contract: root `DESIGN.md`.
- [x] Tokens — one blue accent, white page, pale rows, 16/10/8 radii, done-green and effort-orange; watch, widgets and Live Activity follow
- [x] Shared components — solid-accent selected option rows, flat secondary capsules, bare icon buttons
- [x] Onboarding — welcome, statement pages, inline coach answers, guided first set (log, RPE, next load), "Building your plan" moment, thin progress line; 15 steps
- [x] Paywall — "Your first 14 days are free" with a dated trial timeline
- [x] Today — session card first, weekly snapshot row, plan-status card below the fold
- [x] Logger — stats bar card, one card per exercise, done-green logged rows
- [x] Default appearance follows the system; strings localized in ja, ko, vi
- [x] Exercise art — 314 écorché illustrations (grok image_edit from one style anchor, target muscle in the accent), 600 px in `Assets.xcassets/ExerciseArt`, imported by `scripts/import-exercise-art.py`; `ExerciseArt` falls back to the data-driven `MuscleThumb`
- [x] Muscle figure — front/back écorché figure with 14 per-muscle alpha masks (color-keyed grok edits cut by `scripts/import-muscle-figure.py`); one `MuscleMapView` drives check-in soreness taps (exact mask hit-test), Progress sets per muscle, roadmap emphasis and exercise detail
- [ ] Not adopted this round — Lyfta explore/program marketplace, Strava/Health toggles on the finish sheet

## Execution order
1. Engine + logger + analytics + coach actions (local, no accounts)
2. Settings/infra, check-in map, nutrition, widgets, watch, onboarding photos, trial status
3. Backend-dependent items after the owner decides: auth/sync provider, RevenueCat, analytics SDKs, Android
4. Launch ops: landing page, App Store copy, Product Hunt kit, content templates
