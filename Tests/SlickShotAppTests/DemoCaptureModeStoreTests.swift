import AppKit
import Foundation
import Testing

@testable import SlickShotApp

struct DemoCaptureModeStoreTests {
    @Test func defaultsToDisabled() {
        let defaults = UserDefaults(suiteName: "DemoCaptureModeStoreTests.default.\(UUID().uuidString)")!
        let store = DemoCaptureModeStore(userDefaults: defaults)

        #expect(store.isEnabled == false)
    }

    @Test func persistsEnabledState() {
        let defaults = UserDefaults(suiteName: "DemoCaptureModeStoreTests.persist.\(UUID().uuidString)")!
        let store = DemoCaptureModeStore(userDefaults: defaults)

        store.isEnabled = true

        let reloaded = DemoCaptureModeStore(userDefaults: defaults)
        #expect(reloaded.isEnabled == true)
    }
}
