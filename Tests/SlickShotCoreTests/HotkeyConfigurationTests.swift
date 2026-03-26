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

    @Test func persistedShortcut_isLoadedWhenValid() {
        let defaults = UserDefaults(suiteName: "HotkeyConfigurationTests.persistedShortcut.\(UUID().uuidString)")!
        defaults.set(kVK_ANSI_K, forKey: HotkeyConfiguration.keyCodeDefaultsKey)
        defaults.set(Int(cmdKey | shiftKey), forKey: HotkeyConfiguration.modifiersDefaultsKey)

        let configuration = HotkeyConfiguration(userDefaults: defaults)

        #expect(configuration.keyCode == UInt32(kVK_ANSI_K))
        #expect(configuration.carbonModifiers == UInt32(cmdKey | shiftKey))
        #expect(configuration.displayString == "Shift-Command-K")
    }

    @Test func save_persistsShortcutUsingHotkeyConfigurationDefaultsKeys() {
        let defaults = UserDefaults(suiteName: "HotkeyConfigurationTests.save.\(UUID().uuidString)")!
        let configuration = HotkeyConfiguration(
            keyCode: UInt32(kVK_ANSI_J),
            carbonModifiers: UInt32(controlKey | optionKey)
        )

        configuration.save(to: defaults)

        #expect(defaults.object(forKey: HotkeyConfiguration.keyCodeDefaultsKey) as? Int == kVK_ANSI_J)
        #expect(defaults.object(forKey: HotkeyConfiguration.modifiersDefaultsKey) as? Int == Int(controlKey | optionKey))
        #expect(HotkeyConfiguration(userDefaults: defaults) == configuration)
    }

    @Test func invalidShortcut_fallsBackToDefault() {
        let defaults = UserDefaults(suiteName: "HotkeyConfigurationTests.invalidShortcut.\(UUID().uuidString)")!
        defaults.set(-1, forKey: HotkeyConfiguration.keyCodeDefaultsKey)
        defaults.set(0, forKey: HotkeyConfiguration.modifiersDefaultsKey)

        let configuration = HotkeyConfiguration(userDefaults: defaults)

        #expect(configuration == .default)
    }

    @Test func invalidShortcut_isNotConsideredValidPersistedConfiguration() {
        let defaults = UserDefaults(suiteName: "HotkeyConfigurationTests.invalidPersisted.\(UUID().uuidString)")!
        defaults.set(kVK_ANSI_S, forKey: HotkeyConfiguration.keyCodeDefaultsKey)
        defaults.set(Int(controlKey | optionKey | cmdKey | (1 << 20)), forKey: HotkeyConfiguration.modifiersDefaultsKey)

        #expect(HotkeyConfiguration.hasValidPersistedConfiguration(userDefaults: defaults) == false)
        #expect(HotkeyConfiguration(userDefaults: defaults) == .default)
    }
}
