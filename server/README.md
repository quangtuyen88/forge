# forge-server

Coach proxy: model access, RAG over `knowledge/`, medical guard. Same code on Node and Cloudflare Workers.

## Providers and fallback

`PROVIDER` is `workers-ai` (default on the Worker), `gemini`, or `claude`.
Requests try `PROVIDER` first, then the fallback chain `workers-ai → gemini → claude`, keeping only usable providers (Workers AI needs the `AI` binding; gemini/claude need their API keys). `/health` lists the chain; responses include the `provider` that answered.

## Node

    pnpm install && pnpm build
    APP_SECRET=... GEMINI_API_KEY=... pnpm start   # or PROVIDER=claude ANTHROPIC_API_KEY=...

## Worker deploy

    pnpm install && pnpm build && npx wrangler login
    npx wrangler secret put APP_SECRET   # plus GEMINI_API_KEY / ANTHROPIC_API_KEY if you want HTTP fallbacks
    pnpm deploy

Optional hybrid retrieval (default is local BM25):

    npx wrangler vectorize create forge-coach --dimensions=768 --metric=cosine
    # uncomment [[vectorize]] in wrangler.toml, pnpm deploy, then:
    curl -X POST https://forge-coach.<account>.workers.dev/admin/reindex -H "x-forge-secret: $APP_SECRET"

With `AI` + `VECTORS` bound, retrieval fuses BM25 and vector results (RRF); if the vector path fails it falls back to BM25.

## Accounts, sync, billing (D1)

Full request/response contract: [`API.md`](API.md). Storage is D1 (`DB` binding); without the binding the Worker falls back to in-memory Maps (dev only, resets per isolate) and Node `pnpm start` also uses memory queries.

Setup:

    npx wrangler d1 create forge            # paste database_id into wrangler.toml (REPLACE_ME)
    npx wrangler d1 migrations apply forge --remote
    npx wrangler secret put GOOGLE_CLIENT_ID      # Google OAuth client id (aud for /auth/google)
    npx wrangler secret put RESEND_API_KEY        # email sign-in codes (Apple: aud is app.regulift, no secret needed)
    npx wrangler secret put RC_WEBHOOK_SECRET     # RevenueCat webhook Authorization header value
    npx wrangler secret put RC_SECRET_KEY         # RevenueCat REST key (promotional referral grants)
    npx wrangler secret put ADMIN_SECRET          # x-forge-admin header for /admin/revshare

RevenueCat dashboard: webhook URL `https://forge-coach.<account>.workers.dev/billing/revenuecat`, Authorization header = `RC_WEBHOOK_SECRET`.

Endpoints (all JSON; app gate `x-forge-secret` except `/waitlist`, `/r/…`, `/billing/revenuecat`):

- `POST /auth/apple|/auth/google|/auth/email/start|/auth/email/verify|/auth/logout`, `GET /me`, `DELETE /me` — Bearer sessions (32-byte base64url token, SHA-256 stored, 180-day sliding expiry).
- `POST /sync` — LWW record sync (`profile|session|checkin|measurement|nutrition`, ≤ 500 changes, data ≤ 64 KB); response = changes with `seq > cursor` not accepted from this request.
- `POST /billing/revenuecat` — tier mapping (pro while the `pro` entitlement is active), subscription event log, referral rewards (give a month / get a month via RevenueCat promotional grants, once).
- `GET /referral`, `POST /referral/redeem`, `POST /attribution`, `GET /admin/revshare?month=YYYY-MM` (revenue = INITIAL_PURCHASE + RENEWAL per promo code, share = 30%).
- `/coach` now accepts an optional Bearer: free 5 / pro 60 questions per UTC day (`429` over; anonymous requests keep the IP limiter only).

## Social

All `POST`/`GET` under `/social/` require a Bearer session (`API.md` → Social).

- `GET/PUT /social/profile` — handle `[a-z0-9_]{3,20}` (input lowercased; uniqueness → `409 Handle taken`), displayName 1–40, bio ≤ 160.
- `GET /social/users/:handle` — public profile + `stats: { sessions (all-time session posts), streakWeeks (consecutive ISO weeks with a session in the last 12), topPRs: top 3 PR payloads by e1rm }` + `following`.
- `POST/DELETE /social/follow/:userId` — self-follow 400, idempotent.
- `GET /social/feed?cursor=<createdAt>` — newest-first posts from followed users + self, 30 per page, `nextCursor`; items carry author, `kudos`, `kudoed`, `comments` counts.
- `POST /social/posts` — `{ type: "session"|"pr", payload }` (payload ≤ 8 KB).
- `POST/DELETE /social/posts/:id/kudos` — idempotent; `GET/POST /social/posts/:id/comments` (`text` 1–500, oldest first, 100).
- `GET /social/leaderboard?week=YYYY-Www` (default current ISO week) — self + followed, `sessions` count and `tonnageKg` sum (`payload.tonnageKg`) for the week, sorted sessions desc then tonnage desc.

Moderation: comments and posts are plain text only (no media, no links rendering); nothing is auto-moderated yet.

## Rate limiting

Rate limiting: 20 questions per minute per IP via the `COACH_LIMIT` binding (`[[ratelimits]]` in `wrangler.toml`); over-limit requests get `429`.

The iOS app now ships the secret at build time (`App/Secrets.local.xcconfig`).

## Waitlist

Public (no secret) landing-page endpoints:

- `POST /waitlist` — CORS-enabled (`*`, preflight `OPTIONS` handled); body `{email, ref?}` (email ≤ 120 chars, regex-validated) → `{ok, code}`. `code` = first 8 hex chars of `SHA-256(email + APP_SECRET)` — the submitter's permanent share code. Rate-limited by IP like `/coach`; each signup is stored in `forge_events` (`name` `waitlist`, blobs `[waitlist, email, ref]`).
- `GET /r/<code>` — 302 → `https://regulift.app/?ref=<code>` (share links for "Give a month, get a month").

Referral accounting lives in the Analytics Engine data (`ref` blob on `waitlist` events); there is no separate referral store.

## Endpoints

- `POST /coach` — header `x-forge-secret`; body `{question, context, history?, coach?}` (`coach`: `Nova` default or `Kai`) → `{answer, refused, citations, provider, action}`. `action` is `null` or `{type:"swap",from,to}` / `{type:"earlyDeload"}` / `{type:"restartBlock"}`, parsed from a trailing `ACTION {...}` line the model may emit for swap / early-deload / missed-week requests.
- `GET /health` — `{ok, providers, chunks}`
- `POST /events` — header `x-forge-secret`; body `{device, events: [{name, ts, props?}]}` (max 50, names `[a-z_]{1,40}`) → `{ok, accepted}`. Writes one Analytics Engine data point per valid event.
- `GET /config?device=<id>` — header `x-forge-secret` → `{paywall: {variant, headline, subline, annualBadge}}`. Variant is a deterministic 50/50 split (`fnv1a(device) % 2`, exported `assignVariant`); A = current copy, B = alternate.
- `POST /feedback` — header `x-forge-secret`; body `{device, text (≤2000), screen?}` → `{ok}`. Stored in the same dataset as a `feedback` data point; rate-limited like `/coach`.

Events and feedback are stored in the Analytics Engine dataset bound as `EVENTS` (`forge_events`) via `[[analytics_engine_datasets]]` in `wrangler.toml`; query it with `npx wrangler analytics-engine dataset forge_events`. Without the binding, events are logged instead.

## Eval

`pnpm eval` — POSTs `eval/questions.json` to `COACH_URL` (default `http://localhost:8787`) with `APP_SECRET`; checks refusals, citations, and bracketed citations in answers. Exit 1 on any failure.

Tests: `pnpm build && pnpm test`
