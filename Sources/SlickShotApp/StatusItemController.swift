import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onCaptureScreenshot: () -> Void

    init(onCaptureScreenshot: @escaping () -> Void = {}) {
        self.onCaptureScreenshot = onCaptureScreenshot
        super.init()
    }

    func install() {
        guard let button = statusItem.button else { return }
        button.title = "S"
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Screenshot", action: #selector(captureScreenshot), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SlickShot", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func captureScreenshot() {
        onCaptureScreenshot()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
