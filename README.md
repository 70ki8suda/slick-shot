# SlickShot

SlickShot is a macOS menu bar utility for transient screenshots.

It uses the native macOS interactive region capture flow, then routes the result into a temporary HUD-style thumbnail instead of writing files to the Desktop.

## Direct Sale + Auto Updates

SlickShot is set up for a direct-sale flow:

- LP + Stripe Checkout for the purchase
- clean URLs at `/thanks` and `/download` for the post-purchase handoff
- Sparkle for in-app automatic updates
- Developer ID signing + notarized release artifacts for website distribution
- Cloudflare Worker + D1 + R2 + Resend for gated fulfillment

Relevant files:

- `docs/lp/index.html`
- `docs/lp/thanks.html`
- `docs/lp/download.html`
- `docs/lp/_redirects`
- `cloudflare/worker`
- `cloudflare/d1/001_initial_paid_download_flow.sql`
- `Scripts/build-release.sh`
- `Scripts/generate-appcast.sh`

## What It Does

- Trigger native macOS region capture from a global hotkey or menu bar action.
- Keep captures in a transient thumbnail stack instead of saving to the Desktop.
- Show the thumbnail HUD on the same display where the capture happened.
- Drag screenshots into other apps through managed temporary PNG files.
- Remove screenshots automatically after successful drag-and-drop or after the retention window expires.
- Let you dismiss the current capture from a hover-only close control.
- Show shortcut onboarding and Screen Recording guidance in the settings window.

## Install

Install a Raycast-launchable app bundle into `~/Applications`:

```bash
./Scripts/install-app.sh
```

This creates `~/Applications/SlickShot.app`.
The installer also creates a local signing identity in `~/Library/Keychains/slickshot-signing.keychain-db` so Screen Recording permission survives app reinstalls during development.
When `SLICKSHOT_SU_FEED_URL` and `SLICKSHOT_SPARKLE_PUBLIC_ED_KEY` are configured, the app bundle also includes Sparkle update metadata.

After that you can:

- launch `SlickShot` from Raycast
- launch it directly from Finder or Spotlight
- use the global shortcut after first-launch onboarding

## First Launch

On first launch, SlickShot opens its settings window in onboarding mode when no valid shortcut is saved.

1. Click the shortcut recorder.
2. Press the key combination you want to use.
3. Save it implicitly by finishing the recording.
4. Trigger `Capture Screenshot` once to let macOS ask for Screen Recording permission if needed.

If macOS blocks capture, SlickShot opens the settings window and links to `Privacy & Security > Screen Recording`.

## Current UX

- Capture selection is currently the native macOS selection HUD for stability.
- Post-capture thumbnails use a lightweight futuristic glass/HUD treatment.
- The stack stays intentionally small and transient: drag out, close, or wait for expiry.

## Development

Run the app directly from the package during development:

```bash
swift run SlickShotApp
```

Run tests:

```bash
swift test
```

## Release

To build a direct-sale release artifact with Sparkle metadata embedded:

```bash
SLICKSHOT_DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
SLICKSHOT_SPARKLE_PUBLIC_ED_KEY="YOUR_PUBLIC_ED25519_KEY" \
SLICKSHOT_SU_FEED_URL="https://downloads.slick-shot.com/appcast.xml" \
./Scripts/build-release.sh
```

Optional notarization:

```bash
SLICKSHOT_DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
SLICKSHOT_NOTARY_PROFILE="slickshot-notary" \
SLICKSHOT_SPARKLE_PUBLIC_ED_KEY="YOUR_PUBLIC_ED25519_KEY" \
SLICKSHOT_SU_FEED_URL="https://downloads.slick-shot.com/appcast.xml" \
./Scripts/build-release.sh
```

The release script produces `dist/SlickShot.zip`.

To generate or refresh the Sparkle appcast feed after placing release archives in `dist/updates`:

```bash
./Scripts/generate-appcast.sh /Users/yasudanaoki/Desktop/slick-shot/dist/updates
```

## Paid Download Fulfillment

The direct-sale flow is split between Pages and a same-origin Worker:

- Pages serves the landing page and the `/thanks` and `/download` UI routes
- `_redirects` rewrites `/thanks` to `thanks.html` and `/download` to `download.html`
- The Cloudflare Worker is mounted on `https://slick-shot.com/api/*`
- The Worker verifies Stripe sessions, stores purchase state in D1, streams gated downloads from R2, and sends re-download email through Resend

### Required Worker secrets

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`
- `APP_URL=https://slick-shot.com`
- `DOWNLOAD_BASE_URL=https://downloads.slick-shot.com`

### Required infrastructure bindings

- D1 binding: `DB`
- R2 binding: `DOWNLOADS`
- Worker route: `slick-shot.com/api/*`
- Worker route: `www.slick-shot.com/api/*`

### Stripe setup

- Payment Link success URL: `https://slick-shot.com/thanks?session_id={CHECKOUT_SESSION_ID}`
- Webhook endpoint: `https://slick-shot.com/api/stripe/webhook`

### D1 migration

Run the initial schema:

```bash
cd /Users/yasudanaoki/Desktop/slick-shot/cloudflare/worker
npx wrangler d1 execute slick-shot --file ../d1/001_initial_paid_download_flow.sql
```

### Artifact storage

- Upload the notarized release archive to `downloads.slick-shot.com/SlickShot.zip`
- Sparkle `SUFeedURL` should point to `https://downloads.slick-shot.com/appcast.xml`

For direct sales, wire the LP CTA to your Stripe Payment Link and rely on:

- `https://slick-shot.com/thanks?session_id=...` for purchase confirmation
- `https://slick-shot.com/download?token=...` for immediate and emailed re-download links
- the same-origin Worker route so relative `/api/*` requests from static Pages succeed without extra client config

## Hotkey

The default global shortcut is `Control-Option-Command-S`.

SlickShot stores the configured shortcut in `UserDefaults` and falls back to the default when the saved values are missing or invalid.

## Current Limitations

- The development installer uses a local self-managed signing identity; shipping builds still require your real Developer ID certificate.
- Screen Recording permission still needs to be granted manually in macOS.
- Drag-and-drop behavior has automated coverage for temp-file lifecycle, but target-app acceptance is still best verified manually in apps like Slack.
- The capture selection UI is intentionally using the native macOS overlay right now. A custom SlickShot capture HUD is planned on top of this stable baseline.
- The LP still uses placeholder Stripe and download URLs until you wire production values.
