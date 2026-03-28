export interface Env {
  DB: D1Database;
  DOWNLOADS: R2Bucket;
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  RESEND_API_KEY: string;
  RESEND_FROM_EMAIL: string;
  APP_URL: string;
  DOWNLOAD_BASE_URL: string;
}

export interface DownloadTokenRecord {
  id: string;
  purchase_id: string;
  token_hash: string;
  purpose: string;
  expires_at: string;
  used_at: string | null;
  created_at: string;
}

export interface PurchaseRecord {
  id: string;
  email: string;
  stripe_session_id: string;
  stripe_payment_intent_id: string | null;
  status: string;
  product_slug: string;
  download_count: number;
  last_downloaded_at: string | null;
  fulfilled_at: string | null;
  last_email_sent_at: string | null;
  created_at: string;
  updated_at: string;
}
