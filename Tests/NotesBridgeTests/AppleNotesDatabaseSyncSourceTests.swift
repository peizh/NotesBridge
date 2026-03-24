import Testing
@testable import NotesBridge

struct AppleNotesDatabaseSyncSourceTests {
    private let dataSource = AppleNotesDatabaseSyncSource()
    @MainActor private let dataFolderSelector = AppleNotesDataFolderSelector()

    @Test
    func validatesSelectedGroupContainerAndPrefersRootDatabaseWhenPresent() throws {
        let rootURL = try makeDataFolder(
            noteStoreRelativePaths: [
                "NoteStore.sqlite",
                "Accounts/LocalAccount/NoteStore.sqlite",
                "Accounts/OtherAccount/NoteStore.sqlite",
            ]
        )
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let selection = try dataSource.validateDataFolder(at: rootURL.path)

        #expect(selection.rootURL == rootURL)
        #expect(selection.databaseURL.path.hasSuffix("group.com.apple.notes/NoteStore.sqlite"))
    }

    @Test
    func fallsBackToAccountDatabaseWhenRootDatabaseIsMissing() throws {
        let rootURL = try makeDataFolder(
            noteStoreRelativePaths: [
                "Accounts/LocalAccount/NoteStore.sqlite",
            ]
        )
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let selection = try dataSource.validateDataFolder(at: rootURL.path)

        #expect(selection.databaseURL.path.hasSuffix("Accounts/LocalAccount/NoteStore.sqlite"))
    }

    @Test
    func reportsLimitedAccessWhenOnlyRootDatabaseIsVisible() throws {
        let rootURL = try makeDataFolder(
            noteStoreRelativePaths: [
                "NoteStore.sqlite",
            ]
        )
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let inspection = dataSource.inspectDataFolder(at: rootURL.path)

        #expect(inspection.level == .limited)
    }

    @Test
    func reportsAccessibleAccessWhenRootDatabaseAlreadyContainsNotes() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/group.com.apple.notes", isDirectory: true)
        let candidateScan = AppleNotesDatabaseCandidateScan(
            candidateURLs: [rootURL.appendingPathComponent("NoteStore.sqlite", isDirectory: false)],
            rootCandidatePresent: true,
            accountsDirectoryExists: true,
            accountsIsDirectory: true,
            localAccountCandidatePresent: false,
            rootEntries: ["Accounts", "NoteStore.sqlite"],
            accountDirectoryNames: [".DS_Store{hidden}"],
            accountsEnumerationError: nil
        )
        let candidateReport = AppleNotesDatabaseCandidateReport(
            rootURL: rootURL,
            databaseURL: rootURL.appendingPathComponent("NoteStore.sqlite", isDirectory: false),
            folderCount: 5,
            totalNoteCount: 12,
            documentCount: 12,
            skippedLockedNotes: 0,
            folderTitleColumn: "ztitle2",
            noteTitleColumn: "ztitle1",
            noteFolderColumn: "zfolder",
            folderReferenceStats: []
        )

        let inspection = dataSource.resolvedAccessStatus(
            rootURL: rootURL,
            candidateScan: candidateScan,
            candidateReports: [candidateReport]
        )

        #expect(inspection.level == .accessible)
        #expect(inspection.message.contains("sync can proceed using the root database"))
    }

    @Test
    func rejectsNonGroupContainerSelections() throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let invalidURL = baseURL.appendingPathComponent("wrong-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        do {
            _ = try dataSource.validateDataFolder(at: invalidURL.path)
            Issue.record("Expected invalidDataFolder error.")
        } catch let error as AppleNotesSyncDataSourceError {
            #expect(error == .invalidDataFolder)
        }
    }

    @Test
    func rejectsSelectionsWithoutNoteStoreDatabase() throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let rootURL = baseURL.appendingPathComponent("group.com.apple.notes", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        do {
            _ = try dataSource.validateDataFolder(at: rootURL.path)
            Issue.record("Expected noteStoreNotFound error.")
        } catch let error as AppleNotesSyncDataSourceError {
            #expect(error == .noteStoreNotFound)
        }
    }

    @Test
    func buildsDocumentSelectClauseWithoutDanglingCommaWhenFolderReferencesAreMissing() {
        let clause = dataSource.joinedSelectClause([
            "nd.znote AS pk",
            "nd.zdata AS data",
            "'' AS title",
            "n.zcreationdate1 AS createdAt1",
        ])

        #expect(!clause.contains(",\n                ,"))
        #expect(clause.contains("nd.znote AS pk"))
        #expect(clause.contains("nd.zdata AS data"))
        #expect(clause.contains("'' AS title"))
    }

    @Test
    func manifestQueryOnlyIncludesNotesWithLocalBodyData() {
        let query = dataSource.manifestSelectSQL(columns: [
            "n.z_pk AS pk",
            "'' AS title",
        ])

        #expect(query.contains("JOIN zicnotedata AS nd ON nd.znote = n.z_pk"))
        #expect(query.contains("AND nd.zdata IS NOT NULL"))
    }

    @Test
    func stagesSnapshotsUnderUserCachesDirectory() throws {
        let snapshotRoot = try dataSource.snapshotRootDirectory()

        #expect(snapshotRoot.path.contains("/Library/Caches/"))
        #expect(snapshotRoot.lastPathComponent == "AppleNotesSnapshots")
        #expect(FileManager.default.fileExists(atPath: snapshotRoot.path))
    }

    @Test
    @MainActor
    func defaultsPickerToAppleNotesGroupContainerFolder() {
        let defaultURL = dataFolderSelector.defaultAppleNotesDataFolderURL()

        #expect(defaultURL.path.hasSuffix("/Library/Group Containers/group.com.apple.notes"))
        #expect(defaultURL.lastPathComponent == "group.com.apple.notes")
    }

    private func makeDataFolder(noteStoreRelativePaths: [String]) throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let rootURL = baseURL.appendingPathComponent("group.com.apple.notes", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        for relativePath in noteStoreRelativePaths {
            let noteStoreURL = rootURL.appendingPathComponent(relativePath, isDirectory: false)
            try FileManager.default.createDirectory(at: noteStoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: noteStoreURL.path, contents: Data())
        }

        return rootURL
    }
}
