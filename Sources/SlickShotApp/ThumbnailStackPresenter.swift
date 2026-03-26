import CoreGraphics
import Foundation
import SlickShotCore

struct ThumbnailStackPresenter {
    struct Presentation: Equatable {
        let items: [Item]
    }

    struct Item: Identifiable, Equatable {
        enum Role: Equatable {
            case foreground
            case background(depth: Int)
        }

        let id: UUID
        let role: Role
        let offset: CGSize
        let scale: CGFloat
        let zIndex: Int
        let record: ScreenshotRecord
    }

    let maxVisibleItems: Int
    let backgroundStep: CGFloat
    let backgroundScaleStep: CGFloat

    init(
        maxVisibleItems: Int = 3,
        backgroundStep: CGFloat = 14,
        backgroundScaleStep: CGFloat = 0.06
    ) {
        self.maxVisibleItems = maxVisibleItems
        self.backgroundStep = backgroundStep
        self.backgroundScaleStep = backgroundScaleStep
    }

    func present(records: [ScreenshotRecord]) -> Presentation {
        let visible = records.enumerated()
            .sorted(by: Self.sortNewestFirst)
            .prefix(maxVisibleItems)

        let items = visible.enumerated().map { visibleIndex, indexedRecord in
            let record = indexedRecord.element
            let depth = visibleIndex
            let role: Item.Role = visibleIndex == 0 ? .foreground : .background(depth: depth)
            let step = CGFloat(depth)
            return Item(
                id: record.id,
                role: role,
                offset: CGSize(width: -backgroundStep * step, height: backgroundStep * step),
                scale: max(0.82, 1 - (backgroundScaleStep * step)),
                zIndex: maxVisibleItems - depth,
                record: record
            )
        }

        return Presentation(items: items)
    }

    private static func sortNewestFirst(
        lhs: (offset: Int, element: ScreenshotRecord),
        rhs: (offset: Int, element: ScreenshotRecord)
    ) -> Bool {
        if lhs.element.createdAt != rhs.element.createdAt {
            return lhs.element.createdAt > rhs.element.createdAt
        }

        if lhs.offset != rhs.offset {
            return lhs.offset < rhs.offset
        }

        return lhs.element.id.uuidString > rhs.element.id.uuidString
    }
}
