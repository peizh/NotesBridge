import Foundation

protocol Syncing: Sendable {
    func sync(
        document: AppleNotesSyncDocument,
        settings: AppSettings,
        existingRelativePath: String?,
        plannedRelativePath: String,
        plannedRelativePathsBySourceIdentifier: [String: String]
    ) throws -> NoteSyncResult
}

struct NoteSyncResult: Sendable {
    let record: SyncRecord
    let unresolvedInternalLinkCount: Int
}

struct SyncEngine: Syncing {
    private let vaultClient: ObsidianVaultClient

    init(vaultClient: ObsidianVaultClient = ObsidianVaultClient()) {
        self.vaultClient = vaultClient
    }

    func sync(
        document: AppleNotesSyncDocument,
        settings: AppSettings,
        existingRelativePath: String?,
        plannedRelativePath: String,
        plannedRelativePathsBySourceIdentifier: [String: String]
    ) throws -> NoteSyncResult {
        let export = try vaultClient.export(
            note: document,
            settings: settings,
            existingRelativePath: existingRelativePath,
            plannedRelativePath: plannedRelativePath,
            plannedRelativePathsBySourceIdentifier: plannedRelativePathsBySourceIdentifier
        )
        return NoteSyncResult(
            record: SyncRecord(
                noteID: document.id,
                relativePath: export.relativePath,
                lastSyncedAt: Date(),
                sourceUpdatedAt: document.updatedAt,
                sourceName: document.displayName,
                sourceFolderPath: document.exportFolderPath
            ),
            unresolvedInternalLinkCount: export.unresolvedInternalLinkCount
        )
    }
}
