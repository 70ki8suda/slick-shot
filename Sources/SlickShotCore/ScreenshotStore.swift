import Foundation
import CoreGraphics

public final class ScreenshotStore {
    private let now: () -> Date
    private var nextSequence: Int = 0
    private var records: [UUID: Entry] = [:]

    private struct Entry {
        let sequence: Int
        let record: ScreenshotRecord
    }

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
        records[id] = Entry(sequence: nextSequence, record: record)
        nextSequence += 1
        return id
    }

    public func delete(id: UUID) {
        records[id] = nil
    }

    public var activeRecords: [ScreenshotRecord] {
        records.values
            .sorted {
                if $0.record.createdAt != $1.record.createdAt {
                    return $0.record.createdAt > $1.record.createdAt
                }
                return $0.sequence < $1.sequence
            }
            .map(\.record)
    }

    public func list() -> [ScreenshotRecord] {
        activeRecords
    }
}
