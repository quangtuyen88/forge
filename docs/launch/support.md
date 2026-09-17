# Support playbook

Inbox: in-app feedback (Worker `/feedback` events), no public email.

## Labels & SLAs

| Label | Use | SLA |
|-------|-----|-----|
| `urgent-crash` | App unusable, data loss, crash loop | 4 h (same day) |
| `refund-billing` | Refunds, subscription, charge questions | 24 h |
| `coach-issue` | Coach wrong/no answer/server errors | 24 h |
| `bug` | Reproducible non-blocking defect | 48 h |
| `healthkit` | Permissions, missing recovery data | 48 h |
| `feature` | Requests | 1 week (batch reply) |
| `waitlist` | Waitlist/referral questions | 48 h |
| `feedback-love` | Praise | when there's a minute (ask for review) |

Escalation: `urgent-crash` with data loss → reproduce in Simulator with seeded data before replying; check Workers status page for `coach-issue` bursts.

## 8 macro replies

**1. Refund** — "Refunds go through Apple, since they process all App Store payments — I can't charge or refund from my side. Fastest path: reportaproblem.apple.com, sign in with your Apple ID, find Forge, click Request a Refund. Apple usually answers in 24–48 h. If it's a bug that ruined your week, tell me what happened — I want to fix it regardless of the refund."

**2. HealthKit permissions denied → recovery data missing** — "The recovery readout uses Apple Health (sleep, HRV, resting HR), read-only. To re-enable: Settings app → Privacy & Security → Health → Forge → turn on the categories. Or Forge → Settings → Recovery → Connect Apple Health. Your training and check-ins never needed it — this only sharpens the fatigue model."

**3. Coach not answering** — "The coach needs a connection; training and logging are fully offline, only the chat calls the server. First, check Settings → Coach server status. If it says warming up, the backend provider is briefly unavailable and usually recovers in minutes — retry. If it keeps failing, send me the exact message under the input field and I'll check the server logs."

**4. Coach refused a question** — "That's on purpose: Forge refuses medical, injury-rehab, and dosing questions and points to a professional. Programming questions — volume, loads, swaps, deloads, fatigue — are always fair game. If it refused something that's clearly training, paste the question and I'll tune the guard."

**5. I missed a week / lost my streak** — "Nothing to restore — Forge never punishes missed days. Open the coach and say 'I missed a week'; it can adjust or restart the block, and the volume engine already discounted for the layoff. Detraining was accounted for; your ego wasn't."

**6. Data deletion / privacy** — "Everything lives on your device. Settings → Reset removes your profile, log, and coach history from the phone. Deleting the app does the same. Coach chats are never stored server-side. If you want your waitlist/feedback records gone too, reply here and I'll clear them."

**7. Restore purchase / trial ended early** — "Settings → Subscription → Restore Purchases, signed into the same Apple ID you subscribed with. If the trial shows as used, that's Apple's 7-day-per-Apple-ID rule across reinstalls — if it ended early (not by reinstall), tell me the dates and I'll check what Apple reports."

**8. Feature request ack** — "Logged, thank you — feature requests shape the roadmap directly. The near-term list right now: CSV import, supersets, warm-up calculator, Android. No promises on dates, but you'll see it in What's New if it ships. Anything else you'd want first?"

## In-app feedback intake

The app's feedback sheet (`FeedbackSheet`) posts to `POST /feedback` → Analytics Engine dataset `forge_events`, event name `feedback`, blobs `[feedback, device, text]` (device = anonymous UUID from UserDefaults). There is no inbox for it — pull them on a support sweep (SLA: daily during launch week, 2–3×/week after).

Query (Analytics Engine SQL API — `blob1` = name, `blob2` = device, `blob3` = text):

```bash
curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/analytics_engine/sql" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  --data-urlencode "query=SELECT _timestamp, blob2 AS device, blob3 AS text FROM forge_events WHERE blob1 = 'feedback' AND _timestamp > NOW() - INTERVAL '7' DAY ORDER BY _timestamp DESC LIMIT 100"
```

(Also how you audit waitlist signups: `... WHERE blob1 = 'waitlist'` — blob2 = email, blob3 = referrer code.)

Triage pulled feedback with the same labels; replies go by asking the user to email (feedback is one-way) — hence the macro asking for a reply address when the report is actionable.

## Beta survey (TestFlight)

Send 3 weeks into beta, after the first full mesocycle:

1. How many years have you been lifting? (open numeric)
2. What program were you on before Forge? (short answer)
3. How often did you train per week during the beta? (1–7)
4. Did the prescribed loads feel right, too light, or too heavy? (Likert 1–5 + comment)
5. Did a fatigue adjustment (light session / early deload) ever fire? Did you agree with it? (yes/no + why)
6. Did you use the coach chat? What did you ask? (never / once / weekly + examples)
7. What almost made you stop using Forge? (open)
8. What would you pay for it? ($0 / $9.99 / $19.99 / $29.99+ per month)
9. Would you recommend it to a training partner? (0–10, NPS)
10. Anything broken, missing, or annoying? (open)

TestFlight message template:

> Three weeks in — thank you. 5 minutes to tell me what's working and what isn't: [survey link]. Everything is read by a human (me). Next build fixes [X] and adds [Y] from your last reports.

Keep the survey in the TestFlight tester group so emails aren't collected; pull scores into the tracking sheet weekly.
