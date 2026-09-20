# web — Forge landing page

Static site, no build step, no framework. Inter Tight loads from Google Fonts. Dark UI (default `color-scheme: dark`) uses lime `#B4FF00` as the accent, matching the app's neon-green workout accents (`Theme.swift` accent is `#00F076` dark / `#1E7D32` light).

## Deploy

Cloudflare Pages:

- Project root: `web/`
- Build command: none
- Output directory: `/` (the root of `web/`)

Custom domain: `regulift.app` (Workers custom domain in `wrangler.toml`; share links 302 to `https://regulift.app/?ref=<code>`).

The waitlist form posts to `https://forge-coach.quangtuyen88.workers.dev/waitlist` (CORS-enabled, no secret) with `{ email, ref? }` and returns `{ ok, code }` (an 8-hex referral code). Share links point at `…/r/<code>` on the same Worker, which 302s to `?ref=<code>`; `app.js` captures `?ref=` and re-attaches it to the waitlist POST.

## Find my plan

`index.html#find-plan` is a dependency-free quiz (goal → days per week → session length → equipment → experience). Options mirror `ForgeCore/Sources/ForgeCore/Program.swift` (3–6 day splits, 45/60/90 min sessions) and `App/Forge/OnboardingView.swift` (`Goal`, `Experience`, `GymPreset`). The preview is a **reviewed, versioned static starter template** keyed by those answers — it never computes loads, and it is labelled "Starter structure — calibrated in the app."

- Answers persist to `localStorage` under `regulift.plan.v1` (non-sensitive only).
- A versioned opaque plan code (`RP1-<base36>`) can be copied and restored; it encodes only the five answers.
- No account, birthday, injury, payment or personal data is collected for the preview, and nothing is written to the URL or analytics.

## Files

- `index.html` — landing (hero + find-my-plan + waitlist, features, how it works, pricing, FAQ, footer)
- `privacy.html`, `terms.html` — legal drafts (**DRAFT — legal review**)
- `styles.css`, `app.js`
- `assets/` — app icon + coach hero art copied from `App/Forge/Assets.xcassets`
