# SlickShot Paid Download Flow Design

Date: 2026-03-28

## Summary

SlickShot is sold directly from a static landing page at `slick-shot.com` using Stripe Payment Links.
The next step is to add purchase-gated download fulfillment so that:

- a customer can download immediately on the same device after payment
- a customer also receives an email with a re-download link
- download access is granted only after Stripe payment confirmation

The implementation should fit the existing stack:

- Cloudflare Pages for the landing page and static pages
- Cloudflare Worker for backend logic
- Cloudflare D1 for purchase records
- Cloudflare R2 for release artifacts
- Stripe for one-time payment
- Resend for transactional email

## Goals

- Confirm Stripe payment server-side before granting download access
- Support immediate post-purchase download on the same device
- Support later re-download from an emailed link
- Keep release artifacts in R2 behind short-lived signed URLs
- Preserve the current static LP architecture

## Non-goals

- License key generation
- Per-device activation
- Multi-product catalog management
- Subscription billing
- Customer account system

## Architecture

### Pages

Pages continues to host:

- landing page
- `thanks` page
- `download` page
- legal pages

Pages remains static. It does not verify purchases directly.

### Worker

The Worker owns all sensitive operations:

- verify Stripe checkout sessions
- receive Stripe webhooks
- upsert purchase records into D1
- issue short-lived download tokens
- generate R2 signed URLs
- trigger transactional email through Resend

### D1

D1 stores the durable purchase state and short-lived download tokens.

### R2

R2 stores release artifacts such as:

- `SlickShot.zip`
- `appcast.xml`

Customers never receive a permanent public artifact URL. Downloads are always mediated through Worker-issued short-lived URLs.

### Stripe

Stripe Payment Links handles one-time payment collection.
After successful payment, Stripe redirects to:

- `https://slick-shot.com/thanks?session_id=...`

Stripe webhook acts as the authoritative async fallback for completed payments.

### Resend

Resend sends the re-download email once payment has been confirmed.

## Data Model

### purchases

- `id`
- `email`
- `stripe_session_id`
- `stripe_payment_intent_id`
- `status`
- `product_slug`
- `download_count`
- `last_downloaded_at`
- `created_at`
- `updated_at`

### download_tokens

- `id`
- `purchase_id`
- `token`
- `purpose`
- `expires_at`
- `used_at`
- `created_at`

## Request Flow

### Immediate Download

1. Customer clicks the purchase CTA on the landing page.
2. Stripe Payment Link collects payment.
3. Stripe redirects to `https://slick-shot.com/thanks?session_id=...`.
4. `thanks` page JS calls Worker `POST /api/checkout/confirm` with the `session_id`.
5. Worker retrieves the Checkout Session from Stripe and confirms payment success.
6. Worker upserts the purchase into D1.
7. Worker creates:
   - one short-lived immediate download token
   - one re-download token for email flow
8. Worker sends a re-download email through Resend.
9. Worker returns an immediate download URL payload to the `thanks` page.
10. User clicks download and receives a short-lived R2 signed URL.

### Later Re-download

1. Customer opens the email link, such as `https://slick-shot.com/download?token=...`.
2. `download` page JS calls Worker `POST /api/download/resolve`.
3. Worker validates the token in D1.
4. Worker confirms token validity and related purchase state.
5. Worker returns a short-lived R2 signed URL.
6. Download begins.

### Webhook Fallback

1. Stripe sends `checkout.session.completed` to the Worker webhook.
2. Worker verifies the Stripe signature.
3. Worker upserts the purchase into D1 if not already present.
4. Worker can safely resend or recover the email path if the browser redirect path was interrupted.

## Worker API

### `POST /api/checkout/confirm`

Input:

- `session_id`

Behavior:

- fetch checkout session from Stripe
- confirm payment status
- store or update purchase
- issue immediate token
- issue email token
- send email

Response:

- `ok`
- `email`
- `download_url`

### `POST /api/download/resolve`

Input:

- `token`

Behavior:

- validate token
- validate purchase
- create short-lived R2 signed URL

Response:

- `ok`
- `signed_url`

### `POST /api/stripe/webhook`

Behavior:

- verify Stripe signature
- handle `checkout.session.completed`
- persist purchase state

### `POST /api/redownload/request`

Input:

- `email`

Behavior:

- find latest valid purchase for email
- issue new re-download token
- send email

## Page Behavior

### `thanks`

States:

- verifying payment
- download ready
- confirmation failed

Behavior:

- reads `session_id` from the query string
- calls Worker confirmation API
- shows immediate download CTA on success
- confirms that a re-download email was sent

### `download`

States:

- validating token
- starting download
- token invalid or expired

Behavior:

- reads `token` from query string
- resolves signed URL via Worker
- starts artifact download
- offers re-send path if invalid

## Security Rules

- never treat redirect arrival as proof of payment
- always verify `session_id` server-side with Stripe
- never expose permanent R2 URLs
- use short-lived download tokens
- use short-lived R2 signed URLs
- invalidate access when purchase status becomes refunded
- keep webhook signature verification enabled in production

## Operational Defaults

- immediate download token TTL: 15 minutes
- email re-download token TTL: 24 hours
- signed R2 URL TTL: short-lived, for example 5 minutes
- product slug: `slickshot`

## Failure Handling

- if `thanks` verification fails, show retry and support guidance
- if webhook arrives before `thanks`, purchase should still be recoverable
- if email send fails, immediate download should still work
- if token expires, user should be able to request a fresh email link

## Testing

Minimum coverage:

- successful checkout confirmation
- webhook signature verification
- token validation and expiry behavior
- refunded purchase denied at download resolution
- repeated confirm calls remain idempotent
- email resend path for valid purchaser

## Implementation Notes

- Frontend remains static HTML and small JS files
- Backend is implemented as a Cloudflare Worker using Node.js-compatible patterns
- D1 should be the source of truth for purchase fulfillment state
- R2 should remain private behind signed URL generation
- LP copy can continue to say that download starts after Stripe payment and updates are delivered in-app
