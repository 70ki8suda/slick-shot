# SlickShot Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working macOS prototype that captures a selected region into a transient thumbnail stack instead of the Desktop and supports drag-to-share with timed cleanup.

**Architecture:** Use a Swift Package executable with an AppKit app lifecycle so the prototype can run with `swift run` on a machine that has Command Line Tools but not full Xcode. Keep business logic in focused `Sources/SlickShotCore` types that are tested independently, and keep AppKit UI orchestration in `Sources/SlickShotApp`.

**Tech Stack:** Swift 6, AppKit, CoreGraphics, Carbon hotkey APIs, XCTest, Swift Package Manager

---

## Chunk 1: Bootstrap, lifecycle, and retention core

### Task 1: Create the package and app entry point

**Files:**
- Create: `Package.swift`
- Create: `Sources/SlickShotApp/main.swift`
- Create: `Sources/SlickShotApp/AppDelegate.swift`
- Create: `Sources/SlickShotApp/StatusItemController.swift`
- Create: `Sources/SlickShotCore/ScreenshotRecord.swift`
- Create: `Tests/SlickShotCoreTests/ScreenshotStoreTests.swift`

- [ ] **Step 1: Write the failing store tests**

```swift
func test_insert_creates_pending_record_with_expiry() { ... }
func test_delete_removes_record() { ... }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScreenshotStoreTests`
Expected: FAIL because `ScreenshotStore` does not exist yet

- [ ] **Step 3: Add package manifest and minimal store implementation**

Create the executable and test targets. Add a minimal `ScreenshotStore` with insert/delete/list APIs and deterministic clock injection for expiry timestamps.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ScreenshotStoreTests`
Expected: PASS

- [ ] **Step 5: Add minimal AppKit entry point**

Create a menu bar app with:
- a status item
- a `Capture Screenshot` menu action placeholder
- a `Quit SlickShot` menu action

- [ ] **Step 6: Verify the prototype launches**

Run: `swift run SlickShotApp`
Expected: app starts without compile errors and shows a menu bar item

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: bootstrap SlickShot menu bar prototype"
```

### Task 2: Implement screenshot retention and expiry logic

**Files:**
- Create: `Sources/SlickShotCore/ScreenshotStore.swift`
- Modify: `Sources/SlickShotCore/ScreenshotRecord.swift`
- Modify: `Tests/SlickShotCoreTests/ScreenshotStoreTests.swift`

- [ ] **Step 1: Write failing tests for lifecycle transitions**

```swift
func test_markDropped_transitions_record() { ... }
func test_expireRemovesOldRecordsAfterRetention() { ... }
func test_visibleStack_returns_latest_three_records() { ... }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScreenshotStoreTests`
Expected: FAIL because lifecycle and visible-stack behavior are missing

- [ ] **Step 3: Implement minimal lifecycle logic**

Add:
- `ScreenshotStatus`
- retention expiry
- visible stack selection for newest three records
- drop/delete transitions

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ScreenshotStoreTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SlickShotCore Tests/SlickShotCoreTests
git commit -m "feat: add screenshot lifecycle store"
```

## Chunk 2: Overlay, capture, drag-and-drop, and hotkey

### Task 3: Render the transient thumbnail overlay

**Files:**
- Create: `Sources/SlickShotApp/ThumbnailOverlayController.swift`
- Create: `Sources/SlickShotApp/ThumbnailStackView.swift`
- Create: `Sources/SlickShotApp/ThumbnailItemView.swift`
- Modify: `Sources/SlickShotApp/AppDelegate.swift`
- Modify: `Sources/SlickShotCore/ScreenshotStore.swift`

- [ ] **Step 1: Write failing tests for presentation ordering**

```swift
func test_visibleStack_orders_newest_first() { ... }
func test_visibleStack_caps_background_items_at_three_total() { ... }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScreenshotStoreTests`
Expected: FAIL until overlay-facing ordering behavior is finalized

- [ ] **Step 3: Implement bottom-right overlay UI**

Render:
- one foreground thumbnail
- up to two offset background thumbnails
- hoverable trash button
- insert/remove animations

- [ ] **Step 4: Verify the app shows a thumbnail from a seeded record**

Run: `swift run SlickShotApp`
Expected: launching a debug-seeded record shows the overlay in the bottom-right corner

- [ ] **Step 5: Commit**

```bash
git add Sources/SlickShotApp Sources/SlickShotCore Tests
git commit -m "feat: add thumbnail overlay stack"
```

### Task 4: Add region capture overlay and image creation

**Files:**
- Create: `Sources/SlickShotApp/CaptureCoordinator.swift`
- Create: `Sources/SlickShotApp/CaptureOverlayWindow.swift`
- Create: `Sources/SlickShotApp/CaptureOverlayView.swift`
- Create: `Sources/SlickShotApp/ScreenCaptureService.swift`
- Modify: `Sources/SlickShotApp/StatusItemController.swift`
- Modify: `Sources/SlickShotApp/AppDelegate.swift`
- Modify: `Tests/SlickShotCoreTests/ScreenshotStoreTests.swift`

- [ ] **Step 1: Write a failing integration-style test for capture completion insertion**

```swift
func test_captureCompletion_insertsRecordIntoStore() { ... }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScreenshotStoreTests`
Expected: FAIL because capture completion plumbing is missing

- [ ] **Step 3: Implement minimal region capture**

Build:
- full-screen dimming overlay
- click-drag rectangle selection
- cancel with `Escape`
- capture selected rect into `NSImage`
- insertion into `ScreenshotStore`

- [ ] **Step 4: Verify manual capture works**

Run: `swift run SlickShotApp`
Expected: choosing `Capture Screenshot` opens the selector and produces an overlay thumbnail

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: add region capture flow"
```

### Task 5: Add drag-and-drop and transient file cleanup

**Files:**
- Create: `Sources/SlickShotApp/DragSessionProvider.swift`
- Create: `Sources/SlickShotCore/TemporaryFileManager.swift`
- Modify: `Sources/SlickShotApp/ThumbnailItemView.swift`
- Modify: `Sources/SlickShotCore/ScreenshotStore.swift`
- Create: `Tests/SlickShotCoreTests/TemporaryFileManagerTests.swift`

- [ ] **Step 1: Write failing tests for temp file creation and cleanup**

```swift
func test_writePNG_createsTemporaryFile() { ... }
func test_cleanupRemovesTemporaryFile() { ... }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TemporaryFileManagerTests`
Expected: FAIL because the manager does not exist yet

- [ ] **Step 3: Implement drag payload creation**

Create temp PNG files on drag start, expose them through pasteboard/file URL drag payloads, and clean them up on successful drop, expiry, and manual delete.

- [ ] **Step 4: Verify manual drag behavior**

Run: `swift run SlickShotApp`
Expected: dragging a thumbnail into a file-accepting app transfers the image and removes it from SlickShot on success

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: add drag transfer cleanup"
```

### Task 6: Add configurable global hotkey and final polish

**Files:**
- Create: `Sources/SlickShotApp/HotkeyMonitor.swift`
- Create: `Sources/SlickShotApp/SettingsWindowController.swift`
- Modify: `Sources/SlickShotApp/AppDelegate.swift`
- Modify: `Sources/SlickShotApp/StatusItemController.swift`
- Modify: `README.md`

- [ ] **Step 1: Write the failing tests for hotkey preference parsing**

```swift
func test_defaultShortcut_isPresent() { ... }
func test_invalidShortcut_fallsBackToDefault() { ... }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter Hotkey`
Expected: FAIL because the shortcut preference type does not exist yet

- [ ] **Step 3: Implement minimal configurable hotkey support**

Add:
- a default shortcut
- Carbon hotkey registration
- a small settings window with current shortcut text and permission state

- [ ] **Step 4: Verify the end-to-end flow**

Run: `swift test`
Expected: PASS

Run: `swift run SlickShotApp`
Expected: the app launches, capture can be triggered from the menu and hotkey, thumbnails can be dragged away, and stale screenshots disappear after retention

- [ ] **Step 5: Commit**

```bash
git add README.md Sources Tests
git commit -m "feat: add hotkey-driven screenshot workflow"
```
