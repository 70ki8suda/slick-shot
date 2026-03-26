import Foundation
import Testing

@testable import SlickShotCore

private extension Data {
    static func stub() -> Data {
        Data([0x01, 0x02, 0x03])
    }
}

@Test func test_insert_createsPendingRecordWithFiveMinuteExpiry() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let store = ScreenshotStore(now: { now })
    let id = store.insert(
        image: .stub(),
        sourceDisplay: "main",
        selectionRect: CGRect(x: 10, y: 20, width: 30, height: 40)
    )

    let record = try #require(store.activeRecords.first)
    #expect(record.id == id)
    #expect(record.status == .pending)
    #expect(record.expiresAt == now.addingTimeInterval(300))
}

@Test func test_delete_removesExistingRecordImmediately() {
    let store = ScreenshotStore(now: Date.init)
    let id = store.insert(image: .stub(), sourceDisplay: "main", selectionRect: .zero)

    store.delete(id: id)

    #expect(store.activeRecords.isEmpty)
}

@Test func test_activeRecords_withTiedCreatedAtKeepsInsertionOrder() {
    let now = Date(timeIntervalSince1970: 1_000)
    let store = ScreenshotStore(now: { now })

    let firstID = store.insert(image: .stub(), sourceDisplay: "main", selectionRect: .zero)
    let secondID = store.insert(image: .stub(), sourceDisplay: "secondary", selectionRect: .zero)

    let records = store.activeRecords

    #expect(records.count == 2)
    #expect(records[0].id == firstID)
    #expect(records[1].id == secondID)
}
