import { describe, expect, it, vi } from "vitest";
import { requestRedownload } from "../src/handlers/requestRedownload";

describe("requestRedownload", () => {
  it("creates a token and sends a re-download email", async () => {
    const sendRedownloadEmail = vi.fn(async () => undefined);
    const response = await requestRedownload(
      new Request("https://slick-shot.com/api/redownload/request", {
        method: "POST",
        body: JSON.stringify({ email: "buyer@example.com" }),
      }),
      {
        APP_URL: "https://slick-shot.com",
      } as never,
      {
        findLatestPaidPurchaseByEmail: async () => ({ id: "purchase-1" }) as never,
        createDownloadTokenRecord: async () => undefined,
        sendRedownloadEmail,
      }
    );

    expect(response.status).toBe(200);
    expect(sendRedownloadEmail).toHaveBeenCalledOnce();
  });
});
