import Foundation
import CoreGraphics

public final class ScreenshotStore {
    public static let didChangeNotification = Notification.Name("SlickShotCore.ScreenshotStoreDidChange")
    public static let retentionInterval: TimeInterval = 300
    nonisolated(unsafe) public private(set) static var current: ScreenshotStore?

    private let now: () -> Date
    private let temporaryFileManager: TemporaryFileManaging
    private var nextSequence: Int = 0
    private var records: [UUID: Entry] = [:]
    private var pausedRetentionIntervals: [UUID: TimeInterval] = [:]

    public var onChange: (() -> Void)?

    private struct Entry {
        let sequence: Int
        var record: ScreenshotRecord
    }

    public enum DragPreparationError: Error, Equatable {
        case missingRecord
        case expiredRecord
        case unavailableRecord
    }

    public init(
        now: @escaping () -> Date = Date.init,
        temporaryFileManager: TemporaryFileManaging = TemporaryFileManager()
    ) {
        self.now = now
        self.temporaryFileManager = temporaryFileManager
        temporaryFileManager.recoverStaleFiles()
        Self.current = self
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
        guard let entry = records.removeValue(forKey: id) else {
            return
        }
        cleanupTemporaryFile(for: entry.record)
        pausedRetentionIntervals.removeValue(forKey: id)
        notifyChange()
    }

    func markDragging(id: UUID) {
        guard let entry = records[id], entry.record.status == .pending else {
            return
        }

        if removeExpiredRecordIfNeeded(id: id, entry: entry) {
            return
        }

        pausedRetentionIntervals[id] = max(0, entry.record.expiresAt.timeIntervalSince(now()))
        updateRecord(for: id) { record in
            record.status = .dragging
        }
    }

    public func beginDrag(id: UUID) throws -> URL {
        guard let entry = records[id] else {
            throw DragPreparationError.missingRecord
        }

        guard entry.record.status != .dropped else {
            throw DragPreparationError.unavailableRecord
        }

        if removeExpiredRecordIfNeeded(id: id, entry: entry) {
            throw DragPreparationError.expiredRecord
        }

        let fileURL = try existingOrNewTemporaryFileURL(for: id)
        pausedRetentionIntervals[id] = max(0, entry.record.expiresAt.timeIntervalSince(now()))
        updateRecord(for: id) { record in
            record.status = .dragging
            record.temporaryBackingURL = fileURL
        }
        return fileURL
    }

    public func cancelDrag(id: UUID) {
        guard let entry = records[id] else {
            return
        }

        let remaining = pausedRetentionIntervals.removeValue(forKey: id)
        cleanupTemporaryFile(for: entry.record)
        updateRecord(for: id) { record in
            record.status = .pending
            if let remaining {
                record.expiresAt = now().addingTimeInterval(remaining)
            }
            record.temporaryBackingURL = nil
        }
    }

    public func markDropped(id: UUID) {
        guard let entry = records[id], entry.record.status != .dropped else {
            return
        }

        let remaining = pausedRetentionIntervals.removeValue(forKey: id)
        cleanupTemporaryFile(for: entry.record)
        updateRecord(for: id) { record in
            record.expiresAt = remaining.map { now().addingTimeInterval($0) } ?? record.expiresAt
            record.status = .dropped
            record.temporaryBackingURL = nil
        }
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

        expiredIDs.forEach {
            if let entry = records[$0] {
                cleanupTemporaryFile(for: entry.record)
            }
            records[$0] = nil
        }
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

    private func updateRecord(for id: UUID, mutate: (inout ScreenshotRecord) -> Void) {
        guard var entry = records[id] else {
            return
        }

        mutate(&entry.record)
        records[id] = entry
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

        cleanupTemporaryFile(for: entry.record)
        records[id] = nil
        pausedRetentionIntervals.removeValue(forKey: id)
        notifyChange()
        return true
    }

    private func existingOrNewTemporaryFileURL(for id: UUID) throws -> URL {
        guard let record = records[id]?.record else {
            throw DragPreparationError.missingRecord
        }

        if let existingURL = record.temporaryBackingURL,
           FileManager.default.fileExists(atPath: existingURL.path) {
            return existingURL
        }

        return try temporaryFileManager.writePNG(data: record.imageRepresentation, for: id)
    }

    private func cleanupTemporaryFile(for record: ScreenshotRecord) {
        guard let temporaryBackingURL = record.temporaryBackingURL else {
            return
        }

        temporaryFileManager.cleanup(temporaryBackingURL)
    }
}
