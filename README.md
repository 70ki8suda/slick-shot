# SlickShot

SlickShot is a macOS menu bar utility for transient screenshots.

The capture backend uses ScreenCaptureKit screenshot APIs while preserving the existing region-selection and permission flow.

## What It Does

- Capture a selected screen region from the menu bar or the global hotkey.
- Keep new captures in a temporary thumbnail stack instead of writing to the Desktop.
- Drag thumbnails into other apps via managed temporary PNG files.
- Remove screenshots automatically after successful drag-and-drop or after the retention window expires.
- Show the current shortcut and Screen Recording permission state in the settings window.
- Prompt for a shortcut on first launch when no valid saved hotkey exists.

## Install

Install a Raycast-launchable app bundle into `~/Applications`:

```bash
./Scripts/install-app.sh
```

This creates `~/Applications/SlickShot.app`.

After that you can:

- launch `SlickShot` from Raycast
- launch it directly from Finder or Spotlight
- use the global shortcut after first-launch onboarding

## First Launch

On first launch, SlickShot opens its settings window in onboarding mode when no valid shortcut is saved.

1. Click the shortcut recorder.
2. Press the key combination you want to use.
3. Save it implicitly by finishing the recording.
4. Trigger `Capture Screenshot` once to prompt for Screen Recording permission if needed.

If macOS blocks capture, SlickShot opens the settings window and links to `Privacy & Security > Screen Recording`.

## Development

Run the app directly from the package during development:

```bash
swift run SlickShotApp
```

Run tests:

```bash
swift test
```

## Hotkey

The default global shortcut is `Control-Option-Command-S`.

SlickShot stores the configured shortcut in `UserDefaults` and falls back to the default when the saved values are missing or invalid.

## Current Limitations

- The app is currently unsigned with ad-hoc signing for local development and testing.
- Screen Recording permission still needs to be granted manually in macOS.
- Drag-and-drop behavior has automated coverage for temp-file lifecycle, but target-app acceptance is still best verified manually in apps like Slack.
- The current bundle installer is local-only and does not produce a notarized release artifact.
```bash
./Scripts/install-app.sh
```

This creates `~/Applications/SlickShot.app`, which Raycast can launch through its normal application search.

On first use, macOS Screen Recording permission is required. If permission is missing, SlickShot opens its settings window and provides a shortcut to the `Privacy & Security > Screen Recording` pane.

## Hotkey behavior

The default global shortcut is `Control-Option-Command-S`.

On first launch, or whenever the stored hotkey values are missing or invalid, SlickShot opens its settings window in shortcut onboarding mode so you can record a replacement key combination.

SlickShot resolves the shortcut from its stored hotkey configuration and falls back to that default if the stored values are missing or invalid until you save a new shortcut.
