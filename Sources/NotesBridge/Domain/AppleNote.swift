import Foundation

struct AppleNotesFolder: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var accountName: String?
    var noteCount: Int

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? "Untitled Folder" : trimmedName

        guard let accountName, !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return baseName
        }

        return "\(baseName) (\(accountName))"
    }
}

struct AppleNoteSummary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var folder: String
    var createdAt: Date?
    var updatedAt: Date?
    var shared: Bool
    var passwordProtected: Bool

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }
}

struct AppleNoteDocument: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var folder: String
    var createdAt: Date?
    var updatedAt: Date?
    var shared: Bool
    var passwordProtected: Bool
    var plaintext: String
    var htmlBody: String

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    var summary: AppleNoteSummary {
        AppleNoteSummary(
            id: id,
            name: name,
            folder: folder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            shared: shared,
            passwordProtected: passwordProtected
        )
    }

    static func lockedPlaceholder(from summary: AppleNoteSummary) -> AppleNoteDocument {
        AppleNoteDocument(
            id: summary.id,
            name: summary.name,
            folder: summary.folder,
            createdAt: summary.createdAt,
            updatedAt: summary.updatedAt,
            shared: summary.shared,
            passwordProtected: true,
            plaintext: "",
            htmlBody: ""
        )
    }
}
