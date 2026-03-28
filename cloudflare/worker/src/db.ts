import type { DownloadTokenRecord, PurchaseRecord } from "./env";

export interface PurchaseInput {
  id?: string;
  email: string;
  stripeSessionId: string;
  stripePaymentIntentId?: string | null;
  status: string;
  productSlug: string;
}

export interface DownloadTokenInput {
  id?: string;
  purchaseId: string;
  tokenHash: string;
  purpose: string;
  expiresAt: string;
}

function mapPurchase(row: Record<string, unknown> | null): PurchaseRecord | null {
  if (!row) return null;

  return {
    id: String(row.id),
    email: String(row.email),
    stripe_session_id: String(row.stripe_session_id),
    stripe_payment_intent_id: row.stripe_payment_intent_id ? String(row.stripe_payment_intent_id) : null,
    status: String(row.status),
    product_slug: String(row.product_slug),
    download_count: Number(row.download_count ?? 0),
    last_downloaded_at: row.last_downloaded_at ? String(row.last_downloaded_at) : null,
    fulfilled_at: row.fulfilled_at ? String(row.fulfilled_at) : null,
    last_email_sent_at: row.last_email_sent_at ? String(row.last_email_sent_at) : null,
    created_at: String(row.created_at),
    updated_at: String(row.updated_at),
  };
}

function mapDownloadToken(row: Record<string, unknown> | null): DownloadTokenRecord | null {
  if (!row) return null;

  return {
    id: String(row.id),
    purchase_id: String(row.purchase_id),
    token_hash: String(row.token_hash),
    purpose: String(row.purpose),
    expires_at: String(row.expires_at),
    used_at: row.used_at ? String(row.used_at) : null,
    created_at: String(row.created_at),
  };
}

export async function findPurchaseBySessionId(db: D1Database, stripeSessionId: string): Promise<PurchaseRecord | null> {
  const result = await db
    .prepare("SELECT * FROM purchases WHERE stripe_session_id = ? LIMIT 1")
    .bind(stripeSessionId)
    .first<Record<string, unknown>>();

  return mapPurchase(result);
}

export async function findPurchaseByPaymentIntentId(
  db: D1Database,
  stripePaymentIntentId: string
): Promise<PurchaseRecord | null> {
  const result = await db
    .prepare("SELECT * FROM purchases WHERE stripe_payment_intent_id = ? LIMIT 1")
    .bind(stripePaymentIntentId)
    .first<Record<string, unknown>>();

  return mapPurchase(result);
}

export async function findLatestPaidPurchaseByEmail(db: D1Database, email: string): Promise<PurchaseRecord | null> {
  const result = await db
    .prepare(
      "SELECT * FROM purchases WHERE email = ? AND status = 'paid' ORDER BY datetime(created_at) DESC LIMIT 1"
    )
    .bind(email)
    .first<Record<string, unknown>>();

  return mapPurchase(result);
}

export async function upsertPurchase(db: D1Database, input: PurchaseInput): Promise<PurchaseRecord> {
  const now = new Date().toISOString();
  const id = input.id ?? crypto.randomUUID();

  await db
    .prepare(
      `INSERT INTO purchases (
        id, email, stripe_session_id, stripe_payment_intent_id, status, product_slug,
        download_count, last_downloaded_at, fulfilled_at, last_email_sent_at, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, 0, NULL, NULL, NULL, ?, ?)
      ON CONFLICT(stripe_session_id) DO UPDATE SET
        email = excluded.email,
        stripe_payment_intent_id = excluded.stripe_payment_intent_id,
        status = excluded.status,
        product_slug = excluded.product_slug,
        updated_at = excluded.updated_at`
    )
    .bind(
      id,
      input.email,
      input.stripeSessionId,
      input.stripePaymentIntentId ?? null,
      input.status,
      input.productSlug,
      now,
      now
    )
    .run();

  const purchase = await findPurchaseBySessionId(db, input.stripeSessionId);
  if (!purchase) {
    throw new Error("Failed to upsert purchase");
  }

  return purchase;
}

export async function markPurchaseFulfilled(db: D1Database, purchaseId: string): Promise<void> {
  const now = new Date().toISOString();
  await db
    .prepare("UPDATE purchases SET fulfilled_at = COALESCE(fulfilled_at, ?), last_email_sent_at = ?, updated_at = ? WHERE id = ?")
    .bind(now, now, now, purchaseId)
    .run();
}

export async function markPurchaseRefunded(db: D1Database, purchaseId: string): Promise<void> {
  const now = new Date().toISOString();
  await db
    .prepare("UPDATE purchases SET status = 'refunded', updated_at = ? WHERE id = ?")
    .bind(now, purchaseId)
    .run();
}

export async function incrementPurchaseDownload(db: D1Database, purchaseId: string): Promise<void> {
  const now = new Date().toISOString();
  await db
    .prepare(
      "UPDATE purchases SET download_count = download_count + 1, last_downloaded_at = ?, updated_at = ? WHERE id = ?"
    )
    .bind(now, now, purchaseId)
    .run();
}

export async function createDownloadTokenRecord(
  db: D1Database,
  input: DownloadTokenInput
): Promise<DownloadTokenRecord> {
  const id = input.id ?? crypto.randomUUID();
  const now = new Date().toISOString();

  await db
    .prepare(
      `INSERT INTO download_tokens (id, purchase_id, token_hash, purpose, expires_at, used_at, created_at)
       VALUES (?, ?, ?, ?, ?, NULL, ?)`
    )
    .bind(id, input.purchaseId, input.tokenHash, input.purpose, input.expiresAt, now)
    .run();

  const record = await findDownloadTokenByHash(db, input.tokenHash);
  if (!record) {
    throw new Error("Failed to create download token");
  }

  return record;
}

export async function findDownloadTokenByHash(
  db: D1Database,
  tokenHash: string
): Promise<DownloadTokenRecord | null> {
  const result = await db
    .prepare("SELECT * FROM download_tokens WHERE token_hash = ? LIMIT 1")
    .bind(tokenHash)
    .first<Record<string, unknown>>();

  return mapDownloadToken(result);
}

export async function markDownloadTokenUsed(db: D1Database, tokenId: string): Promise<void> {
  const now = new Date().toISOString();
  await db
    .prepare("UPDATE download_tokens SET used_at = COALESCE(used_at, ?) WHERE id = ?")
    .bind(now, tokenId)
    .run();
}
