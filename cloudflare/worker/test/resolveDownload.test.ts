import { describe, expect, it } from "vitest";
import { resolveDownload } from "../src/handlers/resolveDownload";

describe("resolveDownload", () => {
  it("returns a secure download url for a valid token", async () => {
    const response = await resolveDownload(
      new Request("https://slick-shot.com/api/download/resolve", {
        method: "POST",
        body: JSON.stringify({ token: "plain-token" }),
      }),
      {} as never,
      {
        findDownloadTokenByHash: async () =>
          ({
            id: "token-1",
            purchase_id: "purchase-1",
            expires_at: new Date(Date.now() + 60_000).toISOString(),
            used_at: null,
          }) as never,
        findPurchaseById: async () =>
          ({
            id: "purchase-1",
            status: "paid",
          }) as never,
        buildDownloadUrl: (token) => `https://slick-shot.com/api/download/file?token=${token}`,
      }
    );

    const body = await response.json();
    expect(response.status).toBe(200);
    expect(body.signed_url).toContain("/api/download/file?token=");
  });
});
