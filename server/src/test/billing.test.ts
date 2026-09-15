import test from "node:test";
import assert from "node:assert/strict";
import { apiApp, call, login } from "./helpers.js";

const JUNE = Date.UTC(2025, 5, 15); // 2025-06-15

function rcEvent(type: string, over: Record<string, unknown> = {}) {
  return {
    event: {
      type,
      app_user_id: "",
      product_id: "forge.pro.annual",
      price: 59.99,
      currency: "USD",
      entitlement_ids: ["pro"],
      occurred_at: JUNE,
      ...over,
    },
  };
}

function billingApp() {
  const grants: string[] = [];
  const { app, queries } = apiApp({
    env: { ENV: "dev", RC_WEBHOOK_SECRET: "rc-wh", RC_SECRET_KEY: "rc-sk", ADMIN_SECRET: "admin-s" },
    rcGrant: async (uid) => { grants.push(uid); },
  });
  return { app, queries, grants };
}

type App = ReturnType<typeof import("../app.js").createApp>;

async function webhook(app: App, event: object, auth: string | null = "rc-wh") {
  return call(app, "POST", "/billing/revenuecat", { body: event, headers: auth ? { authorization: auth } : {} });
}

test("webhook with the wrong Authorization header returns 401", async () => {
  const { app } = billingApp();
  const { user } = await login(app, "buyer");
  assert.equal((await webhook(app, rcEvent("INITIAL_PURCHASE", { app_user_id: user.id }), "nope")).status, 401);
  assert.equal((await webhook(app, rcEvent("INITIAL_PURCHASE", { app_user_id: user.id }), null)).status, 401);
});

test("INITIAL_PURCHASE flips the tier to pro and logs the event", async () => {
  const { app } = billingApp();
  const { user, token } = await login(app, "buyer");
  const res = await webhook(app, rcEvent("INITIAL_PURCHASE", {
    app_user_id: user.id,
    subscriber_attributes: { promo_code: { value: "IRON8FUL" } },
  }));
  assert.equal(res.status, 200);
  assert.equal(((await res.json()) as { tier: string }).tier, "pro");
  assert.equal(((await (await call(app, "GET", "/me", { token })).json()) as { user: { tier: string } }).user.tier, "pro");
  const share = await call(app, "GET", "/admin/revshare?month=2025-06", { headers: { "x-forge-admin": "admin-s" } });
  const { codes } = await share.json() as { codes: { code: string; events: number; revenue: number }[] };
  assert.deepEqual(codes, [{ code: "IRON8FUL", subscribers: 1, events: 1, revenue: 59.99, share: 18 }]);
});

test("EXPIRATION flips the tier back to free", async () => {
  const { app } = billingApp();
  const { user } = await login(app, "buyer");
  await webhook(app, rcEvent("INITIAL_PURCHASE", { app_user_id: user.id }));
  const res = await webhook(app, rcEvent("EXPIRATION", { app_user_id: user.id }));
  assert.equal(((await res.json()) as { tier: string }).tier, "free");
});

test("CANCELLATION keeps pro until expiration_at_ms passes", async () => {
  const { app } = billingApp();
  const { user } = await login(app, "buyer");
  await webhook(app, rcEvent("INITIAL_PURCHASE", { app_user_id: user.id }));
  const future = await webhook(app, rcEvent("CANCELLATION", { app_user_id: user.id, expiration_at_ms: Date.now() + 86_400_000 }));
  assert.equal(((await future.json()) as { tier: string }).tier, "pro");
  const past = await webhook(app, rcEvent("CANCELLATION", { app_user_id: user.id, expiration_at_ms: Date.now() - 86_400_000 }));
  assert.equal(((await past.json()) as { tier: string }).tier, "free");
});

test("redeem: own code 409, unknown 404, then ok; twice 409", async () => {
  const { app } = billingApp();
  const a = await login(app, "referee");
  const b = await login(app, "referrer");
  assert.equal((await call(app, "POST", "/referral/redeem", { token: a.token, body: { code: a.user.referralCode } })).status, 409);
  assert.equal((await call(app, "POST", "/referral/redeem", { token: a.token, body: { code: "zzzzzzzz" } })).status, 404);
  assert.equal((await call(app, "POST", "/referral/redeem", { token: a.token, body: { code: b.user.referralCode } })).status, 200);
  assert.equal((await call(app, "POST", "/referral/redeem", { token: a.token, body: { code: b.user.referralCode } })).status, 409);
});

test("referee's first INITIAL_PURCHASE grants both users once and never again", async () => {
  const { app, queries, grants } = billingApp();
  const referee = await login(app, "referee");
  const referrer = await login(app, "referrer");
  await call(app, "POST", "/referral/redeem", { token: referee.token, body: { code: referrer.user.referralCode } });

  await webhook(app, rcEvent("INITIAL_PURCHASE", { app_user_id: referee.user.id }));
  assert.deepEqual(grants, [referee.user.id, referrer.user.id]);
  const ref = await call(app, "GET", "/referral", { token: referrer.token });
  assert.deepEqual(await ref.json(), { code: referrer.user.referralCode, referred: 1, rewarded: 1 });
  assert.notEqual((await queries.getReferralByReferee(referee.user.id))?.rewarded_at, null);

  await webhook(app, rcEvent("RENEWAL", { app_user_id: referee.user.id }));
  await webhook(app, rcEvent("INITIAL_PURCHASE", { app_user_id: referee.user.id }));
  assert.equal(grants.length, 2); // never rewarded twice
});

test("attribution: stored promo_code is used when the event has none", async () => {
  const { app } = billingApp();
  const u1 = await login(app, "p1");
  const u2 = await login(app, "p2");
  await call(app, "POST", "/attribution", { token: u1.token, body: { promoCode: "PROMO9" } });
  await call(app, "POST", "/attribution", { token: u2.token, body: { promoCode: "PROMO9" } });
  await webhook(app, rcEvent("INITIAL_PURCHASE", { app_user_id: u1.user.id, price: 59.99 }));
  await webhook(app, rcEvent("RENEWAL", { app_user_id: u2.user.id, price: 39.99 }));
  const res = await call(app, "GET", "/admin/revshare?month=2025-06", { headers: { "x-forge-admin": "admin-s" } });
  const { month, codes } = await res.json() as { month: string; codes: { code: string; subscribers: number; events: number; revenue: number; share: number }[] };
  assert.equal(month, "2025-06");
  assert.deepEqual(codes, [{ code: "PROMO9", subscribers: 2, events: 2, revenue: 99.98, share: 29.99 }]);
});

test("revshare rejects bad admin secret and bad month", async () => {
  const { app } = billingApp();
  await login(app, "x");
  assert.equal((await call(app, "GET", "/admin/revshare?month=2025-06", { headers: { "x-forge-admin": "wrong" } })).status, 401);
  assert.equal((await call(app, "GET", "/admin/revshare?month=junk", { headers: { "x-forge-admin": "admin-s" } })).status, 400);
});

test("webhook for an unknown subscriber is acked and ignored", async () => {
  const { app } = billingApp();
  const res = await webhook(app, rcEvent("INITIAL_PURCHASE", { app_user_id: "no-such-user" }));
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, ignored: true });
});
