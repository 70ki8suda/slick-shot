import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

enum ScreenCaptureServiceError: Error {
    case failedToCreateImage
    case failedToEncodeImage
}

protocol ScreenCaptureScreen {
    var frame: CGRect { get }
}

extension NSScreen: ScreenCaptureScreen {}
extension SCDisplay: ScreenCaptureScreen {}

struct DisplayCaptureRequest: Equatable {
    let displayIndex: Int
    let globalRect: CGRect
    let localRect: CGRect
}

@MainActor
final class ScreenCaptureService: ScreenCaptureServiceProtocol {
    var captureFlow: ScreenCaptureFlow {
        .overlayRectSelection
    }

    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func captureInteractiveImage() async throws -> ScreenCapturePayload? {
        nil
    }

    func captureImage(in rect: CGRect) async throws -> ScreenCapturePayload {
        let selectionRect = rect.standardized.integral
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let requests = Self.captureRequests(for: selectionRect, screens: shareableContent.displays)
        guard !requests.isEmpty else {
            throw ScreenCaptureServiceError.failedToCreateImage
        }

        let image = try await compositeImage(
            from: requests,
            displays: shareableContent.displays,
            in: selectionRect
        )
        guard let pngData = Self.pngData(from: image) else {
            throw ScreenCaptureServiceError.failedToEncodeImage
        }

        let sourceDisplay = requests.count == 1 ? "Display \(requests[0].displayIndex)" : "Multiple Displays"
        return ScreenCapturePayload(
            imageData: pngData,
            sourceDisplay: sourceDisplay
        )
    }

    static func captureRequests(
        for rect: CGRect,
        screens: [any ScreenCaptureScreen]
    ) -> [DisplayCaptureRequest] {
        let selectionRect = rect.standardized.integral

        return screens.enumerated().compactMap { index, screen in
            let intersection = screen.frame.intersection(selectionRect)
            guard !intersection.isNull, !intersection.isEmpty else {
                return nil
            }

            return DisplayCaptureRequest(
                displayIndex: index + 1,
                globalRect: intersection.integral,
                localRect: CGRect(
                    x: intersection.minX - screen.frame.minX,
                    y: intersection.minY - screen.frame.minY,
                    width: intersection.width,
                    height: intersection.height
                ).integral
            )
        }
    }

    private func compositeImage(
        from requests: [DisplayCaptureRequest],
        displays: [SCDisplay],
        in selectionRect: CGRect
    ) async throws -> CGImage {
        let segments = try await captureSegments(from: requests, displays: displays, selectionRect: selectionRect)
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

    private func captureSegments(
        from requests: [DisplayCaptureRequest],
        displays: [SCDisplay],
        selectionRect: CGRect
    ) async throws -> [CapturedDisplaySegment] {
        var segments: [CapturedDisplaySegment] = []

        for request in requests {
            let display = displays[request.displayIndex - 1]
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let scale = max(CGFloat(SCShareableContent.info(for: filter).pointPixelScale), 1)
            let configuration = SCStreamConfiguration()
            configuration.captureResolution = .best
            configuration.showsCursor = false
            configuration.sourceRect = request.localRect
            configuration.width = max(Int(request.localRect.width * scale), 1)
            configuration.height = max(Int(request.localRect.height * scale), 1)

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            segments.append(
                CapturedDisplaySegment(
                    image: image,
                    rectInSelection: CGRect(
                        x: request.globalRect.minX - selectionRect.minX,
                        y: request.globalRect.minY - selectionRect.minY,
                        width: request.globalRect.width,
                        height: request.globalRect.height
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

    private static func pngData(from cgImage: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}

private struct CapturedDisplaySegment {
    let image: CGImage
    let rectInSelection: CGRect
    let scale: CGFloat
}
