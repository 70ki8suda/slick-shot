import Carbon.HIToolbox
import Foundation
import Testing

@testable import SlickShotApp

struct HotkeyConfigurationTests {
    @Test func defaultShortcut_isPresent() {
        let configuration = HotkeyConfiguration.default

        #expect(configuration.keyCode == UInt32(kVK_ANSI_S))
        #expect(configuration.carbonModifiers == UInt32(cmdKey | optionKey | controlKey))
        #expect(configuration.displayString == "Control-Option-Command-S")
    }

    @Test func invalidShortcut_fallsBackToDefault() {
        let defaults = UserDefaults(suiteName: "HotkeyConfigurationTests.invalidShortcut.\(UUID().uuidString)")!
        defaults.set(-1, forKey: HotkeyConfiguration.keyCodeDefaultsKey)
        defaults.set(0, forKey: HotkeyConfiguration.modifiersDefaultsKey)

        let configuration = HotkeyConfiguration(userDefaults: defaults)

        #expect(configuration == .default)
    }
}
