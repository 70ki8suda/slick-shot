import type { DownloadTokenRecord, Env, PurchaseRecord } from "../env";
import { incrementPurchaseDownload, markDownloadTokenUsed } from "../db";
import { streamDownloadFromR2 } from "../downloads";
import { hashToken } from "../tokens";

export interface ServeDownloadDependencies {
  findDownloadTokenByHash: (tokenHash: string) => Promise<DownloadTokenRecord | null>;
  findPurchaseById: (purchaseId: string) => Promise<PurchaseRecord | null>;
  markDownloadTokenUsed: (tokenId: string) => Promise<void>;
  incrementPurchaseDownload: (purchaseId: string) => Promise<void>;
  streamDownloadFromR2: () => Promise<Response>;
}

function defaultDependencies(env: Env): ServeDownloadDependencies {
  return {
    findDownloadTokenByHash: async (tokenHash) => {
      const result = await env.DB.prepare("SELECT * FROM download_tokens WHERE token_hash = ? LIMIT 1")
        .bind(tokenHash)
        .first<Record<string, unknown>>();
      if (!result) return null;
      return {
        id: String(result.id),
        purchase_id: String(result.purchase_id),
        token_hash: String(result.token_hash),
        purpose: String(result.purpose),
        expires_at: String(result.expires_at),
        used_at: result.used_at ? String(result.used_at) : null,
        created_at: String(result.created_at),
      };
    },
    findPurchaseById: async (purchaseId) => {
      const result = await env.DB.prepare("SELECT * FROM purchases WHERE id = ? LIMIT 1").bind(purchaseId).first<Record<string, unknown>>();
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
    markDownloadTokenUsed: (tokenId) => markDownloadTokenUsed(env.DB, tokenId),
    incrementPurchaseDownload: (purchaseId) => incrementPurchaseDownload(env.DB, purchaseId),
    streamDownloadFromR2: () => streamDownloadFromR2(env),
  };
}

export async function serveDownload(
  request: Request,
  env: Env,
  deps: ServeDownloadDependencies = defaultDependencies(env)
): Promise<Response> {
  const url = new URL(request.url);
  const token = url.searchParams.get("token")?.trim() ?? "";

  if (!token) {
    return new Response("Missing token", { status: 400 });
  }

  const tokenHash = await hashToken(token);
  const record = await deps.findDownloadTokenByHash(tokenHash);
  if (!record || record.used_at || new Date(record.expires_at).getTime() < Date.now()) {
    return new Response("Expired token", { status: 410 });
  }

  const purchase = await deps.findPurchaseById(record.purchase_id);
  if (!purchase || purchase.status !== "paid") {
    return new Response("Purchase not eligible", { status: 403 });
  }

  await deps.markDownloadTokenUsed(record.id);
  await deps.incrementPurchaseDownload(purchase.id);
  return deps.streamDownloadFromR2();
}
