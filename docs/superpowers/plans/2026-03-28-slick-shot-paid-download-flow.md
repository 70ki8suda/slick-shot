# SlickShot Paid Download Flow Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add purchase-gated fulfillment so SlickShot buyers can download immediately after Stripe payment and re-download later from an emailed link.

**Architecture:** Keep `docs/lp` static on Cloudflare Pages. Mount a Cloudflare Worker on the same site origin for `/api/*` so the static pages can call relative API paths without CORS or cross-origin state issues. The Worker verifies Stripe sessions, receives webhooks, persists purchases and download tokens in D1, generates short-lived R2 signed URLs, and sends re-download email through Resend.

**Tech Stack:** Static HTML/CSS/JS, Cloudflare Pages, Cloudflare Worker, Cloudflare D1, Cloudflare R2, Stripe, Resend, Vitest or Node test runner where practical.

---

## File Structure

### Existing files to modify

- Modify: `/Users/yasudanaoki/Desktop/slick-shot/docs/lp/thanks.html`
  - Render verification, ready, and failure states for post-purchase confirmation.
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/docs/lp/download.html`
  - Render token validation and download start flow.
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/docs/lp/script.js`
  - Add `thanks` and `download` page runtime logic.
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/README.md`
  - Document fulfillment setup, Worker env vars, and deployment steps.

### New backend files

- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/package.json`
  - Worker package and local scripts.
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/wrangler.toml`
  - Worker bindings for D1, R2, env vars, and routes.
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/index.ts`
  - Worker entrypoint and route dispatch.
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/env.ts`
  - Typed environment bindings.
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/stripe.ts`
  - Stripe client setup and helpers.
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/db.ts`
  - D1 helpers for purchases and tokens.
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/tokens.ts`
  - Token creation and hashing helpers.
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/downloads.ts`
  - R2 signed URL generation.
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/email.ts`
  - Resend integration.
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/handlers/confirmCheckout.ts`
  - `POST /api/checkout/confirm`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/handlers/resolveDownload.ts`
  - `POST /api/download/resolve`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/handlers/stripeWebhook.ts`
  - `POST /api/stripe/webhook`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/handlers/requestRedownload.ts`
  - `POST /api/redownload/request`

### Database schema files

- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/d1/001_initial_paid_download_flow.sql`
  - Purchases and download token tables.

### Test files

- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/confirmCheckout.test.ts`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/resolveDownload.test.ts`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/stripeWebhook.test.ts`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/requestRedownload.test.ts`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/pageRuntime.test.ts`

## Pre-flight Deployment Assumptions

- [ ] Cloudflare Pages serves `https://slick-shot.com`
- [ ] Cloudflare Worker is routed to `https://slick-shot.com/api/*` and `https://www.slick-shot.com/api/*`
- [ ] Stripe Payment Link success redirect is configured to `https://slick-shot.com/thanks?session_id={CHECKOUT_SESSION_ID}`
- [ ] `downloads.slick-shot.com` already serves artifacts from R2
- [ ] Resend sender domain or sender email is verified before turning on purchase emails

## Chunk 1: Worker Scaffold And Schema

### Task 1: Add Worker package scaffold

**Files:**
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/package.json`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/wrangler.toml`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/env.ts`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/index.ts`

- [ ] **Step 1: Write the failing smoke test**

Create `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/smoke.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import worker from "../src/index";

describe("worker smoke", () => {
  it("returns 404 for unknown routes", async () => {
    const response = await worker.fetch(
      new Request("https://example.com/nope"),
      {} as never,
      {} as never
    );

    expect(response.status).toBe(404);
  });
});
```

- [ ] **Step 2: Run the smoke test to verify it fails**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- smoke.test.ts
```

Expected: FAIL because worker package and test runner are not configured yet.

- [ ] **Step 3: Add minimal package and worker entrypoint**

Create `package.json` with:

```json
{
  "name": "slick-shot-worker",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "wrangler dev",
    "test": "vitest run"
  },
  "dependencies": {
    "stripe": "^20.1.0"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.20260301.0",
    "jsdom": "^26.0.0",
    "typescript": "^5.8.0",
    "vitest": "^3.1.0",
    "wrangler": "^4.9.0"
  }
}
```

Create `src/env.ts`:

```ts
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
```

Create `src/index.ts`:

```ts
import type { Env } from "./env";

export default {
  async fetch(request: Request, _env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/health") {
      return Response.json({ ok: true });
    }

    return new Response("Not Found", { status: 404 });
  },
};
```

Create `wrangler.toml` with placeholders for:

```toml
name = "slick-shot-worker"
main = "src/index.ts"
compatibility_date = "2026-03-28"

[[routes]]
pattern = "slick-shot.com/api/*"
zone_name = "slick-shot.com"

[[routes]]
pattern = "www.slick-shot.com/api/*"
zone_name = "slick-shot.com"

[[d1_databases]]
binding = "DB"
database_name = "slick-shot"
database_id = "REPLACE_ME"

[[r2_buckets]]
binding = "DOWNLOADS"
bucket_name = "slick-shot-downloads"
```

- [ ] **Step 4: Run the smoke test to verify it passes**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm install
npm test -- smoke.test.ts
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/yasudanaoki/Desktop/slick-shot add cloudflare/worker
git -C /Users/yasudanaoki/Desktop/slick-shot commit -m "feat: scaffold fulfillment worker"
```

### Task 2: Add D1 schema

**Files:**
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/d1/001_initial_paid_download_flow.sql`
- Test: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/schema.test.ts`

- [ ] **Step 1: Write the failing schema assertion test**

Create `schema.test.ts`:

```ts
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
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- schema.test.ts
```

Expected: FAIL because SQL file does not exist.

- [ ] **Step 3: Write minimal schema**

Create SQL:

```sql
CREATE TABLE purchases (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  stripe_session_id TEXT NOT NULL UNIQUE,
  stripe_payment_intent_id TEXT,
  status TEXT NOT NULL,
  product_slug TEXT NOT NULL,
  download_count INTEGER NOT NULL DEFAULT 0,
  last_downloaded_at TEXT,
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
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- schema.test.ts
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/yasudanaoki/Desktop/slick-shot add cloudflare/d1 cloudflare/worker/test/schema.test.ts
git -C /Users/yasudanaoki/Desktop/slick-shot commit -m "feat: add purchase fulfillment schema"
```

## Chunk 2: Purchase Confirmation And Download Resolution

### Task 3: Implement checkout confirmation handler

**Files:**
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/stripe.ts`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/db.ts`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/tokens.ts`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/handlers/confirmCheckout.ts`
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/index.ts`
- Test: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/confirmCheckout.test.ts`

- [ ] **Step 1: Write the failing confirm test**

Create a test that posts `{ session_id: "cs_test_123" }` to `/api/checkout/confirm` and expects:

```ts
expect(response.status).toBe(200);
expect(body.ok).toBe(true);
expect(body.download_url).toContain("/download?token=");
```

Stub Stripe session retrieval and D1 writes with in-memory doubles.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- confirmCheckout.test.ts
```

Expected: FAIL because route and handler do not exist.

- [ ] **Step 3: Add minimal implementation**

Implement:

- `createStripeClient(env)`
- `upsertPurchase(env.DB, purchaseInput)`
- `createDownloadToken(purpose, ttlSeconds)`
- `confirmCheckout(request, env)`

`confirmCheckout` should:

1. parse JSON body
2. retrieve checkout session from Stripe
3. reject if payment not completed
4. persist purchase
5. load existing purchase by `stripe_session_id` first
6. if purchase already exists and status is `paid`, reuse the existing immediate token or mint a replacement without resending email
7. create immediate token only when needed
8. mark fulfillment state so a later webhook or page refresh does not send duplicate re-download email
8. return:

```ts
return Response.json({
  ok: true,
  email: session.customer_details?.email ?? null,
  download_url: `${env.APP_URL}/download?token=${token}`,
});
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- confirmCheckout.test.ts
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/yasudanaoki/Desktop/slick-shot add cloudflare/worker/src cloudflare/worker/test/confirmCheckout.test.ts
git -C /Users/yasudanaoki/Desktop/slick-shot commit -m "feat: confirm Stripe checkout sessions"
```

### Task 4: Implement download resolution

**Files:**
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/downloads.ts`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/handlers/resolveDownload.ts`
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/db.ts`
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/index.ts`
- Test: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/resolveDownload.test.ts`

- [ ] **Step 1: Write the failing resolve test**

Create a test that posts `{ token: "plain-token" }` and expects a signed URL payload:

```ts
expect(response.status).toBe(200);
expect(body.signed_url).toContain("SlickShot.zip");
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- resolveDownload.test.ts
```

Expected: FAIL because route and handler do not exist.

- [ ] **Step 3: Add minimal implementation**

Implement:

- `findDownloadTokenByHash`
- `markTokenUsed`
- `createSignedDownloadUrl`
- `resolveDownload(request, env)`

`resolveDownload` should:

1. parse token
2. hash token
3. load token record
4. reject expired or refunded purchase
5. generate short-lived R2 signed URL for `SlickShot.zip`
6. increment `download_count`
7. return JSON with `signed_url`

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- resolveDownload.test.ts
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/yasudanaoki/Desktop/slick-shot add cloudflare/worker/src cloudflare/worker/test/resolveDownload.test.ts
git -C /Users/yasudanaoki/Desktop/slick-shot commit -m "feat: resolve gated downloads"
```

## Chunk 3: Webhook And Email Re-download

### Task 5: Implement Stripe webhook handler

**Files:**
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/handlers/stripeWebhook.ts`
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/stripe.ts`
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/index.ts`
- Test: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/stripeWebhook.test.ts`

- [ ] **Step 1: Write the failing webhook test**

Test that a valid `checkout.session.completed` event:

- returns `200`
- upserts the purchase

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- stripeWebhook.test.ts
```

Expected: FAIL because webhook handler does not exist.

- [ ] **Step 3: Add minimal implementation**

Implement signature verification and handle only:

- `checkout.session.completed`
- `charge.refunded`
- `charge.refund.updated`

For refund-related events:

- locate the purchase using `stripe_payment_intent_id` or related charge/payment linkage
- update purchase `status` to `refunded`
- invalidate future download resolution for that purchase, even if older tokens still exist
- keep the handler idempotent so repeated webhook deliveries do not duplicate fulfillment or state transitions

Ignore unrelated events with `200`.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- stripeWebhook.test.ts
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/yasudanaoki/Desktop/slick-shot add cloudflare/worker/src cloudflare/worker/test/stripeWebhook.test.ts
git -C /Users/yasudanaoki/Desktop/slick-shot commit -m "feat: persist Stripe webhook completions"
```

### Task 6: Implement email re-download flow

**Files:**
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/email.ts`
- Create: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/handlers/requestRedownload.ts`
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/handlers/confirmCheckout.ts`
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/src/index.ts`
- Test: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/requestRedownload.test.ts`

- [ ] **Step 1: Write the failing email flow test**

Test that a valid email request:

- creates a fresh token
- invokes the email sender
- returns `200`

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- requestRedownload.test.ts
```

Expected: FAIL because handler does not exist.

- [ ] **Step 3: Add minimal implementation**

Implement:

- `sendRedownloadEmail({ to, downloadUrl })`
- `requestRedownload(request, env)`
- call email sender from `confirmCheckout`
- guard `confirmCheckout` so email send happens once per new purchase fulfillment, not on every page refresh
- if webhook and redirect race, dedupe by `stripe_session_id` and persisted purchase status
- if the purchase is already marked `fulfilled`, skip duplicate email sends and only mint a fresh token when explicitly needed

Email body can be plain text:

```txt
SlickShot の再ダウンロードはこちら:
https://slick-shot.com/download?token=...
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- requestRedownload.test.ts
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/yasudanaoki/Desktop/slick-shot add cloudflare/worker/src cloudflare/worker/test/requestRedownload.test.ts
git -C /Users/yasudanaoki/Desktop/slick-shot commit -m "feat: send re-download emails"
```

## Chunk 4: Static Pages Runtime And Docs

### Task 7: Wire `thanks` page runtime

**Files:**
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/docs/lp/thanks.html`
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/docs/lp/script.js`
- Test: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/pageRuntime.test.ts`

- [ ] **Step 1: Write the failing runtime test**

Extend `package.json` test tooling to support DOM tests:

```json
{
  "scripts": {
    "test": "vitest run"
  }
}
```

Use `// @vitest-environment jsdom` in the runtime test file.

Test that the `thanks` page logic:

- reads `session_id`
- calls `/api/checkout/confirm`
- renders a visible download CTA

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- pageRuntime.test.ts
```

Expected: FAIL because `thanks` logic is missing.

- [ ] **Step 3: Add minimal implementation**

Add `data-page="thanks"` markup and JS that:

- shows verifying state
- calls `/api/checkout/confirm`
- swaps in download CTA on success
- shows retry and support text on failure

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- pageRuntime.test.ts
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/yasudanaoki/Desktop/slick-shot add docs/lp/thanks.html docs/lp/script.js cloudflare/worker/test/pageRuntime.test.ts
git -C /Users/yasudanaoki/Desktop/slick-shot commit -m "feat: wire thanks page confirmation flow"
```

### Task 8: Wire `download` page runtime

**Files:**
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/docs/lp/download.html`
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/docs/lp/script.js`
- Test: `/Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker/test/pageRuntime.test.ts`

- [ ] **Step 1: Write the failing download runtime test**

Test that the `download` page logic:

- reads `token`
- calls `/api/download/resolve`
- redirects browser to signed URL

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- pageRuntime.test.ts
```

Expected: FAIL because download page logic is missing.

- [ ] **Step 3: Add minimal implementation**

Add `data-page="download"` markup and JS that:

- shows validating state
- calls `/api/download/resolve`
- redirects to `signed_url`
- shows token expired state on failure

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test -- pageRuntime.test.ts
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /Users/yasudanaoki/Desktop/slick-shot add docs/lp/download.html docs/lp/script.js cloudflare/worker/test/pageRuntime.test.ts
git -C /Users/yasudanaoki/Desktop/slick-shot commit -m "feat: wire download token page"
```

### Task 9: Document deployment and secrets

**Files:**
- Modify: `/Users/yasudanaoki/Desktop/slick-shot/README.md`

- [ ] **Step 1: Write the failing doc checklist**

Add a short checklist in comments or draft notes covering:

- Stripe secret
- Stripe webhook secret
- Resend API key
- Resend sender email
- D1 binding
- R2 binding
- Worker deploy route
- Stripe Payment Link success redirect format with `session_id`

- [ ] **Step 2: Verify current README is missing these details**

Run:

```bash
rg -n "STRIPE_WEBHOOK_SECRET|RESEND_API_KEY|D1|R2" /Users/yasudanaoki/Desktop/slick-shot/README.md
```

Expected: incomplete or missing coverage

- [ ] **Step 3: Add minimal deployment docs**

Document:

- Pages + Worker split
- required env vars
- D1 migration step
- R2 artifact key
- Stripe Payment Link success URL set to `https://slick-shot.com/thanks?session_id={CHECKOUT_SESSION_ID}`
- Stripe webhook endpoint
- Worker route mounting for `/api/*` on `slick-shot.com`
- note that relative `/api/*` calls from static Pages rely on the Worker being bound to the same hostname

- [ ] **Step 4: Verify README contains the new setup**

Run:

```bash
rg -n "STRIPE_WEBHOOK_SECRET|RESEND_API_KEY|D1|R2|thanks\\?session_id" /Users/yasudanaoki/Desktop/slick-shot/README.md
```

Expected: matching lines found

- [ ] **Step 5: Commit**

```bash
git -C /Users/yasudanaoki/Desktop/slick-shot add README.md
git -C /Users/yasudanaoki/Desktop/slick-shot commit -m "docs: document paid download fulfillment setup"
```

## Verification Pass

- [ ] Run all worker tests:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npm test
```

- [ ] Run landing page smoke check:

```bash
rg -n "data-page=|data-hero-video|data-stripe-link" /Users/yasudanaoki/Desktop/slick-shot/docs/lp
```

- [ ] Run formatting or linting if configured

- [ ] Create a final commit for any post-review cleanup

```bash
git -C /Users/yasudanaoki/Desktop/slick-shot status
```
