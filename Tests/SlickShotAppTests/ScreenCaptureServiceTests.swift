import AppKit
import CoreGraphics
import Testing

@testable import SlickShotApp

@MainActor
@Test func test_captureRequest_mapsRectIntoSelectedDisplayLocalCoordinates() throws {
    let screens = [
        TestScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
        TestScreen(frame: CGRect(x: 1512, y: -98, width: 1920, height: 1080)),
        TestScreen(frame: CGRect(x: 3432, y: -98, width: 1920, height: 1200))
    ]

    let request = try #require(
        ScreenCaptureService.captureRequest(
            for: CGRect(x: 3532, y: 2, width: 300, height: 200),
            screens: screens
        )
    )

    #expect(request.displayIndex == 3)
    #expect(request.rect == CGRect(x: 100, y: 100, width: 300, height: 200))
}

@MainActor
@Test func test_captureRequest_returnsNilWhenRectFallsOutsideAllDisplays() {
    let screens = [
        TestScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    ]

    let request = ScreenCaptureService.captureRequest(
        for: CGRect(x: 5000, y: 5000, width: 200, height: 100),
        screens: screens
    )

    #expect(request == nil)
}

private struct TestScreen: ScreenCaptureScreen {
    let frame: CGRect
}
