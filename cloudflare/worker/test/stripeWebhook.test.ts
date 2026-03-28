import { describe, expect, it, vi } from "vitest";
import { stripeWebhook } from "../src/handlers/stripeWebhook";

describe("stripeWebhook", () => {
  it("persists checkout.session.completed", async () => {
    const upsertPurchase = vi.fn(async () => ({ id: "purchase-1" }) as never);

    const response = await stripeWebhook(
      new Request("https://slick-shot.com/api/stripe/webhook", {
        method: "POST",
        headers: { "stripe-signature": "sig" },
        body: "{}",
      }),
      {} as never,
      {
        verifyEvent: async () =>
          ({
            type: "checkout.session.completed",
            data: {
              object: {
                id: "cs_test_123",
                payment_status: "paid",
                customer_details: { email: "buyer@example.com" },
                payment_intent: "pi_test_123",
              },
            },
          }) as never,
        upsertPurchase,
        findPurchaseByPaymentIntentId: async () => null,
        markPurchaseRefunded: async () => undefined,
      }
    );

    expect(response.status).toBe(200);
    expect(upsertPurchase).toHaveBeenCalledOnce();
  });

  it("marks refunded purchases", async () => {
    const markPurchaseRefunded = vi.fn(async () => undefined);
    const response = await stripeWebhook(
      new Request("https://slick-shot.com/api/stripe/webhook", {
        method: "POST",
        headers: { "stripe-signature": "sig" },
        body: "{}",
      }),
      {} as never,
      {
        verifyEvent: async () =>
          ({
            type: "charge.refunded",
            data: {
              object: {
                payment_intent: "pi_test_123",
              },
            },
          }) as never,
        upsertPurchase: async () => ({ id: "purchase-1" }) as never,
        findPurchaseByPaymentIntentId: async () => ({ id: "purchase-1", status: "paid" }) as never,
        markPurchaseRefunded,
      }
    );

    expect(response.status).toBe(200);
    expect(markPurchaseRefunded).toHaveBeenCalledWith("purchase-1");
  });
});
