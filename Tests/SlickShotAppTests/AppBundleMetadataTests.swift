import Testing
import Foundation

@testable import SlickShotApp

struct AppBundleMetadataTests {
    @Test func bundleMetadata_matchesRaycastLaunchableAppShape() {
        #expect(AppBundleMetadata.appName == "SlickShot")
        #expect(AppBundleMetadata.bundleIdentifier == "com.yasudanaoki.SlickShot")
        #expect(AppBundleMetadata.executableName == "SlickShot")
        #expect(AppBundleMetadata.bundlePackageType == "APPL")
    }

    @Test func installerScript_resignsAppBundleAfterWritingInfoPlist() throws {
        let scriptURL = URL(fileURLWithPath: "/Users/yasudanaoki/Desktop/slick-shot/Scripts/install-app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(script.contains("codesign --force --deep --sign - \"$APP_DIR\""))
    }
}
