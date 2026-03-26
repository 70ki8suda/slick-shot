import Carbon.HIToolbox
import Foundation
import Testing

@testable import SlickShotApp

struct HotkeyOnboardingTests {
    @Test func onboarding_isShownWhenNoValidSavedHotkeyExists() {
        let defaults = UserDefaults(suiteName: "HotkeyOnboardingTests.missing.\(UUID().uuidString)")!

        #expect(AppDelegate.shouldShowHotkeyOnboarding(userDefaults: defaults) == true)
    }

    @Test func onboarding_isNotShownOnceAValidSavedHotkeyExists() {
        let defaults = UserDefaults(suiteName: "HotkeyOnboardingTests.valid.\(UUID().uuidString)")!
        HotkeyConfiguration(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey | shiftKey)
        ).save(to: defaults)

        #expect(AppDelegate.shouldShowHotkeyOnboarding(userDefaults: defaults) == false)
    }

    @Test func onboarding_isShownForInvalidPersistedHotkeyValues() {
        let defaults = UserDefaults(suiteName: "HotkeyOnboardingTests.invalid.\(UUID().uuidString)")!
        defaults.set(-1, forKey: HotkeyConfiguration.keyCodeDefaultsKey)
        defaults.set(0, forKey: HotkeyConfiguration.modifiersDefaultsKey)

        #expect(AppDelegate.shouldShowHotkeyOnboarding(userDefaults: defaults) == true)
    }
}
