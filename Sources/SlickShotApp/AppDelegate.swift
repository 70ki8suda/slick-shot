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
    private var feedbackPlayer: CaptureFeedbackPlaying?
    private var updateController: UpdateController?
    private var demoCaptureModeStore: DemoCaptureModeStore?
    private var hotkeyConfiguration = HotkeyConfiguration()
    private let exposesDemoCaptureMode = AppBundleMetadata.exposesDemoCaptureMode()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ScreenshotStore()
        self.store = store
        hotkeyConfiguration = HotkeyConfiguration()
        let captureService = ScreenCaptureService()
        let feedbackPlayer = CaptureFeedbackPlayer()
        self.feedbackPlayer = feedbackPlayer
        let demoCaptureModeStore = DemoCaptureModeStore()
        self.demoCaptureModeStore = demoCaptureModeStore
        let updateController = UpdateController()
        self.updateController = updateController
        overlayController = ThumbnailOverlayController(store: store, feedbackPlayer: feedbackPlayer)
        let settingsWindowController = SettingsWindowController(
            shortcutDisplayProvider: { [weak self] in
                self?.hotkeyConfiguration.displayString ?? HotkeyConfiguration.default.displayString
            },
            permissionStatusProvider: {
                "Uses macOS system capture"
            },
            onShortcutSaved: { [weak self] configuration in
                self?.applyHotkeyConfiguration(configuration)
            }
        )
        self.settingsWindowController = settingsWindowController
        captureCoordinator = CaptureCoordinator(
            store: store,
            captureService: captureService,
            overlayFactory: LiveCaptureOverlaySessionFactory(
                feedbackPlayer: feedbackPlayer,
                presentationModeProvider: { [weak self, weak demoCaptureModeStore] in
                    guard self?.exposesDemoCaptureMode == true else { return .standard }
                    return (demoCaptureModeStore?.isEnabled ?? false) ? .demoRecording : .standard
                }
            ),
            settingsWindowController: settingsWindowController,
            feedbackPlayer: feedbackPlayer
        )
        statusItemController = StatusItemController(
            hotkeyDisplayStringProvider: { [weak self] in
                self?.hotkeyConfiguration.displayString ?? HotkeyConfiguration.default.displayString
            },
            demoCaptureModeProvider: { [weak self, weak demoCaptureModeStore] in
                guard self?.exposesDemoCaptureMode == true else { return false }
                return demoCaptureModeStore?.isEnabled ?? false
            },
            onCaptureScreenshot: { [weak self] in
                self?.startCapture()
            },
            onToggleDemoCaptureMode: exposesDemoCaptureMode ? { [weak self] in
                self?.toggleDemoCaptureMode()
            } : nil,
            onCheckForUpdates: { [weak self] in
                self?.updateController?.checkForUpdates()
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
        if Self.shouldShowHotkeyOnboarding() {
            settingsWindowController.showHotkeyOnboarding()
        }
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

    nonisolated static func shouldShowHotkeyOnboarding(userDefaults: UserDefaults = .standard) -> Bool {
        HotkeyConfiguration.hasValidPersistedConfiguration(userDefaults: userDefaults) == false
    }

    private func startCapture() {
        captureCoordinator?.startCapture()
    }

    private func applyHotkeyConfiguration(_ configuration: HotkeyConfiguration) {
        hotkeyConfiguration = configuration
        hotkeyMonitor?.update(configuration: configuration)
        statusItemController?.install()
    }

    private func toggleDemoCaptureMode() {
        guard exposesDemoCaptureMode else { return }
        guard let demoCaptureModeStore else { return }
        demoCaptureModeStore.isEnabled.toggle()
        statusItemController?.install()
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
