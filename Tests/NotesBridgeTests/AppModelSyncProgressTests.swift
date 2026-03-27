import Combine
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

        let snapshots = await captureProgressSnapshots(from: model) {
            await model.syncAllNotes()
        }

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
        #expect(model.statusMessage.contains("Full sync: Processed 3 note(s) across 2 folder(s): updated 0, added 3, and left 0 unchanged."))
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

        let snapshots = await captureProgressSnapshots(from: model) {
            await model.syncAllNotes()
        }
        let sawInFlightProgress = snapshots.contains { snapshot in
            snapshot.totalNotes == 2 &&
                snapshot.totalFolders == 1 &&
                snapshot.currentFolderName == "Inbox"
        }

        #expect(sawInFlightProgress)
        #expect(model.syncProgress == nil)
        #expect(model.statusMessage.contains("Failed to sync Apple Notes to Obsidian."))
    }

    @MainActor
    @Test
    func incrementalSyncFallbackKeepsFallbackReasonInFinalStatus() async {
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
            ],
            missingDocumentIDsOnIncrementalLoad: [2]
        )
        let model = AppModel(
            appleNotesSyncDataSource: syncDataSource,
            syncEngine: StubSyncEngine(syncDelay: 0.01),
            persistence: StubPersistenceStore(settings: settings),
            appUpdater: makeTestAppUpdater(),
            startImmediately: false
        )

        await model.syncChangedNotes()

        #expect(model.statusMessage.contains("Incremental sync could not load 1 changed note(s) by ID, so it fell back to a full sync."))
        #expect(model.statusMessage.contains("Full sync: Processed 2 note(s) across 1 folder(s): updated 0, added 2, and left 0 unchanged."))
    }

    @MainActor
    @Test
    func incrementalSyncUsesManifestSelectedDatabaseForTargetedLoads() async {
        var settings = AppSettings.default
        settings.vaultPath = "/tmp/notesbridge-tests"
        settings.appleNotesDataPath = "/tmp/group.com.apple.notes"

        let folder = AppleNotesFolder(
            id: "folder-1",
            name: "Inbox",
            accountName: nil,
            noteCount: 1
        )
        let syncDataSource = StubAppleNotesSyncDataSource(
            folders: [folder],
            documentsByFolderName: [
                "Inbox": [
                    note(id: "note-1", name: "First", folder: "Inbox"),
                ],
            ],
            manifestSelectedDatabaseRelativePath: "Accounts/Primary/NoteStore.sqlite",
            requiredPreferredDatabaseRelativePathForIncrementalLoad: "Accounts/Primary/NoteStore.sqlite"
        )
        let model = AppModel(
            appleNotesSyncDataSource: syncDataSource,
            syncEngine: StubSyncEngine(syncDelay: 0.01),
            persistence: StubPersistenceStore(settings: settings),
            appUpdater: makeTestAppUpdater(),
            startImmediately: false
        )

        await model.syncChangedNotes()

        #expect(!model.statusMessage.contains("fell back to a full sync"))
        #expect(model.statusMessage.contains("Processed 1 note(s): updated 0, added 1, moved 0 to _Removed, and left 0 unchanged."))
    }

    @MainActor
    @Test
    func incrementalSyncWithNoExportsAndNoRemovalsSkipsChangedDocumentLoad() async {
        var settings = AppSettings.default
        settings.vaultPath = "/tmp/notesbridge-tests"
        settings.appleNotesDataPath = "/tmp/group.com.apple.notes"

        let dataSource = RecordingIncrementalDataSource(
            folders: [
                AppleNotesFolder(id: "folder-1", name: "Inbox", accountName: nil, noteCount: 1),
            ],
            documentsByFolderName: [
                "Inbox": [Self.note(id: "note-1", name: "Stable", folder: "Inbox")],
            ],
            syncIndex: SyncIndex(
                records: [
                    AppleNotesSyncDocument.canonicalID(for: 1): SyncRecord(
                        noteID: AppleNotesSyncDocument.canonicalID(for: 1),
                        relativePath: "Apple Notes/Inbox/Stable.md",
                        sourceUpdatedAt: nil,
                        sourceName: "Stable",
                        sourceFolderPath: "Inbox"
                    ),
                ],
                pathAliases: [
                    AppleNotesSyncDocument.canonicalID(for: 1): "Apple Notes/Inbox/Stable.md",
                ]
            )
        )

        let model = AppModel(
            appleNotesSyncDataSource: dataSource,
            persistence: StubPersistenceStore(settings: settings, syncIndex: dataSource.syncIndex),
            appUpdater: makeTestAppUpdater(),
            startImmediately: false
        )

        await model.syncChangedNotes()

        #expect(dataSource.loadDocumentsCallCount == 0)
        #expect(model.statusMessage.contains("found no changes"))
    }

    @MainActor
    @Test
    func noOpIncrementalSummaryShowsCachedPathIndex() async {
        var settings = AppSettings.default
        settings.vaultPath = "/tmp/notesbridge-tests"
        settings.appleNotesDataPath = "/tmp/group.com.apple.notes"

        let dataSource = RecordingIncrementalDataSource(
            folders: [
                AppleNotesFolder(id: "folder-1", name: "Inbox", accountName: nil, noteCount: 1),
            ],
            documentsByFolderName: [
                "Inbox": [Self.note(id: "note-1", name: "Stable", folder: "Inbox")],
            ],
            syncIndex: SyncIndex(
                records: [
                    AppleNotesSyncDocument.canonicalID(for: 1): SyncRecord(
                        noteID: AppleNotesSyncDocument.canonicalID(for: 1),
                        relativePath: "Apple Notes/Inbox/Stable.md",
                        sourceUpdatedAt: nil,
                        sourceName: "Stable",
                        sourceFolderPath: "Inbox"
                    ),
                ],
                pathAliases: [
                    AppleNotesSyncDocument.canonicalID(for: 1): "Apple Notes/Inbox/Stable.md",
                ]
            )
        )

        let model = AppModel(
            appleNotesSyncDataSource: dataSource,
            persistence: StubPersistenceStore(settings: settings, syncIndex: dataSource.syncIndex),
            appUpdater: makeTestAppUpdater(),
            startImmediately: false
        )

        await model.syncChangedNotes()

        #expect(model.statusMessage.contains("index"))
        #expect(model.statusMessage.contains("cached"))
    }

    @MainActor
    private func captureProgressSnapshots(
        from model: AppModel,
        perform operation: @escaping @MainActor () async -> Void
    ) async -> [SyncProgress] {
        var snapshots: [SyncProgress] = []
        let cancellable = model.$syncProgress
            .compactMap { $0 }
            .removeDuplicates()
            .sink { progress in
                snapshots.append(progress)
            }

        await operation()

        // Allow any final main-actor publication to drain before returning snapshots.
        await Task.yield()
        cancellable.cancel()

        if let progress = model.syncProgress, snapshots.last != progress {
            snapshots.append(progress)
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
        NoOpAppUpdater(version: AppVersion(shortVersionString: "0.2.3", buildNumber: "1"))
    }
}

private struct StubAppleNotesSyncDataSource: AppleNotesSyncDataSourcing {
    var folders: [AppleNotesFolder]
    var documentsByFolderName: [String: [AppleNotesSyncDocument]]
    var missingDocumentIDsOnIncrementalLoad: Set<Int64> = []
    var manifestSelectedDatabaseRelativePath: String? = "Accounts/LocalAccount/NoteStore.sqlite"
    var requiredPreferredDatabaseRelativePathForIncrementalLoad: String? = nil

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

    func loadManifest(fromDataFolder path: String) throws -> AppleNotesSyncManifest {
        let documents = folders.flatMap { documentsByFolderName[$0.displayName] ?? [] }
        return AppleNotesSyncManifest(
            folders: folders,
            entries: documents.map { document in
                AppleNotesSyncManifestEntry(
                    databaseNoteID: document.databaseNoteID,
                    sourceNoteIdentifier: document.sourceNoteIdentifierRaw,
                    folderDatabaseID: document.folderDatabaseID,
                    name: document.name,
                    folder: document.folder,
                    folderPath: document.folderPath,
                    updatedAt: document.updatedAt,
                    passwordProtected: document.passwordProtected,
                    trashed: false
                )
            },
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:],
            sourceDiagnostics: nil,
            selectedDatabaseRelativePath: manifestSelectedDatabaseRelativePath
        )
    }

    func loadDocuments(
        fromDataFolder path: String,
        noteIDs: Set<Int64>,
        preferredDatabaseRelativePath: String?
    ) throws -> AppleNotesSyncSnapshot {
        let allDocuments = folders.flatMap { documentsByFolderName[$0.displayName] ?? [] }
        if let requiredPreferredDatabaseRelativePathForIncrementalLoad,
           preferredDatabaseRelativePath != requiredPreferredDatabaseRelativePathForIncrementalLoad
        {
            return AppleNotesSyncSnapshot(
                folders: folders,
                documents: [],
                skippedLockedNotes: 0,
                skippedLockedNotesByFolder: [:]
            )
        }
        return AppleNotesSyncSnapshot(
            folders: folders,
            documents: allDocuments.filter {
                noteIDs.contains($0.databaseNoteID) && !missingDocumentIDsOnIncrementalLoad.contains($0.databaseNoteID)
            },
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:]
        )
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

private final class RecordingIncrementalDataSource: AppleNotesSyncDataSourcing, @unchecked Sendable {
    let folders: [AppleNotesFolder]
    let documentsByFolderName: [String: [AppleNotesSyncDocument]]
    let syncIndex: SyncIndex

    private let lock = NSLock()
    private(set) var loadDocumentsCallCount = 0

    init(
        folders: [AppleNotesFolder],
        documentsByFolderName: [String: [AppleNotesSyncDocument]],
        syncIndex: SyncIndex
    ) {
        self.folders = folders
        self.documentsByFolderName = documentsByFolderName
        self.syncIndex = syncIndex
    }

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

    func loadManifest(fromDataFolder path: String) throws -> AppleNotesSyncManifest {
        let documents = folders.flatMap { documentsByFolderName[$0.displayName] ?? [] }
        return AppleNotesSyncManifest(
            folders: folders,
            entries: documents.map { document in
                AppleNotesSyncManifestEntry(
                    databaseNoteID: document.databaseNoteID,
                    sourceNoteIdentifier: document.sourceNoteIdentifierRaw,
                    folderDatabaseID: document.folderDatabaseID,
                    name: document.name,
                    folder: document.folder,
                    folderPath: document.folderPath,
                    updatedAt: document.updatedAt,
                    passwordProtected: document.passwordProtected,
                    trashed: false
                )
            },
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
        lock.lock()
        loadDocumentsCallCount += 1
        lock.unlock()

        let allDocuments = folders.flatMap { documentsByFolderName[$0.displayName] ?? [] }
        return AppleNotesSyncSnapshot(
            folders: folders,
            documents: allDocuments.filter { noteIDs.contains($0.databaseNoteID) },
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:]
        )
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
            changeKind: existingRelativePath == nil ? .created : .updated,
            unresolvedInternalLinkCount: 0
        )
    }
}

private enum StubSyncError: Error {
    case failed
}
