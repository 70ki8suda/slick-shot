import AppKit
import CoreGraphics
import Foundation

enum ScreenCaptureServiceError: Error {
    case failedToEncodeImage
    case failedToRunNativeCapture
}

@MainActor
final class ScreenCaptureService: ScreenCaptureServiceProtocol {
    var captureFlow: ScreenCaptureFlow {
        .overlayRectSelection
    }

    func hasScreenRecordingPermission() -> Bool {
        true
    }

    func requestScreenRecordingPermission() -> Bool {
        true
    }

    func captureInteractiveImage() async throws -> ScreenCapturePayload? {
        nil
    }

    func captureImage(in rect: CGRect) async throws -> ScreenCapturePayload {
        let selectionRect = rect.standardized.integral
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let result = try await Self.runNativeCapture(rect: selectionRect, outputURL: outputURL)
        guard result.terminationStatus == 0 else {
            throw ScreenCaptureServiceError.failedToRunNativeCapture
        }

        guard let pngData = try? Data(contentsOf: outputURL), pngData.isEmpty == false else {
            throw ScreenCaptureServiceError.failedToEncodeImage
        }

        return ScreenCapturePayload(
            imageData: pngData,
            sourceDisplay: Self.sourceDisplayName(for: selectionRect)
        )
    }

    private static func sourceDisplayName(for rect: CGRect) -> String {
        let midpoint = CGPoint(x: rect.midX, y: rect.midY)
        if let index = NSScreen.screens.firstIndex(where: { $0.frame.contains(midpoint) }) {
            return "Display \(index + 1)"
        }

        return "Display"
    }

    private static func runNativeCapture(rect: CGRect, outputURL: URL) async throws -> NativeCaptureResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = [
                "-x",
                "-t", "png",
                "-R", "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))",
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
