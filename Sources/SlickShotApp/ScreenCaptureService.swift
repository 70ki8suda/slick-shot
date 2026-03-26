import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum ScreenCaptureServiceError: Error {
    case failedToCreateImage
    case failedToEncodeImage
    case failedToRunNativeCapture
}

@MainActor
final class ScreenCaptureService: ScreenCaptureServiceProtocol {
    var captureFlow: ScreenCaptureFlow {
        .nativeInteractiveSelection
    }

    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func captureInteractiveImage() async throws -> ScreenCapturePayload? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let result = try await Self.runNativeCapture(outputURL: outputURL)
        guard result.terminationStatus == 0 else {
            if hasScreenRecordingPermission() == false || result.standardError.localizedCaseInsensitiveContains("not authorized") {
                throw NSError(domain: SCStreamErrorDomain, code: -3801)
            }
            return nil
        }

        guard
            FileManager.default.fileExists(atPath: outputURL.path),
            let data = try? Data(contentsOf: outputURL),
            data.isEmpty == false
        else {
            return nil
        }

        return ScreenCapturePayload(
            imageData: data,
            sourceDisplay: "Display"
        )
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
        if let image = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) {
            return image
        }

        if #available(macOS 15.2, *) {
            return try await SCScreenshotManager.captureImage(in: rect)
        }

        if let image = CGDisplayCreateImage(CGMainDisplayID(), rect: rect) {
            return image
        }

        throw ScreenCaptureServiceError.failedToCreateImage
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

    private static func runNativeCapture(outputURL: URL) async throws -> NativeCaptureResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", "-t", "png", outputURL.path]
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
