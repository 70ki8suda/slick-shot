import Testing
import Foundation

@testable import SlickShotApp

struct AppBundleMetadataTests {
    @Test func bundleMetadata_matchesRaycastLaunchableAppShape() {
        #expect(AppBundleMetadata.appName == "SlickShot")
        #expect(AppBundleMetadata.bundleIdentifier == "com.yasudanaoki.SlickShot")
        #expect(AppBundleMetadata.executableName == "SlickShot")
        #expect(AppBundleMetadata.bundlePackageType == "APPL")
        #expect(AppBundleMetadata.iconFileName == "AppIcon")
    }

    @Test func installerScript_buildsIconAndResignsAppBundle() throws {
        let scriptURL = URL(fileURLWithPath: "/Users/yasudanaoki/Desktop/slick-shot/Scripts/install-app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(script.contains("iconutil -c icns"))
        #expect(script.contains("SlickShot Local Signing"))
        #expect(script.contains("security create-keychain"))
        #expect(script.contains("security list-keychains -d user -s"))
        #expect(script.contains("security add-trusted-cert -d -r trustRoot -k \"$KEYCHAIN_PATH\" \"$certificate\""))
        #expect(script.contains("codesign --force --deep --keychain \"$KEYCHAIN_PATH\" --sign \"$IDENTITY_HASH\" \"$APP_DIR\""))
    }
}
