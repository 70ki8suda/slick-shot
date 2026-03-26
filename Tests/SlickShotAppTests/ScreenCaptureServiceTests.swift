import AppKit
import CoreGraphics
import Testing

@testable import SlickShotApp

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
