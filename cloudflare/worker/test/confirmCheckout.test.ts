import { describe, expect, it, vi } from "vitest";
import { confirmCheckout } from "../src/handlers/confirmCheckout";

describe("confirmCheckout", () => {
  it("confirms paid session and returns a download page url", async () => {
    const sendRedownloadEmail = vi.fn(async () => undefined);
    const markPurchaseFulfilled = vi.fn(async () => undefined);
    const response = await confirmCheckout(
      new Request("https://slick-shot.com/api/checkout/confirm", {
        method: "POST",
        body: JSON.stringify({ session_id: "cs_test_123" }),
      }),
      {
        APP_URL: "https://slick-shot.com",
      } as never,
      {
        getCheckoutSession: async () =>
          ({
            id: "cs_test_123",
            payment_status: "paid",
            customer_details: { email: "buyer@example.com" },
            payment_intent: "pi_test_123",
          }) as never,
        findPurchaseBySessionId: async () => null,
        upsertPurchase: async () =>
          ({
            id: "purchase-1",
            fulfilled_at: null,
          }) as never,
        createDownloadTokenRecord: async () => undefined,
        markPurchaseFulfilled,
        sendRedownloadEmail,
        buildDownloadUrl: (token) => `https://slick-shot.com/download?token=${token}`,
      }
    );

    const body = await response.json();
    expect(response.status).toBe(200);
    expect(body.ok).toBe(true);
    expect(body.download_url).toContain("/download?token=");
    expect(sendRedownloadEmail).toHaveBeenCalledOnce();
    expect(markPurchaseFulfilled).toHaveBeenCalledWith("purchase-1");
  });

  it("is idempotent for an already fulfilled purchase", async () => {
    const sendRedownloadEmail = vi.fn(async () => undefined);
    const response = await confirmCheckout(
      new Request("https://slick-shot.com/api/checkout/confirm", {
        method: "POST",
        body: JSON.stringify({ session_id: "cs_test_123" }),
      }),
      {
        APP_URL: "https://slick-shot.com",
      } as never,
      {
        getCheckoutSession: async () =>
          ({
            id: "cs_test_123",
            payment_status: "paid",
            customer_details: { email: "buyer@example.com" },
            payment_intent: "pi_test_123",
          }) as never,
        findPurchaseBySessionId: async () =>
          ({
            id: "purchase-1",
            fulfilled_at: "2026-03-28T00:00:00.000Z",
          }) as never,
        upsertPurchase: async () =>
          ({
            id: "purchase-1",
            fulfilled_at: "2026-03-28T00:00:00.000Z",
          }) as never,
        createDownloadTokenRecord: async () => undefined,
        markPurchaseFulfilled: async () => undefined,
        sendRedownloadEmail,
        buildDownloadUrl: (token) => `https://slick-shot.com/download?token=${token}`,
      }
    );

    expect(response.status).toBe(200);
    expect(sendRedownloadEmail).not.toHaveBeenCalled();
  });
});
