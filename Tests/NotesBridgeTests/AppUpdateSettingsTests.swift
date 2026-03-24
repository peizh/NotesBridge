import Combine
import Foundation
import Testing
@testable import NotesBridge

struct AppUpdateSettingsTests {
    @Test
    func readsVersionAndBuildFromBundleInfoDictionary() throws {
        let bundle = try makeBundle(
            infoDictionary: [
                "CFBundleIdentifier": "notes.tests.bundle",
                "CFBundleName": "NotesBridge Tests",
                "CFBundlePackageType": "BNDL",
                "CFBundleShortVersionString": "1.2.3",
                "CFBundleVersion": "456",
            ]
        )

        let version = AppVersion.current(bundle: bundle)

        #expect(version.shortVersionString == "1.2.3")
        #expect(version.buildNumber == "456")
    }

    @Test
    func fallsBackToDefaultVersionWhenInfoDictionaryIsMissingValues() throws {
        let bundle = try makeBundle(
            infoDictionary: [
                "CFBundleIdentifier": "notes.tests.bundle",
                "CFBundleName": "NotesBridge Tests",
                "CFBundlePackageType": "BNDL",
            ]
        )

        let version = AppVersion.current(bundle: bundle)

        #expect(version.shortVersionString == "0.0.0")
        #expect(version.buildNumber == "0")
    }

    @MainActor
    @Test
    func modelExposesUpdaterStateForDirectDownloadBuild() {
        let updater = StubAppUpdater(
            state: AppUpdateState(
                isEnabled: true,
                currentVersion: AppVersion(shortVersionString: "2.0.0", buildNumber: "200"),
                canCheckForUpdates: true,
                automaticallyChecksForUpdates: true,
                automaticallyDownloadsUpdates: false
            )
        )
        let model = AppModel(
            persistence: StubUpdatePersistenceStore(),
            buildFlavor: .directDownload,
            appUpdater: updater,
            startImmediately: false
        )

        #expect(model.showsAppUpdateSettings)
        #expect(model.currentAppVersion == "2.0.0")
        #expect(model.currentAppBuildNumber == "200")
        #expect(model.currentAppVersionDisplay == "2.0.0 (200)")
        #expect(model.canCheckForUpdates)
        #expect(model.automaticallyChecksForUpdates)
        #expect(!model.automaticallyDownloadsUpdates)

        model.checkForUpdates()
        #expect(updater.checkForUpdatesCallCount == 1)
    }

    @MainActor
    @Test
    func modelUpdatesSparklePreferencesThroughFacade() {
        let updater = StubAppUpdater(
            state: AppUpdateState(
                isEnabled: true,
                currentVersion: AppVersion(shortVersionString: "2.0.0", buildNumber: "200"),
                canCheckForUpdates: true,
                automaticallyChecksForUpdates: true,
                automaticallyDownloadsUpdates: true
            )
        )
        let model = AppModel(
            persistence: StubUpdatePersistenceStore(),
            buildFlavor: .directDownload,
            appUpdater: updater,
            startImmediately: false
        )

        model.setAutomaticallyChecksForUpdates(false)
        pumpMainRunLoop()

        #expect(!model.automaticallyChecksForUpdates)
        #expect(!model.automaticallyDownloadsUpdates)

        model.setAutomaticallyChecksForUpdates(true)
        model.setAutomaticallyDownloadsUpdates(true)
        pumpMainRunLoop()

        #expect(model.automaticallyChecksForUpdates)
        #expect(model.automaticallyDownloadsUpdates)
    }

    @MainActor
    @Test
    func appStoreBuildKeepsUpdateSettingsHidden() {
        let model = AppModel(
            persistence: StubUpdatePersistenceStore(),
            buildFlavor: .appStore,
            startImmediately: false
        )

        #expect(!model.showsAppUpdateSettings)
        #expect(!model.canCheckForUpdates)
    }

    private func makeBundle(infoDictionary: [String: Any]) throws -> Bundle {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesBridge-AppVersion-\(UUID().uuidString)", isDirectory: true)
        let bundleURL = rootURL.appendingPathComponent("Fixture.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: infoDictionary,
            format: .xml,
            options: 0
        )
        try plistData.write(
            to: bundleURL.appendingPathComponent("Info.plist", isDirectory: false),
            options: .atomic
        )

        return try #require(Bundle(url: bundleURL))
    }

    @MainActor
    private func pumpMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
}

private struct StubUpdatePersistenceStore: PersistenceStoring {
    func loadSettings() -> AppSettings {
        AppSettings.default
    }

    func saveSettings(_ settings: AppSettings) throws {}

    func loadSyncIndex() -> SyncIndex {
        SyncIndex()
    }

    func saveSyncIndex(_ index: SyncIndex) throws {}
}

@MainActor
private final class StubAppUpdater: AppUpdating {
    private let subject: CurrentValueSubject<AppUpdateState, Never>
    private(set) var checkForUpdatesCallCount = 0

    init(state: AppUpdateState) {
        self.subject = CurrentValueSubject(state)
    }

    var currentState: AppUpdateState {
        subject.value
    }

    var statePublisher: AnyPublisher<AppUpdateState, Never> {
        subject.eraseToAnyPublisher()
    }

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        let current = subject.value
        subject.send(
            AppUpdateState(
                isEnabled: current.isEnabled,
                currentVersion: current.currentVersion,
                canCheckForUpdates: current.canCheckForUpdates,
                automaticallyChecksForUpdates: enabled,
                automaticallyDownloadsUpdates: enabled ? current.automaticallyDownloadsUpdates : false
            )
        )
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        let current = subject.value
        subject.send(
            AppUpdateState(
                isEnabled: current.isEnabled,
                currentVersion: current.currentVersion,
                canCheckForUpdates: current.canCheckForUpdates,
                automaticallyChecksForUpdates: current.automaticallyChecksForUpdates,
                automaticallyDownloadsUpdates: enabled
            )
        )
    }
}
