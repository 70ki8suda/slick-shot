import AppKit
import Foundation
import SlickShotCore

@MainActor
final class DragSessionProvider: NSObject, NSDraggingSource {
    private let storeResolver: () -> ScreenshotStore?
    private let feedbackPlayer: CaptureFeedbackPlaying
    private var activeRecordID: UUID?

    var hasActiveDrag: Bool {
        activeRecordID != nil
    }

    init(
        storeResolver: @escaping () -> ScreenshotStore? = { ScreenshotStore.current },
        feedbackPlayer: CaptureFeedbackPlaying = NullCaptureFeedbackPlayer()
    ) {
        self.storeResolver = storeResolver
        self.feedbackPlayer = feedbackPlayer
    }

    func beginDrag(
        for record: ScreenshotRecord,
        from sourceView: NSView,
        event: NSEvent
    ) -> Bool {
        guard activeRecordID == nil, let store = storeResolver() else {
            return false
        }

        do {
            let fileURL = try startManagedDrag(for: record.id, store: store)
            let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
            let previewImage = NSImage(data: record.displayThumbnailRepresentation)
                ?? NSImage(data: record.imageRepresentation)
            draggingItem.setDraggingFrame(sourceView.bounds, contents: previewImage)
            activeRecordID = record.id

            let session = sourceView.beginDraggingSession(with: [draggingItem], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
            return true
        } catch {
            NSLog("SlickShot drag start failed: %@", String(describing: error))
            return false
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        finishManagedDrag(operation: operation)
    }

    func startManagedDrag(for id: UUID) throws -> URL {
        guard let store = storeResolver() else {
            throw ScreenshotStore.DragPreparationError.missingRecord
        }

        return try startManagedDrag(for: id, store: store)
    }

    func finishManagedDrag(operation: NSDragOperation) {
        guard let activeRecordID else {
            return
        }

        self.activeRecordID = nil

        guard let store = storeResolver() else {
            return
        }

        if operation == [] {
            store.cancelDrag(id: activeRecordID)
        } else {
            store.markDropped(id: activeRecordID)
            feedbackPlayer.playDropCompleted()
        }
    }

    private func startManagedDrag(for id: UUID, store: ScreenshotStore) throws -> URL {
        let fileURL = try store.beginDrag(id: id)
        activeRecordID = id
        return fileURL
    }
}
