import type { Env } from "./env";
import { confirmCheckout } from "./handlers/confirmCheckout";
import { resolveDownload } from "./handlers/resolveDownload";
import { requestRedownload } from "./handlers/requestRedownload";
import { serveDownload } from "./handlers/serveDownload";
import { stripeWebhook } from "./handlers/stripeWebhook";

function jsonMethodNotAllowed() {
  return Response.json({ ok: false, error: "method-not-allowed" }, { status: 405 });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return Response.json({ ok: true });
    }

    if (url.pathname === "/api/checkout/confirm") {
      if (request.method !== "POST") return jsonMethodNotAllowed();
      return confirmCheckout(request, env);
    }

    if (url.pathname === "/api/download/resolve") {
      if (request.method !== "POST") return jsonMethodNotAllowed();
      return resolveDownload(request, env);
    }

    if (url.pathname === "/api/download/file") {
      if (request.method !== "GET") return jsonMethodNotAllowed();
      return serveDownload(request, env);
    }

    if (url.pathname === "/api/stripe/webhook") {
      if (request.method !== "POST") return jsonMethodNotAllowed();
      return stripeWebhook(request, env);
    }

    if (url.pathname === "/api/redownload/request") {
      if (request.method !== "POST") return jsonMethodNotAllowed();
      return requestRedownload(request, env);
    }

    return new Response("Not Found", { status: 404 });
  },
};
