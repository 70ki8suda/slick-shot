import Testing

@testable import SlickShotApp

struct AppBundleMetadataTests {
    @Test func bundleMetadata_matchesRaycastLaunchableAppShape() {
        #expect(AppBundleMetadata.appName == "SlickShot")
        #expect(AppBundleMetadata.bundleIdentifier == "com.yasudanaoki.SlickShot")
        #expect(AppBundleMetadata.executableName == "SlickShot")
        #expect(AppBundleMetadata.bundlePackageType == "APPL")
    }
}
