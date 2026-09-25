# iOS end-to-end tests

## Requirements

Requirements: Xcode with an available iOS Simulator runtime and [Maestro](https://maestro.mobile.dev/) on `PATH`.

## Full app regression

```sh
pnpm --dir server run test:app:e2e
```

The same suite is available through `make test-app-e2e`. It builds once, creates a fresh simulator, and runs `.maestro/01-*.yaml` through `.maestro/17-*.yaml` sequentially so each flow validates the state produced by the previous flow. Coverage includes onboarding, check-in, workout logging and resume, voice controls, workout tools, progress reports, nutrition CRUD, Crew/account entry, settings persistence, custom exercises, measurements, theme/unit changes, an on-device Coach prompt-attack refusal, the six-week program roadmap, muscle-emphasis drill-down, daily fuel guidance, and the Progress Journey timeline. Normal Coach composition is exercised without sending a request to the external coach service.

## Journey timeline (`17-journey.yaml`)

Run the Journey flow independently on a fresh, debug-seeded simulator:

```sh
make test-journey-e2e
```

The dedicated runner builds the app, creates a fresh simulator, seeds deterministic local training history with `--seed-demo`, and runs only `.maestro/17-journey.yaml`. The full stateful suite also runs this flow after the earlier feature flows. Every assertion is required; the flow contains no `optional: true`.

1. Progress is titled `My Progress` with a reachable `Settings` control; Overview stays the default segment, and the Photos tool row states the concealed photo state (`Private progress photos`).
2. `Timeline` exposes the dynamic month chooser, filter chip (`All`), `Add note`, a locale-aware day heading, and the explicit `View workout` source action.
3. A visible progress-photo card, when seeded, stays concealed (`private, not revealed` · `View privately`) until an explicit one-time reveal.
4. One workout card opens the canonical `SessionDetailView`; a set is edited in place, the same card remains unique after a cold relaunch, and the same source still opens.
5. A private note is saved, survives a cold relaunch, and remains available without a network request.
6. Hiding and restoring a workout changes only timeline visibility; the canonical workout still opens with its sets and tonnage.
7. The dynamic month chooser is opened without fixed calendar labels. Filtering to `Workouts` hides the note; resetting to `All` restores it.

Largest supported text is exercised separately: set `xcrun simctl ui <udid> content_size accessibility-extra-extra-large`, open the timeline, and confirm the date rail collapses to full-width headings while the source action keeps non-zero bounds and still opens the workout detail.

Manual-only: the post-session `View in timeline` handoff, exact scroll-anchor restoration across tabs, and VoiceOver double-tap activation (Maestro drives the accessibility proxy, not VoiceOver itself).

## Adapters intentionally disabled in v1

The Journey timeline is a local projection of records the app already keeps, and the app is explicit about the integration points it does *not* have — the UI states each one instead of leaving a gap that reads as “nothing found”:

- **Health / HealthKit** — no import adapter. The timeline projects only what was recorded in the app.
- **Photos and image bytes** — a photo entry never loads image bytes. A reveal is in-memory on this device, is cleared when the app backgrounds or the owner changes, defaults off (`Show photo details`), and only ever opens the existing `ProgressPhotosView`.
- **Cloud sync** — `JourneyReflection`, `JourneyVisibilityOverride` and `JourneyPrivateProfile` are deliberately absent from `SyncEngine`'s allowlist. Notes, hides and the private profile never leave the device.
- **Server fetch** — nothing is requested to draw the timeline; the month, the filter and the page come from the local store.
- **Generated content** — no detected milestones, no written monthly review, no inferred PRs and no advice about results beyond the existing charts. The `Not in this timeline` card lists exactly these.
- **Public sharing** — notes and body entries are never posted, shared or published, and there is no export or share token for them.
- **Extra navigation** — the timeline is a segment inside the existing Progress tab, never a second tab or a parallel history. Hiding an entry is display-only: the record behind it stays in History, Body stats and Photos, and `View in timeline` after a saved session writes only the remembered segment.

## Full feature video

```sh
make record-app-tour
```

This builds a fresh simulator app, records one H.264 video while the complete stateful Maestro tour runs, and writes `artifacts/regulift-full-feature-tour.mp4`. Override the destination with `OUTPUT=/path/tour.mp4`.

## Onboarding and profile only

```sh
pnpm --dir server run test:onboarding:e2e
```

The same flow is also available through `make test-onboarding-e2e`.

The command builds the Debug simulator app, creates a fresh iPhone simulator, completes all eight onboarding steps, verifies the generated plan and debug paywall transition, edits the training profile, then relaunches Settings to verify persistence. The fresh simulator is shut down but retained; its UDID is printed for inspection.

Build only:

```sh
make build-ios
```

## 18-coach-clarify

Covers the two things this release changed in the conversation and in Settings:

- a question that already says "body weight" is answered, not met with
  "body weight or the load for an exercise?";
- the offline-voice rows exist and the toggle stays disabled until the Whisper model is
  really on disk (`settings.voice.offline`, `settings.voice.download`).

Voice flows always run on the OS recognizer: `VoicePipelineFactory` skips WhisperKit when the
app is launched with `--os-speech-only`, so no test depends on a 150 MB model download.

## Coach voice mode

`make test-coach-e2e` covers the Coach chat actions, voice mode driven by a scripted speaker,
and the microphone-off state. The DEBUG launch arguments are `-coachVoiceScript "<sentence>"`
(voice mode hears that sentence word by word instead of the microphone) and
`-voiceUnavailable YES` (voice mode opens into the microphone-off failure). Set `ONLY_VOICE=1`
to run only the voice flows; screenshots land in `artifacts/coach-e2e/<timestamp>/`.

## Share Cards v2 (inside 03-logger)

The composer is exercised where a real saved session exists, at the end of the logger flow:
`summary.shareCard` opens it, `share.preview` / `share.format` / `share.detail.rpe` /
`share.export` prove the surface, and `share.close` returns to the summary with the workout
still saved. Sharing is never on the path to finishing a workout, so the flow ends on
**Done** exactly as it did before.
