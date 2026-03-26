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
- Create: `Sources/SlickShotCore/ScreenshotStore.swift`
- Create: `Tests/SlickShotCoreTests/ScreenshotStoreTests.swift`

- [ ] **Step 1: Write the failing store tests**

```swift
func test_insert_createsPendingRecordWithFiveMinuteExpiry() {
  let now = Date(timeIntervalSince1970: 1_000)
  let store = ScreenshotStore(now: { now })
  let id = store.insert(image: .stub(), sourceDisplay: "main", selectionRect: CGRect(x: 10, y: 20, width: 30, height: 40))

  let record = try XCTUnwrap(store.activeRecords.first)
  XCTAssertEqual(record.id, id)
  XCTAssertEqual(record.status, .pending)
  XCTAssertEqual(record.expiresAt, now.addingTimeInterval(300))
}

func test_delete_removesExistingRecordImmediately() {
  let store = ScreenshotStore(now: Date.init)
  let id = store.insert(image: .stub(), sourceDisplay: "main", selectionRect: .zero)

  store.delete(id: id)

  XCTAssertTrue(store.activeRecords.isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScreenshotStoreTests`
Expected: FAIL because `ScreenshotStore` does not exist yet

- [ ] **Step 3: Add package manifest and minimal store implementation**

Create the executable and test targets. Add a minimal `ScreenshotStore` with insert/delete/list APIs and deterministic clock injection for expiry timestamps. Define `ScreenshotRecord` with the v1 core fields needed by later tasks: `id`, `createdAt`, `expiresAt`, `status`, `imageRepresentation`, `displayThumbnailRepresentation`, `sourceDisplay`, `selectionRect`, and optional `temporaryBackingURL`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ScreenshotStoreTests`
Expected: PASS

- [ ] **Step 5: Add minimal AppKit entry point**

Create a menu bar app with:
- a status item
- a `Capture Screenshot` menu action stub that is intentionally a no-op in this chunk and becomes functional in Task 4
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
func test_markDropped_transitionsPendingRecordToDropped() { ... }
func test_expireRemovesRecordsOlderThanFiveMinutes() { ... }
func test_markDragging_pausesExpiryUntilDragEnds() { ... }
func test_activeRecords_returnsNewestFirstAcrossPendingStates() { ... }
func test_reconcileExpiryOnAppDidBecomeActive_removesExpiredRecordsAfterResume() { ... }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScreenshotStoreTests`
Expected: FAIL because lifecycle and ordered active-record behavior are missing

- [ ] **Step 3: Implement minimal lifecycle logic**

Add:
- `ScreenshotStatus`
- 5-minute retention expiry
- ordered active record listing
- `markDragging` transition and timer pause/resume behavior
- timestamp-based expiry reconciliation invoked on app resume/background return via `applicationDidBecomeActive`
- drop/delete transitions
- store change publication so AppKit overlay controllers can observe updates without owning lifecycle logic

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
- Create: `Sources/SlickShotApp/ThumbnailStackPresenter.swift`
- Create: `Sources/SlickShotApp/ThumbnailStackView.swift`
- Create: `Sources/SlickShotApp/ThumbnailItemView.swift`
- Modify: `Sources/SlickShotApp/AppDelegate.swift`
- Create: `Tests/SlickShotAppTests/ThumbnailStackPresenterTests.swift`

- [ ] **Step 1: Write failing tests for presentation ordering**

```swift
func test_presenter_ordersNewestActiveRecordsFirst() { ... }
func test_presenter_capsVisibleItemsAtThree() { ... }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScreenshotStoreTests`
Expected: FAIL until overlay-facing presentation behavior is implemented in `ThumbnailStackPresenter`

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
- Create: `Sources/SlickShotApp/SettingsWindowController.swift`
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
- permission gating that routes missing permissions into the settings/status window instead of attempting capture
- settings/status copy that explicitly says `Screen Recording access is required for SlickShot to capture screenshots.` and opens the macOS `Privacy & Security > Screen Recording` pane

- [ ] **Step 4: Verify manual capture works**

Run: `swift run SlickShotApp`
Expected: choosing `Capture Screenshot` opens the selector and produces an overlay thumbnail

Run: `swift run SlickShotApp`
Expected: pressing `Escape` during selection cancels capture and leaves no new store entry or thumbnail

- [ ] **Step 5: Verify missing-permission behavior**

Run: `swift run SlickShotApp`
Expected: on a machine without the required permission, capture does not fail silently and the settings/status window explains the missing access

- [ ] **Step 6: Commit**

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

Create temp PNG files on drag start, expose them through pasteboard/file URL drag payloads, and clean them up on successful drop, rejected-drag recovery, expiry, manual delete, and startup recovery of stale temp files.

- [ ] **Step 4: Verify manual drag behavior**

Run: `swift run SlickShotApp`
Expected: dragging a thumbnail into a file-accepting app transfers the image and removes it from SlickShot on success

Run: `swift run SlickShotApp`
Expected: if a drag is rejected, the thumbnail remains available and still expires normally later

Run: `swift test --filter TemporaryFileManagerTests`
Expected: PASS, including startup cleanup coverage for stale temporary files

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: add drag transfer cleanup"
```

### Task 6: Add configurable global hotkey and final polish

**Files:**
- Create: `Sources/SlickShotApp/HotkeyMonitor.swift`
- Modify: `Sources/SlickShotApp/AppDelegate.swift`
- Modify: `Sources/SlickShotApp/StatusItemController.swift`
- Modify: `README.md`
- Create: `Tests/SlickShotCoreTests/HotkeyConfigurationTests.swift`

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
- startup cleanup trigger for stale temporary drag files

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
