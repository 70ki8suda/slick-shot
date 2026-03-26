import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import SlickShotApp
@testable import SlickShotCore

struct DragSessionProviderTests {
    @MainActor
    @Test func successfulDrop_playsCompletionFeedback() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DragSessionProviderTests.success.\(UUID().uuidString)",
            isDirectory: true
        )
        let store = ScreenshotStore(
            now: { Date(timeIntervalSince1970: 1_000) },
            temporaryFileManager: TemporaryFileManager(rootDirectory: temporaryRoot)
        )
        let recordID = store.insert(
            image: Data([0x01, 0x02]),
            sourceDisplay: "Display 1",
            selectionRect: CGRect(x: 1, y: 2, width: 3, height: 4)
        )
        let feedbackPlayer = TestCaptureFeedbackPlayer()
        let provider = DragSessionProvider(
            storeResolver: { store },
            feedbackPlayer: feedbackPlayer
        )

        _ = try provider.startManagedDrag(for: recordID)
        provider.finishManagedDrag(operation: NSDragOperation.copy)

        #expect(feedbackPlayer.dropCompletedCallCount == 1)
        #expect(store.activeRecords.isEmpty)
    }

    @MainActor
    @Test func cancelledDrop_doesNotPlayCompletionFeedback() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DragSessionProviderTests.cancel.\(UUID().uuidString)",
            isDirectory: true
        )
        let store = ScreenshotStore(
            now: { Date(timeIntervalSince1970: 1_000) },
            temporaryFileManager: TemporaryFileManager(rootDirectory: temporaryRoot)
        )
        let recordID = store.insert(
            image: Data([0x01, 0x02]),
            sourceDisplay: "Display 1",
            selectionRect: CGRect(x: 1, y: 2, width: 3, height: 4)
        )
        let feedbackPlayer = TestCaptureFeedbackPlayer()
        let provider = DragSessionProvider(
            storeResolver: { store },
            feedbackPlayer: feedbackPlayer
        )

        _ = try provider.startManagedDrag(for: recordID)
        provider.finishManagedDrag(operation: [])

        #expect(feedbackPlayer.dropCompletedCallCount == 0)
        #expect(store.activeRecords.count == 1)
        #expect(store.activeRecords.first?.status == .pending)
    }
}
