# Forge backend API contract v1 (Cloudflare Worker + D1)

Base URL: the coach Worker (`Theme.coachServer`). Every request carries `x-forge-secret: <APP_SECRET>` (app gate, existing). Authenticated endpoints also carry `Authorization: Bearer <session token>`. JSON in and out. Errors: `{ "error": "<message>" }` with 400/401/403/404/409/429/500.

## Auth
- `POST /auth/apple` `{ identityToken, fullName? }` → `{ token, user }`. Verifies the Apple identity token (JWKS `https://appleid.apple.com/auth/keys`, aud = `app.regulift`, iss = `https://appleid.apple.com`), upserts the user by `apple_sub`.
- `POST /auth/google` `{ idToken }` → `{ token, user }`. Verifies against `https://www.googleapis.com/oauth2/v3/certs`, aud = `env.GOOGLE_CLIENT_ID`, upserts by `google_sub`.
- `POST /auth/email/start` `{ email }` → `{ ok: true, devCode? }`. Stores a 6-digit code (hashed, 10 min). Sends it with Resend when `env.RESEND_API_KEY` is set, otherwise returns `devCode` (dev only; never when `env.ENV === "production"`).
- `POST /auth/email/verify` `{ email, code }` → `{ token, user }`.
- `POST /auth/logout` (Bearer) → `{ ok: true }`.
- `GET /me` (Bearer) → `{ user }`.
- `DELETE /me` (Bearer) → `{ ok: true }` deletes the user and every row that references it.

`user` = `{ id, email?, tier: "free" | "pro", referralCode, handle? }`. Session token: 32 random bytes base64url; stored as SHA-256 hash; 180-day expiry sliding on use.

## Sync (Bearer)
- `POST /sync` `{ cursor: number, changes: Change[] }` → `{ cursor: number, changes: Change[], serverTime: string }`.
- `Change = { type: "profile" | "session" | "checkin" | "measurement" | "nutrition" | "exercise", id: string, updatedAt: string (ISO 8601), deleted?: boolean, data: object }`.
- Server rule: last-writer-wins per `(type, id)` by `updatedAt`; every accepted write gets a new `seq`; the response returns rows with `seq > cursor` that were not in the request, and `cursor` = max seq. Max 500 changes per request; `data` ≤ 64 KB.

## Billing (RevenueCat)
- `POST /billing/revenuecat` — RevenueCat webhook. `Authorization` header must equal `env.RC_WEBHOOK_SECRET`. Handles `INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `EXPIRATION`, `BILLING_ISSUE`, `PRODUCT_CHANGE`, `TEST`: maps `app_user_id` (our user id) → `tier` (`pro` while an entitlement is active, else `free`), appends to `subscription_events` (event, product_id, price, currency, promo_code from subscriber attributes, occurred_at). On the first `INITIAL_PURCHASE` (or trial start) of a user with `referred_by`, grants the referrer 30 days of `pro` via RevenueCat's REST API `POST https://api.revenuecat.com/v1/subscribers/{app_user_id}/entitlements/pro/promotional { duration: "monthly" }` with `env.RC_SECRET_KEY`, and the referee too (give a month / get a month); records `referrals.rewarded_at`.
- `GET /referral` (Bearer) → `{ code, referred: number, rewarded: number }`.
- `POST /referral/redeem` (Bearer) `{ code }` → `{ ok: true }`; 409 if already redeemed or own code.
- `POST /attribution` (Bearer) `{ promoCode }` → `{ ok: true }` (stored on the user; also set as a RevenueCat subscriber attribute by the app).
- `GET /admin/revshare?month=YYYY-MM` (`x-forge-admin: env.ADMIN_SECRET`) → `{ month, codes: [{ code, subscribers, events, revenue, share }] }` with `share = revenue * 0.30`.

## Coach limits
- `/coach` accepts an optional Bearer. Per-user daily cap: free 5, pro 60 (`coach_usage`), 429 `{ error: "Daily coach limit reached. Upgrade for more." }`. The IP limiter stays.

## Social (Bearer) — wave 5
- `GET /social/profile` / `PUT /social/profile` `{ handle, displayName, bio }` (handle: `[a-z0-9_]{3,20}`, unique).
- `GET /social/users/:handle` → public profile + stats (sessions, streak, top 3 PRs) + `following: bool`.
- `POST /social/follow/:userId`, `DELETE /social/follow/:userId`.
- `GET /social/feed?cursor=` → posts from followed users and self, newest first, 30 per page.
- `POST /social/posts` `{ type: "session" | "pr", payload }` → `{ post }`.
- `POST /social/posts/:id/kudos`, `DELETE /social/posts/:id/kudos`, `GET/POST /social/posts/:id/comments` `{ text }` (≤ 500 chars).
- `GET /social/leaderboard?week=YYYY-Www` → `[{ userId, handle, sessions, tonnageKg }]` for self + followed.
- `GET /social/crew?week=YYYY-Www` → crew week view for self + the first 50 followed users (a legacy self-follow row is ignored): `{ week, weekStart, members, streakWeeks, records, lifts }`. `week` defaults to the current ISO week; malformed → 400. Week placement uses each post's local date (`payload.localDate` when `YYYY-MM-DD`, else the UTC date of `created_at`). `members[i] = { userId, handle|null, displayName|null, isSelf, target, days, sessions }` — self first, then followed sorted by displayName (case-insensitive); `target` = the most recent session `weekTarget` rounded and clamped to 1-7 (default 3). `records` = pr posts with an `e1rm` in (0, 1000] whose local date is inside the week, newest first, with viewer-aware `kudos`/`kudoed`; `weightKg`/`reps` are kept only inside the bounds (weight in (0, 1000], reps an integer 1-100). `lifts` = per exercise id, per followed user (never self): the last 12 points of the 16 weeks ending on the week's Sunday, `deltas` relative to the first kept point (1 decimal), `changeKg`, `record`, `lastDate`; every point's e1rm is bounded to (0, 1000] so all emitted numbers are finite. `streakWeeks` = consecutive weeks (max 26) in which ≥ 2 members were active and every one trained; a member counts for a week from their first session post ever (MIN `created_at` over all their session posts), not just the loaded 26-week window. pr posts are fetched from SQL only within the requested week's bounds.
- `GET /c/:handle` — public invite page (no auth, no app secret, no DB read). The path is lowercased; the handle must match `[a-z0-9_]{3,20}` else 404. Returns inert HTML titled "Train with @<handle> on Regulift" linking `regulift://crew/<handle>` ("Open in Regulift") and `https://regulift.app` ("Get Regulift").
- New post payload fields (optional; older posts keep working — UTC-date fallback, default target 3): `session` adds `localDate` ("YYYY-MM-DD"), `weekTarget` (finite number) and `lifts: { "<exerciseId>": e1rm }` — an object map, one entry per exercise (the earlier array form `[{ id, e1rm }]` is still accepted); `pr` adds `exerciseId`, `weightKg`, `reps` and `localDate`. Value bounds, enforced by the server (anything outside is ignored, never an error): `e1rm`/`weightKg` finite in (0, 1000]; `reps` an integer 1-100; `weekTarget` finite.
