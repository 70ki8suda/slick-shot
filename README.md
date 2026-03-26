# SlickShot

SlickShot is a macOS menu bar utility for transient screenshots.

## Current feature set

- Capture a selected screen region from the menu bar or the global hotkey.
- Keep new captures in a temporary thumbnail stack instead of writing to the Desktop.
- Drag thumbnails into other apps via managed temporary PNG files.
- Remove screenshots automatically after successful drag-and-drop or after the retention window expires.
- Show the current shortcut and Screen Recording permission state in the settings window.

## Run locally

SlickShot is currently developed and run as a Swift Package executable:

```bash
swift run SlickShotApp
```

On first use, macOS Screen Recording permission is required. If permission is missing, SlickShot opens its settings window and provides a shortcut to the `Privacy & Security > Screen Recording` pane.

## Hotkey behavior

The default global shortcut is `Control-Option-Command-S`.

SlickShot resolves the shortcut from its stored hotkey configuration and falls back to that default if the stored values are missing or invalid.
