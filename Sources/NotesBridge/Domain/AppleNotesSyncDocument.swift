import Foundation

enum AppleNotesAttachmentRenderStyle: String, Codable, Hashable, Sendable {
    case embed
    case link
}

struct AppleNotesSyncAttachment: Identifiable, Hashable, Sendable {
    let token: String
    let logicalIdentifier: String
    let sourceURL: URL
    let preferredFilename: String
    let renderStyle: AppleNotesAttachmentRenderStyle
    let modifiedAt: Date?
    let fileSize: Int64?

    var id: String { token }
}

struct AppleNotesSyncDocument: Identifiable, Hashable, Sendable {
    let databaseNoteID: Int64
    let id: String
    var folderDatabaseID: Int64?
    var legacyNoteID: String?
    var name: String
    var folder: String
    var folderPath: String?
    var createdAt: Date?
    var updatedAt: Date?
    var shared: Bool
    var passwordProtected: Bool
    var markdownTemplate: String
    var attachments: [AppleNotesSyncAttachment]

    init(
        databaseNoteID: Int64,
        folderDatabaseID: Int64? = nil,
        legacyNoteID: String? = nil,
        name: String,
        folder: String,
        folderPath: String? = nil,
        createdAt: Date?,
        updatedAt: Date?,
        shared: Bool,
        passwordProtected: Bool,
        markdownTemplate: String,
        attachments: [AppleNotesSyncAttachment]
    ) {
        self.databaseNoteID = databaseNoteID
        self.id = Self.canonicalID(for: databaseNoteID)
        self.folderDatabaseID = folderDatabaseID
        self.legacyNoteID = legacyNoteID
        self.name = name
        self.folder = folder
        self.folderPath = folderPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.shared = shared
        self.passwordProtected = passwordProtected
        self.markdownTemplate = markdownTemplate
        self.attachments = attachments
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

    static func canonicalID(for databaseNoteID: Int64) -> String {
        "apple-notes-db://note/\(databaseNoteID)"
    }
}

struct AppleNotesSyncSnapshot: Sendable {
    var folders: [AppleNotesFolder]
    var documents: [AppleNotesSyncDocument]
    var skippedLockedNotes: Int
    var skippedLockedNotesByFolder: [String: Int]
    var sourceDiagnostics: String? = nil
}

struct AppleNotesDataFolderSelection: Equatable, Sendable {
    let rootURL: URL
    let databaseURL: URL

    static func resolved(
        rootPath: String,
        databaseRelativePath: String = "Accounts/LocalAccount/NoteStore.sqlite"
    ) -> AppleNotesDataFolderSelection {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        return AppleNotesDataFolderSelection(
            rootURL: rootURL,
            databaseURL: rootURL.appendingPathComponent(databaseRelativePath, isDirectory: false)
        )
    }
}
