import Foundation
import CoreGraphics

public final class ScreenshotStore {
    public static let didChangeNotification = Notification.Name("SlickShotCore.ScreenshotStoreDidChange")
    public static let retentionInterval: TimeInterval = 300

    private let now: () -> Date
    private var nextSequence: Int = 0
    private var records: [UUID: Entry] = [:]

    public var onChange: (() -> Void)?

    private struct Entry {
        let sequence: Int
        var record: ScreenshotRecord
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
            expiresAt: createdAt.addingTimeInterval(Self.retentionInterval),
            status: .pending,
            imageRepresentation: image,
            displayThumbnailRepresentation: image,
            sourceDisplay: sourceDisplay,
            selectionRect: selectionRect
        )
        records[id] = Entry(sequence: nextSequence, record: record)
        nextSequence += 1
        notifyChange()
        return id
    }

    public func delete(id: UUID) {
        guard records.removeValue(forKey: id) != nil else {
            return
        }
        notifyChange()
    }

    public func markDragging(id: UUID) {
        updateStatus(for: id, to: .dragging)
    }

    public func markDropped(id: UUID) {
        updateStatus(for: id, to: .dropped)
    }

    public func expire() {
        let now = now()
        let expiredIDs = records.compactMap { entry -> UUID? in
            guard entry.value.record.status != .dragging else { return nil }
            return now >= entry.value.record.expiresAt ? entry.key : nil
        }

        guard !expiredIDs.isEmpty else {
            return
        }

        expiredIDs.forEach { records[$0] = nil }
        notifyChange()
    }

    public func reconcileExpiry() {
        expire()
    }

    public func record(id: UUID) -> ScreenshotRecord? {
        records[id]?.record
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

    private func updateStatus(for id: UUID, to status: ScreenshotStatus) {
        guard let entry = records[id], entry.record.status != status else {
            return
        }

        records[id] = Entry(
            sequence: entry.sequence,
            record: ScreenshotRecord(
                id: entry.record.id,
                createdAt: entry.record.createdAt,
                expiresAt: entry.record.expiresAt,
                status: status,
                imageRepresentation: entry.record.imageRepresentation,
                displayThumbnailRepresentation: entry.record.displayThumbnailRepresentation,
                sourceDisplay: entry.record.sourceDisplay,
                selectionRect: entry.record.selectionRect,
                temporaryBackingURL: entry.record.temporaryBackingURL
            )
        )
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        onChange?()
    }
}
