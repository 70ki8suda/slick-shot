import AppKit
import Foundation
import Testing

@testable import SlickShotApp

struct CaptureOverlayWindowTests {
    @MainActor
    @Test func begin_capturesPreviousFrontmostAppAndReactivatesItOnEnd() {
        let previousApp = TestRunningApplication(bundleIdentifier: "com.openai.codex")
        let frontmostProvider = TestFrontmostApplicationProvider(frontmostApplication: previousApp)
        let appActivator = TestApplicationActivator()
        let window = CaptureOverlayWindow(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            frontmostProvider: frontmostProvider,
            appActivator: appActivator,
            onSelection: { _ in },
            onCancel: {}
        )

        window.begin()
        window.end()

        #expect(appActivator.activateCallCount == 0)
        #expect(previousApp.activateCallCount == 1)
        #expect(previousApp.lastActivationOptions == [])
    }

    @MainActor
    @Test func begin_doesNotTryToReactivateSlickShotItself() {
        let frontmostProvider = TestFrontmostApplicationProvider(
            frontmostApplication: TestRunningApplication(bundleIdentifier: AppBundleMetadata.bundleIdentifier)
        )
        let appActivator = TestApplicationActivator()
        let window = CaptureOverlayWindow(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            frontmostProvider: frontmostProvider,
            appActivator: appActivator,
            onSelection: { _ in },
            onCancel: {}
        )

        window.begin()
        window.end()

        let frontmostApp = frontmostProvider.frontmostApplication as? TestRunningApplication
        #expect(appActivator.activateCallCount == 0)
        #expect(frontmostApp?.activateCallCount == 0)
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
private final class TestApplicationActivator: ApplicationActivating {
    private(set) var activateCallCount = 0

    func activateSlickShot() {
        activateCallCount += 1
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
