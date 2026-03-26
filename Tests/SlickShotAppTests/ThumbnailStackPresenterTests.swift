import CoreGraphics
import Foundation
import Testing

@testable import SlickShotApp
@testable import SlickShotCore

private func makeRecord(id: UUID, createdAt: Date) -> ScreenshotRecord {
    ScreenshotRecord(
        id: id,
        createdAt: createdAt,
        expiresAt: createdAt.addingTimeInterval(300),
        status: .pending,
        imageRepresentation: Data([0x01]),
        displayThumbnailRepresentation: Data([0x01]),
        sourceDisplay: "main",
        selectionRect: CGRect(x: 1, y: 2, width: 3, height: 4)
    )
}

@Test func test_presenter_ordersNewestActiveRecordsFirst() {
    let presenter = ThumbnailStackPresenter()
    let now = Date(timeIntervalSince1970: 1_000)
    let older = makeRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, createdAt: now)
    let newer = makeRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, createdAt: now.addingTimeInterval(1))

    let presentation = presenter.present(records: [older, newer])

    #expect(presentation.items.map(\.id) == [newer.id, older.id])
    #expect(presentation.items.first?.role == .foreground)
    #expect(presentation.items.dropFirst().allSatisfy { item in
        if case .background = item.role {
            return true
        }
        return false
    })
}

@Test func test_presenter_capsVisibleItemsAtThree() {
    let presenter = ThumbnailStackPresenter()
    let now = Date(timeIntervalSince1970: 1_000)
    let records = (0..<4).map { index in
        makeRecord(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-000000000%03d", index + 1))!,
            createdAt: now.addingTimeInterval(TimeInterval(index))
        )
    }

    let presentation = presenter.present(records: records)

    #expect(presentation.items.count == 3)
    #expect(presentation.items.map(\.id) == [records[3].id, records[2].id, records[1].id])
}
