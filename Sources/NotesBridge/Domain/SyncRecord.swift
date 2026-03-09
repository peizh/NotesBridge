import Foundation

struct SyncRecord: Codable, Identifiable, Equatable, Sendable {
    let noteID: String
    var relativePath: String
    var lastSyncedAt: Date
    var sourceUpdatedAt: Date?

    var id: String { noteID }
}

struct SyncIndex: Codable, Sendable {
    var records: [String: SyncRecord] = [:]
    var lastFullSyncAt: Date?
    var lastFullSyncNoteCount: Int?
    var lastFullSyncFolderCount: Int?
}
