import AppKit
import SlickShotCore

@MainActor
final class ThumbnailItemView: NSView {
    private let imageView = NSImageView()
    private let dragSessionProvider = DragSessionProvider()
    private var record: ScreenshotRecord?
    private var mouseDownEvent: NSEvent?
    private var hasStartedDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 0.92).cgColor

        imageView.imageScaling = .scaleAxesIndependently
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with record: ScreenshotRecord) {
        self.record = record
        imageView.image = NSImage(data: record.displayThumbnailRepresentation)
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
}
