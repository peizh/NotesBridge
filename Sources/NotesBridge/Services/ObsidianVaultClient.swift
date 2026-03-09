import AppKit
import Foundation

struct ObsidianExportResult: Sendable {
    let fileURL: URL
    let relativePath: String
}

enum ObsidianVaultError: LocalizedError {
    case vaultNotConfigured

    var errorDescription: String? {
        switch self {
        case .vaultNotConfigured:
            "Choose an Obsidian vault before exporting notes."
        }
    }
}

struct ObsidianVaultClient: Sendable {
    func export(
        note: AppleNoteDocument,
        markdown: String,
        settings: AppSettings
    ) throws -> ObsidianExportResult {
        guard let vaultPath = settings.vaultPath, !vaultPath.isEmpty else {
            throw ObsidianVaultError.vaultNotConfigured
        }

        let fileManager = FileManager.default
        let vaultURL = URL(fileURLWithPath: vaultPath, isDirectory: true)
        let exportRoot = vaultURL.appendingPathComponent(sanitizePathComponent(settings.exportFolderName), isDirectory: true)
        let folderURL = exportRoot.appendingPathComponent(sanitizePathComponent(note.folder), isDirectory: true)

        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let fileName = "\(sanitizePathComponent(note.displayName)) [\(shortIdentifier(for: note.id))].md"
        let fileURL = folderURL.appendingPathComponent(fileName)
        let relativePath = fileURL.path.replacingOccurrences(of: "\(vaultURL.path)/", with: "")

        let frontMatter = """
        ---
        source: "apple-notes"
        apple_notes_id: "\(yamlEscaped(note.id))"
        apple_notes_folder: "\(yamlEscaped(note.folder))"
        created_at: "\(note.createdAt?.iso8601String ?? "")"
        updated_at: "\(note.updatedAt?.iso8601String ?? "")"
        shared: \(note.shared)
        ---

        """

        let contents = frontMatter + markdown.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)

        return ObsidianExportResult(fileURL: fileURL, relativePath: relativePath)
    }

    func revealVault(at path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    private func sanitizePathComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\\n\r\t")
        let pieces = value.components(separatedBy: invalidCharacters)
        let sanitized = pieces.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Untitled" : sanitized
    }

    private func shortIdentifier(for noteID: String) -> String {
        let hash = noteID.unicodeScalars.reduce(into: UInt32(2166136261)) { partialResult, scalar in
            partialResult ^= scalar.value
            partialResult &*= 16777619
        }
        return String(format: "%08x", hash)
    }

    private func yamlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
