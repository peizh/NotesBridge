import Foundation

struct SyncEngine: Sendable {
    private let vaultClient: ObsidianVaultClient

    init(vaultClient: ObsidianVaultClient = ObsidianVaultClient()) {
        self.vaultClient = vaultClient
    }

    func sync(
        document: AppleNoteDocument,
        markdown: String,
        settings: AppSettings
    ) throws -> SyncRecord {
        let export = try vaultClient.export(note: document, markdown: markdown, settings: settings)
        return SyncRecord(
            noteID: document.id,
            relativePath: export.relativePath,
            lastSyncedAt: Date(),
            sourceUpdatedAt: document.updatedAt
        )
    }
}
