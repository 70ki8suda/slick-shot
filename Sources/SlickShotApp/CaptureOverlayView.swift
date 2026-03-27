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

        let framePath = NSBezierPath(rect: selectionRect)
        framePath.lineWidth = 1.4
        NSColor(calibratedRed: 0.48, green: 0.95, blue: 1, alpha: 0.92).setStroke()
        framePath.stroke()

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
        edgeLayers.forEach { layer?.addSublayer($0) }
    }

    private func updateReticleLayers(animated: Bool) {
        guard let displayedReticleRect else {
            cancelReticleAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            lagGlowLayer.opacity = 0
            outerFrameLayer.opacity = 0
            topEdgeLayer.opacity = 0
            bottomEdgeLayer.opacity = 0
            leftEdgeLayer.opacity = 0
            rightEdgeLayer.opacity = 0
            lagGlowLayer.path = nil
            outerFrameLayer.path = nil
            topEdgeLayer.path = nil
            bottomEdgeLayer.path = nil
            leftEdgeLayer.path = nil
            rightEdgeLayer.path = nil
            topEdgeLayer.strokeStart = 0
            topEdgeLayer.strokeEnd = 1
            bottomEdgeLayer.strokeStart = 0
            bottomEdgeLayer.strokeEnd = 1
            leftEdgeLayer.strokeStart = 0
            leftEdgeLayer.strokeEnd = 1
            rightEdgeLayer.strokeStart = 0
            rightEdgeLayer.strokeEnd = 1
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
            topEdgeLayer.opacity = 0
            bottomEdgeLayer.opacity = 0
            leftEdgeLayer.opacity = 0
            rightEdgeLayer.opacity = 0
            lagGlowLayer.path = nil
            outerFrameLayer.path = nil
            topEdgeLayer.path = nil
            bottomEdgeLayer.path = nil
            leftEdgeLayer.path = nil
            rightEdgeLayer.path = nil
            CATransaction.commit()
            return
        }
        let outerFramePath = Self.outerReticlePath(in: outerRect).cgPath
        let edgePaths = Self.edgePaths(in: outerRect, inset: 24)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lagGlowLayer.path = outerFramePath
        outerFrameLayer.path = outerFramePath
        topEdgeLayer.path = edgePaths.top
        bottomEdgeLayer.path = edgePaths.bottom
        leftEdgeLayer.path = edgePaths.left
        rightEdgeLayer.path = edgePaths.right
        lagGlowLayer.opacity = 0
        outerFrameLayer.opacity = animated ? 0 : 1
        topEdgeLayer.opacity = 1
        bottomEdgeLayer.opacity = 1
        leftEdgeLayer.opacity = 1
        rightEdgeLayer.opacity = 1
        CATransaction.commit()

        if animated {
            scheduleOuterFrameReveal()
            animateLineExpansion(for: topEdgeLayer, duration: 0.41)
            animateLineExpansion(for: bottomEdgeLayer, duration: 0.41)
            animateLineExpansion(for: leftEdgeLayer, duration: 0.41)
            animateLineExpansion(for: rightEdgeLayer, duration: 0.41)
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
        let cornerCut = min(max(min(rect.width, rect.height) * 0.065, 7), 14)
        let lowerStepInset = min(max(rect.width * 0.09, 14), 24)
        let lowerStepDrop = min(max(rect.height * 0.11, 12), 24)
        let lowerStepWidth = min(max(rect.width * 0.13, 18), 34)
        let bottomRightX = rect.maxX - cornerCut
        let stepTopY = rect.minY + cornerCut + lowerStepDrop
        let stepInnerX = bottomRightX - lowerStepInset
        let stepBottomX = stepInnerX - lowerStepWidth

        path.move(to: CGPoint(x: rect.minX + cornerCut, y: rect.maxY))
        path.line(to: CGPoint(x: rect.maxX - cornerCut, y: rect.maxY))
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerCut))
        path.line(to: CGPoint(x: rect.maxX, y: stepTopY))
        path.line(to: CGPoint(x: stepInnerX, y: stepTopY))
        path.line(to: CGPoint(x: stepInnerX, y: rect.minY + cornerCut))
        path.line(to: CGPoint(x: stepBottomX, y: rect.minY))
        path.line(to: CGPoint(x: rect.minX + cornerCut, y: rect.minY))
        path.line(to: CGPoint(x: rect.minX, y: rect.minY + cornerCut))
        path.line(to: CGPoint(x: rect.minX, y: rect.maxY - cornerCut))
        path.close()
        return path
    }

    private static func edgePaths(in rect: CGRect, inset: CGFloat) -> (top: CGPath, bottom: CGPath, left: CGPath, right: CGPath) {
        let horizontalInset = min(inset, rect.width * 0.3)
        let verticalInset = min(inset, rect.height * 0.3)

        func horizontalPath(y: CGFloat) -> CGPath {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: rect.minX + horizontalInset, y: y))
            path.line(to: CGPoint(x: rect.maxX - horizontalInset, y: y))
            return path.cgPath
        }

        func verticalPath(x: CGFloat) -> CGPath {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x, y: rect.minY + verticalInset))
            path.line(to: CGPoint(x: x, y: rect.maxY - verticalInset))
            return path.cgPath
        }

        return (
            top: horizontalPath(y: rect.maxY),
            bottom: horizontalPath(y: rect.minY),
            left: verticalPath(x: rect.minX),
            right: verticalPath(x: rect.maxX)
        )
    }

}
