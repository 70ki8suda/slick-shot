import Foundation

final class DemoCaptureModeStore {
    static let defaultsKey = "slickshot.demoCaptureModeEnabled"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: Self.defaultsKey) }
        set { userDefaults.set(newValue, forKey: Self.defaultsKey) }
    }
}
