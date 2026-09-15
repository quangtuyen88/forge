# web — Forge landing page

Static site, no build step, no framework. Inter Tight loads from Google Fonts; colours follow the app's `Theme.swift` (`#3866D6` accent, `#F3F4F8`/`#0B0C10` page) with dark mode via `prefers-color-scheme`.

## Deploy

Cloudflare Pages:

- Project root: `web/`
- Build command: none
- Output directory: `/` (the root of `web/`)

Custom domain: `vnbnode.com/forge/` (the `/r/<code>` share links 302 to `https://vnbnode.com/forge/?ref=<code>`).

The waitlist form posts to `https://forge-coach.quangtuyen88.workers.dev/waitlist` (CORS-enabled, no secret). Share links point at `…/r/<code>` on the same Worker.

## Files

- `index.html` — landing (hero + waitlist, features, how it works, pricing, FAQ, footer)
- `privacy.html`, `terms.html` — legal drafts (**DRAFT — legal review**)
- `styles.css`, `app.js`
- `assets/` — app icon + coach hero art copied from `App/Forge/Assets.xcassets`
