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

## Rate limiting

Rate limiting: 20 questions per minute per IP via the `COACH_LIMIT` binding (`[[ratelimits]]` in `wrangler.toml`); over-limit requests get `429`.

The iOS app now ships the secret at build time (`App/Secrets.local.xcconfig`).

## Waitlist

Public (no secret) landing-page endpoints:

- `POST /waitlist` — CORS-enabled (`*`, preflight `OPTIONS` handled); body `{email, ref?}` (email ≤ 120 chars, regex-validated) → `{ok, code}`. `code` = first 8 hex chars of `SHA-256(email + APP_SECRET)` — the submitter's permanent share code. Rate-limited by IP like `/coach`; each signup is stored in `forge_events` (`name` `waitlist`, blobs `[waitlist, email, ref]`).
- `GET /r/<code>` — 302 → `https://vnbnode.com/forge/?ref=<code>` (share links for "Give a month, get a month").

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
