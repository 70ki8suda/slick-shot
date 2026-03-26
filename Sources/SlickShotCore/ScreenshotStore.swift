import Foundation
import CoreGraphics

public final class ScreenshotStore {
    private let now: () -> Date
    private var records: [UUID: ScreenshotRecord] = [:]

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    @discardableResult
    public func insert(image: Data, sourceDisplay: String, selectionRect: CGRect) -> UUID {
        let id = UUID()
        let createdAt = now()
        let record = ScreenshotRecord(
            id: id,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(300),
            status: .pending,
            imageRepresentation: image,
            displayThumbnailRepresentation: image,
            sourceDisplay: sourceDisplay,
            selectionRect: selectionRect
        )
        records[id] = record
        return id
    }

    public func delete(id: UUID) {
        records[id] = nil
    }

    public var activeRecords: [ScreenshotRecord] {
        records.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func list() -> [ScreenshotRecord] {
        activeRecords
    }
}
