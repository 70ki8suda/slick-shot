import Foundation
import Testing

@testable import SlickShotCore

private extension Data {
    static func stub() -> Data {
        Data([0x01, 0x02, 0x03])
    }
}

@Test func test_markDropped_transitionsPendingRecordToDropped() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let store = ScreenshotStore(now: { now })
    let id = store.insert(image: .stub(), sourceDisplay: "main", selectionRect: .zero)

    store.markDropped(id: id)

    let record = try #require(store.record(id: id))
    #expect(record.id == id)
    #expect(record.status == .dropped)
    #expect(store.activeRecords.isEmpty)
}

@Test func test_expireRemovesRecordsOlderThanFiveMinutes() {
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ScreenshotStore(now: { currentDate })
    let id = store.insert(image: .stub(), sourceDisplay: "main", selectionRect: .zero)

    currentDate = currentDate.addingTimeInterval(301)
    store.expire()

    #expect(store.activeRecords.isEmpty)
    #expect(store.record(id: id) == nil)
}

@Test func test_expireRemovesRecordsAtFiveMinuteBoundary() {
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ScreenshotStore(now: { currentDate })
    let id = store.insert(image: .stub(), sourceDisplay: "main", selectionRect: .zero)

    currentDate = currentDate.addingTimeInterval(300)
    store.expire()

    #expect(store.record(id: id) == nil)
    #expect(store.activeRecords.isEmpty)
}

@Test func test_markDragging_pausesExpiryUntilDragEnds() throws {
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ScreenshotStore(now: { currentDate })
    let id = store.insert(image: .stub(), sourceDisplay: "main", selectionRect: .zero)

    store.markDragging(id: id)
    currentDate = currentDate.addingTimeInterval(301)
    store.expire()

    let draggingRecord = try #require(store.record(id: id))
    #expect(draggingRecord.status == .dragging)

    store.markDropped(id: id)
    currentDate = currentDate.addingTimeInterval(1)
    store.expire()

    #expect(store.record(id: id) != nil)

    currentDate = currentDate.addingTimeInterval(299)
    store.expire()

    #expect(store.record(id: id) == nil)
}

@Test func test_markDragging_doesNotResurrectExpiredRecord() {
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ScreenshotStore(now: { currentDate })
    let id = store.insert(image: .stub(), sourceDisplay: "main", selectionRect: .zero)

    currentDate = currentDate.addingTimeInterval(301)
    store.markDragging(id: id)

    #expect(store.record(id: id) == nil)
    #expect(store.activeRecords.isEmpty)
}

@Test func test_activeRecords_returnsNewestFirstForSameTimestamp() {
    let now = Date(timeIntervalSince1970: 1_000)
    let store = ScreenshotStore(now: { now })

    let firstID = store.insert(image: .stub(), sourceDisplay: "first", selectionRect: .zero)
    let secondID = store.insert(image: .stub(), sourceDisplay: "second", selectionRect: .zero)

    let records = store.activeRecords

    #expect(records.map(\.id) == [secondID, firstID])
}

@Test func test_activeRecords_returnsNewestFirstAcrossStates() throws {
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ScreenshotStore(now: { currentDate })

    let oldestID = store.insert(image: .stub(), sourceDisplay: "oldest", selectionRect: .zero)
    currentDate = currentDate.addingTimeInterval(1)
    let middleID = store.insert(image: .stub(), sourceDisplay: "middle", selectionRect: .zero)
    store.markDragging(id: middleID)
    currentDate = currentDate.addingTimeInterval(1)
    let newestID = store.insert(image: .stub(), sourceDisplay: "newest", selectionRect: .zero)
    store.markDropped(id: newestID)

    let records = store.activeRecords

    #expect(records.map(\.id) == [middleID, oldestID])
    #expect(records.map(\.status) == [.dragging, .pending])
    #expect(store.record(id: newestID)?.status == .dropped)
}

@Test func test_reconcileExpiry_removesExpiredRecordsAfterResume() {
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ScreenshotStore(now: { currentDate })
    let id = store.insert(image: .stub(), sourceDisplay: "main", selectionRect: .zero)

    currentDate = currentDate.addingTimeInterval(301)
    store.reconcileExpiry()

    #expect(store.record(id: id) == nil)
}

@Test func test_changePublication_notifiesOnStoreMutations() {
    let store = ScreenshotStore(now: Date.init)
    var changes = 0
    store.onChange = {
        changes += 1
    }

    let id = store.insert(image: .stub(), sourceDisplay: "main", selectionRect: .zero)
    store.markDropped(id: id)
    store.delete(id: id)

    #expect(changes == 3)
}
