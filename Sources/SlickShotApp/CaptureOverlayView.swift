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
    private var pendingOuterFrameReveal: DispatchWorkItem?
    private let topEdgeLayer = CAShapeLayer()
    private let bottomEdgeLayer = CAShapeLayer()
    private let leftEdgeLayer = CAShapeLayer()
    private let rightEdgeLayer = CAShapeLayer()
    private let outerFrameLayer = CAShapeLayer()
    private let lagGlowLayer = CAShapeLayer()
    private let reticleTiming = CAMediaTimingFunction(controlPoints: 0.22, 1.14, 0.28, 1)
    private let minimumDecoratedExtent: CGFloat = 72

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
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        pendingReticleUpdate?.cancel()
        pendingOuterFrameReveal?.cancel()
        cancelReticleAnimations()
        displayedReticleRect = nil
        updateReticleLayers(animated: false)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        pendingOuterFrameReveal?.cancel()
        cancelReticleAnimations()
        displayedReticleRect = nil
        updateReticleLayers(animated: false)
        scheduleReticleUpdate()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        defer {
            startPoint = nil
            currentPoint = nil
            pendingReticleUpdate?.cancel()
            pendingOuterFrameReveal?.cancel()
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
        let edgeLayers = [topEdgeLayer, bottomEdgeLayer, leftEdgeLayer, rightEdgeLayer]
        for edgeLayer in edgeLayers {
            edgeLayer.fillColor = NSColor.clear.cgColor
            edgeLayer.strokeColor = NSColor(calibratedRed: 0.44, green: 0.92, blue: 1, alpha: 0.92).cgColor
            edgeLayer.lineWidth = 1.35
            edgeLayer.lineCap = .round
            edgeLayer.strokeStart = 0
            edgeLayer.strokeEnd = 1
            edgeLayer.opacity = 0
        }

        lagGlowLayer.fillColor = NSColor.clear.cgColor
        lagGlowLayer.strokeColor = NSColor(calibratedRed: 0.3, green: 0.84, blue: 1, alpha: 0.28).cgColor
        lagGlowLayer.lineWidth = 1.6
        lagGlowLayer.shadowColor = NSColor(calibratedRed: 0.34, green: 0.88, blue: 1, alpha: 0.72).cgColor
        lagGlowLayer.shadowOpacity = 0.46
        lagGlowLayer.shadowRadius = 12
        lagGlowLayer.shadowOffset = .zero
        lagGlowLayer.opacity = 0

        outerFrameLayer.fillColor = NSColor.clear.cgColor
        outerFrameLayer.strokeColor = NSColor(calibratedRed: 0.62, green: 0.97, blue: 1, alpha: 0.68).cgColor
        outerFrameLayer.lineWidth = 1.2
        outerFrameLayer.lineCap = .round
        outerFrameLayer.lineJoin = .round
        outerFrameLayer.opacity = 0

        layer?.addSublayer(lagGlowLayer)
        layer?.addSublayer(outerFrameLayer)
    }

    private func updateReticleLayers(animated: Bool) {
        guard let displayedReticleRect else {
            cancelReticleAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            lagGlowLayer.opacity = 0
            outerFrameLayer.opacity = 0
            lagGlowLayer.path = nil
            outerFrameLayer.path = nil
            CATransaction.commit()
            return
        }

        let outerRect = displayedReticleRect.insetBy(dx: -10, dy: -10)
        guard shouldShowDecoratedReticle(for: outerRect) else {
            cancelReticleAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            lagGlowLayer.opacity = 0
            outerFrameLayer.opacity = 0
            lagGlowLayer.path = nil
            outerFrameLayer.path = nil
            CATransaction.commit()
            return
        }
        let outerFramePath = Self.outerReticlePath(in: outerRect).cgPath

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lagGlowLayer.path = outerFramePath
        outerFrameLayer.path = outerFramePath
        lagGlowLayer.opacity = 0
        outerFrameLayer.opacity = animated ? 0 : 1
        CATransaction.commit()

        if animated {
            scheduleOuterFrameReveal()
        }
    }

    private func scheduleReticleUpdate() {
        pendingReticleUpdate?.cancel()
        guard selectionRect != nil else {
            displayedReticleRect = nil
            updateReticleLayers(animated: false)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let settledRect = self.selectionRect else { return }
            self.displayedReticleRect = settledRect
            self.updateReticleLayers(animated: true)
        }
        pendingReticleUpdate = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
    }

    private func scheduleOuterFrameReveal() {
        pendingOuterFrameReveal?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.selectionRect != nil, self.displayedReticleRect != nil else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.outerFrameLayer.opacity = 1
            CATransaction.commit()
        }
        pendingOuterFrameReveal = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func animateLineExpansion(for layer: CAShapeLayer, duration: CFTimeInterval) {
        layer.removeAnimation(forKey: "reticleStrokeStart")
        layer.removeAnimation(forKey: "reticleStrokeEnd")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.strokeStart = 0.5
        layer.strokeEnd = 0.5
        CATransaction.commit()

        let startAnimation = CABasicAnimation(keyPath: "strokeStart")
        startAnimation.fromValue = 0.5
        startAnimation.toValue = 0
        startAnimation.duration = duration
        startAnimation.timingFunction = reticleTiming

        let endAnimation = CABasicAnimation(keyPath: "strokeEnd")
        endAnimation.fromValue = 0.5
        endAnimation.toValue = 1
        endAnimation.duration = duration
        endAnimation.timingFunction = reticleTiming

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.strokeStart = 0
        layer.strokeEnd = 1
        CATransaction.commit()

        layer.add(startAnimation, forKey: "reticleStrokeStart")
        layer.add(endAnimation, forKey: "reticleStrokeEnd")
    }

    private func cancelReticleAnimations() {
        [topEdgeLayer, bottomEdgeLayer, leftEdgeLayer, rightEdgeLayer].forEach {
            $0.removeAnimation(forKey: "reticleStrokeStart")
            $0.removeAnimation(forKey: "reticleStrokeEnd")
        }
    }

    private func shouldShowDecoratedReticle(for rect: CGRect) -> Bool {
        rect.width >= minimumDecoratedExtent && rect.height >= minimumDecoratedExtent
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

    private static func outerReticlePath(in rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        let horizontalInset = min(max(rect.width * 0.09, 16), 26)
        let verticalInset = min(max(rect.height * 0.09, 12), 22)
        let cornerCut = min(max(min(rect.width, rect.height) * 0.055, 8), 12)
        let sideLean = min(max(rect.width * 0.012, 2), 6)
        let stepOut = min(max(rect.width * 0.055, 10), 20)
        let stepTopY = rect.minY + rect.height * 0.3
        let stepBottomY = rect.minY + rect.height * 0.12

        let leftXTop = rect.minX - horizontalInset
        let leftXBottom = leftXTop + sideLean
        let rightXTop = rect.maxX + horizontalInset
        let rightXBottom = rightXTop - sideLean
        let topY = rect.maxY + verticalInset
        let bottomY = rect.minY - verticalInset

        path.move(to: CGPoint(x: leftXTop + cornerCut, y: topY))
        path.line(to: CGPoint(x: rightXTop - cornerCut, y: topY))
        path.line(to: CGPoint(x: rightXTop, y: topY - cornerCut))
        path.line(to: CGPoint(x: rightXTop + sideLean, y: stepTopY))
        path.line(to: CGPoint(x: rightXTop + stepOut, y: stepTopY - cornerCut))
        path.line(to: CGPoint(x: rightXTop + stepOut, y: stepBottomY + cornerCut))
        path.line(to: CGPoint(x: rightXBottom + sideLean, y: stepBottomY))
        path.line(to: CGPoint(x: rightXBottom, y: bottomY + cornerCut))
        path.line(to: CGPoint(x: rightXBottom - cornerCut, y: bottomY))
        path.line(to: CGPoint(x: leftXBottom + cornerCut, y: bottomY))
        path.line(to: CGPoint(x: leftXBottom, y: bottomY + cornerCut))
        path.line(to: CGPoint(x: leftXTop, y: topY - cornerCut))
        path.close()
        return path
    }

}
