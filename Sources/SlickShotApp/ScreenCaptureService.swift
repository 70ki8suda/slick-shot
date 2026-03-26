import AppKit
import CoreGraphics
import Foundation

enum ScreenCaptureServiceError: Error {
    case failedToEncodeImage
    case failedToRunNativeCapture
}

protocol ScreenCaptureScreen {
    var frame: CGRect { get }
}

extension NSScreen: ScreenCaptureScreen {}

struct NativeCaptureRequest: Equatable {
    let displayIndex: Int
    let rect: CGRect
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
        guard let request = Self.captureRequest(for: selectionRect, screens: NSScreen.screens) else {
            throw ScreenCaptureServiceError.failedToRunNativeCapture
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let result = try await Self.runNativeCapture(request: request, outputURL: outputURL)
        guard result.terminationStatus == 0 else {
            throw ScreenCaptureServiceError.failedToRunNativeCapture
        }

        guard let pngData = try? Data(contentsOf: outputURL), pngData.isEmpty == false else {
            throw ScreenCaptureServiceError.failedToEncodeImage
        }

        return ScreenCapturePayload(
            imageData: pngData,
            sourceDisplay: "Display \(request.displayIndex)"
        )
    }

    static func captureRequest(
        for rect: CGRect,
        screens: [any ScreenCaptureScreen]
    ) -> NativeCaptureRequest? {
        let midpoint = CGPoint(x: rect.midX, y: rect.midY)
        guard let index = screens.firstIndex(where: { $0.frame.contains(midpoint) }) else {
            return nil
        }

        let screen = screens[index]
        return NativeCaptureRequest(
            displayIndex: index + 1,
            rect: CGRect(
                x: rect.minX - screen.frame.minX,
                y: rect.minY - screen.frame.minY,
                width: rect.width,
                height: rect.height
            ).integral
        )
    }

    private static func runNativeCapture(request: NativeCaptureRequest, outputURL: URL) async throws -> NativeCaptureResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = [
                "-x",
                "-D", "\(request.displayIndex)",
                "-t", "png",
                "-R", "\(Int(request.rect.minX)),\(Int(request.rect.minY)),\(Int(request.rect.width)),\(Int(request.rect.height))",
                outputURL.path
            ]
            process.standardError = stderrPipe
            process.terminationHandler = { process in
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                continuation.resume(returning: NativeCaptureResult(
                    terminationStatus: process.terminationStatus,
                    standardError: stderr
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private struct NativeCaptureResult {
    let terminationStatus: Int32
    let standardError: String
}
