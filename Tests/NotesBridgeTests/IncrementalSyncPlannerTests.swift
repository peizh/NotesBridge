import Testing
@testable import NotesBridge

struct IncrementalSyncPlannerTests {
    private let planner = IncrementalSyncPlanner()

    @Test
    func plansCreatedUpdatedAndRemovedNotes() {
        let manifest = AppleNotesSyncManifest(
            folders: [],
            entries: [
                entry(id: 1, name: "Created", folder: "Inbox", updatedAt: date(100)),
                entry(id: 2, name: "Renamed", folder: "Projects", updatedAt: date(200)),
                entry(id: 3, name: "Locked", folder: "Inbox", updatedAt: date(300), passwordProtected: true),
            ],
            skippedLockedNotes: 1,
            skippedLockedNotesByFolder: [:],
            sourceDiagnostics: nil
        )
        let syncIndex = SyncIndex(
            records: [
                AppleNotesSyncDocument.canonicalID(for: 2): SyncRecord(
                    noteID: AppleNotesSyncDocument.canonicalID(for: 2),
                    relativePath: "Apple Notes/Inbox/Old Name.md",
                    sourceUpdatedAt: date(150),
                    sourceName: "Old Name",
                    sourceFolderPath: "Inbox"
                ),
                AppleNotesSyncDocument.canonicalID(for: 4): SyncRecord(
                    noteID: AppleNotesSyncDocument.canonicalID(for: 4),
                    relativePath: "Apple Notes/Inbox/Deleted.md",
                    sourceUpdatedAt: date(50),
                    sourceName: "Deleted",
                    sourceFolderPath: "Inbox"
                ),
            ],
            lastSyncAt: nil,
            lastSyncMode: nil,
            lastIncrementalSyncAt: nil,
            lastAutomaticSyncAt: nil,
            lastFullSyncAt: nil,
            lastFullSyncNoteCount: nil,
            lastFullSyncFolderCount: nil
        )

        let plan = planner.plan(
            manifest: manifest,
            syncIndex: syncIndex,
            indexedRelativePaths: [:],
            settings: .default
        )

        #expect(plan.exports.count == 2)
        #expect(plan.exports.map(\.manifestEntry.id).contains(AppleNotesSyncDocument.canonicalID(for: 1)))
        #expect(plan.exports.map(\.manifestEntry.id).contains(AppleNotesSyncDocument.canonicalID(for: 2)))
        #expect(plan.removedRecords.map(\.noteID) == [AppleNotesSyncDocument.canonicalID(for: 4)])
        #expect(plan.processedNoteCount == 2)
        #expect(plan.skippedLockedNotes == 1)
        #expect(plan.unchangedNoteCount == 0)
    }

    @Test
    func keepsUnchangedNotesOutOfExportPlan() {
        let manifest = AppleNotesSyncManifest(
            folders: [],
            entries: [entry(id: 5, name: "Stable", folder: "Inbox", updatedAt: date(500))],
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:],
            sourceDiagnostics: nil
        )
        let syncIndex = SyncIndex(
            records: [
                AppleNotesSyncDocument.canonicalID(for: 5): SyncRecord(
                    noteID: AppleNotesSyncDocument.canonicalID(for: 5),
                    relativePath: "Apple Notes/Inbox/Stable.md",
                    sourceUpdatedAt: date(500),
                    sourceName: "Stable",
                    sourceFolderPath: "Inbox"
                ),
            ],
            lastSyncAt: nil,
            lastSyncMode: nil,
            lastIncrementalSyncAt: nil,
            lastAutomaticSyncAt: nil,
            lastFullSyncAt: nil,
            lastFullSyncNoteCount: nil,
            lastFullSyncFolderCount: nil
        )

        let plan = planner.plan(
            manifest: manifest,
            syncIndex: syncIndex,
            indexedRelativePaths: [:],
            settings: .default
        )

        #expect(plan.exports.isEmpty)
        #expect(plan.processedNoteCount == 1)
        #expect(plan.unchangedNoteCount == 1)
    }

    @Test
    func prefersPersistedPathAliasesBeforeRecoveryScanResults() {
        let manifest = AppleNotesSyncManifest(
            folders: [],
            entries: [entry(id: 7, name: "Stable", folder: "Inbox", updatedAt: date(700))],
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:],
            sourceDiagnostics: nil
        )
        let syncIndex = SyncIndex(
            records: [:],
            pathAliases: [
                AppleNotesSyncDocument.canonicalID(for: 7): "Apple Notes/Inbox/Stable.md",
                "x-coredata://example/ICNote/p7": "Apple Notes/Inbox/Stable.md",
            ]
        )

        let plan = planner.plan(
            manifest: manifest,
            syncIndex: syncIndex,
            indexedRelativePaths: [
                AppleNotesSyncDocument.canonicalID(for: 7): "Apple Notes/Inbox/Recovered.md",
            ],
            settings: .default
        )

        #expect(plan.exports.first?.existingRelativePath == "Apple Notes/Inbox/Stable.md")
    }

    private func entry(
        id: Int64,
        name: String,
        folder: String,
        updatedAt: Date?,
        passwordProtected: Bool = false
    ) -> AppleNotesSyncManifestEntry {
        AppleNotesSyncManifestEntry(
            databaseNoteID: id,
            sourceNoteIdentifier: "x-coredata://example/ICNote/p\(id)",
            name: name,
            folder: folder,
            updatedAt: updatedAt,
            passwordProtected: passwordProtected,
            trashed: false
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
