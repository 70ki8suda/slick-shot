import type Stripe from "stripe";
import type { Env, PurchaseRecord } from "../env";
import { createDownloadToken } from "../tokens";
import { createSecureDownloadUrl } from "../downloads";
import {
  createDownloadTokenRecord,
  findPurchaseBySessionId,
  markPurchaseFulfilled,
  upsertPurchase,
} from "../db";
import { retrieveCheckoutSession } from "../stripe";
import { sendRedownloadEmail } from "../email";

export interface ConfirmCheckoutDependencies {
  getCheckoutSession: (sessionId: string) => Promise<Stripe.Checkout.Session>;
  findPurchaseBySessionId: (sessionId: string) => Promise<PurchaseRecord | null>;
  upsertPurchase: (
    input: Parameters<typeof upsertPurchase>[1]
  ) => Promise<PurchaseRecord>;
  createDownloadTokenRecord: (
    purchaseId: string,
    tokenHash: string,
    purpose: string,
    expiresAt: string
  ) => Promise<void>;
  markPurchaseFulfilled: (purchaseId: string) => Promise<void>;
  sendRedownloadEmail: (email: string, downloadUrl: string) => Promise<void>;
  buildDownloadUrl: (token: string) => string;
}

function defaultDependencies(env: Env): ConfirmCheckoutDependencies {
  return {
    getCheckoutSession: (sessionId) => retrieveCheckoutSession(env, sessionId),
    findPurchaseBySessionId: (sessionId) => findPurchaseBySessionId(env.DB, sessionId),
    upsertPurchase: (input) => upsertPurchase(env.DB, input),
    createDownloadTokenRecord: (purchaseId, tokenHash, purpose, expiresAt) =>
      createDownloadTokenRecord(env.DB, { purchaseId, tokenHash, purpose, expiresAt }).then(() => undefined),
    markPurchaseFulfilled: (purchaseId) => markPurchaseFulfilled(env.DB, purchaseId),
    sendRedownloadEmail: (email, downloadUrl) => sendRedownloadEmail(env, { to: email, downloadUrl }),
    buildDownloadUrl: (token) => createSecureDownloadUrl(env, token),
  };
}

export async function confirmCheckout(
  request: Request,
  env: Env,
  deps: ConfirmCheckoutDependencies = defaultDependencies(env)
): Promise<Response> {
  let sessionId = "";

  try {
    const body = (await request.json()) as { session_id?: string };
    sessionId = String(body.session_id ?? "").trim();
  } catch {
    return Response.json({ ok: false, error: "invalid-json" }, { status: 400 });
  }

  if (!sessionId) {
    return Response.json({ ok: false, error: "missing-session-id" }, { status: 400 });
  }

  const session = await deps.getCheckoutSession(sessionId);
  const email = session.customer_details?.email ?? session.customer_email ?? "";
  const paymentIntentId =
    typeof session.payment_intent === "string" ? session.payment_intent : session.payment_intent?.id ?? null;

  if (session.payment_status !== "paid" || !email) {
    return Response.json({ ok: false, error: "payment-not-complete" }, { status: 400 });
  }

  const existing = await deps.findPurchaseBySessionId(sessionId);
  const purchase = await deps.upsertPurchase({
    id: existing?.id,
    email,
    stripeSessionId: sessionId,
    stripePaymentIntentId: paymentIntentId,
    status: "paid",
    productSlug: "slickshot",
  });

  const immediate = await createDownloadToken(15 * 60);
  await deps.createDownloadTokenRecord(purchase.id, immediate.tokenHash, "instant", immediate.expiresAt);

  const immediateDownloadUrl = `${env.APP_URL}/download?token=${encodeURIComponent(immediate.token)}`;

  if (!purchase.fulfilled_at) {
    const emailToken = await createDownloadToken(24 * 60 * 60);
    await deps.createDownloadTokenRecord(purchase.id, emailToken.tokenHash, "email_redownload", emailToken.expiresAt);
    await deps.sendRedownloadEmail(email, `${env.APP_URL}/download?token=${encodeURIComponent(emailToken.token)}`);
    await deps.markPurchaseFulfilled(purchase.id);
  }

  return Response.json({
    ok: true,
    email,
    download_url: immediateDownloadUrl,
  });
}
