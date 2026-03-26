import AppKit
import CoreGraphics
import SlickShotCore

@MainActor
final class ThumbnailStackView: NSView {
    private let foregroundSize = CGSize(width: 220, height: 148)
    private let backgroundSize = CGSize(width: 206, height: 136)
    private let presenter: ThumbnailStackPresenter
    private let trashButton = HoverTrashButton(frame: .zero)
    private let feedbackPlayer: CaptureFeedbackPlaying
    private var currentPresentation = ThumbnailStackPresenter.Presentation(items: [])
    private var itemViews: [UUID: ThumbnailItemView] = [:]

    init(
        presenter: ThumbnailStackPresenter = ThumbnailStackPresenter(),
        feedbackPlayer: CaptureFeedbackPlaying = NullCaptureFeedbackPlayer()
    ) {
        self.presenter = presenter
        self.feedbackPlayer = feedbackPlayer
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
                context.duration = 0.5
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                view.animator().alphaValue = 0
                view.animator().layer?.transform = CATransform3DConcat(
                    CATransform3DMakeScale(0.76, 0.76, 1),
                    CATransform3DMakeTranslation(0, -18, 0)
                )
            } completionHandler: {
                view.removeFromSuperview()
            }
        }

        for item in currentPresentation.items {
            let view = itemViews[item.id] ?? {
                let newView = ThumbnailItemView(feedbackPlayer: feedbackPlayer)
                newView.alphaValue = 0
                newView.layer?.transform = CATransform3DConcat(
                    CATransform3DMakeScale(0.94, 0.94, 1),
                    CATransform3DMakeTranslation(0, 14, 0)
                )
                addSubview(newView)
                itemViews[item.id] = newView
                return newView
            }()
            view.configure(with: item.record)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
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
                    context.duration = 0.22
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
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedRed: 0.56, green: 0.94, blue: 1, alpha: 0.22).cgColor
        layer?.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.11, blue: 0.14, alpha: 0.34).cgColor
        contentTintColor = NSColor.white.withAlphaComponent(0.82)
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
        layer?.backgroundColor = NSColor(
            calibratedRed: 0.08,
            green: 0.15,
            blue: 0.19,
            alpha: isHovering ? 0.48 : 0.34
        ).cgColor
        contentTintColor = NSColor.white.withAlphaComponent(isHovering ? 0.98 : 0.82)
    }
}
