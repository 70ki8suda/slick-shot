import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit
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
            sourceDisplay: "Display 1",
            selectionRect: CGRect(x: 10, y: 20, width: 30, height: 40)
        )),
        suspendCapture: true
    )
    let feedbackPlayer = TestCaptureFeedbackPlayer()
    let settingsWindowController = TestSettingsWindowController()
    let coordinator = CaptureCoordinator(
        store: store,
        captureService: captureService,
        overlayFactory: overlayFactory,
        settingsWindowController: settingsWindowController,
        feedbackPlayer: feedbackPlayer
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
    #expect(feedbackPlayer.captureCompletedCallCount == 1)
}

@MainActor
@Test func test_nativeInteractiveCapture_insertsRecordWithoutOverlay() async {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        flow: .nativeInteractiveSelection,
        hasPermission: true,
        result: .success(ScreenCapturePayload(
            imageData: Data([0xBA, 0xBE]),
            sourceDisplay: "Display",
            selectionRect: CGRect(x: 1441, y: 100, width: 1, height: 1)
        ))
    )
    let feedbackPlayer = TestCaptureFeedbackPlayer()
    let settingsWindowController = TestSettingsWindowController()
    let coordinator = CaptureCoordinator(
        store: store,
        captureService: captureService,
        overlayFactory: overlayFactory,
        settingsWindowController: settingsWindowController,
        feedbackPlayer: feedbackPlayer,
        beforeCapture: {}
    )

    coordinator.startCapture()

    #expect(await waitUntil { captureService.interactiveCaptureCallCount == 1 })
    #expect(overlayFactory.makeSessionCallCount == 0)
    #expect(await waitUntil { store.activeRecords.count == 1 })
    #expect(settingsWindowController.showMissingPermissionMessageCallCount == 0)
    #expect(feedbackPlayer.captureCompletedCallCount == 1)
    #expect(store.activeRecords.first?.selectionRect == CGRect(x: 800, y: 600, width: 1, height: 1))
}

@MainActor
@Test func test_nativeInteractiveCaptureCancellation_doesNotInsertRecord() async {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        flow: .nativeInteractiveSelection,
        hasPermission: true,
        interactiveResult: nil,
        result: .success(ScreenCapturePayload(
            imageData: Data([0xBA, 0xBE]),
            sourceDisplay: "Display",
            selectionRect: CGRect(x: 1441, y: 100, width: 1, height: 1)
        ))
    )
    let feedbackPlayer = TestCaptureFeedbackPlayer()
    let settingsWindowController = TestSettingsWindowController()
    let coordinator = CaptureCoordinator(
        store: store,
        captureService: captureService,
        overlayFactory: overlayFactory,
        settingsWindowController: settingsWindowController,
        feedbackPlayer: feedbackPlayer,
        beforeCapture: {}
    )

    coordinator.startCapture()

    #expect(await waitUntil { captureService.interactiveCaptureCallCount == 1 })
    #expect(overlayFactory.makeSessionCallCount == 0)
    #expect(store.activeRecords.isEmpty)
    #expect(settingsWindowController.showMissingPermissionMessageCallCount == 0)
    #expect(feedbackPlayer.captureCompletedCallCount == 0)
}

@MainActor
@Test func test_captureCompletion_waitsForOverlaySettleBeforeCapturing() async throws {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        hasPermission: true,
        result: .success(ScreenCapturePayload(
            imageData: Data([0xCA, 0xFE]),
            sourceDisplay: "Display 1",
            selectionRect: CGRect(x: 10, y: 20, width: 30, height: 40)
        ))
    )
    let settingsWindowController = TestSettingsWindowController()
    let settleGate = TestAsyncGate()
    let coordinator = CaptureCoordinator(
        store: store,
        captureService: captureService,
        overlayFactory: overlayFactory,
        settingsWindowController: settingsWindowController,
        beforeCapture: {
            await settleGate.wait()
        }
    )

    coordinator.startCapture()
    let session = try #require(overlayFactory.session)
    session.simulateSelection(CGRect(x: 10, y: 20, width: 30, height: 40))

    #expect(overlayFactory.session?.endCallCount == 1)
    #expect(store.activeRecords.isEmpty)
    #expect(captureService.capturedRects.isEmpty)

    await settleGate.open()

    #expect(await waitUntil { captureService.capturedRects.count == 1 })
    #expect(await waitUntil { store.activeRecords.count == 1 })
}

@MainActor
@Test func test_captureCancellation_doesNotInsertRecord() {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        hasPermission: true,
        result: .success(ScreenCapturePayload(
            imageData: Data([0x01]),
            sourceDisplay: "Display 1",
            selectionRect: CGRect(x: 10, y: 20, width: 30, height: 40)
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
@Test func test_captureFailure_doesNotPlayCompletionFeedback() async {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        hasPermission: true,
        result: .failure(TestScreenCaptureError.captureFailed)
    )
    let feedbackPlayer = TestCaptureFeedbackPlayer()
    let settingsWindowController = TestSettingsWindowController()
    let coordinator = CaptureCoordinator(
        store: store,
        captureService: captureService,
        overlayFactory: overlayFactory,
        settingsWindowController: settingsWindowController,
        feedbackPlayer: feedbackPlayer,
        onCaptureFailure: { _ in }
    )

    coordinator.startCapture()
    overlayFactory.session?.simulateSelection(CGRect(x: 10, y: 20, width: 30, height: 40))
    _ = await waitUntil { captureService.capturedRects.count == 1 }

    #expect(store.activeRecords.isEmpty)
    #expect(feedbackPlayer.captureCompletedCallCount == 0)
}

@MainActor
@Test func test_startCapture_beginsOverlayEvenWhenPermissionPreflightIsFalse() {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        hasPermission: false,
        result: .success(ScreenCapturePayload(
            imageData: Data([0x01]),
            sourceDisplay: "Display 1",
            selectionRect: CGRect(x: 10, y: 20, width: 30, height: 40)
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
    #expect(overlayFactory.makeSessionCallCount == 1)
    #expect(overlayFactory.session?.beginCallCount == 1)
    #expect(captureService.requestPermissionCallCount == 0)
    #expect(settingsWindowController.showMissingPermissionMessageCallCount == 0)
}

@MainActor
@Test func test_missingPermission_showsSettingsWithoutAutoRequestAfterCaptureFailure() async {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        hasPermission: false,
        requestPermissionResult: false,
        result: .failure(TestScreenCaptureError.permissionDenied)
    )
    let settingsWindowController = TestSettingsWindowController()
    let coordinator = CaptureCoordinator(
        store: store,
        captureService: captureService,
        overlayFactory: overlayFactory,
        settingsWindowController: settingsWindowController
    )

    coordinator.startCapture()
    overlayFactory.session?.simulateSelection(CGRect(x: 10, y: 20, width: 30, height: 40))

    #expect(await waitUntil { captureService.capturedRects.count == 1 })
    #expect(overlayFactory.makeSessionCallCount == 1)
    #expect(captureService.requestPermissionCallCount == 0)
    #expect(await waitUntil { settingsWindowController.showMissingPermissionMessageCallCount == 1 })
}

@MainActor
@Test func test_permissionDeniedCapture_doesNotReportGenericFailureWhenPromptAccepted() async {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        hasPermission: false,
        requestPermissionResult: true,
        result: .failure(TestScreenCaptureError.permissionDenied)
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
    overlayFactory.session?.simulateSelection(CGRect(x: 10, y: 20, width: 30, height: 40))
    _ = await waitUntil { captureService.capturedRects.count == 1 }

    #expect(captureService.requestPermissionCallCount == 0)
    #expect(settingsWindowController.showMissingPermissionMessageCallCount == 1)
    #expect(reportedFailures.isEmpty)
}

@MainActor
@Test func test_permissionDeniedCapture_whenPermissionAlreadyGranted_reportsFailureWithoutPromptLoop() async {
    let store = ScreenshotStore(now: { Date(timeIntervalSince1970: 1_000) })
    let overlayFactory = TestCaptureOverlaySessionFactory()
    let captureService = TestScreenCaptureService(
        hasPermission: true,
        requestPermissionResult: false,
        result: .failure(TestScreenCaptureError.permissionDenied)
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
    overlayFactory.session?.simulateSelection(CGRect(x: 10, y: 20, width: 30, height: 40))

    #expect(await waitUntil { captureService.capturedRects.count == 1 })
    #expect(captureService.requestPermissionCallCount == 0)
    #expect(settingsWindowController.showMissingPermissionMessageCallCount == 0)
    #expect(reportedFailures.count == 1)
    #expect(reportedFailures[0].contains("SCStreamErrorDomain"))
    #expect(reportedFailures[0].contains("-3801"))
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
    let flow: ScreenCaptureFlow
    private let hasPermission: Bool
    private let requestPermissionResult: Bool
    private let result: Result<ScreenCapturePayload, Error>
    private let interactiveResult: ScreenCapturePayload?
    private let suspendCapture: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private var isResumed = false

    private(set) var capturedRects: [CGRect] = []
    private(set) var interactiveCaptureCallCount = 0
    private(set) var requestPermissionCallCount = 0

    init(
        flow: ScreenCaptureFlow = .overlayRectSelection,
        hasPermission: Bool,
        requestPermissionResult: Bool = false,
        interactiveResult: ScreenCapturePayload? = ScreenCapturePayload(
            imageData: Data([0xCA, 0xFE]),
            sourceDisplay: "Display",
            selectionRect: CGRect(x: 800, y: 600, width: 1, height: 1)
        ),
        result: Result<ScreenCapturePayload, Error>,
        suspendCapture: Bool = false
    ) {
        self.flow = flow
        self.hasPermission = hasPermission
        self.requestPermissionResult = requestPermissionResult
        self.interactiveResult = interactiveResult
        self.result = result
        self.suspendCapture = suspendCapture
    }

    var captureFlow: ScreenCaptureFlow {
        flow
    }

    func hasScreenRecordingPermission() -> Bool {
        hasPermission
    }

    func requestScreenRecordingPermission() -> Bool {
        requestPermissionCallCount += 1
        return requestPermissionResult
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
            if case TestScreenCaptureError.permissionDenied = error {
                throw NSError(domain: SCStreamErrorDomain, code: -3801)
            }
            throw error
        }
    }

    func captureInteractiveImage() async throws -> ScreenCapturePayload? {
        interactiveCaptureCallCount += 1
        return interactiveResult
    }

    func resumeCapture() async {
        isResumed = true
        continuation?.resume()
        continuation = nil
    }
}

private enum TestScreenCaptureError: Error {
    case captureFailed
    case permissionDenied
}

actor TestAsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen {
            return
        }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
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
