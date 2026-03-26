import CoreGraphics
import Foundation
import SlickShotCore

struct ScreenCapturePayload: Equatable {
    let imageData: Data
    let sourceDisplay: String
}

@MainActor
protocol ScreenCaptureServiceProtocol {
    func hasScreenRecordingPermission() -> Bool
    func captureImage(in rect: CGRect) async throws -> ScreenCapturePayload
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
    private let store: ScreenshotStore
    private let captureService: ScreenCaptureServiceProtocol
    private let overlayFactory: CaptureOverlaySessionFactory
    private let settingsWindowController: SettingsWindowControlling
    private let onCaptureFailure: (any Error) -> Void

    private var activeSession: CaptureOverlaySession?

    init(
        store: ScreenshotStore,
        captureService: ScreenCaptureServiceProtocol,
        overlayFactory: CaptureOverlaySessionFactory,
        settingsWindowController: SettingsWindowControlling,
        onCaptureFailure: @escaping (any Error) -> Void = { error in
            NSLog("SlickShot capture failed: %@", String(describing: error))
        }
    ) {
        self.store = store
        self.captureService = captureService
        self.overlayFactory = overlayFactory
        self.settingsWindowController = settingsWindowController
        self.onCaptureFailure = onCaptureFailure
    }

    func startCapture() {
        guard activeSession == nil else {
            return
        }

        guard captureService.hasScreenRecordingPermission() else {
            settingsWindowController.showMissingPermissionMessage()
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
            let payload = try await captureService.captureImage(in: selectionRect)
            _ = store.insert(
                image: payload.imageData,
                sourceDisplay: payload.sourceDisplay,
                selectionRect: selectionRect
            )
        } catch {
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
}
