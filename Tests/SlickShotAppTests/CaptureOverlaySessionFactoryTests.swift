import CoreGraphics
import Testing

@testable import SlickShotApp

struct CaptureOverlaySessionFactoryTests {
    @MainActor
    @Test func makeSession_buildsOneOverlayPerScreen() {
        let builder = TestOverlaySessionBuilder()
        let factory = LiveCaptureOverlaySessionFactory(
            screenFramesProvider: TestScreenFramesProvider(frames: [
                CGRect(x: 0, y: 0, width: 1512, height: 982),
                CGRect(x: 1512, y: -98, width: 1920, height: 1080),
                CGRect(x: 3432, y: -98, width: 1920, height: 1200)
            ]),
            sessionBuilder: builder.makeSession(frame:feedbackPlayer:onSelection:onCancel:)
        )

        let session = factory.makeSession(onSelection: { _ in }, onCancel: {})
        session.begin()
        session.end()

        #expect(builder.frames == [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: 1512, y: -98, width: 1920, height: 1080),
            CGRect(x: 3432, y: -98, width: 1920, height: 1200)
        ])
        #expect(builder.sessions.allSatisfy { $0.beginCallCount == 1 })
        #expect(builder.sessions.allSatisfy { $0.endCallCount == 1 })
    }
}

@MainActor
private struct TestScreenFramesProvider: ScreenFramesProviding {
    let frames: [CGRect]

    func screenFrames() -> [CGRect] {
        frames
    }
}

@MainActor
private final class TestOverlaySessionBuilder {
    private(set) var frames: [CGRect] = []
    private(set) var sessions: [TestOverlaySession] = []

    func makeSession(
        frame: CGRect,
        feedbackPlayer: CaptureFeedbackPlaying,
        onSelection: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) -> CaptureOverlaySession {
        frames.append(frame)
        let session = TestOverlaySession(
            feedbackPlayer: feedbackPlayer,
            onSelection: onSelection,
            onCancel: onCancel
        )
        sessions.append(session)
        return session
    }
}

@MainActor
private final class TestOverlaySession: CaptureOverlaySession {
    let feedbackPlayer: CaptureFeedbackPlaying
    let onSelection: (CGRect) -> Void
    let onCancel: () -> Void
    private(set) var beginCallCount = 0
    private(set) var endCallCount = 0

    init(
        feedbackPlayer: CaptureFeedbackPlaying,
        onSelection: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.feedbackPlayer = feedbackPlayer
        self.onSelection = onSelection
        self.onCancel = onCancel
    }

    func begin() {
        beginCallCount += 1
    }

    func end() {
        endCallCount += 1
    }
}
