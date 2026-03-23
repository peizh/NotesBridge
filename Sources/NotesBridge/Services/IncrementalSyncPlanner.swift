import Foundation

struct IncrementalSyncPlan: Sendable {
    var folders: [AppleNotesFolder]
    var exports: [PlannedIncrementalDocumentExport]
    var removedRecords: [SyncRecord]
    var plannedRelativePathsBySourceIdentifier: [String: String]
    var unchangedNoteCount: Int
    var skippedLockedNotes: Int
}

struct PlannedIncrementalDocumentExport: Sendable {
    var manifestEntry: AppleNotesSyncManifestEntry
    var existingRelativePath: String?
    var plannedRelativePath: String
}

struct IncrementalSyncPlanner: Sendable {
    private let vaultClient: ObsidianVaultClient

    init(vaultClient: ObsidianVaultClient = ObsidianVaultClient()) {
        self.vaultClient = vaultClient
    }

    func plan(
        manifest: AppleNotesSyncManifest,
        syncIndex: SyncIndex,
        indexedRelativePaths: [String: String],
        settings: AppSettings
    ) -> IncrementalSyncPlan {
        let presentEntriesByID = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.id, $0) })
        let visibleEntries = manifest.entries
            .filter { !$0.passwordProtected && !$0.trashed }
            .sorted(by: compareEntries)
        let trashedEntryIDs = Set(manifest.entries.filter(\.trashed).map(\.id))
        let presentEntryIDs = Set(manifest.entries.map(\.id))

        var occupiedRelativePaths = Set(indexedRelativePaths.values)
        var plannedRelativePathsBySourceIdentifier: [String: String] = [:]
        var exports: [PlannedIncrementalDocumentExport] = []
        var unchangedNoteCount = 0

        for entry in visibleEntries {
            let existingRelativePath = existingRelativePath(
                for: entry,
                syncIndex: syncIndex,
                indexedRelativePaths: indexedRelativePaths
            )
            let plannedRelativePath = vaultClient.plannedRelativePath(
                for: entry,
                settings: settings,
                existingRelativePath: existingRelativePath,
                occupiedRelativePaths: occupiedRelativePaths
            )

            if let existingRelativePath,
               existingRelativePath != plannedRelativePath
            {
                occupiedRelativePaths.remove(existingRelativePath)
            }
            occupiedRelativePaths.insert(plannedRelativePath)
            plannedRelativePathsBySourceIdentifier[entry.sourceNoteIdentifier] = plannedRelativePath
            plannedRelativePathsBySourceIdentifier[entry.id] = plannedRelativePath

            if let record = syncIndex.records[entry.id],
               record.matches(entry: entry),
               record.relativePath == plannedRelativePath
            {
                unchangedNoteCount += 1
                continue
            }

            exports.append(
                PlannedIncrementalDocumentExport(
                    manifestEntry: entry,
                    existingRelativePath: existingRelativePath,
                    plannedRelativePath: plannedRelativePath
                )
            )
        }

        let removedRecords = syncIndex.records.values
            .filter { record in
                if trashedEntryIDs.contains(record.noteID) {
                    return true
                }
                if let entry = presentEntriesByID[record.noteID] {
                    return entry.trashed
                }
                return !presentEntryIDs.contains(record.noteID)
            }
            .sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }

        return IncrementalSyncPlan(
            folders: manifest.folders.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            },
            exports: exports,
            removedRecords: removedRecords,
            plannedRelativePathsBySourceIdentifier: plannedRelativePathsBySourceIdentifier,
            unchangedNoteCount: unchangedNoteCount,
            skippedLockedNotes: manifest.skippedLockedNotes
        )
    }

    private func compareEntries(_ lhs: AppleNotesSyncManifestEntry, _ rhs: AppleNotesSyncManifestEntry) -> Bool {
        let folderComparison = lhs.exportFolderPath.localizedCaseInsensitiveCompare(rhs.exportFolderPath)
        if folderComparison != .orderedSame {
            return folderComparison == .orderedAscending
        }

        let nameComparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }

    private func existingRelativePath(
        for entry: AppleNotesSyncManifestEntry,
        syncIndex: SyncIndex,
        indexedRelativePaths: [String: String]
    ) -> String? {
        if let relativePath = syncIndex.records[entry.id]?.relativePath {
            return relativePath
        }

        if let relativePath = indexedRelativePaths[entry.id] {
            return relativePath
        }

        if let relativePath = indexedRelativePaths[entry.sourceNoteIdentifierRaw] {
            return relativePath
        }

        if let deepLink = entry.appleNotesDeepLink,
           let relativePath = indexedRelativePaths[deepLink]
        {
            return relativePath
        }

        return nil
    }
}

private extension SyncRecord {
    func matches(entry: AppleNotesSyncManifestEntry) -> Bool {
        sameTimestamp(sourceUpdatedAt, entry.updatedAt)
            && sourceName == entry.displayName
            && sourceFolderPath == entry.exportFolderPath
    }

    func sameTimestamp(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (.some(left), .some(right)):
            return abs(left.timeIntervalSince(right)) < 1
        case (.none, .none):
            return true
        default:
            return false
        }
    }
}
