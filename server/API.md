# Forge backend API contract v1 (Cloudflare Worker + D1)

Base URL: the coach Worker (`Theme.coachServer`). Every request carries `x-forge-secret: <APP_SECRET>` (app gate, existing). Authenticated endpoints also carry `Authorization: Bearer <session token>`. JSON in and out. Errors: `{ "error": "<message>" }` with 400/401/403/404/409/429/500.

## Auth
- `POST /auth/apple` `{ identityToken, fullName? }` → `{ token, user }`. Verifies the Apple identity token (JWKS `https://appleid.apple.com/auth/keys`, aud = `com.vnbnode.forge`, iss = `https://appleid.apple.com`), upserts the user by `apple_sub`.
- `POST /auth/google` `{ idToken }` → `{ token, user }`. Verifies against `https://www.googleapis.com/oauth2/v3/certs`, aud = `env.GOOGLE_CLIENT_ID`, upserts by `google_sub`.
- `POST /auth/email/start` `{ email }` → `{ ok: true, devCode? }`. Stores a 6-digit code (hashed, 10 min). Sends it with Resend when `env.RESEND_API_KEY` is set, otherwise returns `devCode` (dev only; never when `env.ENV === "production"`).
- `POST /auth/email/verify` `{ email, code }` → `{ token, user }`.
- `POST /auth/logout` (Bearer) → `{ ok: true }`.
- `GET /me` (Bearer) → `{ user }`.
- `DELETE /me` (Bearer) → `{ ok: true }` deletes the user and every row that references it.

`user` = `{ id, email?, tier: "free" | "pro", referralCode, handle? }`. Session token: 32 random bytes base64url; stored as SHA-256 hash; 180-day expiry sliding on use.

## Sync (Bearer)
- `POST /sync` `{ cursor: number, changes: Change[] }` → `{ cursor: number, changes: Change[], serverTime: string }`.
- `Change = { type: "profile" | "session" | "checkin" | "measurement" | "nutrition", id: string, updatedAt: string (ISO 8601), deleted?: boolean, data: object }`.
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
