@testable import SlickShotApp

@MainActor
final class TestCaptureFeedbackPlayer: CaptureFeedbackPlaying {
    private(set) var captureCompletedCallCount = 0
    private(set) var dropCompletedCallCount = 0
    private(set) var reticleRevealCallCount = 0

    func playCaptureCompleted() {
        captureCompletedCallCount += 1
    }

    func playDropCompleted() {
        dropCompletedCallCount += 1
    }

    func playReticleReveal() {
        reticleRevealCallCount += 1
    }
}
