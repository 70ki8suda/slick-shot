import AppKit
import Carbon
import Foundation

@MainActor
final class SettingsWindowController: NSWindowController, SettingsWindowControlling {
    private enum PresentationMode {
        case standard
        case hotkeyOnboarding
        case missingPermission
    }

    private let shortcutDisplayProvider: () -> String
    private let permissionStatusProvider: () -> String
    private let onShortcutSaved: (HotkeyConfiguration) -> Void
    private let userDefaults: UserDefaults
    private let messageLabel = NSTextField(
        wrappingLabelWithString: "Screen Recording access is required for SlickShot to capture screenshots."
    )
    private let shortcutValueLabel = NSTextField(labelWithString: "")
    private let permissionValueLabel = NSTextField(labelWithString: "")
    private let shortcutRecorderField = ShortcutRecorderField()
    private var presentationMode: PresentationMode = .standard

    init(
        shortcutDisplayProvider: @escaping () -> String = { HotkeyConfiguration.default.displayString },
        permissionStatusProvider: @escaping () -> String = { "Unknown" },
        onShortcutSaved: @escaping (HotkeyConfiguration) -> Void = { _ in },
        userDefaults: UserDefaults = .standard
    ) {
        self.shortcutDisplayProvider = shortcutDisplayProvider
        self.permissionStatusProvider = permissionStatusProvider
        self.onShortcutSaved = onShortcutSaved
        self.userDefaults = userDefaults
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
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
        presentationMode = .missingPermission
        shortcutRecorderField.stopRecording()
        showSettingsWindow()
    }

    func showHotkeyOnboarding() {
        presentationMode = .hotkeyOnboarding
        showSettingsWindow()
    }

    func showSettingsWindow() {
        guard let window else { return }
        refreshStatus()
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
        window.title = "SlickShot Settings"

        let button = NSButton(
            title: "Open Screen Recording Settings",
            target: self,
            action: #selector(openScreenRecordingSettings)
        )
        button.bezelStyle = .rounded

        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        shortcutValueLabel.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        permissionValueLabel.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        shortcutRecorderField.onShortcutRecorded = { [weak self] configuration in
            self?.applyRecordedShortcut(configuration)
        }

        let stackView = NSStackView(views: [
            messageLabel,
            makeRow(title: "Shortcut", valueLabel: shortcutValueLabel),
            makeRow(title: "Recorder", view: shortcutRecorderField),
            makeRow(title: "Permission", valueLabel: permissionValueLabel),
            button
        ])
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

    private func refreshStatus() {
        messageLabel.stringValue = switch presentationMode {
        case .standard:
            "SlickShot uses the shortcut below for instant screen captures."
        case .hotkeyOnboarding:
            "Choose a shortcut to finish setting up SlickShot. Click the recorder below, then press your preferred key combination."
        case .missingPermission:
            "Screen Recording access is required for SlickShot to capture screenshots."
        }
        shortcutValueLabel.stringValue = shortcutDisplayProvider()
        permissionValueLabel.stringValue = permissionStatusProvider()
        shortcutRecorderField.displayString = shortcutDisplayProvider()
    }

    private func makeRow(title: String, valueLabel: NSTextField) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let row = NSStackView(views: [titleLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        return row
    }

    private func makeRow(title: String, view: NSView) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let row = NSStackView(views: [titleLabel, view])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func applyRecordedShortcut(_ configuration: HotkeyConfiguration) {
        configuration.save(to: userDefaults)
        presentationMode = .standard
        onShortcutSaved(configuration)
        refreshStatus()
    }
}

@MainActor
private final class ShortcutRecorderField: NSControl {
    var onShortcutRecorded: ((HotkeyConfiguration) -> Void)?

    var displayString: String = HotkeyConfiguration.default.displayString {
        didSet {
            if !isRecording {
                updateLabel()
            }
        }
    }

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false {
        didSet {
            updateLabel()
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            heightAnchor.constraint(equalToConstant: 32),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard carbonModifiers != 0 else {
            NSSound.beep()
            return
        }

        let configuration = HotkeyConfiguration(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbonModifiers
        )
        displayString = configuration.displayString
        isRecording = false
        onShortcutRecorded?(configuration)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    func stopRecording() {
        isRecording = false
    }

    private func updateLabel() {
        label.stringValue = isRecording ? "Type shortcut…" : displayString
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let relevantFlags = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt32 = 0
        if relevantFlags.contains(.control) {
            result |= UInt32(controlKey)
        }
        if relevantFlags.contains(.option) {
            result |= UInt32(optionKey)
        }
        if relevantFlags.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        if relevantFlags.contains(.command) {
            result |= UInt32(cmdKey)
        }
        return result
    }
}
