import AppKit
import Foundation

enum NoteExportChangeKind: Sendable {
    case created
    case updated
    case unchanged
}

struct ObsidianExportResult: Sendable {
    let fileURL: URL
    let relativePath: String
    let changeKind: NoteExportChangeKind
    let unresolvedInternalLinkCount: Int
}

struct ObsidianAttachmentStorageResolution: Sendable {
    let baseRelativePath: String
    let sourceDescription: String
    let warning: String?
}

private struct RenderedMarkdownResult: Sendable {
    let markdown: String
    let unresolvedInternalLinkCount: Int
    let attachmentsChanged: Bool
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
    private static let updatedAtPlaceholder = "__NOTESBRIDGE_UPDATED_AT__"
    private let currentDateProvider: @Sendable () -> Date

    init(currentDateProvider: @escaping @Sendable () -> Date = Date.init) {
        self.currentDateProvider = currentDateProvider
    }

    func moveExportedNoteToRemoved(
        relativePath: String,
        settings: AppSettings
    ) throws -> String? {
        let fileManager = FileManager.default
        let vaultURL = try vaultURL(for: settings)
        let sourceURL = vaultURL.appendingPathComponent(relativePath)
        let sourceAttachmentDirectoryURL = attachmentDirectoryURL(
            forNoteRelativePath: relativePath,
            settings: settings,
            vaultURL: vaultURL
        )

        guard fileManager.fileExists(atPath: sourceURL.path)
            || fileManager.fileExists(atPath: sourceAttachmentDirectoryURL.path)
        else {
            return nil
        }

        var occupiedRelativePaths = Set(try indexExistingNotes(settings: settings).values)
        occupiedRelativePaths.remove(relativePath)
        let removedRelativePath = removedRelativePath(
            for: relativePath,
            settings: settings,
            occupiedRelativePaths: occupiedRelativePaths
        )
        let destinationURL = vaultURL.appendingPathComponent(removedRelativePath)
        if fileManager.fileExists(atPath: sourceURL.path) {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }

        let destinationAttachmentDirectoryURL = attachmentDirectoryURL(
            forNoteRelativePath: removedRelativePath,
            settings: settings,
            vaultURL: vaultURL
        )
        if fileManager.fileExists(atPath: sourceAttachmentDirectoryURL.path) {
            try fileManager.createDirectory(at: destinationAttachmentDirectoryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationAttachmentDirectoryURL.path) {
                try fileManager.removeItem(at: destinationAttachmentDirectoryURL)
            }
            try fileManager.moveItem(at: sourceAttachmentDirectoryURL, to: destinationAttachmentDirectoryURL)
        }

        return removedRelativePath
    }

    func export(
        note: AppleNotesSyncDocument,
        settings: AppSettings,
        existingRelativePath: String?,
        plannedRelativePath: String? = nil,
        plannedRelativePathsBySourceIdentifier: [String: String] = [:]
    ) throws -> ObsidianExportResult {
        let fileManager = FileManager.default
        let vaultURL = try vaultURL(for: settings)
        let relativePath = plannedRelativePath
            ?? resolveRelativePath(
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
        let sourceURL = existingRelativePath.map { vaultURL.appendingPathComponent($0) }
        let noteFileExistedBeforeExport = fileManager.fileExists(atPath: fileURL.path)
            || sourceURL.map { fileManager.fileExists(atPath: $0.path) } == true
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let obsoleteAttachmentDirectories = attachmentMigrationCandidates(
            existingRelativePath: existingRelativePath,
            newRelativePath: relativePath,
            vaultURL: vaultURL,
            settings: settings
        )
        var noteFileMoved = false
        var attachmentsChanged = false

        if let existingRelativePath,
           existingRelativePath != relativePath
        {
            noteFileMoved = try moveNoteFileIfNeeded(
                from: vaultURL.appendingPathComponent(existingRelativePath),
                to: fileURL,
                fileManager: fileManager
            )
            attachmentsChanged = try moveAttachmentDirectoryIfNeeded(
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
            fileManager: fileManager,
            plannedRelativePathsBySourceIdentifier: plannedRelativePathsBySourceIdentifier
        )
        attachmentsChanged = attachmentsChanged || renderedMarkdown.attachmentsChanged
        attachmentsChanged = try removeObsoleteAttachmentDirectories(
            obsoleteAttachmentDirectories,
            excluding: attachmentDirectoryURL(
                forNoteRelativePath: relativePath,
                settings: settings,
                vaultURL: vaultURL
            ),
            fileManager: fileManager
        )
            || attachmentsChanged
        let noteBody = renderedMarkdown.markdown.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        let existingContents = try? String(contentsOf: fileURL, encoding: .utf8)
        let comparisonContents = frontMatter(
            for: note,
            updatedAtValue: Self.updatedAtPlaceholder
        ) + noteBody
        let contentChangedIgnoringUpdatedAt = existingContents
            .map(normalizedUpdatedAtContents(in:))
            != comparisonContents
        let shouldRefreshUpdatedAt = !noteFileExistedBeforeExport
            || noteFileMoved
            || attachmentsChanged
            || contentChangedIgnoringUpdatedAt
        let updatedAtValue = shouldRefreshUpdatedAt
            ? currentDateProvider().frontMatterDateString
            : existingUpdatedAtValue(in: existingContents)
                ?? currentDateProvider().frontMatterDateString
        let contents = frontMatter(for: note, updatedAtValue: updatedAtValue) + noteBody
        let noteFileChanged = existingContents != contents
        if noteFileChanged {
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let changeKind: NoteExportChangeKind
        if !noteFileExistedBeforeExport {
            changeKind = .created
        } else if noteFileMoved || contentChangedIgnoringUpdatedAt || attachmentsChanged {
            changeKind = .updated
        } else {
            changeKind = .unchanged
        }

        return ObsidianExportResult(
            fileURL: fileURL,
            relativePath: relativePath,
            changeKind: changeKind,
            unresolvedInternalLinkCount: renderedMarkdown.unresolvedInternalLinkCount
        )
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

    func plannedRelativePath(
        for note: AppleNotesSyncManifestEntry,
        settings: AppSettings,
        existingRelativePath: String?,
        occupiedRelativePaths: Set<String>
    ) -> String {
        resolveRelativePath(
            displayName: note.displayName,
            exportFolderPath: note.exportFolderPath,
            settings: settings,
            existingRelativePath: existingRelativePath
        ) { candidateRelativePath in
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
        fileManager: FileManager,
        plannedRelativePathsBySourceIdentifier: [String: String]
    ) throws -> RenderedMarkdownResult {
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
            var attachmentsChanged = false
            if fileManager.fileExists(atPath: attachmentDirectoryURL.path) {
                let hadTrackableFiles = directoryContainsTrackableFiles(
                    at: attachmentDirectoryURL,
                    fileManager: fileManager
                )
                try? fileManager.removeItem(at: attachmentDirectoryURL)
                attachmentsChanged = attachmentsChanged || hadTrackableFiles
            }
            if fileManager.fileExists(atPath: legacyAttachmentDirectoryURL.path),
               legacyAttachmentDirectoryURL.standardizedFileURL != attachmentDirectoryURL.standardizedFileURL
            {
                let hadTrackableFiles = directoryContainsTrackableFiles(
                    at: legacyAttachmentDirectoryURL,
                    fileManager: fileManager
                )
                try? fileManager.removeItem(at: legacyAttachmentDirectoryURL)
                attachmentsChanged = attachmentsChanged || hadTrackableFiles
            }
            return renderInternalLinks(
                in: markdown,
                for: note,
                plannedRelativePathsBySourceIdentifier: plannedRelativePathsBySourceIdentifier,
                attachmentsChanged: attachmentsChanged
            )
        }

        try fileManager.createDirectory(at: attachmentDirectoryURL, withIntermediateDirectories: true)
        var occupiedFileNames: Set<String> = []
        var expectedFileNames: Set<String> = []
        var attachmentsChanged = false

        for attachment in note.attachments {
            let fileName = resolveAttachmentFileName(
                preferredFilename: attachment.preferredFilename,
                occupiedFileNames: occupiedFileNames
            )
            occupiedFileNames.insert(fileName)
            expectedFileNames.insert(fileName)

            let destinationURL = attachmentDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
            attachmentsChanged = try copyAttachmentIfNeeded(
                attachment,
                to: destinationURL,
                fileManager: fileManager
            ) || attachmentsChanged
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

        attachmentsChanged = try removeStaleAttachments(
            in: attachmentDirectoryURL,
            keepingFileNames: expectedFileNames,
            fileManager: fileManager
        ) || attachmentsChanged

        return renderInternalLinks(
            in: markdown,
            for: note,
            plannedRelativePathsBySourceIdentifier: plannedRelativePathsBySourceIdentifier,
            attachmentsChanged: attachmentsChanged
        )
    }

    private func renderInternalLinks(
        in markdown: String,
        for note: AppleNotesSyncDocument,
        plannedRelativePathsBySourceIdentifier: [String: String],
        attachmentsChanged: Bool
    ) -> RenderedMarkdownResult {
        var renderedMarkdown = markdown
        var unresolvedInternalLinkCount = 0

        for internalLink in note.internalLinks {
            let normalizedTargetIdentifier = AppleNotesSyncDocument.normalizedSourceIdentifier(
                internalLink.targetSourceIdentifier
            )
            let replacement: String

            let targetRelativePath = plannedRelativePathsBySourceIdentifier[normalizedTargetIdentifier]
                ?? AppleNotesSyncDocument.databaseNoteID(fromIdentifier: internalLink.targetSourceIdentifier)
                    .flatMap { plannedRelativePathsBySourceIdentifier[AppleNotesSyncDocument.canonicalID(for: $0)] }

            if let targetRelativePath {
                let wikiTargetPath = (targetRelativePath as NSString).deletingPathExtension
                replacement = "[[\(wikiTargetPath)|\(internalLink.displayText)]]"
            } else {
                replacement = internalLink.displayText
                unresolvedInternalLinkCount += 1
            }

            renderedMarkdown = renderedMarkdown.replacingOccurrences(
                of: "{{note-link:\(internalLink.token)}}",
                with: replacement
            )
        }

        return RenderedMarkdownResult(
            markdown: renderedMarkdown,
            unresolvedInternalLinkCount: unresolvedInternalLinkCount,
            attachmentsChanged: attachmentsChanged
        )
    }

    private func moveNoteFileIfNeeded(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: sourceURL.path),
              sourceURL.standardizedFileURL != destinationURL.standardizedFileURL,
              !fileManager.fileExists(atPath: destinationURL.path)
        else {
            return false
        }

        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return true
    }

    private func moveAttachmentDirectoryIfNeeded(
        from sourceURLs: [URL],
        to destinationURL: URL,
        fileManager: FileManager
    ) throws -> Bool {
        for sourceURL in sourceURLs {
            guard fileManager.fileExists(atPath: sourceURL.path),
                  sourceURL.standardizedFileURL != destinationURL.standardizedFileURL,
                  !fileManager.fileExists(atPath: destinationURL.path)
            else {
                continue
            }

            let hadTrackableFiles = directoryContainsTrackableFiles(
                at: sourceURL,
                fileManager: fileManager
            )
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            return hadTrackableFiles
        }
        return false
    }

    private func copyAttachmentIfNeeded(
        _ attachment: AppleNotesSyncAttachment,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws -> Bool {
        if fileManager.fileExists(atPath: destinationURL.path),
           attachmentFileMatchesSource(attachment, destinationURL: destinationURL)
        {
            return false
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: attachment.sourceURL, to: destinationURL)
        if let modifiedAt = attachment.modifiedAt {
            try? fileManager.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: destinationURL.path)
        }
        return true
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
    ) throws -> Bool {
        var didChange = false
        let existingFiles = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for fileURL in existingFiles where !keepingFileNames.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
            didChange = true
        }

        let remainingFiles = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        if remainingFiles.isEmpty {
            try? fileManager.removeItem(at: directoryURL)
        }
        return didChange
    }

    private func frontMatter(
        for note: AppleNotesSyncDocument,
        updatedAtValue: String
    ) -> String {
        var lines = [
            "---",
            "source: \"apple-notes\"",
        ]
        if let appleNotesDeepLink = note.appleNotesDeepLink {
            lines.append("apple_notes_id: \"\(yamlEscaped(appleNotesDeepLink))\"")
        } else {
            lines.append("apple_notes_id: \"\(yamlEscaped(note.id))\"")
        }
        lines.append("apple_notes_sync_id: \"\(yamlEscaped(note.id))\"")
        if let legacyNoteID = note.legacyNoteID, legacyNoteID != note.id {
            lines.append("apple_notes_legacy_id: \"\(yamlEscaped(legacyNoteID))\"")
        }
        let folderValue = note.exportFolderPath.isEmpty ? note.folderDisplayName : note.exportFolderPath
        lines.append("apple_notes_folder: \"\(yamlEscaped(folderValue))\"")
        lines.append("created_at: \"\(note.createdAt?.frontMatterDateString ?? "")\"")
        lines.append("updated_at: \"\(yamlEscaped(updatedAtValue))\"")
        lines.append("shared: \(note.shared)")
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func existingUpdatedAtValue(in contents: String?) -> String? {
        guard let contents,
              let frontMatterRange = frontMatterRange(in: contents)
        else {
            return nil
        }

        let frontMatter = String(contents[frontMatterRange])
        let pattern = #"(?m)^updated_at: "([^"]*)"$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(frontMatter.startIndex..., in: frontMatter)
        guard let match = regex.firstMatch(in: frontMatter, range: range),
              let valueRange = Range(match.range(at: 1), in: frontMatter)
        else {
            return nil
        }

        return String(frontMatter[valueRange])
    }

    private func normalizedUpdatedAtContents(in contents: String) -> String {
        guard let frontMatterRange = frontMatterRange(in: contents) else {
            return contents
        }

        let frontMatter = String(contents[frontMatterRange])
        let normalizedFrontMatter = frontMatter.replacingOccurrences(
            of: #"(?m)^updated_at: "[^"]*"$"#,
            with: #"updated_at: "\#(Self.updatedAtPlaceholder)""#,
            options: .regularExpression
        )

        return contents.replacingCharacters(in: frontMatterRange, with: normalizedFrontMatter)
    }

    private func frontMatterRange(in contents: String) -> Range<String.Index>? {
        let openingDelimiter = "---\n"
        guard contents.hasPrefix(openingDelimiter),
              let closingRange = contents.range(
                  of: "\n---\n",
                  range: contents.index(contents.startIndex, offsetBy: openingDelimiter.count)..<contents.endIndex
              )
        else {
            return nil
        }

        return contents.startIndex..<closingRange.upperBound
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
            if let syncIdentifier = frontMatterValue(forKey: "apple_notes_sync_id", in: String(line)) {
                identifiers.append(syncIdentifier)
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
        resolveRelativePath(
            displayName: note.displayName,
            exportFolderPath: note.exportFolderPath,
            settings: settings,
            existingRelativePath: existingRelativePath,
            isOccupied: isOccupied
        )
    }

    private func resolveRelativePath(
        displayName: String,
        exportFolderPath: String,
        settings: AppSettings,
        existingRelativePath: String?,
        isOccupied: (String) -> Bool
    ) -> String {
        let exportRootName = sanitizePathComponent(settings.exportFolderName)
        let folderPath = sanitizeRelativePath(exportFolderPath)
        let baseFileName = sanitizePathComponent(displayName)
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

    private func removedRelativePath(
        for relativePath: String,
        settings: AppSettings,
        occupiedRelativePaths: Set<String>
    ) -> String {
        let exportRootName = sanitizePathComponent(settings.exportFolderName)
        let removedRoot = exportRootName + "/_Removed"
        let relativePathInsideExportRoot = relativePath.hasPrefix(exportRootName + "/")
            ? String(relativePath.dropFirst(exportRootName.count + 1))
            : relativePath
        let directory = parentRelativePath(of: relativePathInsideExportRoot)
        let noteStem = noteStem(fromRelativePath: relativePathInsideExportRoot)
        let baseDirectory = directory.isEmpty ? removedRoot : removedRoot + "/" + directory

        var collisionIndex = 1
        while true {
            let fileName = collisionIndex == 1
                ? "\(sanitizePathComponent(noteStem)).md"
                : "\(sanitizePathComponent(noteStem)) \(collisionIndex).md"
            let candidateRelativePath = baseDirectory + "/" + fileName
            if !occupiedRelativePaths.contains(candidateRelativePath) {
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
    ) throws -> Bool {
        var didChange = false
        for candidateURL in candidateURLs {
            guard candidateURL.standardizedFileURL != destinationURL.standardizedFileURL,
                  fileManager.fileExists(atPath: candidateURL.path)
            else {
                continue
            }
            let hadTrackableFiles = directoryContainsTrackableFiles(
                at: candidateURL,
                fileManager: fileManager
            )
            try? fileManager.removeItem(at: candidateURL)
            didChange = didChange || hadTrackableFiles
        }
        return didChange
    }

    private func directoryContainsTrackableFiles(
        at directoryURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]) else {
                continue
            }
            if values.isRegularFile == true {
                return true
            }
        }

        return false
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
    var frontMatterDateString: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: self)
    }
}
