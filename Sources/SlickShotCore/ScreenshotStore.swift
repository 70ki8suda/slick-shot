import Foundation
import CoreGraphics

public final class ScreenshotStore {
    public static let didChangeNotification = Notification.Name("SlickShotCore.ScreenshotStoreDidChange")
    public static let retentionInterval: TimeInterval = 300

    private let now: () -> Date
    private var nextSequence: Int = 0
    private var records: [UUID: Entry] = [:]
    private var pausedRetentionIntervals: [UUID: TimeInterval] = [:]

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
        pausedRetentionIntervals.removeValue(forKey: id)
        notifyChange()
    }

    public func markDragging(id: UUID) {
        guard let entry = records[id], entry.record.status == .pending else {
            return
        }

        if removeExpiredRecordIfNeeded(id: id, entry: entry) {
            return
        }

        pausedRetentionIntervals[id] = max(0, entry.record.expiresAt.timeIntervalSince(now()))
        updateStatus(for: id, to: .dragging)
    }

    public func markDropped(id: UUID) {
        guard let entry = records[id], entry.record.status != .dropped else {
            return
        }

        let remaining = pausedRetentionIntervals.removeValue(forKey: id)
        let expiresAt = remaining.map { now().addingTimeInterval($0) } ?? entry.record.expiresAt

        records[id] = Entry(
            sequence: entry.sequence,
            record: ScreenshotRecord(
                id: entry.record.id,
                createdAt: entry.record.createdAt,
                expiresAt: expiresAt,
                status: .dropped,
                imageRepresentation: entry.record.imageRepresentation,
                displayThumbnailRepresentation: entry.record.displayThumbnailRepresentation,
                sourceDisplay: entry.record.sourceDisplay,
                selectionRect: entry.record.selectionRect,
                temporaryBackingURL: entry.record.temporaryBackingURL
            )
        )
        notifyChange()
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
        expiredIDs.forEach { pausedRetentionIntervals.removeValue(forKey: $0) }
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
            .filter { $0.record.status != .dropped }
            .sorted {
                if $0.record.createdAt != $1.record.createdAt {
                    return $0.record.createdAt > $1.record.createdAt
                }
                return $0.sequence > $1.sequence
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

    private func removeExpiredRecordIfNeeded(id: UUID, entry: Entry) -> Bool {
        guard entry.record.status != .dragging, now() >= entry.record.expiresAt else {
            return false
        }

        records[id] = nil
        pausedRetentionIntervals.removeValue(forKey: id)
        notifyChange()
        return true
    }
}
