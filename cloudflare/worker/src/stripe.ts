import Stripe from "stripe";
import type { Env } from "./env";

export function createStripeClient(env: Pick<Env, "STRIPE_SECRET_KEY">): Stripe {
  return new Stripe(env.STRIPE_SECRET_KEY, {
    appInfo: {
      name: "SlickShot Fulfillment Worker",
      version: "0.1.0",
    },
  });
}

export async function retrieveCheckoutSession(env: Pick<Env, "STRIPE_SECRET_KEY">, sessionId: string) {
  const stripe = createStripeClient(env);
  return stripe.checkout.sessions.retrieve(sessionId);
}

export async function constructWebhookEvent(
  env: Pick<Env, "STRIPE_SECRET_KEY" | "STRIPE_WEBHOOK_SECRET">,
  payload: string,
  signature: string
) {
  const stripe = createStripeClient(env);
  return stripe.webhooks.constructEventAsync(payload, signature, env.STRIPE_WEBHOOK_SECRET);
}
