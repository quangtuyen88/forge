# App Store listing — Forge 1.0

## App name

Forge — AI Strength Coach

## Subtitle (30 chars)

`Auto-regulated strength coach` (29)

## Promotional text (170 chars, editable without review)

`Stop re-running someone else's spreadsheet. Forge reprograms every set from what you actually lifted — loads, volume, deloads, swaps. Your log becomes your coach.`

## Description (≤ 4000 chars)

You didn't stall because you're lazy. You stalled because your program stopped listening.

Static programs — 5/3/1 templates, PPL spreadsheets, PDFs from a forum in 2016 — give everyone the same next week. Forge gives you yours: a training block that reads what you lifted, how you slept, and how beat-up you feel, and reprograms the next session accordingly.

**They log. We program.**

HOW FORGE COACHES

- **Every set adjusts the plan.** Hit the top of your rep range at RPE 8 and next week's load moves up. Miss reps and it holds. Beat a plateau three sessions in a row and the exercise rotates to a variant.
- **Fatigue-aware days.** Log a short night, high soreness, or a rough week and Forge converts the session to what you can recover from. Two red days in a row and it schedules the deload early — before you dig a hole, not after.
- **Volume that tracks your landmarks.** Weekly sets per muscle auto-regulate between minimum effective and maximum recoverable volume — the evidence-based range — instead of climbing until something hurts.
- **A coach in your pocket.** Ask "why did my bench stall?", "swap this exercise", or "I missed a week, what now". The AI coach answers with your actual log in front of it — and can apply the swap or deload to your plan in one tap.
- **Rest timers that think.** 3 minutes for compounds, 90 seconds for isolation, auto-started, with a Live Activity on your Dynamic Island so you never unlock your phone mid-workout.

WHAT YOU GET

- A full mesocycle built from your goal, schedule, equipment, and injury flags
- 300+ exercises with substitution for shoulder, knee, and back constraints
- kg/lb logging with plate math, ghost sets from last week, and PR detection
- Weekly check-ins (sleep, soreness, energy) plus optional Apple Health sleep, HRV, and resting heart rate — read-only, never uploaded
- Progress you can see: e1RM trends, per-muscle volume, calendar heat map, PR board
- Everything on-device and offline; only the coach chat needs a connection

FOR LIFTERS WHO OUTGREW THEIR SPREADSHEET

Forge is built for the intermediate — one to four years in, training 3–6 days a week, past linear progression, tired of being their own coach. If Strong or Hevy is where your log lives but your programming still comes from a PDF, this is the missing half.

IMPORTANT

Forge is a training tool, not medical advice. It refuses medical, injury-rehab, and supplement-dosing questions and points you to a professional. Train hard, see a doctor when something hurts.

PRICING

$19.99/month or $119.99/year after a 7-day free trial. Cancel any time, in the App Store, in two taps.

*(2,486 characters)*

## Keywords (100 chars, comma-separated, no spaces)

`gym,workout,lifting,strength,hypertrophy,powerlifting,barbell,RPE,531,deload,progression,log` (93)

## What's new — 1.0

First public release.
- Auto-regulated mesocycles: volume, loads, and deloads adapt weekly
- AI coach with plan actions: swaps, early deloads, restarts applied in one tap
- Logger with Live Activity rest timers, plate math, and ghost sets
- Fatigue model wired to check-ins and optional Apple Health (sleep/HRV/RHR)
- PR board, e1RM trends, volume analytics, calendar heat map

## Category

- Primary: Health & Fitness
- Secondary: —

## Age rating notes

- Rated 4+ (no objectionable content). No gambling, no user-generated content feeds, no unrestricted web access — the privacy policy and terms open in Safari.
- Health & Fitness questionnaire: contains fitness tracking; no medical/treatment claims anywhere in metadata.

## Review notes

- **No test account needed.** The full app works without an account; the coach chat needs a server key that ships with the build.
- **Live Activity:** started automatically by the in-workout rest timer (ActivityKit). Screenshots of the Dynamic Island Live Activity are in the review notes attachment.
- **HealthKit:** requested on first check-in, read-only, limited to sleep analysis, HRV, and resting heart rate. Used locally by the fatigue model; never transmitted. Declining it hides the recovery readout; nothing else breaks. A screenshot of the permission sheet is attached.
- **AI consent:** before the first coach question, an in-app sheet states that the question, training log, and profile go to Forge's server (Cloudflare Workers AI) and can be declined; consent is revocable in Settings at any time. Medical questions are refused by a guard.
- **Subscriptions:** auto-renewing, 7-day trial, priced $19.99/mo / $119.99/yr; restore purchases in Settings → Subscription.

## Screenshots — 6.9" and 6.5"

### Copy rules

- Headline first, ≤ 6 words, sits above the device. One concrete product moment per shot, shown in real seeded screen content — no mock text, no invented numbers.
- Subline: one short line, ≤ 60 chars, optional. No paragraph under the device.
- No outcome promises, absolutes, or medical/injury claims. Describe what the app does, not what it promises the user.
- Social proof (ratings, testimonials) only when true and sourced.
- Exactly one frame-break shot for rhythm; the rest centred, with callouts only where they earn their place.
- Forge palette throughout, so the set reads as Forge without the logo: page cream `#F3F4F8` background, accent `#3866D6` for callouts and highlights, the navy share-card gradient for scrims.
- Captions are overlaid in Figma on export — never baked into the capture.

### Shot list

1. **"They log. We program."**
   - Subline: `Your log becomes the next session.` (34 chars)
   - Capture: Home (Today) tab, coach set to Kai, seeded block in week 4 with one completed session. "Kai's adjustments" card visible with two changed lifts (one load up, one held) and the week line. Scrolled so the card sits in the top third of the frame.
   - Layout: device frame centred, headline above.
2. **"Every set changes the next."**
   - Subline: `Log it. Rest. The plan moved.` (29 chars)
   - Capture: mid-workout logger — one bench set logged, ghost values on the rows below, rest bar counting down. Dynamic Island: capture the island Live Activity separately with the app backgrounded, crop it, composite above the frame's status-bar area.
   - Layout: frame-break — rotate/offset the device so the top edge crosses the card border; the island crop sits above the frame.
3. **"Deloads before you break."**
   - Subline: `Two red days pull the deload forward.` (37 chars)
   - Capture: Home with the early-deload card — seed two consecutive red check-ins (fatigue ≥ 80). Fallback if the card is awkward to seed: the scheduled Week 6 deload hero chip.
   - Layout: centred, one accent callout pointing at the card title.
4. **"Built around your gym."**
   - Subline: `Dumbbells only, shoulder flagged — plan matches.` (48 chars)
   - Capture: paywall after onboarding seeded with dumbbells-only equipment and the shoulder injury flag, so the "Built for you" lines name both. Scrolled until the "Built for you" card fills the frame.
   - Layout: centred.
5. **"PRs, on the record."**
   - Subline: `Detected, dated, shareable.` (27 chars)
   - Capture: post-workout summary with one PR row visible (e.g. bench e1RM up) and the navy share card on screen.
   - Layout: centred; the navy card anchors the lower third.
6. **"Progress you can read."**
   - Subline: `e1RM trend, badges, streak heat map.` (36 chars)
   - Capture: Progress tab, scrolled so the badge row sits just above the 12-week e1RM chart with the trend line clear.
   - Layout: centred, one callout on the trend line.

### Proofreading checklist

- [ ] Every headline ≤ 6 words — count them out loud
- [ ] Sublines ≤ 60 chars, single line, no paragraph under any device
- [ ] No outcome promises or absolutes in any caption; no medical or injury claims
- [ ] Numbers on screen match the seeded data (weights, week, sets) — no invented stats
- [ ] Palette holds: cream `#F3F4F8`, accent `#3866D6`, navy scrim — set reads as Forge without the logo
- [ ] Spell-check run in Figma before export, not on the PNGs
- [ ] Six shots in this order; only shot 2 breaks the frame

Capture per device (simulator, fresh install, seeded demo data, light mode on the cream background):

```
xcrun simctl list devices | grep "iPhone 17 Pro"     # pick the UDID
xcrun simctl io <udid> screenshot forge-1-they-log.png
xcrun simctl io <udid> screenshot forge-2-every-set.png
xcrun simctl io <udid> screenshot forge-3-deloads.png
xcrun simctl io <udid> screenshot forge-4-your-gym.png
xcrun simctl io <udid> screenshot forge-5-prs.png
xcrun simctl io <udid> screenshot forge-6-progress.png
```

Repeat with the 6.5" device (App Store Connect also takes 5.5"; export 1170×2532 and 1284×2778 as needed).

## Preview video storyboard (15–30 s, 6.9")

| t | Shot | On screen |
|---|------|-----------|
| 0–3 s | Screen recording: Today view opens, volume callout pulses | "Your plan, adjusted overnight" |
| 3–8 s | Logging a set; timer jumps to Dynamic Island | "Log the set. It takes the note." |
| 8–13 s | Coach chat: question typed, answer streams, Apply tapped | "Ask anything. It updates the plan." |
| 13–18 s | PR card share sheet animates out | "PRs worth posting" |
| 18–24 s | Progress charts scroll (e1RM + heat map) | "Proof it's working" |
| 24–27 s | Paywall with trial CTA; app icon end card | "Forge. They log. We program." |

Capture with `xcrun simctl io <udid> recordVideo --codec h264 forge-preview.mp4` (≤ 30 s, no audio needed).
