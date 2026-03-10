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

    private func note(named title: String, in folder: String) -> AppleNoteDocument {
        AppleNoteDocument(
            id: "note-1",
            name: title,
            folder: folder,
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            plaintext: "Body",
            htmlBody: "<div>Body</div>"
        )
    }
}
