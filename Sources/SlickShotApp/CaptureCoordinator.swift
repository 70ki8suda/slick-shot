import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit
import SlickShotCore

struct ScreenCapturePayload: Equatable {
    let imageData: Data
    let sourceDisplay: String
}

enum ScreenCaptureFlow {
    case overlayRectSelection
    case nativeInteractiveSelection
}

@MainActor
protocol ScreenCaptureServiceProtocol {
    var captureFlow: ScreenCaptureFlow { get }
    func hasScreenRecordingPermission() -> Bool
    func requestScreenRecordingPermission() -> Bool
    func captureImage(in rect: CGRect) async throws -> ScreenCapturePayload
    func captureInteractiveImage() async throws -> ScreenCapturePayload?
}

@MainActor
protocol CaptureOverlaySession: AnyObject {
    func begin()
    func end()
}

@MainActor
protocol CaptureOverlaySessionFactory {
    func makeSession(
        onSelection: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) -> CaptureOverlaySession
}

@MainActor
protocol SettingsWindowControlling: AnyObject {
    func showMissingPermissionMessage()
}

@MainActor
final class CaptureCoordinator {
    private static let overlaySettleDelayNanoseconds: UInt64 = 120_000_000

    private let store: ScreenshotStore
    private let captureService: ScreenCaptureServiceProtocol
    private let overlayFactory: CaptureOverlaySessionFactory
    private let settingsWindowController: SettingsWindowControlling
    private let feedbackPlayer: CaptureFeedbackPlaying
    private let beforeCapture: @Sendable () async -> Void
    private let onCaptureFailure: (any Error) -> Void

    private var activeSession: CaptureOverlaySession?
    private var interactiveCaptureTask: Task<Void, Never>?

    init(
        store: ScreenshotStore,
        captureService: ScreenCaptureServiceProtocol,
        overlayFactory: CaptureOverlaySessionFactory,
        settingsWindowController: SettingsWindowControlling,
        feedbackPlayer: CaptureFeedbackPlaying = NullCaptureFeedbackPlayer(),
        beforeCapture: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(nanoseconds: overlaySettleDelayNanoseconds)
        },
        onCaptureFailure: @escaping (any Error) -> Void = { error in
            NSLog("SlickShot capture failed: %@", String(describing: error))
        }
    ) {
        self.store = store
        self.captureService = captureService
        self.overlayFactory = overlayFactory
        self.settingsWindowController = settingsWindowController
        self.feedbackPlayer = feedbackPlayer
        self.beforeCapture = beforeCapture
        self.onCaptureFailure = onCaptureFailure
    }

    func startCapture() {
        guard activeSession == nil, interactiveCaptureTask == nil else {
            return
        }

        if captureService.captureFlow == .nativeInteractiveSelection {
            interactiveCaptureTask = Task { [weak self] in
                await self?.captureInteractively()
            }
            return
        }

        let session = overlayFactory.makeSession(
            onSelection: { [weak self] rect in
                self?.completeCapture(with: rect)
            },
            onCancel: { [weak self] in
                self?.cancelCapture()
            }
        )
        activeSession = session
        session.begin()
    }

    private func captureInteractively() async {
        defer {
            interactiveCaptureTask = nil
        }

        do {
            guard let payload = try await captureService.captureInteractiveImage() else {
                return
            }
            _ = store.insert(
                image: payload.imageData,
                sourceDisplay: payload.sourceDisplay,
                selectionRect: .zero
            )
            feedbackPlayer.playCaptureCompleted()
        } catch {
            if Self.isScreenRecordingPermissionError(error) {
                let granted = captureService.requestScreenRecordingPermission()
                if granted == false {
                    settingsWindowController.showMissingPermissionMessage()
                }
                return
            }
            onCaptureFailure(error)
        }
    }

    private func completeCapture(with rect: CGRect) {
        let selectionRect = rect.standardized.integral
        guard selectionRect.width > 0, selectionRect.height > 0 else {
            cancelCapture()
            return
        }

        endActiveSession()

        Task { [weak self] in
            await self?.captureSelection(selectionRect)
        }
    }

    private func captureSelection(_ selectionRect: CGRect) async {
        do {
            await beforeCapture()
            let payload = try await captureService.captureImage(in: selectionRect)
            _ = store.insert(
                image: payload.imageData,
                sourceDisplay: payload.sourceDisplay,
                selectionRect: selectionRect
            )
            feedbackPlayer.playCaptureCompleted()
        } catch {
            if Self.isScreenRecordingPermissionError(error) {
                let granted = captureService.requestScreenRecordingPermission()
                if granted == false {
                    settingsWindowController.showMissingPermissionMessage()
                }
                return
            }
            onCaptureFailure(error)
        }
    }

    private func cancelCapture() {
        endActiveSession()
    }

    private func endActiveSession() {
        let session = activeSession
        activeSession = nil
        session?.end()
    }

    private static func isScreenRecordingPermissionError(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == -3801
    }
}
