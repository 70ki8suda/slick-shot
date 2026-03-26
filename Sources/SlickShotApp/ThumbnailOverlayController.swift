import AppKit
import Foundation
import SlickShotCore

@MainActor
final class ThumbnailOverlayController: NSObject {
    private let store: ScreenshotStore
    private let presenter: ThumbnailStackPresenter
    private let stackView: ThumbnailStackView
    private let window: NSPanel

    init(store: ScreenshotStore, presenter: ThumbnailStackPresenter = ThumbnailStackPresenter()) {
        self.store = store
        self.presenter = presenter
        self.stackView = ThumbnailStackView(presenter: presenter)
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
        let presentation = presenter.present(records: store.activeRecords)
        let preferredSize = CGSize(
            width: 300,
            height: 176 + (CGFloat(max(0, presentation.items.count - 1)) * 8)
        )

        guard let visibleFrame = Self.resolvedVisibleFrame(
            sourceVisibleFrame: window.screen?.visibleFrame,
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
}
