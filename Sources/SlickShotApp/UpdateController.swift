import AppKit
import Foundation
import Sparkle

@MainActor
final class UpdateController {
    private let updaterController: SPUStandardUpdaterController

    init?(
        bundle: Bundle = .main
    ) {
        guard Self.isConfigured(bundle: bundle) else {
            return nil
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    static func isConfigured(bundle: Bundle = .main) -> Bool {
        guard
            let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        else {
            return false
        }

        return feedURL.isEmpty == false &&
            publicKey.isEmpty == false &&
            publicKey != AppBundleMetadata.sparklePublicEDKey
    }
}
