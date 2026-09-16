# RevenueCat setup (test environment)

Forge uses RevenueCat instead of raw StoreKit 2 (`App/Forge/Store.swift`). Without an API key the app runs in a **not-configured mode**: the paywall shows fallback prices, buying shows "Purchases are not configured in this build", and `load()`/`listen()` are no-ops. Nothing else is needed to build and run.

## One-time dashboard setup

1. Create a RevenueCat project, then add an **app** with bundle id `app.regulift` (App Store connect credentials later; the local `Forge/Forge.storekit` file works in the simulator).
2. Add products `app.regulift.monthly` and `app.regulift.annual` (subscription group "Forge Pro").
3. Create entitlement **`pro`** and attach both products.
4. Create offering **`default`** with a monthly and an annual package (any `$rc.monthly` / `$rc.annual` package types; the app matches by product identifier first, package type second).

## Keys

- Simulator/dev: put the **Test Store** API key (`test_…`) in `App/Secrets.local.xcconfig`:
  ```
  REVENUECAT_API_KEY = test_...
  ```
- TestFlight/production: the **Apple App Store** key in the same variable (set per-build via CI xcconfig). `Secrets.example.xcconfig` documents the placeholder.

## Webhook → Worker

In the RevenueCat dashboard (Project settings → Integrations → Webhooks):

- URL: `https://<worker>/billing/revenuecat`
- Authorization header: the Worker's `RC_WEBHOOK_SECRET` value (shared secret, verified server-side).
- Enable **"Sandbox" events** so test purchases forward too.

## App-side notes

- `Store.swift` configures `Purchases` once at init with `storeKitVersion: .storeKit2`.
- `logIn(userID:)` / `logOut()` sync RevenueCat identity with the app account; `setAttributes(referralCode:promoCode:)` forwards attribution keys `referral_code` / `promo_code`.
- `Purchases.logLevel = .debug` in DEBUG builds only.
