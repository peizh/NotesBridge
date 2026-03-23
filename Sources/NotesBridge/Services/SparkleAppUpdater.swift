import Combine
import Foundation
import Sparkle

@MainActor
final class SparkleAppUpdater: NSObject, AppUpdating {
    private static let automaticChecksUserDefaultKey = "SUEnableAutomaticChecks"
    private static let automaticDownloadsUserDefaultKey = "SUAutomaticallyUpdate"

    private let updaterController: SPUStandardUpdaterController
    private let version: AppVersion
    private let subject: CurrentValueSubject<AppUpdateState, Never>
    private var cancellables: Set<AnyCancellable> = []

    init(bundle: Bundle = .main) {
        let version = AppVersion.current(bundle: bundle)
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Self.automaticChecksUserDefaultKey: true,
            Self.automaticDownloadsUserDefaultKey: false,
        ])

        self.version = version
        self.subject = CurrentValueSubject(
            AppUpdateState(
                isEnabled: true,
                currentVersion: version,
                canCheckForUpdates: false,
                automaticallyChecksForUpdates: true,
                automaticallyDownloadsUpdates: false
            )
        )
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()

        bind(updater: updaterController.updater)
        publishState(from: updaterController.updater)
    }

    var currentState: AppUpdateState {
        subject.value
    }

    var statePublisher: AnyPublisher<AppUpdateState, Never> {
        subject.eraseToAnyPublisher()
    }

    func checkForUpdates() {
        guard updaterController.updater.canCheckForUpdates else {
            return
        }
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
        if !enabled {
            updaterController.updater.automaticallyDownloadsUpdates = false
        }
        publishState(from: updaterController.updater)
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyDownloadsUpdates = enabled
        publishState(from: updaterController.updater)
    }

    private func bind(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] _ in
                self?.publishState(from: updater)
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] _ in
                self?.publishState(from: updater)
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self] _ in
                self?.publishState(from: updater)
            }
            .store(in: &cancellables)
    }

    private func publishState(from updater: SPUUpdater) {
        subject.send(
            AppUpdateState(
                isEnabled: true,
                currentVersion: version,
                canCheckForUpdates: updater.canCheckForUpdates,
                automaticallyChecksForUpdates: updater.automaticallyChecksForUpdates,
                automaticallyDownloadsUpdates: updater.automaticallyDownloadsUpdates
            )
        )
    }
}
