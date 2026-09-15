import type { Queries, Tier, UserRow } from "./queries.js";
import { json } from "./http.js";

export interface BillingEnv {
  RC_WEBHOOK_SECRET?: string;
  RC_SECRET_KEY?: string;
  ADMIN_SECRET?: string;
  ENV?: string;
}
export interface BillingCtx {
  queries: Queries;
  env?: BillingEnv;
  now?: () => Date;
  rcGrant?: (appUserId: string) => Promise<void>;
}

/** Grants 30 days of `pro` via the RevenueCat REST API (injectable for tests). */
export async function rcGrantLive(appUserId: string, rcSecretKey: string): Promise<void> {
  const res = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}/entitlements/pro/promotional`, {
    method: "POST",
    headers: { authorization: `Bearer ${rcSecretKey}`, "content-type": "application/json", "x-platform": "ios" },
    body: JSON.stringify({ duration: "monthly" }),
  });
  if (!res.ok) throw new Error(`revenuecat grant failed: ${res.status}`);
}

/** RevenueCat tier mapping: pro while the entitlement is active, else free. */
function tierFor(type: string, entitlements: string[], expirationAtMs: number | null, nowMs: number): Tier {
  if (!entitlements.includes("pro")) return "free";
  if (type === "EXPIRATION") return "free";
  if (type === "CANCELLATION" && expirationAtMs !== null && expirationAtMs < nowMs) return "free";
  return "pro";
}

export async function revenuecatWebhook(ctx: BillingCtx, authorization: string | null, body: unknown): Promise<Response> {
  if (!ctx.env?.RC_WEBHOOK_SECRET || authorization !== ctx.env.RC_WEBHOOK_SECRET) {
    return json(401, { error: "unauthorized" });
  }
  const event = (body as { event?: unknown } | null)?.event;
  if (!event || typeof event !== "object") return json(400, { error: "missing event" });
  const e = event as Record<string, unknown>;
  const now = ctx.now?.() ?? new Date();
  const userId = typeof e.app_user_id === "string" ? e.app_user_id : "";
  const user = userId ? await ctx.queries.getUserById(userId) : null;
  if (!user) return json(200, { ok: true, ignored: true }); // unknown subscriber: ack so RC stops retrying

  const type = typeof e.type === "string" ? e.type : "";
  const entitlements = Array.isArray(e.entitlement_ids)
    ? e.entitlement_ids.filter((x): x is string => typeof x === "string")
    : typeof e.entitlement_id === "string" ? [e.entitlement_id] : [];
  const expMs = typeof e.expiration_at_ms === "number" ? e.expiration_at_ms : null;
  const tier = tierFor(type, entitlements, expMs, now.getTime());
  await ctx.queries.setTier(user.id, tier);

  const attrs = e.subscriber_attributes as Record<string, { value?: unknown }> | undefined;
  const promo = attrs?.promo_code && typeof attrs.promo_code.value === "string" ? attrs.promo_code.value : user.promo_code;
  const occurredAt = typeof e.occurred_at === "number" ? new Date(e.occurred_at).toISOString()
    : typeof e.occurred_at === "string" ? e.occurred_at
    : now.toISOString();
  await ctx.queries.insertSubscriptionEvent({
    user_id: user.id,
    event: type,
    product_id: typeof e.product_id === "string" ? e.product_id : null,
    price: typeof e.price === "number" ? e.price : null,
    currency: typeof e.currency === "string" ? e.currency : null,
    promo_code: promo ?? null,
    occurred_at: occurredAt,
    raw: JSON.stringify(e),
  });

  // Referral reward: referee's first INITIAL_PURCHASE with a redeemed referral — never twice.
  if (type === "INITIAL_PURCHASE" && user.referred_by) {
    const referral = await ctx.queries.getReferralByReferee(user.id);
    if (referral && !referral.rewarded_at) {
      const grant = ctx.rcGrant ?? ((uid: string) => rcGrantLive(uid, ctx.env?.RC_SECRET_KEY ?? ""));
      await grant(user.id);
      await grant(user.referred_by);
      await ctx.queries.markReferralRewarded(user.id, now.toISOString());
    }
  }
  return json(200, { ok: true, tier });
}

export async function referralRedeem(queries: Queries, user: UserRow, code: unknown): Promise<Response> {
  if (typeof code !== "string" || !code.trim() || code.length > 64) return json(400, { error: "code required" });
  const trimmed = code.trim();
  if (trimmed === user.referral_code) return json(409, { error: "cannot redeem your own code" });
  if (user.referred_by) return json(409, { error: "referral already redeemed" });
  const referrer = await queries.getUserByReferralCode(trimmed);
  if (!referrer) return json(404, { error: "code not found" });
  await queries.setReferredBy(user.id, referrer.id);
  await queries.insertReferral(user.id, referrer.id, new Date().toISOString());
  return json(200, { ok: true });
}

const MONTH_RE = /^\d{4}-(0[1-9]|1[0-2])$/;

export async function revshare(
  queries: Queries,
  adminSecret: string | undefined,
  adminHeader: string | null,
  month: string | null,
): Promise<Response> {
  if (!adminSecret || adminHeader !== adminSecret) return json(401, { error: "unauthorized" });
  if (!month || !MONTH_RE.test(month)) return json(400, { error: "month must be YYYY-MM" });
  const codes = await queries.revshareByCode(month);
  return json(200, { month, codes: codes.map((c) => ({ ...c, share: Math.round(c.revenue * 30) / 100 })) });
}
