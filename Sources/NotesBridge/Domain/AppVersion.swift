import Foundation

struct AppVersion: Equatable, Sendable {
    let shortVersionString: String
    let buildNumber: String

    static func current(bundle: Bundle = .main) -> AppVersion {
        AppVersion(
            shortVersionString: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        )
    }
}
