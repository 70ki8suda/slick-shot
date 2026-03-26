import AppKit
import SlickShotCore

@MainActor
final class ThumbnailItemView: NSView {
    private let imageView = NSImageView()
    private let dragSessionProvider: DragSessionProvider
    private var record: ScreenshotRecord?
    private var mouseDownEvent: NSEvent?
    private var hasStartedDrag = false
    private let sheenLayer = CAGradientLayer()
    private let accentLayer = CAShapeLayer()
    private let cornerLayer = CAShapeLayer()

    init(frame frameRect: NSRect = .zero, feedbackPlayer: CaptureFeedbackPlaying = NullCaptureFeedbackPlayer()) {
        self.dragSessionProvider = DragSessionProvider(feedbackPlayer: feedbackPlayer)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedRed: 0.55, green: 0.94, blue: 1, alpha: 0.52).cgColor
        layer?.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.09, blue: 0.12, alpha: 0.42).cgColor
        layer?.shadowColor = NSColor(calibratedRed: 0.32, green: 0.84, blue: 1, alpha: 0.56).cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: 12)

        imageView.imageScaling = .scaleAxesIndependently
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 16
        imageView.layer?.masksToBounds = true
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

    override func layout() {
        super.layout()
        let overlayBounds = bounds.insetBy(dx: 1, dy: 1)
        sheenLayer.frame = overlayBounds
        accentLayer.frame = overlayBounds
        cornerLayer.frame = overlayBounds
        accentLayer.path = NSBezierPath(
            roundedRect: overlayBounds.insetBy(dx: 1.5, dy: 1.5),
            xRadius: 16,
            yRadius: 16
        ).cgPath
        cornerLayer.path = Self.cornerAccentPath(in: overlayBounds, length: 18, inset: 10).cgPath
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
        sheenLayer.colors = [
            NSColor.white.withAlphaComponent(0.18).cgColor,
            NSColor(calibratedRed: 0.72, green: 0.96, blue: 1, alpha: 0.08).cgColor,
            NSColor.clear.cgColor
        ]
        sheenLayer.locations = [0, 0.35, 1]
        sheenLayer.startPoint = CGPoint(x: 0.08, y: 1)
        sheenLayer.endPoint = CGPoint(x: 0.92, y: 0)

        accentLayer.fillColor = NSColor.clear.cgColor
        accentLayer.strokeColor = NSColor(calibratedRed: 0.62, green: 0.96, blue: 1, alpha: 0.34).cgColor
        accentLayer.lineWidth = 1

        cornerLayer.fillColor = NSColor.clear.cgColor
        cornerLayer.strokeColor = NSColor.white.withAlphaComponent(0.72).cgColor
        cornerLayer.lineWidth = 1.4
        cornerLayer.lineCap = .round

        layer?.addSublayer(sheenLayer)
        layer?.addSublayer(accentLayer)
        layer?.addSublayer(cornerLayer)
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
}
