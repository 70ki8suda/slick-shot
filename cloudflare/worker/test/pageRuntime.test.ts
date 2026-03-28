// @vitest-environment jsdom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { initPage } from "../../../docs/lp/script.js";

describe("page runtime", () => {
  beforeEach(() => {
    document.body.innerHTML = "";
  });

  it("confirms checkout on the thanks page and renders a download CTA", async () => {
    document.body.innerHTML = `
      <main data-page="thanks">
        <div data-thanks-status></div>
        <a data-thanks-download hidden></a>
      </main>
    `;
    const fetchMock = vi.fn(async () =>
      new Response(JSON.stringify({ ok: true, download_url: "https://slick-shot.com/download?token=abc" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      })
    );

    const location = new URL("https://slick-shot.com/thanks?session_id=cs_test_123");
    await initPage(document, {
      location,
      fetch: fetchMock,
      alert: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    });

    expect(fetchMock).toHaveBeenCalled();
    expect(document.querySelector("[data-thanks-download]")?.getAttribute("href")).toContain("/download?token=");
    expect(document.querySelector("[data-thanks-download]")?.hasAttribute("hidden")).toBe(false);
  });

  it("resolves token on the download page and redirects to the secure file url", async () => {
    document.body.innerHTML = `
      <main data-page="download">
        <div data-download-status></div>
      </main>
    `;
    const fetchMock = vi.fn(async () =>
      new Response(JSON.stringify({ ok: true, signed_url: "https://slick-shot.com/api/download/file?token=abc" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      })
    );
    const assign = vi.fn();

    const location = new URL("https://slick-shot.com/download?token=abc");
    await initPage(document, {
      location,
      fetch: fetchMock,
      alert: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      assign,
    });

    expect(fetchMock).toHaveBeenCalled();
    expect(assign).toHaveBeenCalledWith("https://slick-shot.com/api/download/file?token=abc");
  });
});
