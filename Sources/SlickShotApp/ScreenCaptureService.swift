import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

enum ScreenCaptureServiceError: Error {
    case failedToCreateImage
    case failedToEncodeImage
}

@MainActor
final class ScreenCaptureService: ScreenCaptureServiceProtocol {
    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func captureImage(in rect: CGRect) async throws -> ScreenCapturePayload {
        let selectionRect = rect.standardized.integral
        let cgImage = try await captureCGImage(in: selectionRect)
        guard let pngData = Self.pngData(from: cgImage) else {
            throw ScreenCaptureServiceError.failedToEncodeImage
        }

        return ScreenCapturePayload(
            imageData: pngData,
            sourceDisplay: Self.sourceDisplayName(for: selectionRect)
        )
    }

    private func captureCGImage(in rect: CGRect) async throws -> CGImage {
        if #available(macOS 15.2, *) {
            return try await SCScreenshotManager.captureImage(in: rect)
        }

        return try await captureImageByDisplay(in: rect)
    }

    private func captureImageByDisplay(in rect: CGRect) async throws -> CGImage {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let segments = try await captureSegments(
            for: shareableContent.displays,
            intersecting: rect
        )
        return try compositeImage(from: segments, in: rect)
    }

    private func captureSegments(
        for displays: [SCDisplay],
        intersecting selectionRect: CGRect
    ) async throws -> [CapturedDisplaySegment] {
        var segments: [CapturedDisplaySegment] = []

        for display in displays {
            let intersection = display.frame.intersection(selectionRect)
            guard !intersection.isNull, !intersection.isEmpty else {
                continue
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let scale = max(CGFloat(SCShareableContent.info(for: filter).pointPixelScale), 1)
            let sourceRect = CGRect(
                x: intersection.minX - display.frame.minX,
                y: intersection.minY - display.frame.minY,
                width: intersection.width,
                height: intersection.height
            )
            let configuration = SCStreamConfiguration()
            configuration.captureResolution = .best
            configuration.showsCursor = false
            configuration.sourceRect = sourceRect
            configuration.width = max(Int(sourceRect.width * scale), 1)
            configuration.height = max(Int(sourceRect.height * scale), 1)

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            segments.append(
                CapturedDisplaySegment(
                    image: image,
                    rectInSelection: CGRect(
                        x: intersection.minX - selectionRect.minX,
                        y: intersection.minY - selectionRect.minY,
                        width: intersection.width,
                        height: intersection.height
                    ),
                    scale: scale
                )
            )
        }

        guard !segments.isEmpty else {
            throw ScreenCaptureServiceError.failedToCreateImage
        }

        return segments
    }

    private func compositeImage(
        from segments: [CapturedDisplaySegment],
        in selectionRect: CGRect
    ) throws -> CGImage {
        let scale = segments.map(\.scale).max() ?? 1
        let width = max(Int(selectionRect.width * scale), 1)
        let height = max(Int(selectionRect.height * scale), 1)
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw ScreenCaptureServiceError.failedToCreateImage
        }

        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high

        for segment in segments {
            context.draw(
                segment.image,
                in: CGRect(
                    x: segment.rectInSelection.minX * scale,
                    y: segment.rectInSelection.minY * scale,
                    width: segment.rectInSelection.width * scale,
                    height: segment.rectInSelection.height * scale
                )
            )
        }

        guard let image = context.makeImage() else {
            throw ScreenCaptureServiceError.failedToCreateImage
        }

        return image
    }

    private static func pngData(from cgImage: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    private static func sourceDisplayName(for rect: CGRect) -> String {
        let midpoint = CGPoint(x: rect.midX, y: rect.midY)
        if let index = NSScreen.screens.firstIndex(where: { $0.frame.contains(midpoint) }) {
            return "Display \(index + 1)"
        }

        return "Display"
    }
}

private struct CapturedDisplaySegment {
    let image: CGImage
    let rectInSelection: CGRect
    let scale: CGFloat
}
