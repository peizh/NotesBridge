import Foundation
import Testing
@testable import NotesBridge

struct AppModelAutomaticSyncTests {
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

private final class AccessSessionProbe: @unchecked Sendable {
    var createdCount = 0
    var stoppedCount = 0
}
