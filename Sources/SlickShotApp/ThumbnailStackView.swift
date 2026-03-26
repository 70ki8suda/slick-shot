import AppKit
import CoreGraphics
import SlickShotCore

@MainActor
final class ThumbnailStackView: NSView {
    private let foregroundSize = CGSize(width: 220, height: 148)
    private let backgroundSize = CGSize(width: 206, height: 136)
    private let presenter: ThumbnailStackPresenter
    private let trashButton = HoverTrashButton(frame: .zero)
    private var currentPresentation = ThumbnailStackPresenter.Presentation(items: [])
    private var itemViews: [UUID: ThumbnailItemView] = [:]

    init(presenter: ThumbnailStackPresenter = ThumbnailStackPresenter()) {
        self.presenter = presenter
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        setupTrashButton()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(records: [ScreenshotRecord]) {
        apply(presenter.present(records: records))
    }

    func apply(_ presentation: ThumbnailStackPresenter.Presentation) {
        let oldIDs = Set(currentPresentation.items.map(\.id))
        currentPresentation = presentation
        syncItemViews(oldIDs: oldIDs)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        layoutTrashButton()
        layoutItemViews()
    }

    private func setupTrashButton() {
        trashButton.translatesAutoresizingMaskIntoConstraints = false
        trashButton.isBordered = false
        trashButton.image = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: "Delete thumbnail"
        )
        addSubview(trashButton)
    }

    private func syncItemViews(oldIDs: Set<UUID>) {
        let newIDs = Set(currentPresentation.items.map(\.id))

        for removedID in oldIDs.subtracting(newIDs) {
            guard let view = itemViews.removeValue(forKey: removedID) else { continue }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                view.animator().alphaValue = 0
            } completionHandler: {
                view.removeFromSuperview()
            }
        }

        for item in currentPresentation.items {
            let view = itemViews[item.id] ?? {
                let newView = ThumbnailItemView()
                newView.alphaValue = 0
                newView.layer?.transform = CATransform3DMakeScale(0.96, 0.96, 1)
                addSubview(newView)
                itemViews[item.id] = newView
                return newView
            }()
            view.configure(with: item.record)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                view.animator().alphaValue = 1
                view.animator().layer?.transform = CATransform3DIdentity
            }
        }
    }

    private func layoutTrashButton() {
        let size: CGFloat = 26
        let inset: CGFloat = 12
        trashButton.frame = CGRect(
            x: bounds.maxX - inset - size,
            y: bounds.maxY - inset - size,
            width: size,
            height: size
        )
    }

    private func layoutItemViews() {
        let anchorX = bounds.maxX - 12
        let anchorY = bounds.minY + 12

        for item in currentPresentation.items {
            guard let view = itemViews[item.id] else { continue }
            let size = item.role == .foreground ? foregroundSize : backgroundSize
            let frame = CGRect(
                x: anchorX - size.width + item.offset.width,
                y: anchorY + item.offset.height,
                width: size.width,
                height: size.height
            )

            view.layer?.zPosition = CGFloat(item.zIndex)
            if view.frame != frame {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    view.animator().frame = frame
                }
            } else {
                view.frame = frame
            }

            let targetScale = CATransform3DMakeScale(item.scale, item.scale, 1)
            view.layer?.transform = targetScale
        }
    }

}

private final class HoverTrashButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        contentTintColor = NSColor.white.withAlphaComponent(0.75)
        imagePosition = .imageOnly
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        setHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHover(false)
    }

    private func setHover(_ isHovering: Bool) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(isHovering ? 0.16 : 0.08).cgColor
        contentTintColor = NSColor.white.withAlphaComponent(isHovering ? 0.95 : 0.75)
    }
}
