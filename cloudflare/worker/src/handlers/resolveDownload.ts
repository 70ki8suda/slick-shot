import type { DownloadTokenRecord, Env, PurchaseRecord } from "../env";
import { createSecureDownloadUrl } from "../downloads";
import { findDownloadTokenByHash, findPurchaseBySessionId } from "../db";
import { hashToken } from "../tokens";

export interface ResolveDownloadDependencies {
  findDownloadTokenByHash: (tokenHash: string) => Promise<DownloadTokenRecord | null>;
  findPurchaseById: (purchaseId: string) => Promise<PurchaseRecord | null>;
  buildDownloadUrl: (token: string) => string;
}

function defaultDependencies(env: Env): ResolveDownloadDependencies {
  return {
    findDownloadTokenByHash: (tokenHash) => findDownloadTokenByHash(env.DB, tokenHash),
    findPurchaseById: async (purchaseId) => {
      const result = await env.DB.prepare("SELECT * FROM purchases WHERE id = ? LIMIT 1").bind(purchaseId).first();
      if (!result) return null;
      return {
        id: String(result.id),
        email: String(result.email),
        stripe_session_id: String(result.stripe_session_id),
        stripe_payment_intent_id: result.stripe_payment_intent_id ? String(result.stripe_payment_intent_id) : null,
        status: String(result.status),
        product_slug: String(result.product_slug),
        download_count: Number(result.download_count ?? 0),
        last_downloaded_at: result.last_downloaded_at ? String(result.last_downloaded_at) : null,
        fulfilled_at: result.fulfilled_at ? String(result.fulfilled_at) : null,
        last_email_sent_at: result.last_email_sent_at ? String(result.last_email_sent_at) : null,
        created_at: String(result.created_at),
        updated_at: String(result.updated_at),
      };
    },
    buildDownloadUrl: (token) => createSecureDownloadUrl(env, token),
  };
}

export async function resolveDownload(
  request: Request,
  env: Env,
  deps: ResolveDownloadDependencies = defaultDependencies(env)
): Promise<Response> {
  let token = "";

  try {
    const body = (await request.json()) as { token?: string };
    token = String(body.token ?? "").trim();
  } catch {
    return Response.json({ ok: false, error: "invalid-json" }, { status: 400 });
  }

  if (!token) {
    return Response.json({ ok: false, error: "missing-token" }, { status: 400 });
  }

  const tokenHash = await hashToken(token);
  const record = await deps.findDownloadTokenByHash(tokenHash);
  if (!record) {
    return Response.json({ ok: false, error: "token-not-found" }, { status: 404 });
  }

  if (record.used_at || new Date(record.expires_at).getTime() < Date.now()) {
    return Response.json({ ok: false, error: "token-expired" }, { status: 410 });
  }

  const purchase = await deps.findPurchaseById(record.purchase_id);
  if (!purchase || purchase.status !== "paid") {
    return Response.json({ ok: false, error: "purchase-not-eligible" }, { status: 403 });
  }

  return Response.json({
    ok: true,
    signed_url: deps.buildDownloadUrl(token),
  });
}
