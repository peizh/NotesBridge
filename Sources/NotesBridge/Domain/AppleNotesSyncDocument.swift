import Foundation

enum AppleNotesAttachmentRenderStyle: String, Codable, Hashable, Sendable {
    case embed
    case link
}

struct AppleNotesSyncInternalLink: Identifiable, Hashable, Sendable {
    let token: String
    let targetSourceIdentifier: String
    let displayText: String

    var id: String { token }
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
    let sourceNoteIdentifier: String
    let sourceNoteIdentifierRaw: String
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
    var internalLinks: [AppleNotesSyncInternalLink]
    var attachments: [AppleNotesSyncAttachment]

    init(
        databaseNoteID: Int64,
        sourceNoteIdentifier: String? = nil,
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
        internalLinks: [AppleNotesSyncInternalLink] = [],
        attachments: [AppleNotesSyncAttachment]
    ) {
        self.databaseNoteID = databaseNoteID
        self.id = Self.canonicalID(for: databaseNoteID)
        let resolvedSourceIdentifier = sourceNoteIdentifier ?? Self.canonicalID(for: databaseNoteID)
        self.sourceNoteIdentifier = Self.normalizedSourceIdentifier(resolvedSourceIdentifier)
        self.sourceNoteIdentifierRaw = resolvedSourceIdentifier
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
        self.internalLinks = internalLinks
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

    static func normalizedSourceIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func databaseNoteID(fromIdentifier value: String) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("apple-notes-db://note/") {
            let suffix = trimmed.dropFirst("apple-notes-db://note/".count)
            return Int64(suffix)
        }

        let pattern = #"/ICNote/p(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              let tokenRange = Range(match.range(at: 1), in: trimmed)
        else {
            return nil
        }

        return Int64(trimmed[tokenRange])
    }

    var appleNotesDeepLink: String? {
        let preferredIdentifier = legacyNoteID ?? sourceNoteIdentifierRaw
        let trimmedIdentifier = preferredIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else {
            return nil
        }

        if trimmedIdentifier.lowercased().hasPrefix("applenotes:note/") {
            return trimmedIdentifier
        }

        return "applenotes:note/\(trimmedIdentifier)"
    }
}

struct AppleNotesSyncSnapshot: Sendable {
    var folders: [AppleNotesFolder]
    var documents: [AppleNotesSyncDocument]
    var skippedLockedNotes: Int
    var skippedLockedNotesByFolder: [String: Int]
    var failedTableDecodes: Int = 0
    var failedScanDecodes: Int = 0
    var partialScanPageFailures: Int = 0
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

extension String {
    var appleNotesInternalLinkIdentifier: String? {
        guard let range = range(
            of: "applenotes:note/",
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let suffix = self[range.upperBound...]
        let trimmedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier: String
        if trimmedSuffix.lowercased().hasPrefix("x-coredata://") {
            identifier = trimmedSuffix
        } else {
            identifier = String(trimmedSuffix.prefix { character in
                character != "?" && !character.isWhitespace
            })
        }
        guard !identifier.isEmpty else {
            return nil
        }

        return AppleNotesSyncDocument.normalizedSourceIdentifier(identifier)
    }
}
