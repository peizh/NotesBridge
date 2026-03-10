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
        settings: AppSettings,
        existingRelativePath: String?
    ) throws -> ObsidianExportResult {
        let fileManager = FileManager.default
        let vaultURL = try vaultURL(for: settings)
        let relativePath = resolveRelativePath(for: note, settings: settings, existingRelativePath: existingRelativePath) { candidateRelativePath in
            if candidateRelativePath == existingRelativePath {
                return false
            }

            let candidateURL = vaultURL.appendingPathComponent(candidateRelativePath)
            return fileManager.fileExists(atPath: candidateURL.path)
        }
        let fileURL = vaultURL.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let existingRelativePath,
           existingRelativePath != relativePath
        {
            let existingFileURL = vaultURL.appendingPathComponent(existingRelativePath)
            if fileManager.fileExists(atPath: existingFileURL.path),
               existingFileURL.standardizedFileURL != fileURL.standardizedFileURL,
               !fileManager.fileExists(atPath: fileURL.path)
            {
                try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: existingFileURL, to: fileURL)
            }
        }

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

    func plannedRelativePath(
        for note: AppleNoteDocument,
        settings: AppSettings,
        existingRelativePath: String?,
        occupiedRelativePaths: Set<String>
    ) -> String {
        resolveRelativePath(for: note, settings: settings, existingRelativePath: existingRelativePath) { candidateRelativePath in
            occupiedRelativePaths.contains(candidateRelativePath)
        }
    }

    private func vaultURL(for settings: AppSettings) throws -> URL {
        guard let vaultPath = settings.vaultPath, !vaultPath.isEmpty else {
            throw ObsidianVaultError.vaultNotConfigured
        }

        return URL(fileURLWithPath: vaultPath, isDirectory: true)
    }

    private func resolveRelativePath(
        for note: AppleNoteDocument,
        settings: AppSettings,
        existingRelativePath: String?,
        isOccupied: (String) -> Bool
    ) -> String {
        let exportRootName = sanitizePathComponent(settings.exportFolderName)
        let folderName = sanitizePathComponent(note.folder)
        let baseFileName = sanitizePathComponent(note.displayName)
        let directoryPath = exportRootName + "/" + folderName

        var collisionIndex = 1

        while true {
            let fileName = collisionIndex == 1
                ? "\(baseFileName).md"
                : "\(baseFileName) \(collisionIndex).md"
            let candidateRelativePath = directoryPath + "/" + fileName
            let isCurrentPath = existingRelativePath == candidateRelativePath

            if isCurrentPath || !isOccupied(candidateRelativePath) {
                return candidateRelativePath
            }

            collisionIndex += 1
        }
    }

    private func sanitizePathComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\\n\r\t")
        let pieces = value.components(separatedBy: invalidCharacters)
        let sanitized = pieces.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Untitled" : sanitized
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
