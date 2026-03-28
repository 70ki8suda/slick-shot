import { describe, expect, it } from "vitest";
import worker from "../src/index";

describe("worker smoke", () => {
  it("returns 404 for unknown routes", async () => {
    const response = await worker.fetch(new Request("https://example.com/nope"), {} as never, {} as never);
    expect(response.status).toBe(404);
  });
});
