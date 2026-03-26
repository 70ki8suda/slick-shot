import AppKit
import CoreGraphics

@MainActor
final class CaptureOverlayView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var displayedReticleRect: CGRect?
    private var pendingReticleUpdate: DispatchWorkItem?
    private let lagFrameLayer = CAShapeLayer()
    private let lagCornerLayer = CAShapeLayer()
    private let lagGlowLayer = CAShapeLayer()
    private let reticleTiming = CAMediaTimingFunction(controlPoints: 0.16, 0.88, 0.24, 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configureReticleLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.01, green: 0.05, blue: 0.08, alpha: 0.42).setFill()
        Self.dimmingRects(in: bounds, excluding: selectionRect).forEach { $0.fill() }

        guard let selectionRect else { return }

        NSColor(calibratedRed: 0.42, green: 0.92, blue: 1, alpha: 0.08).setFill()
        NSBezierPath(rect: selectionRect).fill()

        drawScanlines(in: selectionRect)

        let framePath = NSBezierPath(rect: selectionRect)
        framePath.lineWidth = 1.4
        NSColor(calibratedRed: 0.48, green: 0.95, blue: 1, alpha: 0.92).setStroke()
        framePath.stroke()

        let cornerPath = Self.crosshairAccentPath(in: selectionRect, length: 18, gap: 7)
        cornerPath.lineWidth = 2.4
        NSColor.white.withAlphaComponent(0.86).setStroke()
        cornerPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        pendingReticleUpdate?.cancel()
        displayedReticleRect = selectionRect
        updateReticleLayers(animated: false)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        scheduleReticleUpdate()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        defer {
            startPoint = nil
            currentPoint = nil
            pendingReticleUpdate?.cancel()
            displayedReticleRect = nil
            updateReticleLayers(animated: false)
            needsDisplay = true
        }

        guard let selectionRect else {
            onCancel?()
            return
        }

        let screenRect = convertSelectionToScreen(selectionRect)
        guard screenRect.width > 0, screenRect.height > 0 else {
            onCancel?()
            return
        }

        onSelection?(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        super.keyDown(with: event)
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func convertSelectionToScreen(_ rect: CGRect) -> CGRect {
        guard let window else { return .zero }
        return CGRect(
            x: window.frame.minX + rect.minX,
            y: window.frame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        ).integral
    }

    private func configureReticleLayers() {
        lagGlowLayer.fillColor = NSColor.clear.cgColor
        lagGlowLayer.strokeColor = NSColor(calibratedRed: 0.3, green: 0.84, blue: 1, alpha: 0.28).cgColor
        lagGlowLayer.lineWidth = 1.6
        lagGlowLayer.shadowColor = NSColor(calibratedRed: 0.34, green: 0.88, blue: 1, alpha: 0.72).cgColor
        lagGlowLayer.shadowOpacity = 0.46
        lagGlowLayer.shadowRadius = 12
        lagGlowLayer.shadowOffset = .zero
        lagGlowLayer.opacity = 0

        lagFrameLayer.fillColor = NSColor.clear.cgColor
        lagFrameLayer.strokeColor = NSColor(calibratedRed: 0.44, green: 0.92, blue: 1, alpha: 0.92).cgColor
        lagFrameLayer.lineWidth = 1.2
        lagFrameLayer.lineJoin = .round
        lagFrameLayer.opacity = 0

        lagCornerLayer.fillColor = NSColor.clear.cgColor
        lagCornerLayer.strokeColor = NSColor.white.withAlphaComponent(0.94).cgColor
        lagCornerLayer.lineWidth = 1.8
        lagCornerLayer.lineCap = .round
        lagCornerLayer.opacity = 0

        layer?.addSublayer(lagGlowLayer)
        layer?.addSublayer(lagFrameLayer)
        layer?.addSublayer(lagCornerLayer)
    }

    private func updateReticleLayers(animated: Bool) {
        guard let displayedReticleRect else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            lagGlowLayer.opacity = 0
            lagFrameLayer.opacity = 0
            lagCornerLayer.opacity = 0
            lagGlowLayer.path = nil
            lagFrameLayer.path = nil
            lagCornerLayer.path = nil
            CATransaction.commit()
            return
        }

        let outerRect = displayedReticleRect.insetBy(dx: -12, dy: -12)
        let framePath = NSBezierPath(rect: outerRect).cgPath
        let cornerPath = Self.crosshairAccentPath(in: outerRect, length: 20, gap: 10).cgPath

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setAnimationTimingFunction(reticleTiming)
        } else {
            CATransaction.setDisableActions(true)
        }
        lagGlowLayer.opacity = 1
        lagFrameLayer.opacity = 1
        lagCornerLayer.opacity = 1
        lagGlowLayer.path = framePath
        lagFrameLayer.path = framePath
        lagCornerLayer.path = cornerPath
        CATransaction.commit()
    }

    private func scheduleReticleUpdate() {
        pendingReticleUpdate?.cancel()
        guard let selectionRect else {
            displayedReticleRect = nil
            updateReticleLayers(animated: false)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.displayedReticleRect = selectionRect
            self.updateReticleLayers(animated: true)
        }
        pendingReticleUpdate = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075, execute: workItem)
    }

    nonisolated static func dimmingRects(in bounds: CGRect, excluding selectionRect: CGRect?) -> [CGRect] {
        guard let selectionRect else {
            return [bounds]
        }

        return [
            CGRect(
                x: bounds.minX,
                y: selectionRect.maxY,
                width: bounds.width,
                height: bounds.maxY - selectionRect.maxY
            ),
            CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: selectionRect.minY - bounds.minY
            ),
            CGRect(
                x: bounds.minX,
                y: selectionRect.minY,
                width: selectionRect.minX - bounds.minX,
                height: selectionRect.height
            ),
            CGRect(
                x: selectionRect.maxX,
                y: selectionRect.minY,
                width: bounds.maxX - selectionRect.maxX,
                height: selectionRect.height
            )
        ].filter { !$0.isEmpty }
    }

    private func drawScanlines(in rect: CGRect) {
        let path = NSBezierPath()
        let step: CGFloat = 6
        var y = rect.minY + step
        while y < rect.maxY {
            path.move(to: CGPoint(x: rect.minX + 1, y: y))
            path.line(to: CGPoint(x: rect.maxX - 1, y: y))
            y += step
        }
        path.lineWidth = 0.8
        NSColor.white.withAlphaComponent(0.08).setStroke()
        path.stroke()
    }

    private static func crosshairAccentPath(in rect: CGRect, length: CGFloat, gap: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let halfGap = gap / 2

        func drawCrosshair(center: CGPoint, horizontalDirection: CGFloat, verticalDirection: CGFloat) {
            path.move(to: CGPoint(x: center.x - (horizontalDirection * halfGap), y: center.y))
            path.line(to: CGPoint(x: center.x - (horizontalDirection * (halfGap + length)), y: center.y))
            path.move(to: CGPoint(x: center.x, y: center.y - (verticalDirection * halfGap)))
            path.line(to: CGPoint(x: center.x, y: center.y - (verticalDirection * (halfGap + length))))
        }

        drawCrosshair(
            center: CGPoint(x: rect.minX, y: rect.maxY),
            horizontalDirection: -1,
            verticalDirection: 1
        )
        drawCrosshair(
            center: CGPoint(x: rect.maxX, y: rect.maxY),
            horizontalDirection: 1,
            verticalDirection: 1
        )
        drawCrosshair(
            center: CGPoint(x: rect.maxX, y: rect.minY),
            horizontalDirection: 1,
            verticalDirection: -1
        )
        drawCrosshair(
            center: CGPoint(x: rect.minX, y: rect.minY),
            horizontalDirection: -1,
            verticalDirection: -1
        )

        return path
    }
}
