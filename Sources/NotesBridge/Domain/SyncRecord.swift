import Foundation

struct SyncRecord: Codable, Identifiable, Equatable, Sendable {
    let noteID: String
    var relativePath: String
    var lastSyncedAt: Date
    var sourceUpdatedAt: Date?

    var id: String { noteID }

    init(
        noteID: String,
        relativePath: String,
        lastSyncedAt: Date = Date(),
        sourceUpdatedAt: Date?
    ) {
        self.noteID = noteID
        self.relativePath = relativePath
        self.lastSyncedAt = lastSyncedAt
        self.sourceUpdatedAt = sourceUpdatedAt
    }
}

struct SyncIndex: Codable, Sendable {
    var records: [String: SyncRecord] = [:]
    var lastFullSyncAt: Date?
    var lastFullSyncNoteCount: Int?
    var lastFullSyncFolderCount: Int?
}
