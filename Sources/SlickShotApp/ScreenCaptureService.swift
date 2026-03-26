import AppKit
import CoreGraphics

enum ScreenCaptureServiceError: Error {
    case failedToCreateImage
    case failedToEncodeImage
}

@MainActor
final class ScreenCaptureService: ScreenCaptureServiceProtocol {
    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func captureImage(in rect: CGRect) throws -> ScreenCapturePayload {
        guard let cgImage = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            throw ScreenCaptureServiceError.failedToCreateImage
        }

        let image = NSImage(cgImage: cgImage, size: rect.size)
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw ScreenCaptureServiceError.failedToEncodeImage
        }

        return ScreenCapturePayload(
            imageData: pngData,
            sourceDisplay: Self.sourceDisplayName(for: rect)
        )
    }

    private static func sourceDisplayName(for rect: CGRect) -> String {
        let midpoint = CGPoint(x: rect.midX, y: rect.midY)
        if let index = NSScreen.screens.firstIndex(where: { $0.frame.contains(midpoint) }) {
            return "Display \(index + 1)"
        }

        return "Display"
    }
}
