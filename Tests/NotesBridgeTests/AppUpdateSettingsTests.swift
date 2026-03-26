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

    @MainActor
    @Test
    func knownFolderCountFallsBackToPersistedFullSyncCountBeforeFolderRefresh() {
        let model = AppModel(
            notesClient: StubAppleNotesClient(),
            persistence: StubUpdatePersistenceStore(
                syncIndex: makeSyncIndex(
                    noteCount: 437,
                    knownFolderCount: nil,
                    lastFullSyncFolderCount: 19
                )
            ),
            startImmediately: false
        )

        #expect(model.syncedNoteCount == 437)
        #expect(model.folderSummaries.isEmpty)
        #expect(model.knownFolderCount == 19)
    }

    @MainActor
    @Test
    func knownFolderCountPrefersLoadedFolderSummariesAfterRefresh() async {
        let folders = [
            AppleNotesFolder(id: "inbox", name: "Inbox", accountName: nil, noteCount: 2),
            AppleNotesFolder(id: "projects", name: "Projects", accountName: nil, noteCount: 4),
            AppleNotesFolder(id: "archive", name: "Archive", accountName: nil, noteCount: 1),
        ]
        let model = AppModel(
            notesClient: StubAppleNotesClient(folders: folders),
            persistence: StubUpdatePersistenceStore(
                syncIndex: makeSyncIndex(
                    noteCount: 437,
                    knownFolderCount: 19,
                    lastFullSyncFolderCount: 19
                )
            ),
            startImmediately: false
        )

        await model.refreshFolderSummaries()

        #expect(model.knownFolderCount == 3)
    }

    @MainActor
    @Test
    func refreshingFolderSummariesPersistsKnownFolderCount() async {
        let folders = [
            AppleNotesFolder(id: "inbox", name: "Inbox", accountName: nil, noteCount: 2),
            AppleNotesFolder(id: "projects", name: "Projects", accountName: nil, noteCount: 4),
            AppleNotesFolder(id: "archive", name: "Archive", accountName: nil, noteCount: 1),
        ]
        let persistence = RecordingUpdatePersistenceStore(
            syncIndex: makeSyncIndex(
                noteCount: 437,
                knownFolderCount: 19,
                lastFullSyncFolderCount: 19
            )
        )
        let model = AppModel(
            notesClient: StubAppleNotesClient(folders: folders),
            persistence: persistence,
            startImmediately: false
        )

        await model.refreshFolderSummaries()

        #expect(persistence.savedSyncIndex?.knownFolderCount == 3)
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
    var syncIndex = SyncIndex()

    func loadSettings() -> AppSettings {
        AppSettings.default
    }

    func saveSettings(_ settings: AppSettings) throws {}

    func loadSyncIndex() -> SyncIndex {
        syncIndex
    }

    func saveSyncIndex(_ index: SyncIndex) throws {}
}

private struct StubAppleNotesClient: AppleNotesClient {
    var folders: [AppleNotesFolder] = []

    func fetchFolders() throws -> [AppleNotesFolder] {
        folders
    }

    func fetchNoteSummaries(inFolderID folderID: String) throws -> [AppleNoteSummary] {
        []
    }

    func fetchDocuments(inFolderID folderID: String) throws -> [AppleNoteDocument] {
        []
    }

    func fetchDocument(id: String, inFolderID folderID: String) throws -> AppleNoteDocument {
        throw AppleNotesError.invalidResponse
    }

    func updateNote(id: String, htmlBody: String) throws {}
}

private final class RecordingUpdatePersistenceStore: @unchecked Sendable, PersistenceStoring {
    private let initialSyncIndex: SyncIndex
    private let lock = NSLock()
    private var _savedSyncIndex: SyncIndex?

    var savedSyncIndex: SyncIndex? {
        lock.lock()
        defer { lock.unlock() }
        return _savedSyncIndex
    }

    init(syncIndex: SyncIndex) {
        self.initialSyncIndex = syncIndex
    }

    func loadSettings() -> AppSettings {
        AppSettings.default
    }

    func saveSettings(_ settings: AppSettings) throws {}

    func loadSyncIndex() -> SyncIndex {
        initialSyncIndex
    }

    func saveSyncIndex(_ index: SyncIndex) throws {
        lock.lock()
        _savedSyncIndex = index
        lock.unlock()
    }
}

private func makeSyncIndex(
    noteCount: Int,
    knownFolderCount: Int? = nil,
    lastFullSyncFolderCount: Int? = nil
) -> SyncIndex {
    var records: [String: SyncRecord] = [:]
    for index in 0..<noteCount {
        let noteID = "note-\(index)"
        records[noteID] = SyncRecord(
            noteID: noteID,
            relativePath: "Apple Notes/Note \(index).md",
            sourceUpdatedAt: nil
        )
    }

    return SyncIndex(
        records: records,
        knownFolderCount: knownFolderCount,
        lastSyncAt: nil,
        lastSyncMode: nil,
        lastIncrementalSyncAt: nil,
        lastAutomaticSyncAt: nil,
        lastFullSyncAt: lastFullSyncFolderCount == nil ? nil : Date(),
        lastFullSyncNoteCount: noteCount,
        lastFullSyncFolderCount: lastFullSyncFolderCount
    )
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
