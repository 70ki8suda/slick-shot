import AppKit
import Foundation
import SlickShotCore

@MainActor
final class ThumbnailOverlayController: NSObject {
    private let store: ScreenshotStore
    private let presenter: ThumbnailStackPresenter
    private let stackView: ThumbnailStackView
    private let window: NSPanel

    init(
        store: ScreenshotStore,
        presenter: ThumbnailStackPresenter = ThumbnailStackPresenter(),
        feedbackPlayer: CaptureFeedbackPlaying = NullCaptureFeedbackPlayer()
    ) {
        self.store = store
        self.presenter = presenter
        self.stackView = ThumbnailStackView(
            presenter: presenter,
            feedbackPlayer: feedbackPlayer,
            onDeleteCurrent: { id in
                store.delete(id: id)
            }
        )
        self.window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()
        configureWindow()
        bindStore()
    }

    func show() {
        refresh()
        positionWindow()
        window.orderFrontRegardless()
    }

    private func configureWindow() {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.hidesOnDeactivate = false
        window.acceptsMouseMovedEvents = true
        window.contentView = stackView
    }

    private func bindStore() {
        store.onChange = { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        stackView.apply(records: store.activeRecords)
        positionWindow()
    }

    private func positionWindow() {
        let records = store.activeRecords
        let presentation = presenter.present(records: records)
        let preferredSize = CGSize(
            width: 300,
            height: 176 + (CGFloat(max(0, presentation.items.count - 1)) * 8)
        )

        guard let visibleFrame = Self.resolvedVisibleFrame(
            sourceVisibleFrame: Self.preferredVisibleFrame(
                for: records.first,
                availableScreens: NSScreen.screens
            ) ?? window.screen?.visibleFrame,
            fallbackVisibleFrames: NSScreen.screens.map(\.visibleFrame)
        ) else { return }

        let frame = Self.makeWindowFrame(
            preferredSize: preferredSize,
            itemCount: presentation.items.count,
            visibleFrame: visibleFrame
        )
        window.setFrame(frame, display: false)
    }

    nonisolated static func makeWindowFrame(
        preferredSize: CGSize,
        itemCount: Int,
        visibleFrame: CGRect
    ) -> CGRect {
        let clampedSize = CGSize(
            width: min(preferredSize.width, visibleFrame.width),
            height: min(preferredSize.height, visibleFrame.height)
        )

        let origin = CGPoint(
            x: max(visibleFrame.minX, visibleFrame.maxX - clampedSize.width),
            y: max(visibleFrame.minY, visibleFrame.minY)
        )

        return CGRect(origin: origin, size: clampedSize)
    }

    nonisolated static func resolvedVisibleFrame(
        sourceVisibleFrame: CGRect?,
        fallbackVisibleFrames: [CGRect]
    ) -> CGRect? {
        if let sourceVisibleFrame {
            return sourceVisibleFrame
        }

        return fallbackVisibleFrames.max { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }
    }

    nonisolated static func preferredVisibleFrame(
        for record: ScreenshotRecord?,
        availableScreens: [NSScreen]
    ) -> CGRect? {
        guard let record else { return nil }
        return preferredVisibleFrame(
            for: record.selectionRect,
            availableFrames: availableScreens.map { ($0.frame, $0.visibleFrame) }
        )
    }

    nonisolated static func preferredVisibleFrame(
        for selectionRect: CGRect,
        availableFrames: [(frame: CGRect, visibleFrame: CGRect)]
    ) -> CGRect? {
        let selectionRect = selectionRect.standardized
        guard selectionRect.isEmpty == false else { return nil }

        let selectionCenter = CGPoint(x: selectionRect.midX, y: selectionRect.midY)
        if let containingScreen = availableFrames.first(where: { $0.frame.contains(selectionCenter) }) {
            return containingScreen.visibleFrame
        }

        let bestIntersection = availableFrames
            .map { screen in
                (visibleFrame: screen.visibleFrame, area: screen.frame.intersection(selectionRect).area)
            }
            .max { lhs, rhs in lhs.area < rhs.area }

        guard let bestIntersection, bestIntersection.area > 0 else {
            return nil
        }

        return bestIntersection.visibleFrame
    }
}

private extension CGRect {
    var area: CGFloat {
        guard isNull == false, isEmpty == false else { return 0 }
        return width * height
    }
}
