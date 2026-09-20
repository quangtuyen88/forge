# Regulift × Ladder — Net-New Feature Candidates

**Reviewed:** 20 September 2026  
**Purpose:** Identify worthwhile additions without rebuilding features already implemented.  
**Status:** Product/engineering proposal based on public sources and your implementation updates, not a hands-on app or repository audit.

## 1. Correct the baseline first

Your later feature list reports Focus Mode, Gym Profiles, missed-workout recovery, explanations, structured Coach memory, onboarding/import analysis and training experiments as implemented. Do not put those back in a “missing” backlog because an older generated roadmap calls them new.

The inspected Regulift landing page also advertises explanations, Coach changes/memory, post-workout next loads, voice, Watch and widgets. Public copy confirms the claim, not its implementation quality. [R1]

The candidates below are **not confirmed implemented in the available evidence**. Before opening tickets, find an existing equivalent. A missing mention on a website is not proof that a feature is absent.

### Source limitations

Ladder's supplied quiz URL exposed its page shell, not the interactive question sequence. I did not complete the quiz. Its public site does describe goal/style-based plan matching. [L1]

Ladder's App Store listing/release history describes Flex-workout discovery and wearable/Apple Health workout import. Its homepage describes weekly coach programming and spoken workout guidance; its pricing page describes Team Chat. These are developer-published capabilities, not independent quality measurements. [L2–L4]

No claim is made that Ladder lacks adaptive internals or that Regulift produces better training outcomes.

## 2. Recommended order

| Order | Candidate | Type | Initial decision |
|---|---|---|---|
| 0 | Accurate public availability, pricing and install path | Observed public funnel issue | Fix before driving additional traffic. |
| 1 | Web plan match + genuine first-session preview | Candidate acquisition gap | Build a thin extension of existing onboarding. |
| 2 | Event-driven spoken Coach | Candidate workout gap | Prototype before full real-time voice AI. |
| 3 | Forward-looking week/block briefing | Extension, not a new weekly-review system | Reuse current decisions and review UI. |
| 4 | Plan-compatible optional sessions | Candidate capability gap | Small reviewed catalog; never random extra volume. |
| 5 | External-activity context | Candidate integration gap | Local/manual pilot before more external services. |
| 6 | Small shared training blocks | Candidate Crew extension | Pilot with existing friends; avoid an empty public feed. |

The first three product items are the next-release candidates. The others require evidence from users. This is not a commitment to implement every Ladder feature.

## 3. Ticket WEB-00 — Make the public funnel accurate

**Observed issue:** the inspected landing page still presents launch-free pricing and a coming-soon App Store message. [R1] These should match the actual product availability and your paid-product strategy.

### Tasks

- [ ] Use an App Store installation CTA only when the correct listing is live.
- [ ] Otherwise use an accurate TestFlight/beta or waitlist destination, not a dead install button.
- [ ] Display the actual current paid offer, trial rules and renewal terms where relevant; do not invent a free tier.
- [ ] Explain the next action after every CTA.
- [ ] Check English/Japanese/Korean wording for the actual funnel you ship.
- [ ] Verify privacy copy against real sync, Coach and dictation behavior.

**Acceptance:** a first-time visitor can understand availability and price and successfully reach the real next step. No claim of App Store approval or paid availability is inferred from the website.

## 4. Ticket WEB-01 — Find My Plan before installing

**Ladder inspiration:** goal/style-based plan matching. [L1]  
**Regulift-specific addition:** show what the existing engine would start with and demonstrate how future sessions adapt. This result/interactive demonstration is our proposal, not a claim about Ladder's exact quiz output.

### Minimum flow

```text
Find my plan
 → goal
 → realistic weekly availability
 → session duration
 → equipment
 → experience / current training
 → editable starter-plan preview
 → actual install/beta action
 → recover these answers in the app
```

Limit choices to configurations the deployed engine actually supports. The supplied older overview supports 3–6-day templates; verify later support before offering a two-day result. Do not fabricate support for a schedule just because it looks useful on a quiz. [R2]

Do not add account creation, birthday, body photos, injury history or payment collection merely to reveal a basic preview.

### Preview

```text
Your starting structure
4-day Upper / Lower

Designed around your selected equipment and time budget.

Monday     Upper A
Tuesday    Lower A
Thursday   Upper B
Saturday   Lower B

Starting loads: calibrated in the app or from imported training history.
This is a starter plan, not a promise of future strength or appearance.
```

An optional “See how it adapts” demo can use clearly labeled example data. It must never pretend it has analyzed the visitor's actual workouts.

### Engineering tasks

- [ ] Reuse existing onboarding schema and constraints.
- [ ] Implement a versioned preview adapter; avoid an independently invented JavaScript training algorithm.
- [ ] If running the actual Swift engine on the web/backend is impractical, use reviewed starter-template previews and label them accordingly; finalize in-app.
- [ ] Store only non-sensitive quiz choices behind an opaque expiring token.
- [ ] Use an associated HTTPS link for an installed app; provide an explicit recovery code or user-initiated saved link after installation.
- [ ] Never promise automatic deferred deep-link recovery from a custom URL scheme.
- [ ] Preserve editability; do not rerun every question after handoff.
- [ ] Keep Strong/Hevy file import in the existing app flow initially.

Apple's archived link guide distinguishes installed-app opening from browser fallback when the app is absent. A reliable post-install recovery flow must be designed separately. [T1]

### Acceptance and measurement

A supported result opens with equivalent answers in the app; expired/invalid tokens fail cleanly; existing users do not overwrite their current plan; no sensitive content appears in URLs or analytics.

Measure preview completion and first-workout completion among eligible visitors. Quiz completion alone is not the success metric. No conversion uplift is assumed in advance.

## 5. Ticket AUDIO-01 — Spoken guidance on top of existing voice logging

**Ladder inspiration:** spoken coaching and music coexistence. [L3, L4]  
**New delta:** speaking useful current guidance back to the lifter. Voice quick-log and Coach dictation already exist.

### V1 is event narration, not a full conversational voice agent

```text
Committed prescription becomes current
 → “Bench press. Set two. 85 kilograms, six to eight reps.”

Set is successfully logged
 → short acknowledgement when enabled

Rest ends
 → “Next set is ready.”

Exercise ends
 → brief next-exercise setup
```

Examples are illustrative; real numbers must come from the committed plan. The voice must never independently decide a new load.

### Tasks

- [ ] Add one audio coordinator shared with current recording, timers and system interruptions.
- [ ] Queue messages using event IDs, plan revision, priority and expiry.
- [ ] Use local, localized templates plus device speech for the first prototype.
- [ ] Provide Off / Minimal / Standard settings and one-tap mute/repeat.
- [ ] Prevent private recovery details from being spoken by default on speakers.
- [ ] Explore audio ducking through the system audio-session API; test it with the actual supported music apps/devices rather than promising universal behavior.
- [ ] Stop stale queued speech after an exercise swap, skipped rest or changed prescription.
- [ ] Handle phone calls, alarms, Siri, Bluetooth disconnection, media-service reset and foreground return.
- [ ] Preserve existing push-to-talk/explicit recording; never introduce silent always-listening.
- [ ] Mirror important information in text/haptics for users who do not use sound.

The Apple interruption guide supports a stateful save/restore/reactivation design. Use current SDK APIs and real-device tests; archived sample code is not the implementation. [T2]

### Acceptance

No duplicated or outdated prescription is spoken after a retry. A model outage cannot block a set or timer. Muting is respected after relaunch. Every supported language has a tested fallback. Interrupted audio does not resume against the user's choice.

**Measure:** hands-free task completion, correction rate, narration disable rate and return-workout completion. Do not infer success from the number of utterances played.

**Deferred:** live duplex voice conversation, emotional synthetic coaching personas, always-on microphones and a separate paid voice provider.

## 6. Ticket WEEK-01 — A forward-looking coaching brief

**Ladder inspiration:** recurring coach-created weekly programming. [L3]  
**New delta:** explain the upcoming week's purpose, not another retrospective statistics screen or a duplicate weekly planner.

### Example

```text
Your next week

Focus: keep the current bench progression.
Change: Thursday's session moves to Friday, as requested.
Unchanged: your remaining exercise selection.

[ Review actual changes ]
```

Generate statements only when matching actual program decisions exist. Do not say recovery is “normal” simply because no Health data is available.

### Tasks

- [ ] Add an upcoming-week mode to the existing weekly review/Coach surface.
- [ ] Read the current block goal, confirmed schedule and committed decision IDs.
- [ ] Limit the default brief to a focus, a material change and what stays stable.
- [ ] Link each personal claim to its local evidence.
- [ ] Recompute or invalidate the brief when the plan changes.
- [ ] Keep Health-dependent explanations local.
- [ ] Allow concise/analytical tone as presentation only; never alter prescriptions based on personality.

**Acceptance:** no stale or invented claim, no additional permission requirement, and no new tab. Measure whether recipients complete their next planned session; compare against the existing weekly review before expanding.

## 7. Ticket FLEX-01 — Optional sessions that respect the plan

**Ladder inspiration:** its published Flex-workout discovery feature. [L2]  
**New delta:** curated extras or replacements selected against current planned work—not a duplicate “I only have 20 minutes” shortcut.

### Small initial catalog

Use only content supported and reviewed for the current engine, such as short core/accessory sessions or a limited conditioning/mobility collection after domain review. An item needs equipment, duration estimate, movement demands, workload semantics and substitution rules.

```text
I want an optional session today
 → show eligible options
 → choose Add or Replace
 → preview effect on remaining sessions
 → confirm
 → record actual completed work
```

### Tasks

- [ ] Add a typed catalog, not a prompt that invents exercise lists.
- [ ] Reuse gym, duration and program constraints.
- [ ] Separate `add_session` from `replace_session` in the engine intent.
- [ ] Allow “No additional session recommended” as a valid result.
- [ ] Count actual work once; adjust planned future work through existing rules.
- [ ] Do not convert conditioning duration into hypertrophy hard sets.
- [ ] Permit preview/undo before execution; distinguish scheduled from completed.
- [ ] Use ordinary search/filters first. Semantic search is optional, not the value proposition.

**Acceptance:** no double-counted workload, no automatic extra hard sets, and no requirement for videos. Measure actual use and disruption to the main plan before growing the catalog.

## 8. Ticket ACTIVITY-01 — Acknowledge training outside Regulift

**Ladder inspiration:** published workout-data import from Apple Health/non-Apple wearables. [L2]  
**New delta:** recognize external sessions as context rather than only knowing the strength workouts logged in Regulift.

### Initial flow

```text
External workout detected or entered manually
 → user confirms what it was
 → show it in the local week
 → ask whether to review today's plan
 → existing rules or user choice decide any adjustment
```

### Tasks

- [ ] Audit whether an equivalent Health workout import already exists.
- [ ] Add an optional manual “trained elsewhere” entry first if adequate.
- [ ] For Health integration, request only the data needed for this feature and process it locally.
- [ ] Deduplicate source workouts; exclude Regulift's own written workouts from being imported as new activity.
- [ ] Preserve original source, activity type and duration without inventing missing effort.
- [ ] Treat estimated calories as estimates, not an exact basis for calorie prescriptions.
- [ ] Offer review rather than apply arbitrary reductions after every run or ride.
- [ ] Keep raw/derived Health activity data out of cloud Coach, analytics and general sync in this design.

**Acceptance:** no duplicate activity, no invented muscle fatigue score, no automatic run-to-hard-set conversion, and no critical dependency on a new external provider.

**Defer:** a broad Garmin/Strava service integration until users request it and its authorization/privacy work is scoped. Existing Apple Watch support is not being rebuilt.

## 9. Ticket CREW-01 — Shared blocks, individualized workouts

**Ladder inspiration:** coach/team identity and Team Chat. [L4]  
**New delta:** a shared training commitment layered on existing Crew. A feed, follow button and kudos are already present.

### Pilot

```text
Invite a friend to a four-week consistency block
 → each person selects their own realistic commitment
 → each keeps their own adaptive plan
 → optional weekly completion check-in
 → shared block-completion summary
```

A participant who trains twice a week and one who trains four times should not be ranked by raw workout count. Do not equate more weight, more sets or avoiding rest with better participation.

### Tasks

- [ ] Extend existing Crew membership/invites; avoid a parallel social graph.
- [ ] Store shared dates/theme plus separate personal commitments.
- [ ] Share only explicitly selected completion information.
- [ ] Reuse block/report/privacy controls; add block, leave and report flows where needed.
- [ ] Keep symptoms, body measurements, private preferences and recovery data private.
- [ ] Start with invite-only friends before any public matching system.
- [ ] Do not imply a human professional is monitoring the group when no such service exists.

**Acceptance:** joining a block does not overwrite either person's program, and leaving removes access to future shared activity. Pilot before building rich chat or a coach marketplace.

## 10. Not recommended for this phase

Keep exercise videos and form-video analysis out of scope, as requested. Do not rebuild already-reported features such as Focus Mode, memory, Gym Profiles, imported-history analysis or experiments.

Do not copy nutrition widgets, a broad social feed, a large coach marketplace or dozens of training styles simply for parity. Do not claim human coaching has been replaced by a personality setting. Do not add a free permanent product tier against your paid-product direction.

## 11. How this relates to ForgeCore

`FORGECORE_INTEGRATION.md` is infrastructure work only where an integration gap actually exists.

| New candidate | Existing-engine connection |
|---|---|
| Web plan preview | Supported starter template/configuration; final calibration in app. |
| Spoken Coach | Read committed prescription/decision events; no independent calculations. |
| Weekly brief | Read current goals/schedule/decisions; local private evidence. |
| Optional sessions | Typed Add/Replace intents; workload reconciliation. |
| External activity | Local context input with explicit provenance; no guessed physiology. |
| Shared block | Personal adherence summary; never share private engine evidence by default. |

## 12. Implementation checkpoint

Before coding, mark each candidate **exists**, **partial**, **not built**, or **out of scope** in the repository inventory. Link the actual implementation. A user's broad completion statement is not permission to ignore duplicates, and an old roadmap is not evidence of a missing feature.

The recommended next release is **accurate acquisition funnel + public plan preview + minimal spoken guidance**, with the weekly brief as a small extension when supported by current decision records. Test the result before adding the larger catalog, activity or community work.

## Sources

[L1] Ladder quiz and homepage, retrieved 20 September 2026. The interactive quiz questions were not available to inspect; goal/style matching is documented on the homepage.
`https://www.joinladder.com/quiz`
`https://www.joinladder.com/`

[L2] Ladder's Japan App Store listing and developer release notes, retrieved 20 September 2026. Source for Flex discovery and workout-data import; not an independent test of functionality.
`https://apps.apple.com/jp/app/ladder-strength-training-plans/id1502936453`

[L3] Ladder homepage, retrieved 20 September 2026. Source for weekly programming and spoken workout guidance.
`https://www.joinladder.com/`

[L4] Ladder pricing/features page, retrieved 20 September 2026. Source for Team Chat and music/coaching coexistence. No price recommendation is made in this document.
`https://www.joinladder.com/pricing`

[R1] Regulift landing page, retrieved 20 September 2026. Describes existing public capabilities and displays launch-free/coming-soon messages; not proof of internal implementation status.
`https://regulift.app/`

[R2] Supplied `OVERVIEW(1).md`, dated 17 September 2026, program templates at lines 18–24. Later implementation updates supersede the older feature baseline where explicitly reported.

[T1] Apple, archived Universal Links conceptual guide. Installed-app opening/browser fallback distinction only; use the current SDK for implementation.
`https://developer.apple.com/library/archive/documentation/General/Conceptual/AppSearch/UniversalLinks.html`

[T2] Apple, archived Responding to Interruptions guide. Audio lifecycle guidance only; use current API names and real-device testing.
`https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioInterruptions/HandlingAudioInterruptions.html`

---

**Bottom line:** take Ladder's clarity and guided experience. Add only the pieces that make Regulift easier to discover, easier to follow and easier to return to—not another long list of features it already has.
