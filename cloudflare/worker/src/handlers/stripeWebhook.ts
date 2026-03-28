import type Stripe from "stripe";
import type { Env, PurchaseRecord } from "../env";
import { findPurchaseByPaymentIntentId, markPurchaseRefunded, upsertPurchase } from "../db";
import { constructWebhookEvent } from "../stripe";

export interface StripeWebhookDependencies {
  verifyEvent: (payload: string, signature: string) => Promise<Stripe.Event>;
  upsertPurchase: (
    input: Parameters<typeof upsertPurchase>[1]
  ) => Promise<PurchaseRecord>;
  findPurchaseByPaymentIntentId: (paymentIntentId: string) => Promise<PurchaseRecord | null>;
  markPurchaseRefunded: (purchaseId: string) => Promise<void>;
}

function defaultDependencies(env: Env): StripeWebhookDependencies {
  return {
    verifyEvent: (payload, signature) => constructWebhookEvent(env, payload, signature),
    upsertPurchase: (input) => upsertPurchase(env.DB, input),
    findPurchaseByPaymentIntentId: (paymentIntentId) => findPurchaseByPaymentIntentId(env.DB, paymentIntentId),
    markPurchaseRefunded: (purchaseId) => markPurchaseRefunded(env.DB, purchaseId),
  };
}

export async function stripeWebhook(
  request: Request,
  env: Env,
  deps: StripeWebhookDependencies = defaultDependencies(env)
): Promise<Response> {
  const signature = request.headers.get("stripe-signature");
  if (!signature) {
    return new Response("Missing stripe-signature", { status: 400 });
  }

  const payload = await request.text();
  const event = await deps.verifyEvent(payload, signature);

  if (event.type === "checkout.session.completed") {
    const session = event.data.object as Stripe.Checkout.Session;
    const email = session.customer_details?.email ?? session.customer_email;
    if (email && session.id) {
      await deps.upsertPurchase({
        email,
        stripeSessionId: session.id,
        stripePaymentIntentId:
          typeof session.payment_intent === "string" ? session.payment_intent : session.payment_intent?.id ?? null,
        status: session.payment_status === "paid" ? "paid" : "pending",
        productSlug: "slickshot",
      });
    }
    return Response.json({ ok: true });
  }

  if (event.type === "charge.refunded" || event.type === "charge.refund.updated") {
    const charge = event.data.object as Stripe.Charge;
    const paymentIntentId = typeof charge.payment_intent === "string" ? charge.payment_intent : charge.payment_intent?.id;
    if (paymentIntentId) {
      const purchase = await deps.findPurchaseByPaymentIntentId(paymentIntentId);
      if (purchase && purchase.status !== "refunded") {
        await deps.markPurchaseRefunded(purchase.id);
      }
    }
    return Response.json({ ok: true });
  }

  return Response.json({ ok: true, ignored: true });
}
