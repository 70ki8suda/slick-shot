import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";

describe("schema", () => {
  it("defines purchases and download_tokens", () => {
    const sql = readFileSync(
      "/Users/yasudanaoki/Desktop/slick-shot/cloudflare/d1/001_initial_paid_download_flow.sql",
      "utf8"
    );

    expect(sql).toContain("CREATE TABLE purchases");
    expect(sql).toContain("CREATE TABLE download_tokens");
  });
});
