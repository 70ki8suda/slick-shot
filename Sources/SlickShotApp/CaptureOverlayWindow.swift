import AppKit
import CoreGraphics

@MainActor
final class CaptureOverlayWindow: NSWindow, CaptureOverlaySession {
    private let overlayView: CaptureOverlayView

    init(
        frame: CGRect = CaptureOverlayWindow.defaultFrame(),
        onSelection: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        overlayView = CaptureOverlayView(frame: CGRect(origin: .zero, size: frame.size))
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        overlayView.onSelection = onSelection
        overlayView.onCancel = onCancel

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        contentView = overlayView
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    func begin() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(overlayView)
    }

    func end() {
        orderOut(nil)
        close()
    }

    private static func defaultFrame() -> CGRect {
        let screens = NSScreen.screens
        if screens.isEmpty {
            return .zero
        }

        return screens
            .map(\.frame)
            .reduce(into: CGRect.null) { partialResult, frame in
                partialResult = partialResult.union(frame)
            }
    }
}

@MainActor
struct LiveCaptureOverlaySessionFactory: CaptureOverlaySessionFactory {
    func makeSession(
        onSelection: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) -> CaptureOverlaySession {
        CaptureOverlayWindow(onSelection: onSelection, onCancel: onCancel)
    }
}
