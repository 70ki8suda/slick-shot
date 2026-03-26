import AppKit
import CoreGraphics

@MainActor
protocol RunningApplicationActivating: AnyObject {
    var bundleIdentifier: String? { get }
    func activate(options: NSApplication.ActivationOptions) -> Bool
}

extension NSRunningApplication: RunningApplicationActivating {}

@MainActor
protocol FrontmostApplicationProviding {
    func currentFrontmostApplication() -> (any RunningApplicationActivating)?
}

@MainActor
struct WorkspaceFrontmostApplicationProvider: FrontmostApplicationProviding {
    func currentFrontmostApplication() -> (any RunningApplicationActivating)? {
        NSWorkspace.shared.frontmostApplication
    }
}

@MainActor
protocol ApplicationActivating {
    func activateSlickShot()
}

@MainActor
struct NSApplicationActivator: ApplicationActivating {
    func activateSlickShot() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class CaptureOverlayWindow: NSWindow, CaptureOverlaySession {
    private let overlayView: CaptureOverlayView
    private let frontmostProvider: FrontmostApplicationProviding
    private let appActivator: ApplicationActivating
    private var previousFrontmostApplication: (any RunningApplicationActivating)?

    init(
        frame: CGRect = CaptureOverlayWindow.defaultFrame(),
        frontmostProvider: FrontmostApplicationProviding = WorkspaceFrontmostApplicationProvider(),
        appActivator: ApplicationActivating = NSApplicationActivator(),
        onSelection: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        overlayView = CaptureOverlayView(frame: CGRect(origin: .zero, size: frame.size))
        self.frontmostProvider = frontmostProvider
        self.appActivator = appActivator
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
        let frontmostApplication = frontmostProvider.currentFrontmostApplication()
        if frontmostApplication?.bundleIdentifier != AppBundleMetadata.bundleIdentifier {
            previousFrontmostApplication = frontmostApplication
        } else {
            previousFrontmostApplication = nil
        }
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(overlayView)
    }

    func end() {
        orderOut(nil)
        _ = previousFrontmostApplication?.activate(options: [])
        previousFrontmostApplication = nil
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
