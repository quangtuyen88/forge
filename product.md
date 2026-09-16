# Forge — Product Requirements Document
**AI Strength Coach for Serious Lifters**
Version 1.0

---

## 1. Overview

| Field | Detail |
|---|---|
| Product | Forge — auto-regulated strength training coach |
| Platform | iOS first, Android v2 |
| Target | Intermediate lifters (1–4 yrs training) plateauing on static programs |
| Price | $12.99/mo or $79.99/yr, 7-day free trial |
| Goal | 2,500 paying subs by month 12 (~$40K MRR) |

---

## 2. Problem

Intermediate lifters outgrow static programs (5/3/1, PPL spreadsheets) but can't afford $150–300/mo coaching. Existing apps are either dumb loggers (Strong, Hevy) or complex/ugly expert tools (RP Hypertrophy — 4.3★, only 224 ratings). Gap: **adaptive programming that feels like a coach, at $20/mo.**

---

## 3. Target Users

- **Primary:** 22–38 y/o lifter, trains 3–5x/wk, tracks lifts in Strong/Hevy, consumes evidence-based fitness content (RP, Stronger by Science, Jeff Nippard)
- **Secondary:** Post-beginners plateauing on linear progression
- **Anti-persona:** Casual gym-goers wanting quick workouts — high churn, do not build for them

---

## 4. Core Value Loop

```
Log workout → AI adjusts next session → visible progress → retention
```

Data lock-in compounds with every session. Switching cost = losing months of training history.

---

## 5. Program Engine — Full Logic Spec

### 5.1 Volume Landmarks (per muscle group, hard sets/week)

| Muscle | MV (maintenance) | MEV (min effective) | MAV (max adaptive) | MRV (max recoverable) |
|---|---|---|---|---|
| Chest | 6 | 8 | 12–16 | 20 |
| Back | 8 | 10 | 14–18 | 22 |
| Quads | 6 | 8 | 12–14 | 18 |
| Hamstrings | 4 | 6 | 10–12 | 16 |
| Glutes | 4 | 6 | 10–14 | 16 |
| Side delts | 6 | 8 | 14–18 | 22 |
| Rear delts | 4 | 6 | 10–14 | 18 |
| Triceps | 4 | 6 | 10–12 | 16 |
| Biceps | 4 | 6 | 10–14 | 18 |
| Calves | 6 | 8 | 12–14 | 18 |
| Abs | 4 | 6 | 10–12 | 16 |

Adjust MRV down ~15–20% for users flagging poor sleep (<6h avg) or high life stress in onboarding.

### 5.2 Set Counting Rules

- A set counts toward a muscle's volume only if taken within **0–4 RIR** (reps in reserve)
- Compounds count 1:1 for primary mover, 0.5 for synergists (e.g., bench = 1 chest + 0.5 triceps + 0.5 front delt)
- Isolation counts 1:1

### 5.3 Mesocycle Structure

```
Week 1:     Start at MEV
Weeks 2–5:  Add 1–2 sets/muscle/week (approach MAV)
Week 6:     Deload — 50% volume, 60–70% intensity, RPE ≤ 6
Repeat
```

### 5.4 Auto-Regulation — Load Progression

Per exercise, compare actual vs target RPE:

```
Δ = RPE_actual − RPE_target

if Δ ≤ −1.0:  load_next = load × 1.05   (too easy, add 5%)
if Δ = −0.5:  load_next = load × 1.025
if Δ = 0:     load_next = load × 1.0 → add reps next session (double progression)
if Δ = +0.5:  load_next = load (repeat)
if Δ ≥ +1.0:  load_next = load × 0.95   (reduce 5%, flag fatigue)
```

### 5.5 Double Progression (isolation + dumbbell work)

```
Target rep range: e.g., 8–12
- Hit top of range on all sets at RPE ≤ target → increase load by smallest increment (2.5 lb / 1 kg)
- New load, restart at bottom of range
```

### 5.6 Fatigue Score (daily, 0–100)

```
Fatigue = 0.35 × acute_chronic_volume_ratio_score
        + 0.25 × soreness_score        (1–5 check-in, scaled)
        + 0.20 × sleep_deficit_score   (HealthKit vs 7-day baseline)
        + 0.20 × missed_RPE_penalty    (sessions where RPE_actual > target + 1)
```

Where acute:chronic volume ratio:

```
ACVR = (last 7 days volume) / (avg weekly volume, last 28 days)
- ACVR 0.8–1.3 → score 0 (green)
- ACVR 1.3–1.5 → score 50 (yellow)
- ACVR > 1.5   → score 100 (red, injury-risk zone)
```

### 5.7 Fatigue-Driven Interventions

| Fatigue score | Action |
|---|---|
| 0–39 | Proceed as planned |
| 40–59 | Proceed; reduce optional/back-off sets by 1 |
| 60–79 | Convert today to light session: −30% volume, cap RPE 7 |
| 80–100 | Force rest day or trigger early deload; notify user with explanation |

### 5.8 Exercise Substitution Map (injury flags)

```
shoulder_flag:
  barbell bench → dumbbell bench (neutral grip)
  overhead press → landmine press
  dips → cable fly
knee_flag:
  back squat → leg press (high foot) or hack squat
  lunges → leg extension (controlled)
back_flag:
  deadlift → hip thrust or cable pull-through
  bent row → chest-supported row
```

Substitution preserves the movement pattern's volume credit.

### 5.9 Estimated 1RM (Epley)

```
e1RM = weight × (1 + reps / 30)
```

Trend per lift over rolling 12 weeks; plateau = no e1RM improvement for 3+ weeks → trigger exercise variant rotation or volume bump for that muscle.

---

## 6. Feature Spec

### 6.1 Onboarding (P0)
- Goal: hypertrophy / strength / both
- Experience level, days/week (3–6), session length (45/60/90 min)
- Equipment profile: barbell / dumbbell / machines / cables / home gym
- Current lifts (or bodyweight-based estimate) → starting weights
- Injury flags: shoulder / knee / back / none

### 6.2 Workout Logger (P0)
- One-thumb logging: weight, reps, RPE in <3 taps per set
- Auto rest timer: 3 min compounds, 90 s isolation (user-adjustable)
- Plate calculator, kg/lb toggle, ghost values from previous session
- Offline-first (local SQLite, background sync)

### 6.3 Daily Check-in (P0)
- 15-second: sleep, soreness, energy sliders (1–5)
- Feeds fatigue model (§5.6)

### 6.4 Progress Analytics (P1)
- e1RM trend charts per lift
- Weekly sets per muscle vs landmarks (MV/MEV/MAV/MRV bands)
- PR detection + shareable card
- Consistency streak

### 6.5 AI Coach Chat (P1)
- Scoped LLM over user's training data
- Handles: "why did weight drop", "swap exercise", "explain my deload"
- Strict scope: training only, no medical/rehab advice

### 6.6 Paywall (P0)
- Shown after onboarding, before first workout
- 7-day trial → $12.99/mo; annual $79.99 default-highlighted ("save 49%")
- RevenueCat for subscription infrastructure

---

## 7. Non-Functional Requirements

- Cold start < 2 s; set-logging interaction < 100 ms
- Full offline workout capability
- HealthKit: read sleep, write workouts
- CSV data export (trust builder, reduces churn fear)
- Privacy: training data on-device + encrypted cloud backup

---

## 8. Monetization & Metrics

| Metric | Target |
|---|---|
| Install → trial | >25% |
| Trial → paid | >50% |
| Monthly churn | <5% |
| LTV | >$300 |
| Organic install share | >70% |

**North Star:** weekly workouts logged per active user (target ≥3).

---

## 9. Go-to-Market

1. **Beta (wk 8):** 100 lifters from r/weightroom, r/naturalbodybuilding, Discord coaching servers — lifetime free for feedback
2. **Launch:** YouTube Shorts/TikTok — "I built an app that programs like a $200 coach" + form-check content + progress timelapses
3. **Growth:** micro-influencer coaches (5–50K followers), 30% rev-share via promo codes; SEO ("RP Hypertrophy alternative")

---

## 10. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Bad programming advice → injury/churn | Conservative defaults, 100-user beta, disclaimers |
| Logger too slow → abandonment | Performance budget; benchmark vs Strong/Hevy |
| Hevy/Strong add AI coaching | Win on depth: they log, we program |
| Medical liability | Disclaimers, injury-flag substitutions, no rehab claims |

---

## 11. Timeline

| Week | Deliverable |
|---|---|
| 1–2 | Exercise DB (300+ exercises, substitution map), program engine core |
| 3–5 | Logger UI, rest timer, offline storage |
| 6–7 | Check-in, fatigue model, paywall, onboarding |
| 8–10 | Closed beta (100 users), iterate |
| 11–12 | Analytics v1, App Store launch |

---

## 12. Financial Model Recap

```
Downloads:           5,000/mo (organic-heavy)
Paid conversion:     5% (high-intent niche)
New subs:            250/mo
MRR added:           250 × $12.99 ≈ $3.2K/mo
Churn:               ~5%/mo → ~20-month lifetime
Steady-state MRR:    $40–70K (months 10–14)
LTV:                 ~$350+
Net margin:          ~70% (low UA spend)
```
