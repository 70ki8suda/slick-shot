import AppKit
import CoreGraphics
import Foundation
import SlickShotCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var overlayController: ThumbnailOverlayController?
    private var captureCoordinator: CaptureCoordinator?
    private var settingsWindowController: SettingsWindowController?
    private var hotkeyMonitor: HotkeyMonitor?
    private var store: ScreenshotStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ScreenshotStore()
        self.store = store
        let hotkeyConfiguration = HotkeyConfiguration()
        let captureService = ScreenCaptureService()
        overlayController = ThumbnailOverlayController(store: store)
        let settingsWindowController = SettingsWindowController(
            shortcutDisplayProvider: { hotkeyConfiguration.displayString },
            permissionStatusProvider: {
                captureService.hasScreenRecordingPermission() ? "Granted" : "Missing"
            }
        )
        self.settingsWindowController = settingsWindowController
        captureCoordinator = CaptureCoordinator(
            store: store,
            captureService: captureService,
            overlayFactory: LiveCaptureOverlaySessionFactory(),
            settingsWindowController: settingsWindowController
        )
        statusItemController = StatusItemController(
            hotkeyDisplayStringProvider: { hotkeyConfiguration.displayString },
            onCaptureScreenshot: { [weak self] in
                self?.startCapture()
            },
            onOpenSettings: { [weak self] in
                self?.settingsWindowController?.showSettingsWindow()
            }
        )
        statusItemController?.install()
        hotkeyMonitor = HotkeyMonitor(
            configuration: hotkeyConfiguration,
            onHotkeyPressed: { [weak self] in
                self?.startCapture()
            }
        )
        hotkeyMonitor?.start()
        if Self.shouldSeedDemoRecords() {
            seedStore(store)
        }
        overlayController?.show()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        store?.reconcileExpiry()
    }

    nonisolated static func shouldSeedDemoRecords(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
#if DEBUG
        environment["SLICKSHOT_SEED_THUMBNAILS"] == "1"
#else
        false
#endif
    }

    private func startCapture() {
        captureCoordinator?.startCapture()
    }

    private func seedStore(_ store: ScreenshotStore) {
        let colors: [NSColor] = [.systemRed, .systemOrange, .systemBlue]
        for (index, color) in colors.enumerated() {
            _ = store.insert(
                image: solidImageData(color: color, size: CGSize(width: 320, height: 210)),
                sourceDisplay: "Seeded \(index + 1)",
                selectionRect: CGRect(x: 40, y: 40, width: 180, height: 120)
            )
        }
    }

    private func solidImageData(color: NSColor, size: CGSize) -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return Data()
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
