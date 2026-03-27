import Foundation
import Testing
@testable import NotesBridge

struct AppModelAutomaticSyncTests {
    @MainActor
    @Test
    func onChangeWatcherDebouncesBackgroundNotificationsWithoutDroppingLifecycleBehavior() async {
        let watcher = ManualNotesDatabaseWatcher()
        let syncProbe = AutomaticSyncProbe()
        var settings = AppSettings.default
        settings.vaultPath = "/tmp/notesbridge-tests"
        settings.appleNotesDataPath = "/tmp/group.com.apple.notes"
        settings.automaticSyncEnabled = true
        settings.automaticSyncTrigger = .onChange

        let model = AppModel(
            appleNotesSyncDataSource: RecordingAutomaticSyncDataSource(),
            syncEngine: RecordingAutomaticSyncEngine(probe: syncProbe),
            persistence: StubAutomaticSyncPersistenceStore(settings: settings),
            appUpdater: NoOpAppUpdater(version: AppVersion(shortVersionString: "0.2.9", buildNumber: "1")),
            notesDatabaseWatcher: watcher,
            automaticSyncDebounceInterval: 0.05,
            startImmediately: false
        )

        model.settings = settings
        await watcher.fire()
        await watcher.fire()
        try? await Task.sleep(nanoseconds: 250_000_000)

        #expect(watcher.startCallCount == 1)
        #expect(watcher.stopCallCount == 1)
        #expect(syncProbe.syncCallCount == 1)
    }

    @MainActor
    @Test
    func onChangeWatcherRetainsDataFolderAccessSessionUntilAutomaticSyncStops() {
        let probe = AccessSessionProbe()
        var settings = AppSettings.default
        settings.appleNotesDataPath = "/tmp/group.com.apple.notes"
        settings.automaticSyncEnabled = true
        settings.automaticSyncTrigger = .onChange

        let model = AppModel(
            appleNotesSyncDataSource: StubAutomaticSyncDataSource(),
            persistence: StubAutomaticSyncPersistenceStore(settings: settings),
            appUpdater: NoOpAppUpdater(version: AppVersion(shortVersionString: "0.2.7", buildNumber: "1")),
            appleNotesDataFolderAccessSessionFactory: { path, _ in
                probe.createdCount += 1
                let url = URL(fileURLWithPath: path ?? "/tmp/group.com.apple.notes", isDirectory: true)
                return AppleNotesDataFolderAccessSession(url: url) {
                    probe.stoppedCount += 1
                }
            },
            startImmediately: false
        )

        model.settings = settings

        #expect(probe.createdCount == 2)
        #expect(probe.stoppedCount == 1)

        var disabledSettings = settings
        disabledSettings.automaticSyncEnabled = false
        model.settings = disabledSettings

        #expect(probe.createdCount == 3)
        #expect(probe.stoppedCount == 3)
    }
}

private struct StubAutomaticSyncPersistenceStore: PersistenceStoring {
    var settings: AppSettings

    func loadSettings() -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) throws {}

    func loadSyncIndex() -> SyncIndex {
        SyncIndex()
    }

    func saveSyncIndex(_ index: SyncIndex) throws {}
}

private struct StubAutomaticSyncDataSource: AppleNotesSyncDataSourcing {
    func validateDataFolder(at path: String) throws -> AppleNotesDataFolderSelection {
        .resolved(rootPath: path)
    }

    func inspectDataFolder(at path: String) -> AppleNotesDataFolderAccessStatus {
        AppleNotesDataFolderAccessStatus(
            level: .accessible,
            message: "The configured Apple Notes data folder is readable."
        )
    }

    func fetchFolders(fromDataFolder path: String) throws -> [AppleNotesFolder] {
        []
    }

    func loadManifest(fromDataFolder path: String) throws -> AppleNotesSyncManifest {
        AppleNotesSyncManifest(
            folders: [],
            entries: [],
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:],
            sourceDiagnostics: nil,
            selectedDatabaseRelativePath: nil
        )
    }

    func loadDocuments(
        fromDataFolder path: String,
        noteIDs: Set<Int64>,
        preferredDatabaseRelativePath: String?
    ) throws -> AppleNotesSyncSnapshot {
        AppleNotesSyncSnapshot(
            folders: [],
            documents: [],
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:]
        )
    }

    func loadSnapshot(fromDataFolder path: String) throws -> AppleNotesSyncSnapshot {
        AppleNotesSyncSnapshot(
            folders: [],
            documents: [],
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:]
        )
    }
}

private struct RecordingAutomaticSyncDataSource: AppleNotesSyncDataSourcing {
    func validateDataFolder(at path: String) throws -> AppleNotesDataFolderSelection {
        .resolved(rootPath: path)
    }

    func inspectDataFolder(at path: String) -> AppleNotesDataFolderAccessStatus {
        AppleNotesDataFolderAccessStatus(
            level: .accessible,
            message: "The configured Apple Notes data folder is readable."
        )
    }

    func fetchFolders(fromDataFolder path: String) throws -> [AppleNotesFolder] {
        [
            AppleNotesFolder(id: "folder-1", name: "Inbox", accountName: nil, noteCount: 1),
        ]
    }

    func loadManifest(fromDataFolder path: String) throws -> AppleNotesSyncManifest {
        AppleNotesSyncManifest(
            folders: try fetchFolders(fromDataFolder: path),
            entries: [
                AppleNotesSyncManifestEntry(
                    databaseNoteID: 1,
                    name: "Stable",
                    folder: "Inbox",
                    updatedAt: Date(timeIntervalSince1970: 1),
                    passwordProtected: false,
                    trashed: false
                ),
            ],
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:],
            sourceDiagnostics: nil,
            selectedDatabaseRelativePath: nil
        )
    }

    func loadDocuments(
        fromDataFolder path: String,
        noteIDs: Set<Int64>,
        preferredDatabaseRelativePath: String?
    ) throws -> AppleNotesSyncSnapshot {
        AppleNotesSyncSnapshot(
            folders: try fetchFolders(fromDataFolder: path),
            documents: [
                AppleNotesSyncDocument(
                    databaseNoteID: 1,
                    name: "Stable",
                    folder: "Inbox",
                    createdAt: Date(timeIntervalSince1970: 0),
                    updatedAt: Date(timeIntervalSince1970: 1),
                    shared: false,
                    passwordProtected: false,
                    markdownTemplate: "Stable",
                    attachments: []
                ),
            ],
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:]
        )
    }

    func loadSnapshot(fromDataFolder path: String) throws -> AppleNotesSyncSnapshot {
        try loadDocuments(
            fromDataFolder: path,
            noteIDs: [1],
            preferredDatabaseRelativePath: nil
        )
    }
}

private final class AccessSessionProbe: @unchecked Sendable {
    var createdCount = 0
    var stoppedCount = 0
}

private final class AutomaticSyncProbe: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var syncCallCount = 0

    func recordSyncCall() {
        lock.lock()
        syncCallCount += 1
        lock.unlock()
    }
}

private struct RecordingAutomaticSyncEngine: Syncing {
    let probe: AutomaticSyncProbe

    func sync(
        document: AppleNotesSyncDocument,
        settings: AppSettings,
        existingRelativePath: String?,
        plannedRelativePath: String,
        plannedRelativePathsBySourceIdentifier: [String: String]
    ) throws -> NoteSyncResult {
        probe.recordSyncCall()
        return NoteSyncResult(
            record: SyncRecord(
                noteID: document.id,
                relativePath: plannedRelativePath,
                sourceUpdatedAt: document.updatedAt
            ),
            changeKind: existingRelativePath == nil ? .created : .updated,
            unresolvedInternalLinkCount: 0
        )
    }
}

private final class ManualNotesDatabaseWatcher: NotesDatabaseWatching, @unchecked Sendable {
    var onChange: (@MainActor @Sendable () -> Void)?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start(dataFolderURL: URL) {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func fire() async {
        await Task { @MainActor in
            onChange?()
        }.value
    }
}
