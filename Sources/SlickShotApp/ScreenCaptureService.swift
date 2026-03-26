import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum ScreenCaptureServiceError: Error {
    case failedToCreateImage
    case failedToEncodeImage
}

protocol ScreenCaptureScreen {
    var frame: CGRect { get }
}

protocol LegacyRegionCapturing {
    func captureImage(in rect: CGRect) -> CGImage?
}

extension NSScreen: ScreenCaptureScreen {}
extension SCDisplay: ScreenCaptureScreen {}

struct QuartzLegacyRegionCapturer: LegacyRegionCapturing {
    func captureImage(in rect: CGRect) -> CGImage? {
        CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        )
    }
}

struct DisplayCaptureRequest: Equatable {
    let displayIndex: Int
    let globalRect: CGRect
    let localRect: CGRect
}

@MainActor
final class ScreenCaptureService: ScreenCaptureServiceProtocol {
    private let screenProvider: @MainActor () -> [any ScreenCaptureScreen]
    private let mouseLocationProvider: @MainActor () -> CGPoint
    private let permissionChecker: @MainActor () -> Bool
    private let permissionRequester: @MainActor () -> Bool
    private let legacyRegionCapturer: any LegacyRegionCapturing

    init(
        screenProvider: @escaping @MainActor () -> [any ScreenCaptureScreen] = {
            NSScreen.screens
        },
        mouseLocationProvider: @escaping @MainActor () -> CGPoint = {
            NSEvent.mouseLocation
        },
        permissionChecker: @escaping @MainActor () -> Bool = {
            CGPreflightScreenCaptureAccess()
        },
        permissionRequester: @escaping @MainActor () -> Bool = {
            CGRequestScreenCaptureAccess()
        },
        legacyRegionCapturer: any LegacyRegionCapturing = QuartzLegacyRegionCapturer()
    ) {
        self.screenProvider = screenProvider
        self.mouseLocationProvider = mouseLocationProvider
        self.permissionChecker = permissionChecker
        self.permissionRequester = permissionRequester
        self.legacyRegionCapturer = legacyRegionCapturer
    }

    var captureFlow: ScreenCaptureFlow {
        .nativeInteractiveSelection
    }

    func hasScreenRecordingPermission() -> Bool {
        permissionChecker()
    }

    func requestScreenRecordingPermission() -> Bool {
        permissionRequester()
    }

    func captureInteractiveImage() async throws -> ScreenCapturePayload? {
        let fileManager = FileManager.default
        let captureDirectory = fileManager.temporaryDirectory.appendingPathComponent("slick-shot-native", isDirectory: true)
        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        let fileURL = captureDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")

        defer {
            try? fileManager.removeItem(at: fileURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", fileURL.path]

        let terminationStatus = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        guard terminationStatus == 0 else {
            return nil
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let imageData = try Data(contentsOf: fileURL)
        guard imageData.isEmpty == false else {
            return nil
        }

        let anchorRect = Self.anchorRect(
            for: mouseLocationProvider(),
            screens: screenProvider()
        )
        let sourceDisplay = Self.sourceDisplay(
            for: anchorRect,
            screens: screenProvider()
        )
        NSLog("SlickShot native screencapture success bytes=%ld", imageData.count)
        return ScreenCapturePayload(
            imageData: imageData,
            sourceDisplay: sourceDisplay,
            selectionRect: anchorRect
        )
    }

    func captureImage(in rect: CGRect) async throws -> ScreenCapturePayload {
        let selectionRect = rect.standardized.integral
        NSLog("SlickShot service captureImage rect=%@", NSStringFromRect(selectionRect))
        let requests = Self.captureRequests(for: selectionRect, screens: screenProvider())
        NSLog(
            "SlickShot service requests=%@",
            String(describing: requests)
        )
        let sourceDisplay = requests.count == 1 ? "Display \(requests[0].displayIndex)" : "Multiple Displays"
        guard let image = legacyRegionCapturer.captureImage(in: selectionRect) else {
            throw ScreenCaptureServiceError.failedToCreateImage
        }
        guard let pngData = Self.pngData(from: image) else {
            throw ScreenCaptureServiceError.failedToEncodeImage
        }
        NSLog(
            "SlickShot quartz capture success sourceDisplay=%@ size=%ld",
            sourceDisplay,
            pngData.count
        )
        return ScreenCapturePayload(
            imageData: pngData,
            sourceDisplay: sourceDisplay,
            selectionRect: selectionRect
        )
    }

    static func anchorRect(
        for mouseLocation: CGPoint,
        screens: [any ScreenCaptureScreen]
    ) -> CGRect {
        guard let screen = screens.first(where: { $0.frame.contains(mouseLocation) }) else {
            return CGRect(origin: mouseLocation, size: CGSize(width: 1, height: 1))
        }

        let clampedPoint = CGPoint(
            x: min(max(mouseLocation.x, screen.frame.minX), screen.frame.maxX - 1),
            y: min(max(mouseLocation.y, screen.frame.minY), screen.frame.maxY - 1)
        )
        return CGRect(origin: clampedPoint, size: CGSize(width: 1, height: 1)).integral
    }

    static func sourceDisplay(
        for anchorRect: CGRect,
        screens: [any ScreenCaptureScreen]
    ) -> String {
        let point = CGPoint(x: anchorRect.midX, y: anchorRect.midY)
        if let index = screens.firstIndex(where: { $0.frame.contains(point) }) {
            return "Display \(index + 1)"
        }
        return "Selection"
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

    func capturePayloadWithFallback(
        selectionRect: CGRect,
        sourceDisplay: String,
        modernCapture: () async throws -> CGImage
    ) async throws -> ScreenCapturePayload {
        do {
            let image = try await modernCapture()
            guard let pngData = Self.pngData(from: image) else {
                throw ScreenCaptureServiceError.failedToEncodeImage
            }
            NSLog(
                "SlickShot service composite success sourceDisplay=%@ size=%ld",
                sourceDisplay,
                pngData.count
            )
            return ScreenCapturePayload(
                imageData: pngData,
                sourceDisplay: sourceDisplay,
                selectionRect: selectionRect
            )
        } catch {
            let nsError = error as NSError
            NSLog(
                "SlickShot modern capture failed domain=%@ code=%ld description=%@",
                nsError.domain,
                nsError.code,
                nsError.localizedDescription
            )
            guard let fallbackImage = legacyRegionCapturer.captureImage(in: selectionRect) else {
                throw error
            }
            NSLog("SlickShot legacy capture fallback succeeded rect=%@", NSStringFromRect(selectionRect))
            guard let pngData = Self.pngData(from: fallbackImage) else {
                throw ScreenCaptureServiceError.failedToEncodeImage
            }
            return ScreenCapturePayload(
                imageData: pngData,
                sourceDisplay: sourceDisplay,
                selectionRect: selectionRect
            )
        }
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
