import AppKit
import CoreGraphics
import SlickShotCore

@MainActor
final class ThumbnailStackView: NSView {
    private let foregroundSize = CGSize(width: 220, height: 148)
    private let backgroundSize = CGSize(width: 206, height: 136)
    private let presenter: ThumbnailStackPresenter
    private let closeButton = HoverCloseButton(frame: .zero)
    private let feedbackPlayer: CaptureFeedbackPlaying
    private let onDeleteCurrent: (UUID) -> Void
    private let backdropGlowLayer = CAGradientLayer()
    private var hoverTrackingArea: NSTrackingArea?
    private var isHoveringForeground = false
    private var foregroundFrame: CGRect = .zero
    private var currentPresentation = ThumbnailStackPresenter.Presentation(items: [])
    private var itemViews: [UUID: ThumbnailItemView] = [:]

    init(
        presenter: ThumbnailStackPresenter = ThumbnailStackPresenter(),
        feedbackPlayer: CaptureFeedbackPlaying = NullCaptureFeedbackPlayer(),
        onDeleteCurrent: @escaping (UUID) -> Void = { _ in }
    ) {
        self.presenter = presenter
        self.feedbackPlayer = feedbackPlayer
        self.onDeleteCurrent = onDeleteCurrent
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        configureBackdropGlow()
        setupCloseButton()
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
        foregroundFrame = .zero
        applyChromeState(animated: false)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        layoutItemViews()
        layoutCloseButton()
        backdropGlowLayer.frame = bounds.insetBy(dx: 12, dy: 8)
        refreshHoverStateFromMouseLocation()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        refreshHoverStateFromMouseLocation()
    }

    override func mouseEntered(with event: NSEvent) {
        refreshHoverStateFromMouseLocation()
    }

    override func mouseExited(with event: NSEvent) {
        setHover(false)
    }

    override func mouseMoved(with event: NSEvent) {
        refreshHoverStateFromMouseLocation()
    }

    private func setupCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.zPosition = 10_000
        closeButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Delete screenshot"
        )
        closeButton.alphaValue = 0
        closeButton.target = self
        closeButton.action = #selector(deleteCurrentRecord)
        addSubview(closeButton, positioned: .above, relativeTo: nil)
    }

    private func configureBackdropGlow() {
        backdropGlowLayer.colors = [
            NSColor(calibratedRed: 0.38, green: 0.9, blue: 1, alpha: 0.14).cgColor,
            NSColor(calibratedRed: 0.76, green: 0.98, blue: 1, alpha: 0.06).cgColor,
            NSColor.clear.cgColor
        ]
        backdropGlowLayer.locations = [0, 0.42, 1]
        backdropGlowLayer.startPoint = CGPoint(x: 0.78, y: 0.16)
        backdropGlowLayer.endPoint = CGPoint(x: 0.18, y: 0.94)
        backdropGlowLayer.opacity = 0
        layer?.addSublayer(backdropGlowLayer)
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
                    CATransform3DMakeScale(0.72, 0.72, 1),
                    CATransform3DMakeTranslation(18, -20, 0)
                )
            } completionHandler: {
                view.removeFromSuperview()
            }
        }

        for item in currentPresentation.items {
            let isNewView = itemViews[item.id] == nil
            let view = itemViews[item.id] ?? {
                let newView = ThumbnailItemView(feedbackPlayer: feedbackPlayer)
                newView.alphaValue = 0
                newView.layer?.transform = CATransform3DConcat(
                    CATransform3DMakeScale(0.9, 0.9, 1),
                    CATransform3DMakeTranslation(0, 22, 0)
                )
                addSubview(newView)
                itemViews[item.id] = newView
                return newView
            }()
            view.configure(with: item.record)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = item.role == .foreground ? 0.34 : 0.26
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                view.animator().alphaValue = 1
                view.animator().layer?.transform = CATransform3DIdentity
            }
            if isNewView {
                view.playArrivalEffect()
            }
        }

        addSubview(closeButton, positioned: .above, relativeTo: nil)
    }

    private func layoutCloseButton() {
        let size: CGFloat = 22
        guard foregroundFrame.isEmpty == false else {
            closeButton.frame = CGRect(x: bounds.maxX - size, y: bounds.maxY - size, width: size, height: size)
            return
        }

        let inset: CGFloat = 6
        closeButton.frame = CGRect(
            x: foregroundFrame.maxX - inset - size,
            y: foregroundFrame.maxY - inset - size,
            width: size,
            height: size
        )
    }

    private func layoutItemViews() {
        let anchorX = bounds.maxX - 12
        let anchorY = bounds.minY + 12
        foregroundFrame = .zero

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

            if item.role == .foreground {
                foregroundFrame = frame
            }

            let targetScale = CATransform3DMakeScale(item.scale, item.scale, 1)
            view.layer?.transform = targetScale
            view.alphaValue = alpha(for: item)
        }
    }

    private func alpha(for item: ThumbnailStackPresenter.Item) -> CGFloat {
        switch item.role {
        case .foreground:
            return 1
        case .background(let depth):
            let base = depth == 1 ? 0.74 : 0.48
            return isHoveringForeground ? min(0.88, base + 0.1) : base
        }
    }

    private func setHover(_ isHovering: Bool) {
        guard isHoveringForeground != isHovering else { return }
        isHoveringForeground = isHovering
        applyChromeState(animated: true)
        needsLayout = true
    }

    private func refreshHoverStateFromMouseLocation() {
        guard let window else {
            setHover(false)
            return
        }
        guard foregroundFrame.isEmpty == false else {
            setHover(false)
            return
        }

        let mouseLocation = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let hoverRect = foregroundFrame.insetBy(dx: -8, dy: -8)
        setHover(hoverRect.contains(mouseLocation))
    }

    private func applyChromeState(animated: Bool) {
        let hasItems = currentPresentation.items.isEmpty == false
        let closeAlpha: CGFloat = hasItems && isHoveringForeground ? 1 : 0
        let glowOpacity: Float = hasItems ? (isHoveringForeground ? 1 : 0.72) : 0

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                closeButton.animator().alphaValue = closeAlpha
            }

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            backdropGlowLayer.opacity = glowOpacity
            CATransaction.commit()
        } else {
            closeButton.alphaValue = closeAlpha
            backdropGlowLayer.opacity = glowOpacity
        }
    }

    @objc
    private func deleteCurrentRecord() {
        guard let id = currentPresentation.items.first?.id else { return }
        onDeleteCurrent(id)
    }

}

private final class HoverCloseButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer?.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.1, blue: 0.12, alpha: 0.54).cgColor
        layer?.shadowColor = NSColor(calibratedRed: 0.34, green: 0.86, blue: 1, alpha: 0.34).cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: 6)
        contentTintColor = NSColor.white.withAlphaComponent(0.9)
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
            alpha: isHovering ? 0.72 : 0.54
        ).cgColor
        layer?.borderColor = NSColor(
            calibratedRed: 1,
            green: 1,
            blue: 1,
            alpha: isHovering ? 0.34 : 0.22
        ).cgColor
        contentTintColor = NSColor.white.withAlphaComponent(isHovering ? 1 : 0.9)
    }
}
