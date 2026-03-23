import Foundation

struct AppVersion: Equatable, Sendable {
    let shortVersionString: String
    let buildNumber: String

    static func current(bundle: Bundle = .main) -> AppVersion {
        AppVersion(
            shortVersionString: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.2",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        )
    }
}
