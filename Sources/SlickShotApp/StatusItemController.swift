import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hotkeyDisplayStringProvider: () -> String
    private let onCaptureScreenshot: () -> Void
    private let onCheckForUpdates: (() -> Void)?
    private let onOpenSettings: () -> Void

    init(
        hotkeyDisplayStringProvider: @escaping () -> String = { HotkeyConfiguration.default.displayString },
        onCaptureScreenshot: @escaping () -> Void = {},
        onCheckForUpdates: (() -> Void)? = nil,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.hotkeyDisplayStringProvider = hotkeyDisplayStringProvider
        self.onCaptureScreenshot = onCaptureScreenshot
        self.onCheckForUpdates = onCheckForUpdates
        self.onOpenSettings = onOpenSettings
        super.init()
    }

    func install() {
        guard let button = statusItem.button else { return }
        button.title = "S"
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Capture Screenshot (\(hotkeyDisplayStringProvider()))",
                action: #selector(captureScreenshot),
                keyEquivalent: ""
            )
        )
        if onCheckForUpdates != nil {
            menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SlickShot", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func captureScreenshot() {
        onCaptureScreenshot()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
