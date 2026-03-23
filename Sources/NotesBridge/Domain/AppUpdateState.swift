import Foundation

struct AppUpdateState: Equatable, Sendable {
    let isEnabled: Bool
    let currentVersion: AppVersion
    let canCheckForUpdates: Bool
    let automaticallyChecksForUpdates: Bool
    let automaticallyDownloadsUpdates: Bool

    static func disabled(version: AppVersion) -> AppUpdateState {
        AppUpdateState(
            isEnabled: false,
            currentVersion: version,
            canCheckForUpdates: false,
            automaticallyChecksForUpdates: false,
            automaticallyDownloadsUpdates: false
        )
    }
}
