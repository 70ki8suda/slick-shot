import AppKit
import Foundation
import SlickShotCore

@MainActor
final class DragSessionProvider: NSObject, NSDraggingSource {
    private let storeResolver: () -> ScreenshotStore?
    private var activeRecordID: UUID?

    init(storeResolver: @escaping () -> ScreenshotStore? = { ScreenshotStore.current }) {
        self.storeResolver = storeResolver
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
            let fileURL = try store.beginDrag(id: record.id)
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
        guard let activeRecordID, let store = storeResolver() else {
            return
        }

        defer { self.activeRecordID = nil }

        if operation == [] {
            store.cancelDrag(id: activeRecordID)
        } else {
            store.markDropped(id: activeRecordID)
        }
    }
}
