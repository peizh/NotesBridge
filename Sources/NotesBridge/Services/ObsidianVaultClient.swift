import AppKit
import Foundation

struct ObsidianExportResult: Sendable {
    let fileURL: URL
    let relativePath: String
}

struct ObsidianAttachmentStorageResolution: Sendable {
    let baseRelativePath: String
    let sourceDescription: String
    let warning: String?
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
        note: AppleNotesSyncDocument,
        settings: AppSettings,
        existingRelativePath: String?
    ) throws -> ObsidianExportResult {
        let fileManager = FileManager.default
        let vaultURL = try vaultURL(for: settings)
        let relativePath = resolveRelativePath(
            for: note,
            settings: settings,
            existingRelativePath: existingRelativePath
        ) { candidateRelativePath in
            if candidateRelativePath == existingRelativePath {
                return false
            }

            return fileManager.fileExists(atPath: vaultURL.appendingPathComponent(candidateRelativePath).path)
        }
        let fileURL = vaultURL.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let obsoleteAttachmentDirectories = attachmentMigrationCandidates(
            existingRelativePath: existingRelativePath,
            newRelativePath: relativePath,
            vaultURL: vaultURL,
            settings: settings
        )

        if let existingRelativePath,
           existingRelativePath != relativePath
        {
            try moveNoteFileIfNeeded(
                from: vaultURL.appendingPathComponent(existingRelativePath),
                to: fileURL,
                fileManager: fileManager
            )
            try moveAttachmentDirectoryIfNeeded(
                from: obsoleteAttachmentDirectories,
                to: attachmentDirectoryURL(
                    forNoteRelativePath: relativePath,
                    settings: settings,
                    vaultURL: vaultURL
                ),
                fileManager: fileManager
            )
        }

        let renderedMarkdown = try renderMarkdownAndSyncAttachments(
            for: note,
            noteRelativePath: relativePath,
            fileURL: fileURL,
            vaultURL: vaultURL,
            settings: settings,
            fileManager: fileManager
        )
        try removeObsoleteAttachmentDirectories(
            obsoleteAttachmentDirectories,
            excluding: attachmentDirectoryURL(
                forNoteRelativePath: relativePath,
                settings: settings,
                vaultURL: vaultURL
            ),
            fileManager: fileManager
        )
        let frontMatter = frontMatter(for: note)
        let contents = frontMatter + renderedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)

        return ObsidianExportResult(fileURL: fileURL, relativePath: relativePath)
    }

    func revealVault(at path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    func plannedRelativePath(
        for note: AppleNotesSyncDocument,
        settings: AppSettings,
        existingRelativePath: String?,
        occupiedRelativePaths: Set<String>
    ) -> String {
        resolveRelativePath(for: note, settings: settings, existingRelativePath: existingRelativePath) { candidateRelativePath in
            occupiedRelativePaths.contains(candidateRelativePath)
        }
    }

    func attachmentStorageResolution(settings: AppSettings) -> ObsidianAttachmentStorageResolution {
        let customBasePath = customAttachmentBaseRelativePath(settings: settings)
        guard settings.useObsidianAttachmentFolder else {
            return ObsidianAttachmentStorageResolution(
                baseRelativePath: customBasePath,
                sourceDescription: "Using NotesBridge attachment folder",
                warning: nil
            )
        }

        guard let vaultURL = try? vaultURL(for: settings) else {
            return ObsidianAttachmentStorageResolution(
                baseRelativePath: customBasePath,
                sourceDescription: "Using NotesBridge attachment folder",
                warning: "Choose an Obsidian vault to read the configured attachment folder. Falling back to \(customBasePath)."
            )
        }

        guard let configuredPath = configuredObsidianAttachmentFolderPath(vaultURL: vaultURL) else {
            return ObsidianAttachmentStorageResolution(
                baseRelativePath: customBasePath,
                sourceDescription: "Using NotesBridge attachment folder",
                warning: "Could not read .obsidian/app.json attachmentFolderPath. Falling back to \(customBasePath)."
            )
        }

        guard let normalizedConfiguredPath = normalizedObsidianAttachmentBaseRelativePath(configuredPath),
              !normalizedConfiguredPath.isEmpty
        else {
            return ObsidianAttachmentStorageResolution(
                baseRelativePath: customBasePath,
                sourceDescription: "Using NotesBridge attachment folder",
                warning: "Obsidian attachmentFolderPath uses the current file location, which is not supported for unified Apple Notes attachments. Falling back to \(customBasePath)."
            )
        }

        return ObsidianAttachmentStorageResolution(
            baseRelativePath: normalizedConfiguredPath,
            sourceDescription: "Using Obsidian attachment folder",
            warning: nil
        )
    }

    func indexExistingNotes(settings: AppSettings) throws -> [String: String] {
        let fileManager = FileManager.default
        let vaultURL = try vaultURL(for: settings)
        let exportRootURL = vaultURL.appendingPathComponent(sanitizePathComponent(settings.exportFolderName), isDirectory: true)
        guard fileManager.fileExists(atPath: exportRootURL.path) else {
            return [:]
        }

        let enumerator = fileManager.enumerator(
            at: exportRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var index: [String: String] = [:]

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "md",
                  let identifiers = try? frontMatterIdentifiers(at: fileURL),
                  !identifiers.isEmpty
            else {
                continue
            }

            let relativePath = fileURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
            for identifier in identifiers {
                index[identifier] = relativePath
            }
        }

        return index
    }

    private func renderMarkdownAndSyncAttachments(
        for note: AppleNotesSyncDocument,
        noteRelativePath: String,
        fileURL: URL,
        vaultURL: URL,
        settings: AppSettings,
        fileManager: FileManager
    ) throws -> String {
        var markdown = note.markdownTemplate
        let attachmentDirectoryURL = attachmentDirectoryURL(
            forNoteRelativePath: noteRelativePath,
            settings: settings,
            vaultURL: vaultURL
        )
        let attachmentDirectoryRelativePath = attachmentDirectoryRelativePath(
            forNoteRelativePath: noteRelativePath,
            settings: settings,
            vaultURL: vaultURL
        )
        let legacyAttachmentDirectoryURL = legacyAttachmentDirectoryURL(for: fileURL)

        if note.attachments.isEmpty {
            if fileManager.fileExists(atPath: attachmentDirectoryURL.path) {
                try? fileManager.removeItem(at: attachmentDirectoryURL)
            }
            if fileManager.fileExists(atPath: legacyAttachmentDirectoryURL.path),
               legacyAttachmentDirectoryURL.standardizedFileURL != attachmentDirectoryURL.standardizedFileURL
            {
                try? fileManager.removeItem(at: legacyAttachmentDirectoryURL)
            }
            return markdown
        }

        try fileManager.createDirectory(at: attachmentDirectoryURL, withIntermediateDirectories: true)
        var occupiedFileNames: Set<String> = []
        var expectedFileNames: Set<String> = []

        for attachment in note.attachments {
            let fileName = resolveAttachmentFileName(
                preferredFilename: attachment.preferredFilename,
                occupiedFileNames: occupiedFileNames
            )
            occupiedFileNames.insert(fileName)
            expectedFileNames.insert(fileName)

            let destinationURL = attachmentDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
            try copyAttachmentIfNeeded(
                attachment,
                to: destinationURL,
                fileManager: fileManager
            )
            let attachmentRelativePath = joinRelativePath(attachmentDirectoryRelativePath, fileName)

            let renderedLink = switch attachment.renderStyle {
            case .embed:
                "![[\(attachmentRelativePath)]]"
            case .link:
                "[[\(attachmentRelativePath)]]"
            }
            markdown = markdown.replacingOccurrences(
                of: "{{attachment:\(attachment.token)}}",
                with: renderedLink
            )
        }

        try removeStaleAttachments(
            in: attachmentDirectoryURL,
            keepingFileNames: expectedFileNames,
            fileManager: fileManager
        )

        return markdown
    }

    private func moveNoteFileIfNeeded(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: sourceURL.path),
              sourceURL.standardizedFileURL != destinationURL.standardizedFileURL,
              !fileManager.fileExists(atPath: destinationURL.path)
        else {
            return
        }

        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private func moveAttachmentDirectoryIfNeeded(
        from sourceURLs: [URL],
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        for sourceURL in sourceURLs {
            guard fileManager.fileExists(atPath: sourceURL.path),
                  sourceURL.standardizedFileURL != destinationURL.standardizedFileURL,
                  !fileManager.fileExists(atPath: destinationURL.path)
            else {
                continue
            }

            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            return
        }
    }

    private func copyAttachmentIfNeeded(
        _ attachment: AppleNotesSyncAttachment,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        if fileManager.fileExists(atPath: destinationURL.path),
           attachmentFileMatchesSource(attachment, destinationURL: destinationURL)
        {
            return
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: attachment.sourceURL, to: destinationURL)
        if let modifiedAt = attachment.modifiedAt {
            try? fileManager.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: destinationURL.path)
        }
    }

    private func attachmentFileMatchesSource(
        _ attachment: AppleNotesSyncAttachment,
        destinationURL: URL
    ) -> Bool {
        guard let sourceValues = try? attachment.sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let destinationValues = try? destinationURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        else {
            return false
        }

        let sourceSize = attachment.fileSize ?? sourceValues.fileSize.map(Int64.init)
        let destinationSize = destinationValues.fileSize.map(Int64.init)
        guard sourceSize == destinationSize else { return false }

        let sourceDate = attachment.modifiedAt ?? sourceValues.contentModificationDate
        let destinationDate = destinationValues.contentModificationDate
        switch (sourceDate, destinationDate) {
        case let (.some(left), .some(right)):
            return abs(left.timeIntervalSince(right)) < 1
        case (.none, .none):
            return true
        default:
            return false
        }
    }

    private func removeStaleAttachments(
        in directoryURL: URL,
        keepingFileNames: Set<String>,
        fileManager: FileManager
    ) throws {
        let existingFiles = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for fileURL in existingFiles where !keepingFileNames.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }

        let remainingFiles = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        if remainingFiles.isEmpty {
            try? fileManager.removeItem(at: directoryURL)
        }
    }

    private func frontMatter(for note: AppleNotesSyncDocument) -> String {
        var lines = [
            "---",
            "source: \"apple-notes\"",
            "apple_notes_id: \"\(yamlEscaped(note.id))\"",
        ]
        if let legacyNoteID = note.legacyNoteID, legacyNoteID != note.id {
            lines.append("apple_notes_legacy_id: \"\(yamlEscaped(legacyNoteID))\"")
        }
        let folderValue = note.exportFolderPath.isEmpty ? note.folderDisplayName : note.exportFolderPath
        lines.append("apple_notes_folder: \"\(yamlEscaped(folderValue))\"")
        lines.append("created_at: \"\(note.createdAt?.iso8601String ?? "")\"")
        lines.append("updated_at: \"\(note.updatedAt?.iso8601String ?? "")\"")
        lines.append("shared: \(note.shared)")
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func attachmentDirectoryURL(
        forNoteRelativePath noteRelativePath: String,
        settings: AppSettings,
        vaultURL: URL
    ) -> URL {
        vaultURL.appendingPathComponent(
            attachmentDirectoryRelativePath(
                forNoteRelativePath: noteRelativePath,
                settings: settings,
                vaultURL: vaultURL
            ),
            isDirectory: true
        )
    }

    private func attachmentDirectoryRelativePath(
        forNoteRelativePath noteRelativePath: String,
        settings: AppSettings,
        vaultURL: URL
    ) -> String {
        let basePath = attachmentStorageResolution(settings: settings).baseRelativePath
        let noteParent = parentRelativePath(of: noteRelativePath)
        let noteStem = noteStem(fromRelativePath: noteRelativePath)
        return joinRelativePath(
            basePath,
            joinRelativePath(noteParent, noteStem)
        )
    }

    private func legacyAttachmentDirectoryURL(for fileURL: URL) -> URL {
        fileURL.deletingPathExtension().appendingPathComponent("", isDirectory: true)
    }

    private func resolveAttachmentFileName(
        preferredFilename: String,
        occupiedFileNames: Set<String>
    ) -> String {
        let sanitizedBaseName = sanitizePathComponent(URL(fileURLWithPath: preferredFilename).deletingPathExtension().lastPathComponent)
        let sanitizedExtension = sanitizePathComponent(URL(fileURLWithPath: preferredFilename).pathExtension)

        var collisionIndex = 1
        while true {
            let fileName = collisionIndex == 1
                ? buildFileName(baseName: sanitizedBaseName, pathExtension: sanitizedExtension)
                : buildFileName(baseName: "\(sanitizedBaseName) \(collisionIndex)", pathExtension: sanitizedExtension)
            if !occupiedFileNames.contains(fileName) {
                return fileName
            }
            collisionIndex += 1
        }
    }

    private func frontMatterIdentifiers(at fileURL: URL) throws -> [String] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---" else { return [] }

        var identifiers: [String] = []
        for line in lines.dropFirst() {
            if line == "---" {
                break
            }

            if let identifier = frontMatterValue(forKey: "apple_notes_id", in: String(line)) {
                identifiers.append(identifier)
            }
            if let legacyIdentifier = frontMatterValue(forKey: "apple_notes_legacy_id", in: String(line)) {
                identifiers.append(legacyIdentifier)
            }
        }

        return identifiers
    }

    private func frontMatterValue(forKey key: String, in line: String) -> String? {
        guard line.hasPrefix("\(key):") else { return nil }
        let value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private func buildFileName(baseName: String, pathExtension: String) -> String {
        guard !pathExtension.isEmpty else { return baseName }
        return "\(baseName).\(pathExtension)"
    }

    private func vaultURL(for settings: AppSettings) throws -> URL {
        guard let vaultPath = settings.vaultPath, !vaultPath.isEmpty else {
            throw ObsidianVaultError.vaultNotConfigured
        }

        return URL(fileURLWithPath: vaultPath, isDirectory: true)
    }

    private func resolveRelativePath(
        for note: AppleNotesSyncDocument,
        settings: AppSettings,
        existingRelativePath: String?,
        isOccupied: (String) -> Bool
    ) -> String {
        let exportRootName = sanitizePathComponent(settings.exportFolderName)
        let folderPath = sanitizeRelativePath(note.exportFolderPath)
        let baseFileName = sanitizePathComponent(note.displayName)
        let directoryPath = folderPath.isEmpty
            ? exportRootName
            : exportRootName + "/" + folderPath

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

    private func sanitizeRelativePath(_ value: String) -> String {
        value
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { component in
                sanitizePathComponent(String(component).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .joined(separator: "/")
    }

    private func customAttachmentBaseRelativePath(settings: AppSettings) -> String {
        let sanitized = sanitizeRelativePath(settings.attachmentFolderName)
        return sanitized.isEmpty ? "_attachments" : sanitized
    }

    private func configuredObsidianAttachmentFolderPath(vaultURL: URL) -> String? {
        let configURL = vaultURL
            .appendingPathComponent(".obsidian", isDirectory: true)
            .appendingPathComponent("app.json", isDirectory: false)
        guard let data = try? Data(contentsOf: configURL),
              let configuration = try? JSONDecoder().decode(ObsidianAppConfiguration.self, from: data)
        else {
            return nil
        }
        return configuration.attachmentFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedObsidianAttachmentBaseRelativePath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "." || trimmed == "./" || trimmed.hasPrefix("./") {
            return nil
        }
        return sanitizeRelativePath(trimmed)
    }

    private func parentRelativePath(of relativePath: String) -> String {
        let parent = (relativePath as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }

    private func noteStem(fromRelativePath relativePath: String) -> String {
        let lastComponent = (relativePath as NSString).lastPathComponent
        return (lastComponent as NSString).deletingPathExtension
    }

    private func joinRelativePath(_ left: String, _ right: String) -> String {
        switch (left.isEmpty, right.isEmpty) {
        case (true, true):
            ""
        case (true, false):
            right
        case (false, true):
            left
        case (false, false):
            left + "/" + right
        }
    }

    private func attachmentMigrationCandidates(
        existingRelativePath: String?,
        newRelativePath: String,
        vaultURL: URL,
        settings: AppSettings
    ) -> [URL] {
        var noteRelativePaths: Set<String> = [newRelativePath]
        if let existingRelativePath {
            noteRelativePaths.insert(existingRelativePath)
        }

        var candidateURLs: [URL] = []
        for noteRelativePath in noteRelativePaths {
            let noteFileURL = vaultURL.appendingPathComponent(noteRelativePath)
            candidateURLs.append(legacyAttachmentDirectoryURL(for: noteFileURL))
            candidateURLs.append(
                vaultURL.appendingPathComponent(
                    joinRelativePath(
                        customAttachmentBaseRelativePath(settings: settings),
                        joinRelativePath(parentRelativePath(of: noteRelativePath), noteStem(fromRelativePath: noteRelativePath))
                    ),
                    isDirectory: true
                )
            )

            if let configuredPath = configuredObsidianAttachmentFolderPath(vaultURL: vaultURL),
               let normalizedConfiguredPath = normalizedObsidianAttachmentBaseRelativePath(configuredPath)
            {
                candidateURLs.append(
                    vaultURL.appendingPathComponent(
                        joinRelativePath(
                            normalizedConfiguredPath,
                            joinRelativePath(parentRelativePath(of: noteRelativePath), noteStem(fromRelativePath: noteRelativePath))
                        ),
                        isDirectory: true
                    )
                )
            }
        }

        var seen: Set<String> = []
        return candidateURLs.filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }

    private func removeObsoleteAttachmentDirectories(
        _ candidateURLs: [URL],
        excluding destinationURL: URL,
        fileManager: FileManager
    ) throws {
        for candidateURL in candidateURLs {
            guard candidateURL.standardizedFileURL != destinationURL.standardizedFileURL,
                  fileManager.fileExists(atPath: candidateURL.path)
            else {
                continue
            }
            try? fileManager.removeItem(at: candidateURL)
        }
    }

    private func yamlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private struct ObsidianAppConfiguration: Decodable {
    var attachmentFolderPath: String?
}

private extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
