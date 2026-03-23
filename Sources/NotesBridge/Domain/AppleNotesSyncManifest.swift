import Foundation

struct AppleNotesSyncManifestEntry: Identifiable, Hashable, Sendable {
    let databaseNoteID: Int64
    let id: String
    let sourceNoteIdentifier: String
    let sourceNoteIdentifierRaw: String
    var folderDatabaseID: Int64?
    var name: String
    var folder: String
    var folderPath: String?
    var updatedAt: Date?
    var passwordProtected: Bool
    var trashed: Bool

    init(
        databaseNoteID: Int64,
        sourceNoteIdentifier: String? = nil,
        folderDatabaseID: Int64? = nil,
        name: String,
        folder: String,
        folderPath: String? = nil,
        updatedAt: Date?,
        passwordProtected: Bool,
        trashed: Bool
    ) {
        self.databaseNoteID = databaseNoteID
        self.id = AppleNotesSyncDocument.canonicalID(for: databaseNoteID)
        let resolvedSourceIdentifier = sourceNoteIdentifier ?? self.id
        self.sourceNoteIdentifier = AppleNotesSyncDocument.normalizedSourceIdentifier(resolvedSourceIdentifier)
        self.sourceNoteIdentifierRaw = resolvedSourceIdentifier
        self.folderDatabaseID = folderDatabaseID
        self.name = name
        self.folder = folder
        self.folderPath = folderPath
        self.updatedAt = updatedAt
        self.passwordProtected = passwordProtected
        self.trashed = trashed
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    var folderDisplayName: String {
        let trimmed = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Notes" : trimmed
    }

    var exportFolderPath: String {
        guard let folderPath else {
            return folderDisplayName
        }
        return folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var appleNotesDeepLink: String? {
        let trimmedIdentifier = sourceNoteIdentifierRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else {
            return nil
        }

        if trimmedIdentifier.lowercased().hasPrefix("applenotes:note/") {
            return trimmedIdentifier
        }

        return "applenotes:note/\(trimmedIdentifier)"
    }
}

struct AppleNotesSyncManifest: Sendable {
    var folders: [AppleNotesFolder]
    var entries: [AppleNotesSyncManifestEntry]
    var skippedLockedNotes: Int
    var skippedLockedNotesByFolder: [String: Int]
    var sourceDiagnostics: String?
}
