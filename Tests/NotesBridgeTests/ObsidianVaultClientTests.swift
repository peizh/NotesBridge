import Testing
@testable import NotesBridge

struct ObsidianVaultClientTests {
    private let client = ObsidianVaultClient()
    private let settings = AppSettings.default

    @Test
    func usesCleanFileNamesWhenNoConflictExists() {
        let relativePath = client.plannedRelativePath(
            for: note(named: "9-11-2025", in: "Inbox"),
            settings: settings,
            existingRelativePath: nil,
            occupiedRelativePaths: []
        )

        #expect(relativePath == "Apple Notes/Inbox/9-11-2025.md")
    }

    @Test
    func appendsSequenceNumbersWhenCleanNamesConflict() {
        let relativePath = client.plannedRelativePath(
            for: note(named: "Daily Note", in: "Inbox"),
            settings: settings,
            existingRelativePath: nil,
            occupiedRelativePaths: [
                "Apple Notes/Inbox/Daily Note.md",
            ]
        )

        #expect(relativePath == "Apple Notes/Inbox/Daily Note 2.md")
    }

    @Test
    func preservesNestedFolderHierarchyWhenFolderPathIsProvided() {
        let relativePath = client.plannedRelativePath(
            for: note(
                named: "Roadmap",
                in: "Work / Projects / Q1",
                folderPath: "Work/Projects/Q1"
            ),
            settings: settings,
            existingRelativePath: nil,
            occupiedRelativePaths: []
        )

        #expect(relativePath == "Apple Notes/Work/Projects/Q1/Roadmap.md")
    }

    @Test
    func migratesLegacyHashPathsToCleanPath() {
        let relativePath = client.plannedRelativePath(
            for: note(named: "Daily Note", in: "Inbox"),
            settings: settings,
            existingRelativePath: "Apple Notes/Inbox/Daily Note [cbb1f1e1].md",
            occupiedRelativePaths: []
        )

        #expect(relativePath == "Apple Notes/Inbox/Daily Note.md")
    }

    @Test
    func keepsExistingCleanPathWhenEditingAnUnchangedNote() {
        let relativePath = client.plannedRelativePath(
            for: note(named: "Daily Note", in: "Inbox"),
            settings: settings,
            existingRelativePath: "Apple Notes/Inbox/Daily Note.md",
            occupiedRelativePaths: [
                "Apple Notes/Inbox/Daily Note.md",
                "Apple Notes/Inbox/Daily Note 2.md",
            ]
        )

        #expect(relativePath == "Apple Notes/Inbox/Daily Note.md")
    }

    @Test
    func recalculatesPathWhenTitleOrFolderChanges() {
        let relativePath = client.plannedRelativePath(
            for: note(named: "New Title", in: "Projects"),
            settings: settings,
            existingRelativePath: "Apple Notes/Inbox/Old Title.md",
            occupiedRelativePaths: []
        )

        #expect(relativePath == "Apple Notes/Projects/New Title.md")
    }

    @Test
    func exportsAttachmentsIntoUnifiedAttachmentFolderAndRendersEmbedsAndLinks() throws {
        let vaultURL = try makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let imageURL = vaultURL.appendingPathComponent("sources/photo.png")
        let archiveURL = vaultURL.appendingPathComponent("sources/archive.zip")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        try Data([0x50, 0x4B, 0x03, 0x04]).write(to: archiveURL)

        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path

        let note = AppleNotesSyncDocument(
            databaseNoteID: 42,
            sourceNoteIdentifier: "x-coredata://legacy/ICNote/p42",
            legacyNoteID: "x-coredata://legacy/ICNote/p42",
            name: "Daily Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "Intro\n{{attachment:image}}\n{{attachment:archive}}",
            attachments: [
                AppleNotesSyncAttachment(
                    token: "image",
                    logicalIdentifier: "image",
                    sourceURL: imageURL,
                    preferredFilename: "photo.png",
                    renderStyle: .embed,
                    modifiedAt: nil,
                    fileSize: 4
                ),
                AppleNotesSyncAttachment(
                    token: "archive",
                    logicalIdentifier: "archive",
                    sourceURL: archiveURL,
                    preferredFilename: "archive.zip",
                    renderStyle: .link,
                    modifiedAt: nil,
                    fileSize: 4
                ),
            ]
        )

        let export = try client.export(note: note, settings: settings, existingRelativePath: nil)
        let fileContents = try String(contentsOf: export.fileURL, encoding: .utf8)
        let attachmentRoot = vaultURL.appendingPathComponent("_attachments/Apple Notes/Inbox/Daily Note", isDirectory: true)

        #expect(fileContents.contains("apple_notes_id: \"applenotes:note/x-coredata://legacy/ICNote/p42\""))
        #expect(fileContents.contains("apple_notes_sync_id: \"apple-notes-db://note/42\""))
        #expect(fileContents.contains("apple_notes_legacy_id: \"x-coredata://legacy/ICNote/p42\""))
        #expect(fileContents.contains("![[_attachments/Apple Notes/Inbox/Daily Note/photo.png]]"))
        #expect(fileContents.contains("[[_attachments/Apple Notes/Inbox/Daily Note/archive.zip]]"))
        #expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent("photo.png").path))
        #expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent("archive.zip").path))
        #expect(export.changeKind == .created)
    }

    @Test
    func reexportingUnchangedNoteReportsUnchanged() throws {
        let vaultURL = try makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path

        let note = AppleNotesSyncDocument(
            databaseNoteID: 100,
            name: "Stable Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "Body",
            attachments: []
        )

        let firstExport = try client.export(note: note, settings: settings, existingRelativePath: nil)
        let secondExport = try client.export(
            note: note,
            settings: settings,
            existingRelativePath: firstExport.relativePath
        )

        #expect(firstExport.changeKind == .created)
        #expect(secondExport.changeKind == .unchanged)
    }

    @Test
    func removingEmptyAttachmentDirectoryDoesNotCountAsUpdated() throws {
        let vaultURL = try makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path

        let note = AppleNotesSyncDocument(
            databaseNoteID: 1001,
            name: "Stable Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "Body",
            attachments: []
        )

        let firstExport = try client.export(note: note, settings: settings, existingRelativePath: nil)
        let emptyAttachmentDirectory = vaultURL.appendingPathComponent(
            "_attachments/Apple Notes/Inbox/Stable Note",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: emptyAttachmentDirectory,
            withIntermediateDirectories: true
        )

        let secondExport = try client.export(
            note: note,
            settings: settings,
            existingRelativePath: firstExport.relativePath
        )

        #expect(secondExport.changeKind == .unchanged)
    }

    @Test
    func changingExistingNoteContentReportsUpdated() throws {
        let vaultURL = try makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path

        let originalNote = AppleNotesSyncDocument(
            databaseNoteID: 101,
            name: "Daily Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "Body",
            attachments: []
        )
        let firstExport = try client.export(note: originalNote, settings: settings, existingRelativePath: nil)

        let updatedNote = AppleNotesSyncDocument(
            databaseNoteID: 101,
            name: "Daily Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "Body changed",
            attachments: []
        )
        let secondExport = try client.export(
            note: updatedNote,
            settings: settings,
            existingRelativePath: firstExport.relativePath
        )

        #expect(secondExport.changeKind == .updated)
    }

    @Test
    func renamingANoteMovesItsAttachmentFolder() throws {
        let vaultURL = try makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let sourceURL = vaultURL.appendingPathComponent("sources/photo.png")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)

        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path

        let originalNote = AppleNotesSyncDocument(
            databaseNoteID: 7,
            name: "Old Title",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "{{attachment:image}}",
            attachments: [
                AppleNotesSyncAttachment(
                    token: "image",
                    logicalIdentifier: "image",
                    sourceURL: sourceURL,
                    preferredFilename: "photo.png",
                    renderStyle: .embed,
                    modifiedAt: nil,
                    fileSize: 4
                ),
            ]
        )
        let firstExport = try client.export(note: originalNote, settings: settings, existingRelativePath: nil)

        let renamedNote = AppleNotesSyncDocument(
            databaseNoteID: 7,
            name: "New Title",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "{{attachment:image}}",
            attachments: originalNote.attachments
        )
        _ = try client.export(
            note: renamedNote,
            settings: settings,
            existingRelativePath: firstExport.relativePath
        )

        let oldAttachmentDirectory = vaultURL.appendingPathComponent("_attachments/Apple Notes/Inbox/Old Title", isDirectory: true)
        let newAttachmentDirectory = vaultURL.appendingPathComponent("_attachments/Apple Notes/Inbox/New Title", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: oldAttachmentDirectory.path))
        #expect(FileManager.default.fileExists(atPath: newAttachmentDirectory.appendingPathComponent("photo.png").path))
    }

    @Test
    func removesStaleAttachmentsWhenANoteNoLongerReferencesThem() throws {
        let vaultURL = try makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let sourceURL = vaultURL.appendingPathComponent("sources/photo.png")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)

        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path

        let noteWithAttachment = AppleNotesSyncDocument(
            databaseNoteID: 9,
            name: "Daily Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "{{attachment:image}}",
            attachments: [
                AppleNotesSyncAttachment(
                    token: "image",
                    logicalIdentifier: "image",
                    sourceURL: sourceURL,
                    preferredFilename: "photo.png",
                    renderStyle: .embed,
                    modifiedAt: nil,
                    fileSize: 4
                ),
            ]
        )
        let firstExport = try client.export(note: noteWithAttachment, settings: settings, existingRelativePath: nil)

        let noteWithoutAttachments = AppleNotesSyncDocument(
            databaseNoteID: 9,
            name: "Daily Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "Body",
            attachments: []
        )
        _ = try client.export(
            note: noteWithoutAttachments,
            settings: settings,
            existingRelativePath: firstExport.relativePath
        )

        let attachmentDirectory = vaultURL.appendingPathComponent("_attachments/Apple Notes/Inbox/Daily Note", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: attachmentDirectory.path))
    }

    @Test
    func usesObsidianConfiguredAttachmentFolderWhenEnabled() throws {
        let vaultURL = try makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let obsidianConfigDirectory = vaultURL.appendingPathComponent(".obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: obsidianConfigDirectory, withIntermediateDirectories: true)
        let appConfiguration = Data(#"{"attachmentFolderPath":"assets"}"#.utf8)
        try appConfiguration.write(
            to: obsidianConfigDirectory.appendingPathComponent("app.json"),
            options: .atomic
        )

        let sourceURL = vaultURL.appendingPathComponent("sources/photo.png")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)

        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path
        settings.useObsidianAttachmentFolder = true

        let note = AppleNotesSyncDocument(
            databaseNoteID: 11,
            name: "Daily Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "{{attachment:image}}",
            attachments: [
                AppleNotesSyncAttachment(
                    token: "image",
                    logicalIdentifier: "image",
                    sourceURL: sourceURL,
                    preferredFilename: "photo.png",
                    renderStyle: .embed,
                    modifiedAt: nil,
                    fileSize: 4
                ),
            ]
        )

        let export = try client.export(note: note, settings: settings, existingRelativePath: nil)
        let fileContents = try String(contentsOf: export.fileURL, encoding: .utf8)

        #expect(fileContents.contains("![[assets/Apple Notes/Inbox/Daily Note/photo.png]]"))
        #expect(
            FileManager.default.fileExists(
                atPath: vaultURL.appendingPathComponent("assets/Apple Notes/Inbox/Daily Note/photo.png").path
            )
        )
    }

    @Test
    func rendersInternalLinksUsingPlannedRelativePathAndAlias() throws {
        let vaultURL = try makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path

        let note = AppleNotesSyncDocument(
            databaseNoteID: 12,
            sourceNoteIdentifier: "SOURCE-CURRENT",
            name: "9/4/2025",
            folder: "Journal",
            folderPath: "Rocky's Digital Garden/Journal",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "See {{note-link:journal-link}}",
            internalLinks: [
                AppleNotesSyncInternalLink(
                    token: "journal-link",
                    targetSourceIdentifier: "TARGET-NOTE",
                    displayText: "9/3/2025"
                ),
            ],
            attachments: []
        )

        let export = try client.export(
            note: note,
            settings: settings,
            existingRelativePath: nil,
            plannedRelativePath: "Apple Notes/Rocky's Digital Garden/Journal/9-4-2025.md",
            plannedRelativePathsBySourceIdentifier: [
                "TARGET-NOTE": "Apple Notes/Rocky's Digital Garden/Journal/9-3-2025.md",
            ]
        )
        let fileContents = try String(contentsOf: export.fileURL, encoding: .utf8)

        #expect(fileContents.contains("[[Apple Notes/Rocky's Digital Garden/Journal/9-3-2025|9/3/2025]]"))
        #expect(export.unresolvedInternalLinkCount == 0)
    }

    @Test
    func usesCollisionResolvedTargetPathsForInternalLinks() throws {
        let vaultURL = try makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path

        let note = AppleNotesSyncDocument(
            databaseNoteID: 13,
            name: "Current Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "{{note-link:daily-link}}",
            internalLinks: [
                AppleNotesSyncInternalLink(
                    token: "daily-link",
                    targetSourceIdentifier: "TARGET-DAILY",
                    displayText: "Daily Note"
                ),
            ],
            attachments: []
        )

        let export = try client.export(
            note: note,
            settings: settings,
            existingRelativePath: nil,
            plannedRelativePath: "Apple Notes/Inbox/Current Note.md",
            plannedRelativePathsBySourceIdentifier: [
                "TARGET-DAILY": "Apple Notes/Inbox/Daily Note 2.md",
            ]
        )
        let fileContents = try String(contentsOf: export.fileURL, encoding: .utf8)

        #expect(fileContents.contains("[[Apple Notes/Inbox/Daily Note 2|Daily Note]]"))
        #expect(export.unresolvedInternalLinkCount == 0)
    }

    @Test
    func resolvesXCoreDataInternalLinksThroughCanonicalDatabaseIDFallback() throws {
        let vaultURL = try makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path

        let note = AppleNotesSyncDocument(
            databaseNoteID: 15,
            name: "Current Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "{{note-link:journal-link}}",
            internalLinks: [
                AppleNotesSyncInternalLink(
                    token: "journal-link",
                    targetSourceIdentifier: "x-coredata://625E753D-DB29-4635-93F4-C869C2726CCF/ICNote/p5916",
                    displayText: "Roadmap Q3"
                ),
            ],
            attachments: []
        )

        let export = try client.export(
            note: note,
            settings: settings,
            existingRelativePath: nil,
            plannedRelativePath: "Apple Notes/Inbox/Current Note.md",
            plannedRelativePathsBySourceIdentifier: [
                AppleNotesSyncDocument.canonicalID(for: 5916): "Apple Notes/NotesBridge Fixtures/Projects/Specs/Roadmap Q3.md",
            ]
        )
        let fileContents = try String(contentsOf: export.fileURL, encoding: .utf8)

        #expect(fileContents.contains("[[Apple Notes/NotesBridge Fixtures/Projects/Specs/Roadmap Q3|Roadmap Q3]]"))
        #expect(export.unresolvedInternalLinkCount == 0)
    }

    @Test
    func fallsBackToPlainTextWhenInternalLinkTargetIsMissing() throws {
        let vaultURL = try makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path

        let note = AppleNotesSyncDocument(
            databaseNoteID: 14,
            name: "Current Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "See {{note-link:missing-link}}",
            internalLinks: [
                AppleNotesSyncInternalLink(
                    token: "missing-link",
                    targetSourceIdentifier: "MISSING-TARGET",
                    displayText: "9/3/2025"
                ),
            ],
            attachments: []
        )

        let export = try client.export(
            note: note,
            settings: settings,
            existingRelativePath: nil,
            plannedRelativePath: "Apple Notes/Inbox/Current Note.md",
            plannedRelativePathsBySourceIdentifier: [:]
        )
        let fileContents = try String(contentsOf: export.fileURL, encoding: .utf8)

        #expect(fileContents.contains("See 9/3/2025"))
        #expect(!fileContents.contains("[[9/3/2025]]"))
        #expect(export.unresolvedInternalLinkCount == 1)
    }

    @Test
    func movesDeletedNoteIntoRemovedFolder() throws {
        let vaultURL = try makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path

        let sourceURL = vaultURL.appendingPathComponent("sources/photo.png")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)

        let note = AppleNotesSyncDocument(
            databaseNoteID: 21,
            name: "Deleted Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "{{attachment:image}}",
            attachments: [
                AppleNotesSyncAttachment(
                    token: "image",
                    logicalIdentifier: "image",
                    sourceURL: sourceURL,
                    preferredFilename: "photo.png",
                    renderStyle: .embed,
                    modifiedAt: nil,
                    fileSize: 4
                ),
            ]
        )
        let export = try client.export(note: note, settings: settings, existingRelativePath: nil)
        let removedRelativePath = try client.moveExportedNoteToRemoved(
            relativePath: export.relativePath,
            settings: settings
        )

        #expect(removedRelativePath == "Apple Notes/_Removed/Inbox/Deleted Note.md")
        #expect(!FileManager.default.fileExists(atPath: export.fileURL.path))
        #expect(
            FileManager.default.fileExists(
                atPath: vaultURL.appendingPathComponent("Apple Notes/_Removed/Inbox/Deleted Note.md").path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: vaultURL.appendingPathComponent("_attachments/Apple Notes/_Removed/Inbox/Deleted Note/photo.png").path
            )
        )
    }

    private func note(
        named title: String,
        in folder: String,
        folderPath: String? = nil
    ) -> AppleNotesSyncDocument {
        AppleNotesSyncDocument(
            databaseNoteID: 1,
            name: title,
            folder: folder,
            folderPath: folderPath,
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "Body",
            attachments: []
        )
    }

    private func makeTemporaryVault() throws -> URL {
        let vaultURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        return vaultURL
    }
}
