# SlickShot Design

## Summary

SlickShot is a macOS-native utility that replaces the user's current screenshot handoff flow:

1. Take a region screenshot.
2. Avoid saving it to the Desktop.
3. Surface it in a transient thumbnail near the bottom-right corner of the screen.
4. Drag it into Slack, AI tools, GitHub, or other apps.
5. Remove it automatically after a successful drop.

The product goal is not long-term screenshot management. It is a lightweight transfer buffer optimized for QA and communication workflows where screenshots are temporary and disposable.

## Problem

The user's current workflow is:

1. Take a macOS screenshot with `command + shift + 4`.
2. Let macOS save the file to the Desktop.
3. Drag the saved file into another app.
4. Delete the file afterward.

This works, but it creates repeated friction:

- Desktop clutter from temporary screenshots.
- Manual cleanup after almost every handoff.
- A mismatch between the screenshot's actual lifespan and its treatment as a permanent file.

## Goals

- Provide a native-feeling region screenshot workflow with a custom shortcut.
- Keep screenshots out of the Desktop and other user-visible persistent folders.
- Show the latest capture as a transient bottom-right thumbnail similar to macOS screenshot previews.
- Allow direct drag-and-drop from the thumbnail into other apps.
- Remove screenshots automatically after a successful drop.
- Remove screenshots automatically after 5 minutes if unused.
- Allow explicit one-click deletion with a visible trash affordance.

## Non-Goals

- Replacing every macOS screenshot mode in v1.
- Supporting full-screen or window capture in v1.
- Providing image editing, annotation, renaming, or export flows.
- Acting as a screenshot history manager or gallery.
- Syncing screenshots across devices or cloud services.
- Automatically copying captures to the clipboard by default.

## Product Decisions

### Capture Model

- v1 supports region capture only.
- The app is triggered by a custom global shortcut, not by overriding `command + shift + 4`.
- The capture interaction should feel close to the native macOS region selector, but it does not need to be a byte-for-byte clone.

### Post-Capture UI

- After a capture succeeds, a transient thumbnail appears near the bottom-right corner of the active screen.
- If multiple screenshots are captured in sequence, the newest item appears in front and at most two older items remain slightly visible behind it.
- The stack should still read visually as a native-style screenshot preview, not as a persistent shelf or tray.

### Deletion Model

- On successful drag-and-drop into another app, the screenshot animates out over roughly 0.5 seconds and is then deleted.
- Each thumbnail also exposes a trash affordance for explicit deletion.
- Any screenshot that is neither dropped nor deleted manually is removed automatically 5 minutes after capture.

## User Experience

### Primary Flow

1. User presses the custom global shortcut.
2. SlickShot presents a full-screen capture overlay.
3. User drags to select a screen region.
4. On mouse-up, SlickShot captures the region.
5. The result is stored in a temporary in-app store instead of the Desktop.
6. A thumbnail preview appears in the bottom-right corner.
7. The user drags the thumbnail into another app.
8. If the target accepts the drop, SlickShot plays a short shrink-and-fade animation and removes the screenshot.

### Secondary Flows

- If the user takes another screenshot before using the first one, the new capture becomes the frontmost thumbnail while older captures remain partially visible behind it.
- If the user decides not to use a screenshot, they can click the trash affordance to remove it immediately.
- If the user ignores the screenshot, SlickShot removes it automatically after 5 minutes.

### Cancellation

- If the user exits the overlay without completing a selection, no image is created and no thumbnail is shown.
- Cancellation should feel silent and low-friction.

## Architecture

SlickShot should be implemented as a new standalone macOS repository using Swift and AppKit. v1 does not need a cross-platform runtime or web-based UI shell.

The app is organized around four main units.

### 1. `CaptureCoordinator`

Responsibilities:

- Register and respond to the global shortcut.
- Launch and dismiss the capture overlay.
- Orchestrate region selection and capture completion.
- Pass successful captures into the temporary store.

Interface expectations:

- Exposes a `beginCapture()`-style entry point.
- Emits either `captureCancelled` or `captureCompleted(image, metadata)`.

### 2. `ScreenshotStore`

Responsibilities:

- Hold active screenshots and their metadata.
- Track lifecycle state such as `pending`, `dragging`, `dropped`, `expired`, and `deleted`.
- Start and cancel 5-minute expiration timers.
- Remove screenshots after successful drop or explicit delete.

Interface expectations:

- Supports insert, list-active, mark-dragging, mark-dropped, delete, and expire operations.
- Publishes store changes so UI overlays can react without owning state logic.

### 3. `ThumbnailOverlayController`

Responsibilities:

- Render the transient bottom-right thumbnail UI.
- Maintain the visual stack rule: one foreground item and up to two visible background items.
- Expose hover and deletion affordances.
- Play arrival and dismissal animations.

Interface expectations:

- Observes the active screenshot list from `ScreenshotStore`.
- Renders based on presentation state only, without making retention decisions itself.

### 4. `DragSessionProvider`

Responsibilities:

- Make a thumbnail draggable to external macOS apps.
- Provide the drag payload in a format acceptable to common drop targets.
- Detect drop success vs. cancellation.
- Inform `ScreenshotStore` when the drop completed successfully.

Interface expectations:

- Starts drag sessions from thumbnail interactions.
- Reports completion events back to the store or coordinator.

## Data Model

Each active screenshot record should contain:

- `id`
- `createdAt`
- `expiresAt`
- `imageRepresentation`
- `displayThumbnailRepresentation`
- `status`
- `sourceDisplay`
- `selectionRect`
- `temporaryBackingURL` if one is created for drag interoperability

v1 should prefer in-memory ownership of screenshots. However, some drag targets may require file-backed transfer. To handle this, SlickShot may materialize a temporary file inside an app-managed temporary directory only when needed for drag interoperability, then remove it after a successful drop or timeout-based cleanup.

## Permissions and System Integration

### Required Permissions

- Screen recording permission is required for region capture.
- Depending on the shortcut registration mechanism, accessibility permission may also be required.

### Permission UX

- If a required permission is missing, SlickShot should surface a small settings/status window from the menu bar app.
- The UI should explain exactly what permission is missing and how to open the corresponding macOS settings pane.
- Failed capture attempts due to missing permissions should fail clearly, not silently.

### Global Shortcut

- The shortcut is configurable, but the initial default can be chosen during implementation.
- If shortcut registration fails because of a conflict or system restriction, the user should see that state in the settings UI and be able to change it.

## Error Handling

### Missing Permissions

- Prevent starting capture if the required permission state is not satisfied.
- Surface a clear explanation and a path to resolve it.

### Capture Cancellation

- Region selection cancellation should leave no stored image and no stale UI.

### Drag Failure or Drop Rejection

- If the user starts dragging but the target does not accept the drop, the screenshot remains active.
- The thumbnail returns to its prior state and the 5-minute expiration timer continues.

### Temporary File Cleanup

- Any temporary drag backing file must be removed after successful drop.
- Cleanup should also run on timer expiry, manual delete, and app restart recovery.

### Timer Accuracy and Consistency

- Expiration should be based on capture timestamp, not UI visibility alone.
- If the app is briefly suspended or backgrounded, expiry reconciliation should occur on resume.

## Visual and Interaction Rules

- The thumbnail should feel close to the native macOS screenshot preview: compact, floating, polished, and non-intrusive.
- The UI should not read as a file manager, gallery, dock, or inbox.
- Dragging should begin naturally from the thumbnail body, not only from a tiny handle.
- The trash affordance should be easy to discover on hover without making the UI noisy at rest.
- Success removal should animate over about 0.5 seconds with a shrink-and-fade effect.

## Testing Strategy

### Unit Tests

- `ScreenshotStore` lifecycle transitions.
- Expiration timer behavior.
- Cleanup rules for manual delete, successful drop, and expiry.
- Visual stacking selection logic for active items.

### Integration Tests

- Capture completion inserts into the store and updates the overlay.
- Successful drop transitions the item into animated removal and deletion.
- Rejected drop leaves the item available.
- Missing permission states produce the expected settings or warning path.

### Manual QA

- Repeated rapid captures.
- Dragging into Slack.
- Dragging into GitHub issue/comment fields.
- Dragging into AI chat tools that accept image drops.
- Permission onboarding on a fresh macOS install.
- App restart while pending screenshots exist or temporary files remain.

## Open Implementation Choices

These items are intentionally left for implementation planning rather than product design changes:

- Exact API choice for region capture implementation.
- Exact mechanism for global shortcut registration.
- Exact UI technology for the settings/status window.

They do not change the product scope or user-facing behavior defined in this spec.

## Success Criteria

The v1 implementation is successful if:

- The user can trigger region capture from a custom shortcut.
- Captures do not land on the Desktop in the normal flow.
- Captures appear as transient bottom-right thumbnails.
- The user can drag those thumbnails directly into external apps.
- Successful drops remove the screenshot automatically after a short animation.
- Unused captures can be deleted manually and also expire after 5 minutes.
- The app feels meaningfully faster and less cluttered than the user's current Desktop-based flow.
