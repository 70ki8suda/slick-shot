import type { Env, PurchaseRecord } from "../env";
import { createDownloadToken } from "../tokens";
import { createDownloadTokenRecord, findLatestPaidPurchaseByEmail } from "../db";
import { sendRedownloadEmail } from "../email";

export interface RequestRedownloadDependencies {
  findLatestPaidPurchaseByEmail: (email: string) => Promise<PurchaseRecord | null>;
  createDownloadTokenRecord: (
    purchaseId: string,
    tokenHash: string,
    purpose: string,
    expiresAt: string
  ) => Promise<void>;
  sendRedownloadEmail: (email: string, downloadUrl: string) => Promise<void>;
}

function defaultDependencies(env: Env): RequestRedownloadDependencies {
  return {
    findLatestPaidPurchaseByEmail: (email) => findLatestPaidPurchaseByEmail(env.DB, email),
    createDownloadTokenRecord: (purchaseId, tokenHash, purpose, expiresAt) =>
      createDownloadTokenRecord(env.DB, { purchaseId, tokenHash, purpose, expiresAt }).then(() => undefined),
    sendRedownloadEmail: (email, downloadUrl) => sendRedownloadEmail(env, { to: email, downloadUrl }),
  };
}

export async function requestRedownload(
  request: Request,
  env: Env,
  deps: RequestRedownloadDependencies = defaultDependencies(env)
): Promise<Response> {
  let email = "";
  try {
    const body = (await request.json()) as { email?: string };
    email = String(body.email ?? "").trim().toLowerCase();
  } catch {
    return Response.json({ ok: false, error: "invalid-json" }, { status: 400 });
  }

  if (!email) {
    return Response.json({ ok: false, error: "missing-email" }, { status: 400 });
  }

  const purchase = await deps.findLatestPaidPurchaseByEmail(email);
  if (!purchase) {
    return Response.json({ ok: false, error: "purchase-not-found" }, { status: 404 });
  }

  const token = await createDownloadToken(24 * 60 * 60);
  await deps.createDownloadTokenRecord(purchase.id, token.tokenHash, "email_redownload", token.expiresAt);
  await deps.sendRedownloadEmail(email, `${env.APP_URL}/download?token=${encodeURIComponent(token.token)}`);

  return Response.json({ ok: true });
}
