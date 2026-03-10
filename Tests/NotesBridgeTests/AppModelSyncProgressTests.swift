import Testing
@testable import NotesBridge

struct AppModelSyncProgressTests {
    @MainActor
    @Test
    func syncProgressAdvancesAndClearsOnSuccess() async {
        var settings = AppSettings.default
        settings.vaultPath = "/tmp/notesbridge-tests"

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
        let notesClient = StubNotesClient(
            folders: [inboxFolder, projectsFolder],
            documentsByFolderID: [
                "folder-1": [
                    note(id: "note-1", name: "First", folder: "Inbox"),
                    note(id: "note-2", name: "Second", folder: "Inbox"),
                ],
                "folder-2": [
                    note(id: "note-3", name: "Third", folder: "Projects"),
                ],
            ]
        )
        let model = AppModel(
            notesClient: notesClient,
            syncEngine: StubSyncEngine(),
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
        let sawCompletedSync = snapshots.contains { snapshot in
            snapshot.completedNotes == 3 && snapshot.completedFolders == 2
        }

        #expect(snapshots.first?.totalNotes == 3)
        #expect(snapshots.first?.totalFolders == 2)
        #expect(sawInitialInboxProgress)
        #expect(sawCompletedFirstFolder)
        #expect(sawCompletedSync)
        #expect(model.syncProgress == nil)
        #expect(model.statusMessage.contains("Synced 3 note(s) across 2 folder(s)."))
    }

    @MainActor
    @Test
    func syncProgressClearsOnFailure() async {
        var settings = AppSettings.default
        settings.vaultPath = "/tmp/notesbridge-tests"

        let folder = AppleNotesFolder(
            id: "folder-1",
            name: "Inbox",
            accountName: nil,
            noteCount: 2
        )
        let notesClient = StubNotesClient(
            folders: [folder],
            documentsByFolderID: [
                "folder-1": [
                    note(id: "note-1", name: "First", folder: "Inbox"),
                    note(id: "note-2", name: "Second", folder: "Inbox"),
                ],
            ]
        )
        let model = AppModel(
            notesClient: notesClient,
            syncEngine: StubSyncEngine(failingNoteID: "note-2"),
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

    private static func note(id: String, name: String, folder: String) -> AppleNoteDocument {
        AppleNoteDocument(
            id: id,
            name: name,
            folder: folder,
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            plaintext: "Body",
            htmlBody: "<div>Body</div>"
        )
    }

    private func note(id: String, name: String, folder: String) -> AppleNoteDocument {
        Self.note(id: id, name: name, folder: folder)
    }
}

private struct StubNotesClient: AppleNotesClient {
    var folders: [AppleNotesFolder]
    var documentsByFolderID: [String: [AppleNoteDocument]]

    func fetchFolders() throws -> [AppleNotesFolder] {
        folders
    }

    func fetchNoteSummaries(inFolderID folderID: String) throws -> [AppleNoteSummary] {
        (documentsByFolderID[folderID] ?? []).map(\.summary)
    }

    func fetchDocuments(inFolderID folderID: String) throws -> [AppleNoteDocument] {
        documentsByFolderID[folderID] ?? []
    }

    func fetchDocument(id: String, inFolderID folderID: String) throws -> AppleNoteDocument {
        guard let document = (documentsByFolderID[folderID] ?? []).first(where: { $0.id == id }) else {
            throw AppleNotesError.noteNotFound(id)
        }

        return document
    }

    func updateNote(id: String, htmlBody: String) throws {}
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

    func sync(
        document: AppleNoteDocument,
        markdown: String,
        settings: AppSettings,
        existingRelativePath: String?
    ) throws -> SyncRecord {
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
