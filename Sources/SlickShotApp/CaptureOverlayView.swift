import AppKit
import CoreGraphics

@MainActor
final class CaptureOverlayView: NSView {
    private static let outerFrameRevealDelay: TimeInterval = 0.12
    private static let outerFrameRevealDuration: TimeInterval = 0.25
    private static let postRevealHoldDuration: TimeInterval = 0.12

    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var displayedReticleRect: CGRect?
    private var pendingReticleUpdate: DispatchWorkItem?
    private var pendingOuterFrameReveal: DispatchWorkItem?
    private var pendingGlassRingReveal: DispatchWorkItem?
    private let feedbackPlayer: CaptureFeedbackPlaying
    private let glassRingView = NSVisualEffectView()
    private let glassRingTintView = NSView()
    private let topEdgeLayer = CAShapeLayer()
    private let bottomEdgeLayer = CAShapeLayer()
    private let leftEdgeLayer = CAShapeLayer()
    private let rightEdgeLayer = CAShapeLayer()
    private let outerFrameLayer = CAShapeLayer()
    private let outerFrameSegmentLayers: [CAShapeLayer] = (0..<12).map { _ in CAShapeLayer() }
    private let lagGlowLayer = CAShapeLayer()
    private let reticleTiming = CAMediaTimingFunction(controlPoints: 0.22, 1.14, 0.28, 1)
    private let minimumDecoratedExtent: CGFloat = 72

    init(
        frame frameRect: NSRect,
        feedbackPlayer: CaptureFeedbackPlaying = NullCaptureFeedbackPlayer()
    ) {
        self.feedbackPlayer = feedbackPlayer
        super.init(frame: frameRect)
        wantsLayer = true
        configureGlassRingView()
        configureReticleLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func layout() {
        super.layout()
        glassRingView.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.02, alpha: 0.34).setFill()
        Self.dimmingRects(in: bounds, excluding: selectionRect).forEach { $0.fill() }

        guard let selectionRect else { return }

        drawGlassSurface(in: selectionRect)
        drawScanlines(in: selectionRect)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        pendingReticleUpdate?.cancel()
        pendingOuterFrameReveal?.cancel()
        pendingGlassRingReveal?.cancel()
        cancelReticleAnimations()
        displayedReticleRect = nil
        updateReticleLayers(animated: false)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        pendingOuterFrameReveal?.cancel()
        pendingGlassRingReveal?.cancel()
        cancelReticleAnimations()
        displayedReticleRect = nil
        updateReticleLayers(animated: false)
        scheduleReticleUpdate()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)

        guard let selectionRect else {
            resetSelectionState()
            onCancel?()
            return
        }

        let screenRect = convertSelectionToScreen(selectionRect)
        guard screenRect.width > 0, screenRect.height > 0 else {
            resetSelectionState()
            onCancel?()
            return
        }

        displayedReticleRect = selectionRect
        updateReticleLayers(animated: true)
        needsDisplay = true

        let delay = dismissalDelayForCurrentReticle()
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.onSelection?(screenRect)
                self.resetSelectionState()
            }
        } else {
            onSelection?(screenRect)
            resetSelectionState()
        }
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
            edgeLayer.strokeColor = NSColor(calibratedRed: 0.92, green: 0.98, blue: 1, alpha: 0.82).cgColor
            edgeLayer.lineWidth = 1.35
            edgeLayer.lineCap = .round
            edgeLayer.strokeStart = 0
            edgeLayer.strokeEnd = 1
            edgeLayer.opacity = 0
        }

        lagGlowLayer.fillColor = NSColor.clear.cgColor
        lagGlowLayer.strokeColor = NSColor(calibratedRed: 0.74, green: 0.95, blue: 1, alpha: 0.2).cgColor
        lagGlowLayer.lineWidth = 1.6
        lagGlowLayer.shadowColor = NSColor(calibratedRed: 0.78, green: 0.96, blue: 1, alpha: 0.44).cgColor
        lagGlowLayer.shadowOpacity = 0.34
        lagGlowLayer.shadowRadius = 16
        lagGlowLayer.shadowOffset = .zero
        lagGlowLayer.opacity = 0

        outerFrameLayer.fillColor = NSColor.clear.cgColor
        outerFrameLayer.strokeColor = NSColor(calibratedRed: 0.9, green: 0.98, blue: 1, alpha: 0.74).cgColor
        outerFrameLayer.lineWidth = 1.2
        outerFrameLayer.lineCap = .round
        outerFrameLayer.lineJoin = .round
        outerFrameLayer.strokeStart = 0
        outerFrameLayer.strokeEnd = 1
        outerFrameLayer.opacity = 0

        for segmentLayer in outerFrameSegmentLayers {
            segmentLayer.fillColor = NSColor.clear.cgColor
            segmentLayer.strokeColor = NSColor(calibratedRed: 0.9, green: 0.98, blue: 1, alpha: 0.74).cgColor
            segmentLayer.lineWidth = 1.2
            segmentLayer.lineCap = .round
            segmentLayer.lineJoin = .round
            segmentLayer.strokeStart = 0
            segmentLayer.strokeEnd = 1
            segmentLayer.opacity = 0
        }

        layer?.addSublayer(lagGlowLayer)
        outerFrameSegmentLayers.forEach { layer?.addSublayer($0) }
    }

    private func configureGlassRingView() {
        glassRingView.frame = bounds
        glassRingView.autoresizingMask = [.width, .height]
        glassRingView.blendingMode = .behindWindow
        glassRingView.material = .hudWindow
        glassRingView.state = .active
        glassRingView.isEmphasized = false
        glassRingView.wantsLayer = true
        glassRingView.layer?.cornerCurve = .continuous
        glassRingView.alphaValue = 0
        glassRingView.isHidden = true

        glassRingTintView.frame = glassRingView.bounds
        glassRingTintView.autoresizingMask = [.width, .height]
        glassRingTintView.wantsLayer = true
        glassRingTintView.layer?.backgroundColor = NSColor(calibratedRed: 0.78, green: 0.95, blue: 1, alpha: 0.04).cgColor

        glassRingView.addSubview(glassRingTintView)
        addSubview(glassRingView, positioned: .below, relativeTo: nil)
    }

    private func updateReticleLayers(animated: Bool) {
        guard let displayedReticleRect else {
            hideGlassRing()
            cancelReticleAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            lagGlowLayer.opacity = 0
            outerFrameLayer.opacity = 0
            lagGlowLayer.path = nil
            outerFrameLayer.path = nil
            outerFrameLayer.strokeStart = 0
            outerFrameLayer.strokeEnd = 1
            outerFrameSegmentLayers.forEach {
                $0.opacity = 0
                $0.path = nil
                $0.strokeStart = 0
                $0.strokeEnd = 1
            }
            CATransaction.commit()
            return
        }

        let outerRect = displayedReticleRect.insetBy(dx: -6, dy: -6)
        guard shouldShowDecoratedReticle(for: outerRect) else {
            hideGlassRing()
            cancelReticleAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            lagGlowLayer.opacity = 0
            outerFrameLayer.opacity = 0
            lagGlowLayer.path = nil
            outerFrameLayer.path = nil
            outerFrameLayer.strokeStart = 0
            outerFrameLayer.strokeEnd = 1
            outerFrameSegmentLayers.forEach {
                $0.opacity = 0
                $0.path = nil
                $0.strokeStart = 0
                $0.strokeEnd = 1
            }
            CATransaction.commit()
            return
        }
        let outerFramePoints = Self.outerReticlePoints(in: outerRect)
        let outerFrameSegmentPaths = Self.outerReticleSegmentPaths(points: outerFramePoints)
        updateGlassRingMask(outerRect: outerRect, innerRect: displayedReticleRect)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lagGlowLayer.path = nil
        outerFrameLayer.path = nil
        lagGlowLayer.opacity = 0
        outerFrameLayer.opacity = animated ? 0 : 1
        for (index, segmentLayer) in outerFrameSegmentLayers.enumerated() {
            segmentLayer.path = index < outerFrameSegmentPaths.count ? outerFrameSegmentPaths[index] : nil
            if animated, index < outerFrameSegmentPaths.count {
                segmentLayer.opacity = 0
                segmentLayer.strokeStart = 0.5
                segmentLayer.strokeEnd = 0.5
            } else {
                segmentLayer.opacity = index < outerFrameSegmentPaths.count ? 1 : 0
                segmentLayer.strokeStart = 0
                segmentLayer.strokeEnd = 1
            }
        }
        CATransaction.commit()

        if animated {
            scheduleOuterFrameReveal()
            scheduleGlassRingReveal()
        } else {
            hideGlassRing()
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
            self.feedbackPlayer.playReticleReveal()
            self.animateOuterFrameReveal(duration: Self.outerFrameRevealDuration)
        }
        pendingOuterFrameReveal = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.outerFrameRevealDelay, execute: workItem)
    }

    private func scheduleGlassRingReveal() {
        pendingGlassRingReveal?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.selectionRect != nil, self.displayedReticleRect != nil else { return }
            self.revealGlassRing()
        }
        pendingGlassRingReveal = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.outerFrameRevealDelay + Self.outerFrameRevealDuration,
            execute: workItem
        )
    }

    private func updateGlassRingMask(outerRect: CGRect, innerRect: CGRect) {
        let outerPath = Self.outerReticlePath(in: outerRect)
        outerPath.appendRect(innerRect)
        outerPath.windingRule = .evenOdd

        let maskLayer = CAShapeLayer()
        maskLayer.frame = bounds
        maskLayer.path = outerPath.cgPath
        maskLayer.fillRule = .evenOdd
        glassRingView.layer?.mask = maskLayer
    }

    private func revealGlassRing() {
        glassRingView.isHidden = false
        glassRingView.animator().alphaValue = 0.5
    }

    private func hideGlassRing() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            glassRingView.animator().alphaValue = 0
        }
        glassRingView.isHidden = true
        glassRingView.layer?.mask = nil
    }

    private func dismissalDelayForCurrentReticle() -> TimeInterval {
        guard
            let displayedReticleRect,
            shouldShowDecoratedReticle(for: displayedReticleRect.insetBy(dx: -6, dy: -6))
        else {
            return 0
        }
        return Self.outerFrameRevealDelay + Self.outerFrameRevealDuration + Self.postRevealHoldDuration
    }

    private func resetSelectionState() {
        startPoint = nil
        currentPoint = nil
        pendingReticleUpdate?.cancel()
        pendingOuterFrameReveal?.cancel()
        pendingGlassRingReveal?.cancel()
        displayedReticleRect = nil
        updateReticleLayers(animated: false)
        needsDisplay = true
    }

    private func animateOuterFrameReveal(duration: CFTimeInterval) {
        for segmentLayer in outerFrameSegmentLayers where segmentLayer.path != nil {
            segmentLayer.removeAnimation(forKey: "outerFrameStrokeStart")
            segmentLayer.removeAnimation(forKey: "outerFrameStrokeEnd")

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            segmentLayer.opacity = 1
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
            segmentLayer.strokeStart = 0
            segmentLayer.strokeEnd = 1
            CATransaction.commit()

            segmentLayer.add(startAnimation, forKey: "outerFrameStrokeStart")
            segmentLayer.add(endAnimation, forKey: "outerFrameStrokeEnd")
        }
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
        outerFrameSegmentLayers.forEach {
            $0.removeAnimation(forKey: "outerFrameStrokeStart")
            $0.removeAnimation(forKey: "outerFrameStrokeEnd")
        }
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

    private func drawGlassSurface(in rect: CGRect) {
        let surfacePath = NSBezierPath(rect: rect)
        NSColor(calibratedRed: 0.86, green: 0.97, blue: 1, alpha: 0.08).setFill()
        surfacePath.fill()

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.97, green: 1, blue: 1, alpha: 0.3),
            NSColor(calibratedRed: 0.88, green: 0.98, blue: 1, alpha: 0.14),
            NSColor(calibratedRed: 0.82, green: 0.96, blue: 1, alpha: 0.06),
            NSColor(calibratedRed: 0.95, green: 1, blue: 1, alpha: 0.16),
        ])
        gradient?.draw(in: surfacePath, angle: 90)

        let cyanBloomRect = CGRect(
            x: rect.minX + rect.width * 0.08,
            y: rect.minY + rect.height * 0.44,
            width: rect.width * 0.58,
            height: rect.height * 0.32
        )
        let cyanBloomPath = NSBezierPath(roundedRect: cyanBloomRect, xRadius: cyanBloomRect.height / 2, yRadius: cyanBloomRect.height / 2)
        NSColor(calibratedRed: 0.72, green: 0.94, blue: 1, alpha: 0.06).setFill()
        cyanBloomPath.fill()

        let topHighlight = NSBezierPath()
        topHighlight.move(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 1.5))
        topHighlight.line(to: CGPoint(x: rect.maxX - 1, y: rect.maxY - 1.5))
        topHighlight.lineWidth = 1
        NSColor(calibratedRed: 0.98, green: 1, blue: 1, alpha: 0.58).setStroke()
        topHighlight.stroke()

        let sideHighlight = NSBezierPath()
        sideHighlight.move(to: CGPoint(x: rect.minX + 1.5, y: rect.minY + rect.height * 0.18))
        sideHighlight.line(to: CGPoint(x: rect.minX + 1.5, y: rect.maxY - rect.height * 0.12))
        sideHighlight.lineWidth = 0.8
        NSColor(calibratedRed: 0.9, green: 0.98, blue: 1, alpha: 0.2).setStroke()
        sideHighlight.stroke()
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
        NSColor.white.withAlphaComponent(0.03).setStroke()
        path.stroke()
    }

    private static func outerReticlePath(in rect: CGRect) -> NSBezierPath {
        let points = outerReticlePoints(in: rect)
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.close()
        return path
    }

    private static func outerReticlePoints(in rect: CGRect) -> [CGPoint] {
        let horizontalInset = min(max(rect.width * 0.04, 6), 10)
        let verticalInset = min(max(rect.height * 0.04, 6), 10)
        let cornerCut: CGFloat = 9
        let stepWidth: CGFloat = cornerCut
        let stepHeight: CGFloat = 74
        let stepBottomOffset: CGFloat = 30

        let leftX = rect.minX - horizontalInset
        let rightX = rect.maxX + horizontalInset
        let outerStepX = rightX + stepWidth
        let topY = rect.maxY + verticalInset
        let bottomY = rect.minY - verticalInset
        let stepBottomY = bottomY + stepBottomOffset
        let stepTopY = stepBottomY + stepHeight

        return [
            CGPoint(x: leftX + cornerCut, y: topY),
            CGPoint(x: rightX - cornerCut, y: topY),
            CGPoint(x: rightX, y: topY - cornerCut),
            CGPoint(x: rightX, y: stepTopY),
            CGPoint(x: outerStepX, y: stepTopY - cornerCut),
            CGPoint(x: outerStepX, y: stepBottomY + cornerCut),
            CGPoint(x: rightX, y: stepBottomY),
            CGPoint(x: rightX, y: bottomY + cornerCut),
            CGPoint(x: rightX - cornerCut, y: bottomY),
            CGPoint(x: leftX + cornerCut, y: bottomY),
            CGPoint(x: leftX, y: bottomY + cornerCut),
            CGPoint(x: leftX, y: topY - cornerCut),
        ]
    }

    private static func outerReticleSegmentPaths(points: [CGPoint]) -> [CGPath] {
        guard points.count > 1 else { return [] }
        return (0..<points.count).map { index in
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            return path.cgPath
        }
    }

}
