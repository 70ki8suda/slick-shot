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
protocol ScreenFramesProviding {
    func screenFrames() -> [CGRect]
}

@MainActor
struct NSScreenFramesProvider: ScreenFramesProviding {
    func screenFrames() -> [CGRect] {
        NSScreen.screens.map(\.frame)
    }
}

enum CaptureOverlayPresentationMode {
    case standard
    case demoRecording
}

@MainActor
final class CaptureOverlayWindow: NSWindow, CaptureOverlaySession {
    private let overlayView: CaptureOverlayView
    private let frontmostProvider: FrontmostApplicationProviding
    private var previousFrontmostApplication: (any RunningApplicationActivating)?

    init(
        frame: CGRect,
        frontmostProvider: FrontmostApplicationProviding = WorkspaceFrontmostApplicationProvider(),
        presentationMode: CaptureOverlayPresentationMode = .standard,
        feedbackPlayer: CaptureFeedbackPlaying = NullCaptureFeedbackPlayer(),
        onSelection: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        overlayView = CaptureOverlayView(frame: CGRect(origin: .zero, size: frame.size), feedbackPlayer: feedbackPlayer)
        self.frontmostProvider = frontmostProvider
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
        switch presentationMode {
        case .standard:
            level = .screenSaver
            sharingType = .none
        case .demoRecording:
            level = .statusBar
            sharingType = .readOnly
        }
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
        previousFrontmostApplication = nil
        close()
    }
}

@MainActor
private final class OneShotReticleFeedbackPlayer: CaptureFeedbackPlaying {
    private let base: CaptureFeedbackPlaying
    private var hasPlayedReticleReveal = false

    init(base: CaptureFeedbackPlaying) {
        self.base = base
    }

    func playCaptureCompleted() {
        base.playCaptureCompleted()
    }

    func playDropCompleted() {
        base.playDropCompleted()
    }

    func playReticleReveal() {
        guard hasPlayedReticleReveal == false else { return }
        hasPlayedReticleReveal = true
        base.playReticleReveal()
    }
}

@MainActor
private final class CaptureOverlaySessionGroup: CaptureOverlaySession {
    let sessions: [CaptureOverlaySession]

    init(sessions: [CaptureOverlaySession]) {
        self.sessions = sessions
    }

    func begin() {
        sessions.forEach { $0.begin() }
    }

    func end() {
        sessions.forEach { $0.end() }
    }
}

@MainActor
struct LiveCaptureOverlaySessionFactory: CaptureOverlaySessionFactory {
    private let screenFramesProvider: ScreenFramesProviding
    private let feedbackPlayer: CaptureFeedbackPlaying
    private let presentationModeProvider: () -> CaptureOverlayPresentationMode
    private let sessionBuilder: (CGRect, CaptureOverlayPresentationMode, CaptureFeedbackPlaying, @escaping (CGRect) -> Void, @escaping () -> Void) -> CaptureOverlaySession

    init(
        screenFramesProvider: ScreenFramesProviding = NSScreenFramesProvider(),
        feedbackPlayer: CaptureFeedbackPlaying = NullCaptureFeedbackPlayer(),
        presentationModeProvider: @escaping () -> CaptureOverlayPresentationMode = { .standard },
        sessionBuilder: @escaping (CGRect, CaptureOverlayPresentationMode, CaptureFeedbackPlaying, @escaping (CGRect) -> Void, @escaping () -> Void) -> CaptureOverlaySession = { frame, presentationMode, feedbackPlayer, onSelection, onCancel in
            CaptureOverlayWindow(frame: frame, presentationMode: presentationMode, feedbackPlayer: feedbackPlayer, onSelection: onSelection, onCancel: onCancel)
        }
    ) {
        self.screenFramesProvider = screenFramesProvider
        self.feedbackPlayer = feedbackPlayer
        self.presentationModeProvider = presentationModeProvider
        self.sessionBuilder = sessionBuilder
    }

    func makeSession(
        onSelection: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) -> CaptureOverlaySession {
        let oneShotFeedbackPlayer = OneShotReticleFeedbackPlayer(base: feedbackPlayer)
        let presentationMode = presentationModeProvider()
        let sessions = screenFramesProvider
            .screenFrames()
            .map { frame in
                sessionBuilder(
                    frame,
                    presentationMode,
                    oneShotFeedbackPlayer,
                    onSelection,
                    onCancel
                )
            }
        return CaptureOverlaySessionGroup(sessions: sessions)
    }
}
