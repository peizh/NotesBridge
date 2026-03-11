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
            startImmediately: false
        )

        let syncTask = Task {
            await model.syncAllNotes()
        }

        let snapshots = await captureProgressSnapshots(from: model, while: syncTask)

        await syncTask.value

        let sawInitialInboxProgress = snapshots.contains { snapshot in
            snapshot.currentFolderName == "Inbox"
                && snapshot.completedNotes == 0
                && snapshot.completedFolders == 0
        }
        let sawCompletedFirstFolder = snapshots.contains { snapshot in
            snapshot.completedNotes == 2 && snapshot.completedFolders == 1
        }
        #expect(snapshots.first?.totalNotes == 3)
        #expect(snapshots.first?.totalFolders == 2)
        #expect(sawInitialInboxProgress)
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
            startImmediately: false
        )

        let syncTask = Task {
            await model.syncAllNotes()
        }

        let snapshots = await captureProgressSnapshots(from: model, while: syncTask)
        let sawFirstCompletedNote = snapshots.contains { snapshot in
            snapshot.completedNotes == 1
        }

        await syncTask.value

        #expect(sawFirstCompletedNote)
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
}

private struct StubAppleNotesSyncDataSource: AppleNotesSyncDataSourcing {
    var folders: [AppleNotesFolder]
    var documentsByFolderName: [String: [AppleNotesSyncDocument]]

    func validateDataFolder(at path: String) throws -> AppleNotesDataFolderSelection {
        .resolved(rootPath: path)
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
        existingRelativePath: String?
    ) throws -> SyncRecord {
        if syncDelay > 0 {
            Thread.sleep(forTimeInterval: syncDelay)
        }

        if document.id == failingNoteID {
            throw StubSyncError.failed
        }

        return SyncRecord(
            noteID: document.id,
            relativePath: "\(document.displayName).md",
            sourceUpdatedAt: document.updatedAt
        )
    }
}

private enum StubSyncError: Error {
    case failed
}
