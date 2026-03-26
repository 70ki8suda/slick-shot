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

@Test func test_presenter_pins_layer_contract_for_visible_stack() {
    let presenter = ThumbnailStackPresenter()
    let now = Date(timeIntervalSince1970: 1_000)
    let records = (0..<3).map { index in
        makeRecord(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-000000000%03d", index + 1))!,
            createdAt: now.addingTimeInterval(TimeInterval(index))
        )
    }

    let presentation = presenter.present(records: records)

    #expect(presentation.items.count == 3)
    #expect(presentation.items[0].offset == .zero)
    #expect(presentation.items[0].scale == 1)
    #expect(presentation.items[0].zIndex == 3)
    #expect(presentation.items[1].offset == CGSize(width: -14, height: 14))
    #expect(presentation.items[1].scale == 0.94)
    #expect(presentation.items[1].zIndex == 2)
    #expect(presentation.items[2].offset == CGSize(width: -28, height: 28))
    #expect(presentation.items[2].scale == 0.88)
    #expect(presentation.items[2].zIndex == 1)
}

@Test func test_presenter_preserves_input_order_for_same_timestamp_ties() {
    let presenter = ThumbnailStackPresenter()
    let createdAt = Date(timeIntervalSince1970: 1_000)
    let first = makeRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, createdAt: createdAt)
    let second = makeRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, createdAt: createdAt)

    let presentation = presenter.present(records: [first, second])

    #expect(presentation.items.map(\.id) == [first.id, second.id])
}

@Test func test_overlay_uses_visible_frame_and_clamps_to_bounds() {
    let visibleFrame = CGRect(x: 100, y: 50, width: 280, height: 220)

    let frame = ThumbnailOverlayController.makeWindowFrame(
        preferredSize: CGSize(width: 320, height: 260),
        itemCount: 3,
        visibleFrame: visibleFrame
    )

    #expect(frame.maxX <= visibleFrame.maxX)
    #expect(frame.minX >= visibleFrame.minX)
    #expect(frame.minY >= visibleFrame.minY)
    #expect(frame.maxY <= visibleFrame.maxY)
    #expect(frame.width == 280)
    #expect(frame.height == 220)
    #expect(frame.origin == CGPoint(x: 100, y: 50))
}

@Test func test_app_delegate_only_seeds_demo_records_in_debug_when_enabled() {
    #expect(AppDelegate.shouldSeedDemoRecords(environment: [:]) == false)
    #expect(AppDelegate.shouldSeedDemoRecords(environment: ["SLICKSHOT_SEED_THUMBNAILS": "1"]) == true)
}
