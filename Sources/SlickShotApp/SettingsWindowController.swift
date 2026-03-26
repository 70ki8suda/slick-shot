import AppKit
import Foundation

@MainActor
final class SettingsWindowController: NSWindowController, SettingsWindowControlling {
    private let messageLabel = NSTextField(
        wrappingLabelWithString: "Screen Recording access is required for SlickShot to capture screenshots."
    )

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configureWindow(window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showMissingPermissionMessage() {
        guard let window else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func configureWindow(_ window: NSWindow) {
        window.title = "SlickShot Permissions"

        let button = NSButton(
            title: "Open Screen Recording Settings",
            target: self,
            action: #selector(openScreenRecordingSettings)
        )
        button.bezelStyle = .rounded

        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0

        let stackView = NSStackView(views: [messageLabel, button])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16
        stackView.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)

        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }
}
