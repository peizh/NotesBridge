import Foundation

struct SyncRecord: Codable, Identifiable, Equatable, Sendable {
    let noteID: String
    var relativePath: String
    var lastSyncedAt: Date
    var sourceUpdatedAt: Date?
    var sourceName: String?
    var sourceFolderPath: String?

    var id: String { noteID }

    init(
        noteID: String,
        relativePath: String,
        lastSyncedAt: Date = Date(),
        sourceUpdatedAt: Date?,
        sourceName: String? = nil,
        sourceFolderPath: String? = nil
    ) {
        self.noteID = noteID
        self.relativePath = relativePath
        self.lastSyncedAt = lastSyncedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.sourceName = sourceName
        self.sourceFolderPath = sourceFolderPath
    }
}

enum SyncRunMode: String, Codable, Sendable {
    case incremental
    case automatic
    case full
}

struct SyncIndex: Codable, Sendable {
    var records: [String: SyncRecord] = [:]
    var knownFolderCount: Int?
    var lastSyncAt: Date?
    var lastSyncMode: SyncRunMode?
    var lastIncrementalSyncAt: Date?
    var lastAutomaticSyncAt: Date?
    var lastFullSyncAt: Date?
    var lastFullSyncNoteCount: Int?
    var lastFullSyncFolderCount: Int?
}
