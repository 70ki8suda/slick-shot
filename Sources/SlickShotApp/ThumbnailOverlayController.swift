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
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let presentation = presenter.present(records: store.activeRecords)
        let visibleCount = max(1, presentation.items.count)
        let height = 176 + (CGFloat(max(0, visibleCount - 1)) * 8)
        let width = 300
        let inset: CGFloat = 18
        let frame = CGRect(
            x: screen.frame.maxX - CGFloat(width) - inset,
            y: screen.frame.minY + inset,
            width: CGFloat(width),
            height: height
        )
        window.setFrame(frame, display: false)
    }
}
