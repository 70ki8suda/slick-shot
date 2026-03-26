import AppKit
import CoreGraphics
import Testing

@testable import SlickShotApp

@MainActor
@Test func test_captureImage_usesLegacyRegionCaptureForSelectedRect() async throws {
    let fallbackImage = try #require(makeCGImage(size: CGSize(width: 80, height: 50)))
    let capturer = TestLegacyRegionCapturer(image: fallbackImage)
    let service = ScreenCaptureService(
        screenProvider: {
            [
                TestScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
                TestScreen(frame: CGRect(x: 1512, y: -98, width: 1920, height: 1080))
            ]
        },
        legacyRegionCapturer: capturer
    )

    let payload = try await service.captureImage(in: CGRect(x: 1600, y: 2, width: 300, height: 200))

    #expect(capturer.capturedRects == [CGRect(x: 1600, y: 2, width: 300, height: 200)])
    #expect(payload.sourceDisplay == "Display 2")
    #expect(payload.imageData.isEmpty == false)
}

@MainActor
@Test func test_capturePayloadWithFallback_usesLegacyCaptureWhenModernCaptureFailsAndPermissionIsGranted() async throws {
    let fallbackImage = try #require(makeCGImage(size: CGSize(width: 40, height: 20)))
    let service = ScreenCaptureService(
        permissionChecker: { true },
        legacyRegionCapturer: TestLegacyRegionCapturer(image: fallbackImage)
    )

    let payload = try await service.capturePayloadWithFallback(
        selectionRect: CGRect(x: 100, y: 200, width: 40, height: 20),
        sourceDisplay: "Display 2",
        modernCapture: {
            throw TestScreenCaptureFailure.modernBackendFailed
        }
    )

    #expect(payload.sourceDisplay == "Display 2")
    #expect(payload.imageData.isEmpty == false)
}

@MainActor
@Test func test_capturePayloadWithFallback_usesLegacyCaptureWhenPermissionCheckerIsFalse() async throws {
    let fallbackImage = try #require(makeCGImage(size: CGSize(width: 40, height: 20)))
    let service = ScreenCaptureService(
        permissionChecker: { false },
        legacyRegionCapturer: TestLegacyRegionCapturer(image: fallbackImage)
    )

    let payload = try await service.capturePayloadWithFallback(
        selectionRect: CGRect(x: 100, y: 200, width: 40, height: 20),
        sourceDisplay: "Display 1",
        modernCapture: {
            throw TestScreenCaptureFailure.modernBackendFailed
        }
    )

    #expect(payload.sourceDisplay == "Display 1")
    #expect(payload.imageData.isEmpty == false)
}

@MainActor
@Test func test_capturePayloadWithFallback_rethrowsOriginalErrorWhenLegacyFallbackUnavailable() async {
    let service = ScreenCaptureService(
        permissionChecker: { false },
        legacyRegionCapturer: TestLegacyRegionCapturer(image: nil)
    )

    await #expect(throws: TestScreenCaptureFailure.self) {
        try await service.capturePayloadWithFallback(
            selectionRect: CGRect(x: 100, y: 200, width: 40, height: 20),
            sourceDisplay: "Display 1",
            modernCapture: {
                throw TestScreenCaptureFailure.modernBackendFailed
            }
        )
    }
}

@MainActor
@Test func test_captureRequests_mapsRectIntoSelectedDisplayLocalCoordinates() throws {
    let screens = [
        TestScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
        TestScreen(frame: CGRect(x: 1512, y: -98, width: 1920, height: 1080)),
        TestScreen(frame: CGRect(x: 3432, y: -98, width: 1920, height: 1200))
    ]

    let requests = ScreenCaptureService.captureRequests(
            for: CGRect(x: 3532, y: 2, width: 300, height: 200),
            screens: screens
        )

    #expect(requests == [
        DisplayCaptureRequest(
            displayIndex: 3,
            globalRect: CGRect(x: 3532, y: 2, width: 300, height: 200),
            localRect: CGRect(x: 100, y: 100, width: 300, height: 200)
        )
    ])
}

@MainActor
@Test func test_captureRequests_splitsRectAcrossDisplays() {
    let screens = [
        TestScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
        TestScreen(frame: CGRect(x: 1512, y: -98, width: 1920, height: 1080)),
        TestScreen(frame: CGRect(x: 3432, y: -98, width: 1920, height: 1200))
    ]

    let requests = ScreenCaptureService.captureRequests(
        for: CGRect(x: 3300, y: 0, width: 300, height: 200),
        screens: screens
    )

    #expect(requests == [
        DisplayCaptureRequest(
            displayIndex: 2,
            globalRect: CGRect(x: 3300, y: 0, width: 132, height: 200),
            localRect: CGRect(x: 1788, y: 98, width: 132, height: 200)
        ),
        DisplayCaptureRequest(
            displayIndex: 3,
            globalRect: CGRect(x: 3432, y: 0, width: 168, height: 200),
            localRect: CGRect(x: 0, y: 98, width: 168, height: 200)
        )
    ])
}

@MainActor
@Test func test_captureRequests_returnsEmptyWhenRectFallsOutsideAllDisplays() {
    let screens = [
        TestScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    ]

    let requests = ScreenCaptureService.captureRequests(
        for: CGRect(x: 5000, y: 5000, width: 200, height: 100),
        screens: screens
    )

    #expect(requests.isEmpty)
}

private struct TestScreen: ScreenCaptureScreen {
    let frame: CGRect
}

private enum TestScreenCaptureFailure: Error {
    case modernBackendFailed
}

private final class TestLegacyRegionCapturer: LegacyRegionCapturing {
    let image: CGImage?
    private(set) var capturedRects: [CGRect] = []

    init(image: CGImage?) {
        self.image = image
    }

    func captureImage(in rect: CGRect) -> CGImage? {
        capturedRects.append(rect)
        return image
    }
}

private func makeCGImage(size: CGSize) -> CGImage? {
    guard
        let context = CGContext(
            data: nil,
            width: max(Int(size.width), 1),
            height: max(Int(size.height), 1),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        return nil
    }

    context.setFillColor(NSColor.systemTeal.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    return context.makeImage()
}
