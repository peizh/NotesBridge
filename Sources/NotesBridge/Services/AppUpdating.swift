import Combine
import Foundation

@MainActor
protocol AppUpdating: AnyObject {
    var currentState: AppUpdateState { get }
    var statePublisher: AnyPublisher<AppUpdateState, Never> { get }

    func checkForUpdates()
    func setAutomaticallyChecksForUpdates(_ enabled: Bool)
    func setAutomaticallyDownloadsUpdates(_ enabled: Bool)
}

@MainActor
enum AppUpdaterFactory {
    static func make(
        buildFlavor: BuildFlavor,
        bundle: Bundle = .main
    ) -> any AppUpdating {
        switch buildFlavor {
        case .directDownload:
            SparkleAppUpdater(bundle: bundle)
        case .appStore:
            NoOpAppUpdater(version: AppVersion.current(bundle: bundle))
        }
    }
}

@MainActor
final class NoOpAppUpdater: AppUpdating {
    private let subject: CurrentValueSubject<AppUpdateState, Never>

    init(version: AppVersion) {
        self.subject = CurrentValueSubject(.disabled(version: version))
    }

    var currentState: AppUpdateState {
        subject.value
    }

    var statePublisher: AnyPublisher<AppUpdateState, Never> {
        subject.eraseToAnyPublisher()
    }

    func checkForUpdates() {}

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {}

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {}
}
