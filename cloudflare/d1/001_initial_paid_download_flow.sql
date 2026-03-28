CREATE TABLE purchases (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  stripe_session_id TEXT NOT NULL UNIQUE,
  stripe_payment_intent_id TEXT UNIQUE,
  status TEXT NOT NULL,
  product_slug TEXT NOT NULL,
  download_count INTEGER NOT NULL DEFAULT 0,
  last_downloaded_at TEXT,
  fulfilled_at TEXT,
  last_email_sent_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE download_tokens (
  id TEXT PRIMARY KEY,
  purchase_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  purpose TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  used_at TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (purchase_id) REFERENCES purchases(id)
);

CREATE INDEX idx_purchases_email_status_created
  ON purchases(email, status, created_at DESC);

CREATE INDEX idx_download_tokens_purchase
  ON download_tokens(purchase_id);
