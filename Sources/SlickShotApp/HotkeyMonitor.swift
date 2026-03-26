import Carbon
import Foundation

struct HotkeyConfiguration: Equatable {
    static let keyCodeDefaultsKey = "slickshot.hotkey.keyCode"
    static let modifiersDefaultsKey = "slickshot.hotkey.modifiers"
    static let `default` = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_S),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    let keyCode: UInt32
    let carbonModifiers: UInt32

    init(
        keyCode: UInt32 = HotkeyConfiguration.default.keyCode,
        carbonModifiers: UInt32 = HotkeyConfiguration.default.carbonModifiers
    ) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init(userDefaults: UserDefaults = .standard) {
        guard let configuration = Self.parse(userDefaults: userDefaults) else {
            self = .default
            return
        }

        self = configuration
    }

    var displayString: String {
        let modifierLabels: [(UInt32, String)] = [
            (UInt32(controlKey), "Control"),
            (UInt32(optionKey), "Option"),
            (UInt32(shiftKey), "Shift"),
            (UInt32(cmdKey), "Command")
        ]
        let keyLabel = Self.keyLabel(for: keyCode)
        let labels = modifierLabels.compactMap { flag, label in
            carbonModifiers & flag == 0 ? nil : label
        } + [keyLabel]
        return labels.joined(separator: "-")
    }

    static func hasValidPersistedConfiguration(userDefaults: UserDefaults = .standard) -> Bool {
        parse(userDefaults: userDefaults) != nil
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(Int(keyCode), forKey: Self.keyCodeDefaultsKey)
        userDefaults.set(Int(carbonModifiers), forKey: Self.modifiersDefaultsKey)
    }

    private static func parse(userDefaults: UserDefaults) -> HotkeyConfiguration? {
        guard
            let rawKeyCode = userDefaults.object(forKey: keyCodeDefaultsKey) as? Int,
            let rawModifiers = userDefaults.object(forKey: modifiersDefaultsKey) as? Int
        else {
            return nil
        }

        let allowedModifiers = Int(controlKey | optionKey | shiftKey | cmdKey)
        guard
            (0...Int(UInt16.max)).contains(rawKeyCode),
            rawModifiers > 0,
            rawModifiers & ~allowedModifiers == 0
        else {
            return nil
        }

        return HotkeyConfiguration(
            keyCode: UInt32(rawKeyCode),
            carbonModifiers: UInt32(rawModifiers)
        )
    }

    private static func keyLabel(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space:
            return "Space"
        case kVK_Return:
            return "Return"
        case kVK_Tab:
            return "Tab"
        case kVK_Escape:
            return "Escape"
        default:
            return "Key \(keyCode)"
        }
    }
}

@MainActor
final class HotkeyMonitor {
    private static let hotKeySignature = OSType(0x534C4B53) // "SLKS"
    private static let hotKeyHandler: EventHandlerUPP = { _, eventRef, userData in
        guard let eventRef, let userData else {
            return noErr
        }

        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
        monitor.handleHotKeyEvent(eventRef)
        return noErr
    }

    private var configuration: HotkeyConfiguration
    private let onHotkeyPressed: @MainActor () -> Void
    private let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    init(
        configuration: HotkeyConfiguration = HotkeyConfiguration(),
        onHotkeyPressed: @escaping @MainActor () -> Void
    ) {
        self.configuration = configuration
        self.onHotkeyPressed = onHotkeyPressed
    }

    func start() {
        stop()
        installEventHandler()
        registerHotKey()
    }

    func update(configuration: HotkeyConfiguration) {
        self.configuration = configuration
        start()
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installEventHandler() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func registerHotKey() {
        let hotKeyID = self.hotKeyID
        let status = RegisterEventHotKey(
            configuration.keyCode,
            configuration.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            NSLog("SlickShot failed to register hotkey: %d", status)
            return
        }
    }

    private func handleHotKeyEvent(_ eventRef: EventRef) {
        var pressedHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &pressedHotKeyID
        )
        guard
            status == noErr,
            pressedHotKeyID.signature == hotKeyID.signature,
            pressedHotKeyID.id == hotKeyID.id
        else {
            return
        }

        onHotkeyPressed()
    }
}
