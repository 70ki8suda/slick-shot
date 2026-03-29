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

    @Test func bundleMetadata_includesSparkleDistributionDefaults() {
        #expect(AppBundleMetadata.sparkleFeedURL == "https://downloads.slick-shot.com/appcast.xml")
        #expect(AppBundleMetadata.sparklePublicEDKey == "REPLACE_WITH_SPARKLE_PUBLIC_ED25519_KEY")
    }

    @Test func distributionBuild_hidesDemoCaptureMode() {
        let distributionBundle = BundleInfoStub([
            AppBundleMetadata.distributionBuildInfoKey: true
        ])
        let developmentBundle = BundleInfoStub([:])

        #expect(AppBundleMetadata.exposesDemoCaptureMode(bundle: developmentBundle) == true)
        #expect(AppBundleMetadata.exposesDemoCaptureMode(bundle: distributionBundle) == false)
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
        #expect(script.contains("Sparkle.framework"))
        #expect(script.contains("install_name_tool -add_rpath \"@executable_path/../Frameworks\""))
        #expect(script.contains("<key>SUFeedURL</key>"))
        #expect(script.contains("<key>SUPublicEDKey</key>"))
    }

    @Test func releaseScript_marksDistributionBuildToHideDemoCaptureMode() throws {
        let scriptURL = URL(fileURLWithPath: "/Users/yasudanaoki/Desktop/slick-shot/Scripts/build-release.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(script.contains("<key>\(AppBundleMetadata.distributionBuildInfoKey)</key>"))
        #expect(script.contains("<true/>"))
    }

    @Test func lpIncludesThanksAndDownloadPagesForDirectSaleFlow() throws {
        let thanksURL = URL(fileURLWithPath: "/Users/yasudanaoki/Desktop/slick-shot/docs/lp/thanks.html")
        let downloadURL = URL(fileURLWithPath: "/Users/yasudanaoki/Desktop/slick-shot/docs/lp/download.html")

        #expect(FileManager.default.fileExists(atPath: thanksURL.path))
        #expect(FileManager.default.fileExists(atPath: downloadURL.path))

        let thanks = try String(contentsOf: thanksURL, encoding: .utf8)
        let download = try String(contentsOf: downloadURL, encoding: .utf8)

        #expect(thanks.contains("ダウンロード"))
        #expect(download.contains("Sparkle"))
        #expect(download.contains("自動更新"))
    }

    @Test func releaseScriptsAndReadmeDescribeSparkleDistributionFlow() throws {
        let buildScriptURL = URL(fileURLWithPath: "/Users/yasudanaoki/Desktop/slick-shot/Scripts/build-release.sh")
        let appcastScriptURL = URL(fileURLWithPath: "/Users/yasudanaoki/Desktop/slick-shot/Scripts/generate-appcast.sh")
        let readmeURL = URL(fileURLWithPath: "/Users/yasudanaoki/Desktop/slick-shot/README.md")

        #expect(FileManager.default.fileExists(atPath: buildScriptURL.path))
        #expect(FileManager.default.fileExists(atPath: appcastScriptURL.path))

        let buildScript = try String(contentsOf: buildScriptURL, encoding: .utf8)
        let appcastScript = try String(contentsOf: appcastScriptURL, encoding: .utf8)
        let readme = try String(contentsOf: readmeURL, encoding: .utf8)

        #expect(buildScript.contains("notarytool"))
        #expect(buildScript.contains("SLICKSHOT_DEVELOPER_ID_APP"))
        #expect(buildScript.contains("install_name_tool -add_rpath \"@executable_path/../Frameworks\""))
        #expect(appcastScript.contains("generate_appcast"))
        #expect(appcastScript.contains("appcast.xml"))
        #expect(readme.contains("Sparkle"))
        #expect(readme.contains("Stripe"))
        #expect(readme.contains("build-release.sh"))
    }
}

private struct BundleInfoStub: BundleInfoProviding {
    let infoDictionary: [String: Any]

    init(_ infoDictionary: [String: Any]) {
        self.infoDictionary = infoDictionary
    }

    func object(forInfoDictionaryKey key: String) -> Any? {
        infoDictionary[key]
    }
}
