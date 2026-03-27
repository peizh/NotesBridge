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
    var pathAliases: [String: String] = [:]
    var knownFolderCount: Int?
    var lastSyncAt: Date?
    var lastSyncMode: SyncRunMode?
    var lastIncrementalSyncAt: Date?
    var lastAutomaticSyncAt: Date?
    var lastFullSyncAt: Date?
    var lastFullSyncNoteCount: Int?
    var lastFullSyncFolderCount: Int?

    mutating func rememberPath(_ relativePath: String, for identifiers: [String]) {
        for identifier in identifiers where !identifier.isEmpty {
            pathAliases[identifier] = relativePath
        }
    }

    mutating func removePathAliases(for identifiers: [String]) {
        for identifier in identifiers where !identifier.isEmpty {
            pathAliases.removeValue(forKey: identifier)
        }
    }

    mutating func removePathAliases(forRelativePath relativePath: String) {
        let identifiers = pathAliases.compactMap { identifier, candidateRelativePath in
            candidateRelativePath == relativePath ? identifier : nil
        }
        removePathAliases(for: identifiers)
    }

    mutating func mergePathAliases(_ aliases: [String: String]) {
        for (identifier, relativePath) in aliases where !identifier.isEmpty {
            pathAliases[identifier] = relativePath
        }
    }

    var occupiedRelativePaths: Set<String> {
        Set(records.values.map(\.relativePath)).union(pathAliases.values)
    }

    init(
        records: [String: SyncRecord] = [:],
        pathAliases: [String: String] = [:],
        knownFolderCount: Int? = nil,
        lastSyncAt: Date? = nil,
        lastSyncMode: SyncRunMode? = nil,
        lastIncrementalSyncAt: Date? = nil,
        lastAutomaticSyncAt: Date? = nil,
        lastFullSyncAt: Date? = nil,
        lastFullSyncNoteCount: Int? = nil,
        lastFullSyncFolderCount: Int? = nil
    ) {
        self.records = records
        self.pathAliases = pathAliases
        self.knownFolderCount = knownFolderCount
        self.lastSyncAt = lastSyncAt
        self.lastSyncMode = lastSyncMode
        self.lastIncrementalSyncAt = lastIncrementalSyncAt
        self.lastAutomaticSyncAt = lastAutomaticSyncAt
        self.lastFullSyncAt = lastFullSyncAt
        self.lastFullSyncNoteCount = lastFullSyncNoteCount
        self.lastFullSyncFolderCount = lastFullSyncFolderCount
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.records = try container.decodeIfPresent([String: SyncRecord].self, forKey: .records) ?? [:]
        self.pathAliases = try container.decodeIfPresent([String: String].self, forKey: .pathAliases) ?? [:]
        self.knownFolderCount = try container.decodeIfPresent(Int.self, forKey: .knownFolderCount)
        self.lastSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        self.lastSyncMode = try container.decodeIfPresent(SyncRunMode.self, forKey: .lastSyncMode)
        self.lastIncrementalSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastIncrementalSyncAt)
        self.lastAutomaticSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastAutomaticSyncAt)
        self.lastFullSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastFullSyncAt)
        self.lastFullSyncNoteCount = try container.decodeIfPresent(Int.self, forKey: .lastFullSyncNoteCount)
        self.lastFullSyncFolderCount = try container.decodeIfPresent(Int.self, forKey: .lastFullSyncFolderCount)
    }
}
