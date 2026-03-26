import CoreGraphics
import Foundation
import Testing

@testable import SlickShotApp
@testable import SlickShotCore

@MainActor
@Test func test_captureCompletion_insertsRecordIntoStore() async throws {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        hasPermission: true,
        result: .success(ScreenCapturePayload(
            imageData: Data([0xCA, 0xFE]),
            sourceDisplay: "Display 1"
        )),
        suspendCapture: true
    )
    let settingsWindowController = TestSettingsWindowController()
    let coordinator = CaptureCoordinator(
        store: store,
        captureService: captureService,
        overlayFactory: overlayFactory,
        settingsWindowController: settingsWindowController
    )

    coordinator.startCapture()
    let session = try #require(overlayFactory.session)

    session.simulateSelection(CGRect(x: 10, y: 20, width: 30, height: 40))

    #expect(store.activeRecords.isEmpty)
    #expect(overlayFactory.session?.endCallCount == 1)
    await captureService.resumeCapture()

    #expect(await waitUntil { store.activeRecords.count == 1 })
    #expect(await waitUntil {
        captureService.capturedRects == [CGRect(x: 10, y: 20, width: 30, height: 40)]
    })

    let record = try #require(store.activeRecords.first)
    #expect(record.imageRepresentation == Data([0xCA, 0xFE]))
    #expect(record.displayThumbnailRepresentation == Data([0xCA, 0xFE]))
    #expect(record.sourceDisplay == "Display 1")
    #expect(record.selectionRect == CGRect(x: 10, y: 20, width: 30, height: 40))
    #expect(settingsWindowController.showMissingPermissionMessageCallCount == 0)
}

@MainActor
@Test func test_captureCancellation_doesNotInsertRecord() {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        hasPermission: true,
        result: .success(ScreenCapturePayload(
            imageData: Data([0x01]),
            sourceDisplay: "Display 1"
        ))
    )
    let settingsWindowController = TestSettingsWindowController()
    let coordinator = CaptureCoordinator(
        store: store,
        captureService: captureService,
        overlayFactory: overlayFactory,
        settingsWindowController: settingsWindowController
    )

    coordinator.startCapture()
    overlayFactory.session?.simulateCancel()

    #expect(store.activeRecords.isEmpty)
    #expect(captureService.capturedRects.isEmpty)
    #expect(overlayFactory.session?.endCallCount == 1)
}

@MainActor
@Test func test_missingPermission_showsSettingsWindowInsteadOfStartingCapture() {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        hasPermission: false,
        result: .success(ScreenCapturePayload(
            imageData: Data([0x01]),
            sourceDisplay: "Display 1"
        ))
    )
    let settingsWindowController = TestSettingsWindowController()
    let coordinator = CaptureCoordinator(
        store: store,
        captureService: captureService,
        overlayFactory: overlayFactory,
        settingsWindowController: settingsWindowController
    )

    coordinator.startCapture()

    #expect(store.activeRecords.isEmpty)
    #expect(overlayFactory.makeSessionCallCount == 0)
    #expect(settingsWindowController.showMissingPermissionMessageCallCount == 1)
}

@MainActor
@Test func test_captureFailureAfterPermissionGranted_reportsFailureWithoutShowingPermissionsWindow() async throws {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        hasPermission: true,
        result: .failure(TestScreenCaptureError.captureFailed),
        suspendCapture: true
    )
    let settingsWindowController = TestSettingsWindowController()
    var reportedFailures: [String] = []
    let coordinator = CaptureCoordinator(
        store: store,
        captureService: captureService,
        overlayFactory: overlayFactory,
        settingsWindowController: settingsWindowController,
        onCaptureFailure: { error in
            reportedFailures.append(String(describing: error))
        }
    )

    coordinator.startCapture()
    let session = try #require(overlayFactory.session)

    session.simulateSelection(CGRect(x: 10, y: 20, width: 30, height: 40))

    #expect(store.activeRecords.isEmpty)
    await captureService.resumeCapture()

    #expect(await waitUntil { reportedFailures == ["captureFailed"] })
    #expect(await waitUntil {
        captureService.capturedRects == [CGRect(x: 10, y: 20, width: 30, height: 40)]
    })

    #expect(store.activeRecords.isEmpty)
    #expect(settingsWindowController.showMissingPermissionMessageCallCount == 0)
    #expect(overlayFactory.session?.endCallCount == 1)
}

@Test func test_overlayDimmingRects_excludeSelectionArea() {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
    let selection = CGRect(x: 20, y: 30, width: 40, height: 20)

    let rects = CaptureOverlayView.dimmingRects(in: bounds, excluding: selection)

    #expect(rects == [
        CGRect(x: 0, y: 50, width: 100, height: 50),
        CGRect(x: 0, y: 0, width: 100, height: 30),
        CGRect(x: 0, y: 30, width: 20, height: 20),
        CGRect(x: 60, y: 30, width: 40, height: 20)
    ])
}

@MainActor
private final class TestCaptureOverlaySessionFactory: CaptureOverlaySessionFactory {
    private(set) var makeSessionCallCount = 0
    private(set) var session: TestCaptureOverlaySession?

    func makeSession(
        onSelection: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) -> CaptureOverlaySession {
        makeSessionCallCount += 1
        let session = TestCaptureOverlaySession(onSelection: onSelection, onCancel: onCancel)
        self.session = session
        return session
    }
}

@MainActor
private final class TestCaptureOverlaySession: CaptureOverlaySession {
    private let onSelection: (CGRect) -> Void
    private let onCancel: () -> Void

    private(set) var beginCallCount = 0
    private(set) var endCallCount = 0

    init(
        onSelection: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSelection = onSelection
        self.onCancel = onCancel
    }

    func begin() {
        beginCallCount += 1
    }

    func end() {
        endCallCount += 1
    }

    func simulateSelection(_ rect: CGRect) {
        onSelection(rect)
    }

    func simulateCancel() {
        onCancel()
    }
}

@MainActor
private final class TestScreenCaptureService: ScreenCaptureServiceProtocol {
    private let hasPermission: Bool
    private let result: Result<ScreenCapturePayload, Error>
    private let suspendCapture: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private var isResumed = false

    private(set) var capturedRects: [CGRect] = []

    init(
        hasPermission: Bool,
        result: Result<ScreenCapturePayload, Error>,
        suspendCapture: Bool = false
    ) {
        self.hasPermission = hasPermission
        self.result = result
        self.suspendCapture = suspendCapture
    }

    func hasScreenRecordingPermission() -> Bool {
        hasPermission
    }

    func captureImage(in rect: CGRect) async throws -> ScreenCapturePayload {
        capturedRects.append(rect)
        if suspendCapture, !isResumed {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        switch result {
        case let .success(payload):
            return payload
        case let .failure(error):
            throw error
        }
    }

    func resumeCapture() async {
        isResumed = true
        continuation?.resume()
        continuation = nil
    }
}

private enum TestScreenCaptureError: Error {
    case captureFailed
}

@MainActor
private final class TestSettingsWindowController: SettingsWindowControlling {
    private(set) var showMissingPermissionMessageCallCount = 0

    func showMissingPermissionMessage() {
        showMissingPermissionMessageCallCount += 1
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
    while true {
        if condition() {
            return true
        }
        if ContinuousClock.now >= deadline {
            return false
        }
        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
}
