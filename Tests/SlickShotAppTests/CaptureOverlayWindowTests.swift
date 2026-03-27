import AppKit
import Foundation
import Testing

@testable import SlickShotApp

struct CaptureOverlayWindowTests {
    @MainActor
    @Test func end_doesNotReactivatePreviousFrontmostApp() {
        let previousApp = TestRunningApplication(bundleIdentifier: "com.openai.codex")
        let frontmostProvider = TestFrontmostApplicationProvider(frontmostApplication: previousApp)
        let window = CaptureOverlayWindow(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            frontmostProvider: frontmostProvider,
            onSelection: { _ in },
            onCancel: {}
        )

        window.begin()
        window.end()

        #expect(previousApp.activateCallCount == 0)
        #expect(previousApp.lastActivationOptions == nil)
    }

    @MainActor
    @Test func begin_doesNotTryToReactivateSlickShotItself() {
        let frontmostProvider = TestFrontmostApplicationProvider(
            frontmostApplication: TestRunningApplication(bundleIdentifier: AppBundleMetadata.bundleIdentifier)
        )
        let window = CaptureOverlayWindow(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            frontmostProvider: frontmostProvider,
            onSelection: { _ in },
            onCancel: {}
        )

        window.begin()
        window.end()

        let frontmostApp = frontmostProvider.frontmostApplication as? TestRunningApplication
        #expect(frontmostApp?.activateCallCount == 0)
    }

    @MainActor
    @Test func standardMode_keepsOverlayOutOfScreenRecordings() {
        let window = CaptureOverlayWindow(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            presentationMode: .standard,
            onSelection: { _ in },
            onCancel: {}
        )

        #expect(window.level == .screenSaver)
        #expect(window.sharingType == .none)
    }

    @MainActor
    @Test func demoRecordingMode_usesRecordableWindowSettings() {
        let window = CaptureOverlayWindow(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            presentationMode: .demoRecording,
            onSelection: { _ in },
            onCancel: {}
        )

        #expect(window.level == .statusBar)
        #expect(window.sharingType == .readOnly)
    }
}

@MainActor
private final class TestFrontmostApplicationProvider: FrontmostApplicationProviding {
    let frontmostApplication: (any RunningApplicationActivating)?

    init(frontmostApplication: (any RunningApplicationActivating)?) {
        self.frontmostApplication = frontmostApplication
    }

    func currentFrontmostApplication() -> (any RunningApplicationActivating)? {
        frontmostApplication
    }
}

@MainActor
private final class TestRunningApplication: RunningApplicationActivating {
    let bundleIdentifier: String?
    private(set) var activateCallCount = 0
    private(set) var lastActivationOptions: NSApplication.ActivationOptions?

    init(bundleIdentifier: String?) {
        self.bundleIdentifier = bundleIdentifier
    }

    func activate(options: NSApplication.ActivationOptions) -> Bool {
        activateCallCount += 1
        lastActivationOptions = options
        return true
    }
}
