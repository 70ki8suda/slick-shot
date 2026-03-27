import AppKit
import SlickShotCore

@MainActor
final class ThumbnailItemView: NSView {
    private let imageView = NSImageView()
    private let dragSessionProvider: DragSessionProvider
    private var record: ScreenshotRecord?
    private var mouseDownEvent: NSEvent?
    private var hasStartedDrag = false
    private var hoverTrackingArea: NSTrackingArea?
    private let sheenLayer = CAGradientLayer()
    private let glowLayer = CAGradientLayer()
    private let rimLayer = CAShapeLayer()
    private let gridLayer = CAShapeLayer()
    private let accentLayer = CAShapeLayer()
    private let cornerLayer = CAShapeLayer()
    private let scanlineLayer = CAGradientLayer()
    private let glassSurfaceLayer = CAShapeLayer()
    private var isHovering = false

    init(frame frameRect: NSRect = .zero, feedbackPlayer: CaptureFeedbackPlaying = NullCaptureFeedbackPlayer()) {
        self.dragSessionProvider = DragSessionProvider(feedbackPlayer: feedbackPlayer)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.shadowColor = NSColor(calibratedRed: 0.82, green: 0.94, blue: 1, alpha: 0.24).cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: 14)

        imageView.imageScaling = .scaleAxesIndependently
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        addSubview(imageView)

        configureOverlayLayers()

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with record: ScreenshotRecord) {
        self.record = record
        imageView.image = NSImage(data: record.displayThumbnailRepresentation)
    }

    func playArrivalEffect() {
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.15, 0, 0.18]
        sweep.toValue = [0.82, 1, 1.18]
        sweep.duration = 0.54
        sweep.timingFunction = CAMediaTimingFunction(name: .easeOut)
        sheenLayer.add(sweep, forKey: "arrivalSweep")

        let halo = CABasicAnimation(keyPath: "opacity")
        halo.fromValue = 0.82
        halo.toValue = 0.34
        halo.duration = 0.42
        halo.timingFunction = CAMediaTimingFunction(name: .easeOut)
        glowLayer.add(halo, forKey: "arrivalGlow")

        let cornerPulse = CABasicAnimation(keyPath: "strokeEnd")
        cornerPulse.fromValue = 0.12
        cornerPulse.toValue = 1
        cornerPulse.duration = 0.34
        cornerPulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        cornerLayer.add(cornerPulse, forKey: "arrivalCorners")
    }

    override func layout() {
        super.layout()
        let overlayBounds = bounds.insetBy(dx: 1, dy: 1)
        let outerShape = Self.thumbnailFramePath(in: overlayBounds.insetBy(dx: 0.5, dy: 0.5))
        let innerShape = Self.thumbnailFramePath(in: overlayBounds.insetBy(dx: 7, dy: 7))
        let imageShape = Self.thumbnailFramePath(in: imageView.frame.insetBy(dx: 0.5, dy: 0.5))

        imageView.layer?.mask = {
            let mask = CAShapeLayer()
            mask.frame = imageView.bounds
            mask.path = Self.thumbnailFramePath(in: imageView.bounds.insetBy(dx: 0.5, dy: 0.5)).cgPath
            return mask
        }()

        glowLayer.frame = overlayBounds.insetBy(dx: -10, dy: -10)
        sheenLayer.frame = overlayBounds
        scanlineLayer.frame = overlayBounds
        glassSurfaceLayer.frame = overlayBounds
        rimLayer.frame = overlayBounds
        gridLayer.frame = overlayBounds
        accentLayer.frame = overlayBounds
        cornerLayer.frame = overlayBounds

        glassSurfaceLayer.path = outerShape.cgPath
        accentLayer.path = outerShape.cgPath
        rimLayer.path = innerShape.cgPath
        gridLayer.path = Self.gridPath(in: overlayBounds.insetBy(dx: 10, dy: 10), spacing: 22).cgPath
        cornerLayer.path = nil

        glowLayer.mask = {
            let mask = CAShapeLayer()
            mask.frame = glowLayer.bounds
            mask.path = outerShape.cgPath
            return mask
        }()
        sheenLayer.mask = {
            let mask = CAShapeLayer()
            mask.frame = sheenLayer.bounds
            mask.path = outerShape.cgPath
            return mask
        }()
        scanlineLayer.mask = {
            let mask = CAShapeLayer()
            mask.frame = scanlineLayer.bounds
            mask.path = imageShape.cgPath
            return mask
        }()
        gridLayer.mask = {
            let mask = CAShapeLayer()
            mask.frame = gridLayer.bounds
            mask.path = innerShape.cgPath
            return mask
        }()
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

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        hasStartedDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard hasStartedDrag == false,
              let record,
              let mouseDownEvent,
              dragDistance(from: mouseDownEvent, to: event) >= 4 else {
            return
        }

        hasStartedDrag = dragSessionProvider.beginDrag(for: record, from: self, event: mouseDownEvent)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        hasStartedDrag = false
    }

    private func dragDistance(from startEvent: NSEvent, to currentEvent: NSEvent) -> CGFloat {
        let start = convert(startEvent.locationInWindow, from: nil)
        let current = convert(currentEvent.locationInWindow, from: nil)
        return hypot(current.x - start.x, current.y - start.y)
    }

    private func configureOverlayLayers() {
        glassSurfaceLayer.fillColor = NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.15, alpha: 0.16).cgColor
        glassSurfaceLayer.strokeColor = nil

        glowLayer.colors = [
            NSColor(calibratedRed: 0.9, green: 0.98, blue: 1, alpha: 0.1).cgColor,
            NSColor(calibratedRed: 0.78, green: 0.94, blue: 1, alpha: 0.07).cgColor,
            NSColor.clear.cgColor
        ]
        glowLayer.locations = [0, 0.42, 1]
        glowLayer.startPoint = CGPoint(x: 0.08, y: 1)
        glowLayer.endPoint = CGPoint(x: 0.9, y: 0.08)

        sheenLayer.colors = [
            NSColor.white.withAlphaComponent(0.28).cgColor,
            NSColor(calibratedRed: 0.74, green: 0.97, blue: 1, alpha: 0.12).cgColor,
            NSColor.clear.cgColor
        ]
        sheenLayer.locations = [0, 0.35, 1]
        sheenLayer.startPoint = CGPoint(x: 0.08, y: 1)
        sheenLayer.endPoint = CGPoint(x: 0.92, y: 0)

        scanlineLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.white.withAlphaComponent(0.08).cgColor,
            NSColor(calibratedRed: 0.6, green: 0.95, blue: 1, alpha: 0.12).cgColor,
            NSColor.clear.cgColor
        ]
        scanlineLayer.locations = [0, 0.46, 0.54, 1]
        scanlineLayer.startPoint = CGPoint(x: 0, y: 1)
        scanlineLayer.endPoint = CGPoint(x: 0, y: 0)

        rimLayer.fillColor = NSColor.clear.cgColor
        rimLayer.strokeColor = NSColor.white.withAlphaComponent(0.16).cgColor
        rimLayer.lineWidth = 1

        gridLayer.fillColor = NSColor.clear.cgColor
        gridLayer.strokeColor = NSColor(calibratedRed: 0.63, green: 0.96, blue: 1, alpha: 0.08).cgColor
        gridLayer.lineWidth = 0.7

        accentLayer.fillColor = NSColor.clear.cgColor
        accentLayer.strokeColor = NSColor(calibratedRed: 0.62, green: 0.96, blue: 1, alpha: 0.42).cgColor
        accentLayer.lineWidth = 1.05

        cornerLayer.fillColor = NSColor.clear.cgColor
        cornerLayer.strokeColor = NSColor.white.withAlphaComponent(0.84).cgColor
        cornerLayer.lineWidth = 1.6
        cornerLayer.lineCap = .round

        layer?.addSublayer(glassSurfaceLayer)
        layer?.addSublayer(glowLayer)
        layer?.addSublayer(sheenLayer)
        layer?.addSublayer(scanlineLayer)
        layer?.addSublayer(rimLayer)
        layer?.addSublayer(gridLayer)
        layer?.addSublayer(accentLayer)
        layer?.addSublayer(cornerLayer)
    }

    private func setHover(_ isHovering: Bool) {
        guard self.isHovering != isHovering else { return }
        self.isHovering = isHovering

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        layer?.shadowOpacity = isHovering ? 0.24 : 0.18
        layer?.shadowRadius = isHovering ? 22 : 18
        accentLayer.strokeColor = NSColor(
            calibratedRed: 0.68,
            green: 0.98,
            blue: 1,
            alpha: isHovering ? 0.6 : 0.42
        ).cgColor
        gridLayer.strokeColor = NSColor(
            calibratedRed: 0.63,
            green: 0.96,
            blue: 1,
            alpha: isHovering ? 0.12 : 0.08
        ).cgColor
        CATransaction.commit()
    }

    private static func thumbnailFramePath(in rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        let cornerCut = min(max(min(rect.width, rect.height) * 0.055, 7), 9)
        let stepWidth = cornerCut
        let stepHeight = min(max(rect.height * 0.5, 56), 74)
        let stepBottomOffset = min(max(rect.height * 0.2, 22), 30)

        let leftX = rect.minX
        let rightX = rect.maxX - stepWidth
        let outerStepX = rect.maxX
        let topY = rect.maxY
        let bottomY = rect.minY
        let stepBottomY = bottomY + stepBottomOffset
        let stepTopY = stepBottomY + stepHeight

        path.move(to: CGPoint(x: leftX + cornerCut, y: topY))
        path.line(to: CGPoint(x: rightX - cornerCut, y: topY))
        path.line(to: CGPoint(x: rightX, y: topY - cornerCut))
        path.line(to: CGPoint(x: rightX, y: stepTopY))
        path.line(to: CGPoint(x: outerStepX, y: stepTopY - cornerCut))
        path.line(to: CGPoint(x: outerStepX, y: stepBottomY + cornerCut))
        path.line(to: CGPoint(x: rightX, y: stepBottomY))
        path.line(to: CGPoint(x: rightX, y: bottomY + cornerCut))
        path.line(to: CGPoint(x: rightX - cornerCut, y: bottomY))
        path.line(to: CGPoint(x: leftX + cornerCut, y: bottomY))
        path.line(to: CGPoint(x: leftX, y: bottomY + cornerCut))
        path.line(to: CGPoint(x: leftX, y: topY - cornerCut))
        path.close()
        return path
    }

    private static func cornerAccentPath(in rect: CGRect, length: CGFloat, inset: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let minX = rect.minX + inset
        let maxX = rect.maxX - inset
        let minY = rect.minY + inset
        let maxY = rect.maxY - inset

        path.move(to: CGPoint(x: minX, y: maxY - length))
        path.line(to: CGPoint(x: minX, y: maxY))
        path.line(to: CGPoint(x: minX + length, y: maxY))

        path.move(to: CGPoint(x: maxX - length, y: maxY))
        path.line(to: CGPoint(x: maxX, y: maxY))
        path.line(to: CGPoint(x: maxX, y: maxY - length))

        path.move(to: CGPoint(x: maxX, y: minY + length))
        path.line(to: CGPoint(x: maxX, y: minY))
        path.line(to: CGPoint(x: maxX - length, y: minY))

        path.move(to: CGPoint(x: minX + length, y: minY))
        path.line(to: CGPoint(x: minX, y: minY))
        path.line(to: CGPoint(x: minX, y: minY + length))

        return path
    }

    private static func gridPath(in rect: CGRect, spacing: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()

        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.line(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }

        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.line(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }

        return path
    }
}
