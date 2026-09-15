# Product Hunt launch kit

## Tagline (≤ 60 chars)

`An AI strength coach that reprograms every set you log` (54)

## Description

Most lifting apps are beautiful notebooks. Forge is the coach that reads the notebook.

You log sets; Forge reprograms the next session — load, volume, exercise selection, deload timing — from your actual performance and recovery. Volume stays inside evidence-based landmarks per muscle. Bad sleep or two red check-ins convert a session instead of breaking the streak. Plateaus trigger variant swaps automatically.

And when you want a human-sounding answer, the in-app coach looks at your log — not generic fitness advice — and can apply swaps, early deloads, or block restarts in one tap.

Built for intermediates who outgrew 5/3/1 spreadsheets. iOS first, $19.99/mo or $119.99/yr after a 7-day trial. Everything on-device except the coach chat.

## First maker comment

Hey — I built Forge because I kept being my own coach badly. My log lived in Strong, my "programming" lived in a spreadsheet that never changed, and the two never talked.

Forge makes the log do the programming. The mesocycle engine is straight volume-landmark and RPE logic (the stuff you'd pay $200/mo for a coach to apply), running on-device: weekly set auto-regulation, load progression, fatigue-driven deloads, plateau detection with variant rotation. The AI coach layer is grounded in that same engine — it cites its rules and can push changes straight into your plan.

Happy to go deep on any part of the engine. What would you want it to auto-regulate first?

## Gallery captions (5)

1. **They log. We program.** — Today view, volume auto-regulated overnight
2. **The logger respects your time** — ghost sets, plate math, rest timer in the Dynamic Island
3. **A coach that has actually read your log** — grounded answers + one-tap plan actions
4. **Fatigue-aware, not streak-obsessed** — short sleep converts the session instead of breaking it
5. **Proof, not vibes** — e1RM trends, per-muscle volume, calendar heat map

## Launch-day checklist

- [ ] Launch Tuesday or Wednesday, 12:01 AM PT (PH day resets at midnight PT)
- [ ] Hunter: self-hunt (fine in 2024+); or line up a hunter with a lifting/fitness audience 1 week before
- [ ] Assets uploaded 24 h before: gallery (5 shots + preview video), icon 240×240, dark-mode first
- [ ] Maker comment posted within 2 minutes of launch (draft above)
- [ ] Both makers marked "maker" on the listing; replies within 15 min for the first 3 h
- [ ] Waitlist email + TestFlight testers notified at launch (not before — PH rules)
- [ ] Reddit r/weightroom, r/naturalbodybuilding posts scheduled 1–2 h after PH peak
- [ ] Track upvotes per hour in the sheet; expected curve: 40% of final count in first 6 h
- [ ] Ship the launch-day update of content pipeline (first TikTok) the same day
- [ ] End of day: reply to every comment; comment a "top questions" summary

## 10 pre-written replies

**1. "How is this different from Strong/Hevy?"**
Those are excellent loggers — I used Strong for years. Forge is the programming layer that reads the log: set targets, loads, volume, deloads. It's a coach that happens to log, not a logger with a chat box.

**2. "How is it different from RP Hypertrophy / fitness AI apps?"**
RP gives you expert templates to follow; Forge generates and re-generates from your logged performance every session, and the volume engine is landmark-based on-device. The AI only explains and executes — the numbers come from deterministic rules, not vibes.

**3. "Does the AI make up training advice?"**
The chat is grounded: it answers from a rulebook (volume landmarks, progression, fatigue policy) and cites the section. Anything medical gets refused. Plan changes go through the engine — the model can't invent numbers.

**4. "What data leaves my phone?"**
Your log stays on-device. A coach question sends the question + a training summary to our Cloudflare Worker to generate the answer. No Health data is ever sent, no ads, no trackers. Privacy policy is linked and specific.

**5. "$20/mo is steep."**
A human coach is $150–300/mo for this logic. If you don't need auto-regulation, free loggers are genuinely fine — Forge is for the plateaued intermediate who's already paying with wasted training time.

**6. "Android?"**
Not yet. iOS first while the engine hardens; Android is on the roadmap if this resonates. Waitlist signups get told first.

**7. "Can I import from Strong/Hevy?"**
CSV import of exercise history is on the 1.1 list. You can also seed starting loads in onboarding in 2 minutes.

**8. "What if it programs something that hurts me?"**
Injury flags (shoulder/knee/back) change the exercise pool and swaps, and everything is RPE-capped. But it's a training tool, not a physio — pain stops the set and starts a conversation with a professional.

**9. "Who wrote the training logic?"**
The engine implements published volume-landmark and RPE-progression frameworks with per-muscle auto-regulation, built and tested as deterministic rules. Happy to nerd out in the comments — the mesocycle generator is the fun part.

**10. "Offline?"**
Fully offline for training, logging, and programming. Only the coach chat needs a connection.
