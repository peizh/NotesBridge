import Testing
@testable import NotesBridge

struct AppModelSyncProgressTests {
    @MainActor
    @Test
    func syncProgressAdvancesAndClearsOnSuccess() async {
        var settings = AppSettings.default
        settings.vaultPath = "/tmp/notesbridge-tests"
        settings.appleNotesDataPath = "/tmp/group.com.apple.notes"

        let inboxFolder = AppleNotesFolder(
            id: "folder-1",
            name: "Inbox",
            accountName: nil,
            noteCount: 2
        )
        let projectsFolder = AppleNotesFolder(
            id: "folder-2",
            name: "Projects",
            accountName: nil,
            noteCount: 1
        )
        let syncDataSource = StubAppleNotesSyncDataSource(
            folders: [inboxFolder, projectsFolder],
            documentsByFolderName: [
                "Inbox": [
                    note(id: "note-1", name: "First", folder: "Inbox"),
                    note(id: "note-2", name: "Second", folder: "Inbox"),
                ],
                "Projects": [
                    note(id: "note-3", name: "Third", folder: "Projects"),
                ],
            ]
        )
        let model = AppModel(
            appleNotesSyncDataSource: syncDataSource,
            syncEngine: StubSyncEngine(syncDelay: 0.01),
            persistence: StubPersistenceStore(settings: settings),
            appUpdater: makeTestAppUpdater(),
            startImmediately: false
        )

        let syncTask = Task {
            await model.syncAllNotes()
        }

        let snapshots = await captureProgressSnapshots(from: model, while: syncTask)

        await syncTask.value

        let sawInboxProgress = snapshots.contains { snapshot in
            snapshot.currentFolderName == "Inbox"
        }
        let sawProjectsProgress = snapshots.contains { snapshot in
            snapshot.currentFolderName == "Projects"
        }
        let sawNotesAdvanceBeforeFolderCompletion = snapshots.contains { snapshot in
            snapshot.completedNotes >= 1 && snapshot.completedFolders == 0
        }
        let sawCompletedFirstFolder = snapshots.contains { snapshot in
            snapshot.completedNotes == 2 && snapshot.completedFolders == 1
        }
        #expect(snapshots.first?.totalNotes == 3)
        #expect(snapshots.first?.totalFolders == 2)
        #expect(sawInboxProgress)
        #expect(sawProjectsProgress)
        #expect(sawNotesAdvanceBeforeFolderCompletion)
        #expect(sawCompletedFirstFolder)
        #expect(model.syncProgress == nil)
        #expect(model.statusMessage.contains("Synced 3 note(s) across 2 folder(s)."))
    }

    @MainActor
    @Test
    func syncProgressClearsOnFailure() async {
        var settings = AppSettings.default
        settings.vaultPath = "/tmp/notesbridge-tests"
        settings.appleNotesDataPath = "/tmp/group.com.apple.notes"

        let folder = AppleNotesFolder(
            id: "folder-1",
            name: "Inbox",
            accountName: nil,
            noteCount: 2
        )
        let syncDataSource = StubAppleNotesSyncDataSource(
            folders: [folder],
            documentsByFolderName: [
                "Inbox": [
                    note(id: "note-1", name: "First", folder: "Inbox"),
                    note(id: "note-2", name: "Second", folder: "Inbox"),
                ],
            ]
        )
        let model = AppModel(
            appleNotesSyncDataSource: syncDataSource,
            syncEngine: StubSyncEngine(
                failingNoteID: AppleNotesSyncDocument.canonicalID(for: 2),
                syncDelay: 0.01
            ),
            persistence: StubPersistenceStore(settings: settings),
            appUpdater: makeTestAppUpdater(),
            startImmediately: false
        )

        let syncTask = Task {
            await model.syncAllNotes()
        }

        let snapshots = await captureProgressSnapshots(from: model, while: syncTask)
        let sawInFlightProgress = snapshots.contains { snapshot in
            snapshot.totalNotes == 2 &&
                snapshot.totalFolders == 1 &&
                snapshot.currentFolderName == "Inbox"
        }

        await syncTask.value

        #expect(sawInFlightProgress)
        #expect(model.syncProgress == nil)
        #expect(model.statusMessage.contains("Failed to sync Apple Notes to Obsidian."))
    }

    @MainActor
    private func captureProgressSnapshots(
        from model: AppModel,
        while task: Task<Void, Never>
    ) async -> [SyncProgress] {
        var snapshots: [SyncProgress] = []
        var sawSyncStart = false

        for _ in 0 ..< 5_000 {
            if model.isSyncing {
                sawSyncStart = true
            }

            if let progress = model.syncProgress, snapshots.last != progress {
                snapshots.append(progress)
            }

            if sawSyncStart && !model.isSyncing && model.syncProgress == nil {
                break
            }

            if task.isCancelled {
                break
            }

            await Task.yield()
        }

        return snapshots
    }

    private static func note(id: String, name: String, folder: String) -> AppleNotesSyncDocument {
        AppleNotesSyncDocument(
            databaseNoteID: Int64(String(id.dropFirst(5))) ?? 0,
            name: name,
            folder: folder,
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "Body",
            attachments: []
        )
    }

    private func note(id: String, name: String, folder: String) -> AppleNotesSyncDocument {
        Self.note(id: id, name: name, folder: folder)
    }

    @MainActor
    private func makeTestAppUpdater() -> NoOpAppUpdater {
        NoOpAppUpdater(version: AppVersion(shortVersionString: "0.2.2", buildNumber: "1"))
    }
}

private struct StubAppleNotesSyncDataSource: AppleNotesSyncDataSourcing {
    var folders: [AppleNotesFolder]
    var documentsByFolderName: [String: [AppleNotesSyncDocument]]

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
        folders
    }

    func loadSnapshot(fromDataFolder path: String) throws -> AppleNotesSyncSnapshot {
        AppleNotesSyncSnapshot(
            folders: folders,
            documents: folders.flatMap { documentsByFolderName[$0.displayName] ?? [] },
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:]
        )
    }
}

private struct StubPersistenceStore: PersistenceStoring {
    var settings: AppSettings
    var syncIndex: SyncIndex = SyncIndex()

    func loadSettings() -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) throws {}

    func loadSyncIndex() -> SyncIndex {
        syncIndex
    }

    func saveSyncIndex(_ index: SyncIndex) throws {}
}

private struct StubSyncEngine: Syncing {
    var failingNoteID: String? = nil
    var syncDelay: TimeInterval = 0

    func sync(
        document: AppleNotesSyncDocument,
        settings: AppSettings,
        existingRelativePath: String?,
        plannedRelativePath: String,
        plannedRelativePathsBySourceIdentifier: [String: String]
    ) throws -> NoteSyncResult {
        if syncDelay > 0 {
            Thread.sleep(forTimeInterval: syncDelay)
        }

        if document.id == failingNoteID {
            throw StubSyncError.failed
        }

        return NoteSyncResult(
            record: SyncRecord(
                noteID: document.id,
                relativePath: plannedRelativePath,
                sourceUpdatedAt: document.updatedAt
            ),
            unresolvedInternalLinkCount: 0
        )
    }
}

private enum StubSyncError: Error {
    case failed
}
