# SlickShot

SlickShot is a macOS menu bar utility for transient screenshots.

It uses the native macOS interactive region capture flow, then routes the result into a temporary HUD-style thumbnail instead of writing files to the Desktop.

## Direct Sale + Auto Updates

SlickShot is set up for a direct-sale flow:

- LP + Stripe Checkout for the purchase
- `thanks.html` / `download.html` pages for the post-purchase handoff
- Sparkle for in-app automatic updates
- Developer ID signing + notarized release artifacts for website distribution

Relevant files:

- `docs/lp/index.html`
- `docs/lp/thanks.html`
- `docs/lp/download.html`
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
SLICKSHOT_SU_FEED_URL="https://downloads.slickshot.app/appcast.xml" \
./Scripts/build-release.sh
```

Optional notarization:

```bash
SLICKSHOT_DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
SLICKSHOT_NOTARY_PROFILE="slickshot-notary" \
SLICKSHOT_SPARKLE_PUBLIC_ED_KEY="YOUR_PUBLIC_ED25519_KEY" \
SLICKSHOT_SU_FEED_URL="https://downloads.slickshot.app/appcast.xml" \
./Scripts/build-release.sh
```

The release script produces `dist/SlickShot.zip`.

To generate or refresh the Sparkle appcast feed after placing release archives in `dist/updates`:

```bash
./Scripts/generate-appcast.sh /Users/yasudanaoki/Desktop/slick-shot/dist/updates
```

For direct sales, wire the LP CTA to your Stripe Payment Link and use:

- Stripe success URL -> `docs/lp/thanks.html`
- Download CTA -> your hosted `SlickShot.zip` or `SlickShot.dmg`
- Sparkle `SUFeedURL` -> your hosted `appcast.xml`

## Hotkey

The default global shortcut is `Control-Option-Command-S`.

SlickShot stores the configured shortcut in `UserDefaults` and falls back to the default when the saved values are missing or invalid.

## Current Limitations

- The development installer uses a local self-managed signing identity; shipping builds still require your real Developer ID certificate.
- Screen Recording permission still needs to be granted manually in macOS.
- Drag-and-drop behavior has automated coverage for temp-file lifecycle, but target-app acceptance is still best verified manually in apps like Slack.
- The capture selection UI is intentionally using the native macOS overlay right now. A custom SlickShot capture HUD is planned on top of this stable baseline.
- The LP still uses placeholder Stripe and download URLs until you wire production values.
