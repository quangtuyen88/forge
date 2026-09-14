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

## Endpoints

- `POST /coach` — header `x-forge-secret`; body `{question, context, history?, coach?}` (`coach`: `Nova` default or `Kai`) → `{answer, refused, citations, provider}`
- `GET /health` — `{ok, providers, chunks}`

## Eval

`pnpm eval` — POSTs `eval/questions.json` to `COACH_URL` (default `http://localhost:8787`) with `APP_SECRET`; checks refusals, citations, and bracketed citations in answers. Exit 1 on any failure.

Tests: `pnpm build && pnpm test`
