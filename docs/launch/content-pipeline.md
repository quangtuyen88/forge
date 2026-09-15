# Content pipeline — TikTok / Reels / Shorts

Goal: 3 posts/week for 8 weeks pre-launch. Every video ends with the waitlist link in bio (`vnbnode.com/forge`).

## 10 script hooks

1. **"I built an app that programs like a $200 coach"** — screen-record Today view regenerating next week after one logged session. Hook: show the diff ("chest +1 set, squat −10 kg, why?").
2. **"Your spreadsheet doesn't know you slept 5 hours"** — split screen: spreadsheet day vs Forge fatigue day converting the session. 
3. **"5/3/1 vs what actually happened"** — log the missed reps, watch the plan adapt. Punchline: "the spreadsheet never found out."
4. **"My app refuses to answer that"** — ask the coach a supplement-dosing question on camera; refusal card; "a coach that knows its lane."
5. **"This plateau detection actually works"** — PR board: 3 sessions flat e1RM → exercise swaps to a variant automatically.
6. **"POV: your rest timer lives in the Dynamic Island"** — hands-full gym shot, island countdown, plate math one-handed.
7. **"I asked an AI why my bench stalled"** — coach chat with citations, tap Apply on the swap. "It reads the rulebook, not the room."
8. **"Volume landmarks explained in 20 seconds"** — MEV/MRV graphic from the app's per-muscle volume screen; "this is why your chest stopped growing at 22 sets."
9. **"Deload week: scheduled by my phone, not my ego"** — two red check-ins → early deload card. Ego vs app.
10. **"They log. We program."** — launch-day brand video: hero shot, 3 feature captions, PR card, end card.

## Shot list template (per video)

| # | Shot | Duration | Overlay | Capture |
|---|------|----------|---------|---------|
| 1 | Hook — face to camera or bold text on screen | 0–2 s | Hook line verbatim | iPhone front cam, natural light |
| 2 | App screen recording (Simulator or device, 60 fps, clean status bar) | 2–8 s | 1–2 word callouts only | `xcrun simctl io <udid> recordVideo` or device screen record |
| 3 | Cutaway: hands logging / gym ambience / PR card | 8–12 s | none or caption | iPhone, gimbal optional |
| 4 | Payoff: the plan diff / PR card / refusal card | 12–18 s | the point, once | screen recording |
| 5 | CTA end card | last 2 s | "Waitlist in bio" | static card |

Rules: vertical 9:16, captions burned in (watch without sound), hook resolved by second 3, no intro logos, one idea per video.

## Progress-timelapse template (weekly, Sunday post)

- **The 3-shot pose** — same spot, same lighting, same pose trio each week: front relaxed, side, back double (or front double). Tripod mark on the floor with tape.
- **Clip:** 1.5 s per pose, whip-cut across weeks (week 1 → week N) in order.
- **PR card overlay:** at the cut of each month, overlay the app's shareable PR card (screenshot → Keynote green-screen it, or screen-record the share sheet) for that month's best lift.
- **Caption formula:** "Week N. [best lift: kg×reps]. Everything else: the app's problem."
- Export 1080×1920, 24 or 30 fps.

## Posting cadence

| Day | Post | Notes |
|-----|------|-------|
| Mon | Timelapse or POV shot (low effort) | consistency beats production |
| Wed | Feature/education video (hooks 2, 4, 8, 9) | mid-week engagement peak |
| Fri or Sat | Build-in-public / hook 1 / PR clip | gym-day traffic |

Cross-post identical cuts to Reels + Shorts (no watermark re-uploads — export clean). Reply to every comment for the first hour; comments are distribution.

## Tracking sheet columns

`date | platform | hook | format (timelapse/feature/POV/build) | video link | views | 3s retention % | avg watch % | likes | comments | shares | waitlist clicks (link in bio UTM) | signups | notes`

Add UTM per post: `?utm_source=tiktok&utm_campaign=<hook-slug>` (shortlink via `/r/` code works too and pays referrals).
