# Regulift roadmap

Principle: **every engine decision produces a readable reason.** One `Decision` object in ForgeCore carries subject, action, causes and whether the lifter may override it. The Today card, the logger, the coach chat, the weekly review and notifications all render the same object, so an explanation is never written twice and never drifts.

```
Decision: remove 1 set from chest
Causes:  soreness high (4/5, two sessions) · last session RPE 9 vs target 8
Action:  sets 14 → 13 this week
Override: allowed (keep original / easier / harder)
```

## 1.0.1 — Trust and activation

| Feature | What ships |
|---|---|
| Why this changed | A card per prescription: headline, last performance, e1RM change, readiness, the plan. Buttons: Why?, Keep original, Make easier, Make harder. Rule-based, no chat text. |
| Zero-effort migration | Import a CSV or paste a log, the app infers exercises, maxes, weekly volume, frequency and preferred rep ranges, flags stalled lifts, suggests a split, and shows a "what I learned" screen ending in Start adaptive block. |
| Missed workout recovery | When sessions are missed the app names one recommended fix in plain words, with shift, compress, skip and light as alternatives. |

## 1.1 — Adaptive intelligence

| Feature | What ships |
|---|---|
| Plateau rescue | A stalled lift triggers exactly one intervention: rotate the variation, change the rep range, cut fatigue, add volume or deload. Never a menu of five. |
| Gym profiles | Home, commercial, hotel, dumbbells only, no machines, bodyweight, or a custom list. Swaps explain themselves: cable row unavailable, chest-supported dumbbell row instead. |
| Time-boxed workouts | I have 20 / 30 / 45 / 60 minutes. The engine keeps the main lift and cuts filler. |

## 1.2 — Personalisation moat

| Feature | What ships | Why it waits |
|---|---|---|
| Run an experiment on me | A four-week A/B on one variable, for example chest volume 8 to 11 sets a week with everything else held. Reviewed at the end: e1RM change, soreness change, keep or revert. | Needs clean history and enough sessions to be honest. |
| Goal / event mode | Target lift, target date, days available, priority lifts. Not a full periodisation simulator. | Easy to over-build; ship after the engine's explanations are trusted. |
| Crew challenges | Behaviour only: three sessions this week, twelve this month, protein hit five days, every set logged. Never tonnage or biggest PR. | Ego leaderboards hurt the product; consistency is the point. |

## Not planned

Exercise video library beyond a demo clip, coach marketplace, meal planning, public social feed, form checks from video, more badges.
