import AppKit
import Foundation
import OSLog

protocol AppleNotesSyncDataSourcing: Sendable {
    func validateDataFolder(at path: String) throws -> AppleNotesDataFolderSelection
    func inspectDataFolder(at path: String) -> AppleNotesDataFolderAccessStatus
    func fetchFolders(fromDataFolder path: String) throws -> [AppleNotesFolder]
    func loadManifest(fromDataFolder path: String) throws -> AppleNotesSyncManifest
    func loadDocuments(
        fromDataFolder path: String,
        noteIDs: Set<Int64>,
        preferredDatabaseRelativePath: String?
    ) throws -> AppleNotesSyncSnapshot
    func loadSnapshot(fromDataFolder path: String) throws -> AppleNotesSyncSnapshot
}

@MainActor
protocol AppleNotesDataFolderSelecting {
    func chooseAppleNotesDataFolder() -> URL?
}

@MainActor
struct AppleNotesDataFolderSelector: AppleNotesDataFolderSelecting {
    func chooseAppleNotesDataFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Apple Notes Data Folder"
        panel.prompt = "Use Folder"
        panel.message = "Select the \"group.com.apple.notes\" folder to allow NotesBridge to read Apple Notes data."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.directoryURL = defaultAppleNotesDataFolderURL()

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    func defaultAppleNotesDataFolderURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.notes", isDirectory: true)
    }
}

enum AppleNotesSyncDataSourceError: Equatable, LocalizedError {
    case invalidDataFolder
    case unreadableDataFolder
    case noteStoreNotFound
    case snapshotStagingFailed(source: String, destinationDirectory: String, underlying: String)
    case missingDatabaseEntity(String)
    case unsupportedAttachment(String)
    case noteBodiesUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidDataFolder:
            "Select the Apple Notes group container folder named group.com.apple.notes."
        case .unreadableDataFolder:
            "The selected Apple Notes data folder is unreadable."
        case .noteStoreNotFound:
            "Could not find NoteStore.sqlite inside the selected Apple Notes data folder."
        case let .snapshotStagingFailed(source, destinationDirectory, underlying):
            "Failed to stage Apple Notes snapshot from \(source) into \(destinationDirectory). \(underlying)"
        case let .missingDatabaseEntity(name):
            "Apple Notes database is missing \(name)."
        case let .unsupportedAttachment(type):
            "Unsupported Apple Notes attachment type: \(type)."
        case let .noteBodiesUnavailable(details):
            details
        }
    }
}

enum AppleNotesDataFolderAccessLevel: String, Sendable {
    case accessible
    case limited
    case invalid
}

struct AppleNotesDataFolderAccessStatus: Sendable {
    var level: AppleNotesDataFolderAccessLevel
    var message: String
}

struct AppleNotesDatabaseSyncSource: AppleNotesSyncDataSourcing {
    private let decoder: AppleNotesNoteProtoDecoder
    private let renderer: AppleNotesMarkdownRenderer
    private let mergeableDataDecoder: AppleNotesMergeableDataProtoDecoder

    init(
        decoder: AppleNotesNoteProtoDecoder = AppleNotesNoteProtoDecoder(),
        renderer: AppleNotesMarkdownRenderer = AppleNotesMarkdownRenderer(),
        mergeableDataDecoder: AppleNotesMergeableDataProtoDecoder = AppleNotesMergeableDataProtoDecoder()
    ) {
        self.decoder = decoder
        self.renderer = renderer
        self.mergeableDataDecoder = mergeableDataDecoder
    }

    func manifestSelectSQL(columns: [String]) -> String {
        """
        SELECT
            \(joinedSelectClause(columns))
        FROM ziccloudsyncingobject AS n
        JOIN zicnotedata AS nd ON nd.znote = n.z_pk
        WHERE n.z_ent = ?
          AND nd.zdata IS NOT NULL
        ORDER BY title COLLATE NOCASE
        """
    }

    func validateDataFolder(at path: String) throws -> AppleNotesDataFolderSelection {
        let rootURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard rootURL.lastPathComponent == "group.com.apple.notes" else {
            throw AppleNotesSyncDataSourceError.invalidDataFolder
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AppleNotesSyncDataSourceError.unreadableDataFolder
        }

        guard let databaseURL = databaseCandidateReport(rootURL: rootURL).candidateURLs.first else {
            throw AppleNotesSyncDataSourceError.noteStoreNotFound
        }

        return AppleNotesDataFolderSelection(rootURL: rootURL, databaseURL: databaseURL)
    }

    func inspectDataFolder(at path: String) -> AppleNotesDataFolderAccessStatus {
        let rootURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard rootURL.lastPathComponent == "group.com.apple.notes" else {
            return AppleNotesDataFolderAccessStatus(
                level: .invalid,
                message: "Select the Apple Notes group container folder named group.com.apple.notes."
            )
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return AppleNotesDataFolderAccessStatus(
                level: .invalid,
                message: "The configured Apple Notes data folder is unreadable."
            )
        }

        let candidateScan = databaseCandidateReport(rootURL: rootURL)
        guard !candidateScan.candidateURLs.isEmpty else {
            return AppleNotesDataFolderAccessStatus(
                level: .invalid,
                message: "No readable NoteStore.sqlite files were found in the configured Apple Notes data folder."
            )
        }

        return resolvedAccessStatus(
            rootURL: rootURL,
            candidateScan: candidateScan,
            candidateReports: inspectionCandidateReports(rootURL: rootURL, candidateScan: candidateScan)
        )
    }

    func resolvedAccessStatus(
        rootURL: URL,
        candidateScan: AppleNotesDatabaseCandidateScan,
        candidateReports: [AppleNotesDatabaseCandidateReport]
    ) -> AppleNotesDataFolderAccessStatus {
        if let accountsEnumerationError = candidateScan.accountsEnumerationError,
           !candidateReports.contains(where: \.containsVisibleNotes)
        {
            return AppleNotesDataFolderAccessStatus(
                level: .limited,
                message: "The Apple Notes root folder is readable, but the Accounts subfolder is not: \(accountsEnumerationError)"
            )
        }

        let hasAccountDatabase = candidateScan.candidateURLs.contains {
            $0.path.contains("/Accounts/")
        }
        if candidateScan.rootCandidatePresent && !hasAccountDatabase {
            let rootDatabasePath = rootURL.appendingPathComponent("NoteStore.sqlite", isDirectory: false).path
            if let rootCandidateReport = candidateReports.first(where: { $0.databaseURL.path == rootDatabasePath }),
               rootCandidateReport.containsVisibleNotes
            {
                return AppleNotesDataFolderAccessStatus(
                    level: .accessible,
                    message: "The root NoteStore.sqlite is readable and already contains your current Apple Notes data. Account databases are not visible, but sync can proceed using the root database."
                )
            }

            return AppleNotesDataFolderAccessStatus(
                level: .limited,
                message: "Only the root NoteStore.sqlite is currently visible. If sync returns 0 notes, re-choose the Apple Notes data folder to restore access to account databases."
            )
        }

        return AppleNotesDataFolderAccessStatus(
            level: .accessible,
            message: "The configured Apple Notes data folder is readable."
        )
    }

    func fetchFolders(fromDataFolder path: String) throws -> [AppleNotesFolder] {
        let selection = try validateDataFolder(at: path)
        var bestSummaries: [AppleNotesFolder] = []
        var bestNoteCount = -1

        for candidateURL in databaseCandidateReport(rootURL: selection.rootURL).candidateURLs {
            let candidateSelection = AppleNotesDataFolderSelection(
                rootURL: selection.rootURL,
                databaseURL: candidateURL
            )
            let summaries = try withDatabaseSnapshot(from: candidateSelection) { database, schema in
                try loadFolderContext(database: database, schema: schema).summaries
            }
            let noteCount = summaries.reduce(0) { $0 + $1.noteCount }
            if noteCount > bestNoteCount {
                bestSummaries = summaries
                bestNoteCount = noteCount
            }
        }

        return bestSummaries
    }

    func loadManifest(fromDataFolder path: String) throws -> AppleNotesSyncManifest {
        AppLog.appleNotes.info("Loading Apple Notes manifest from data folder: \(path, privacy: .public)")
        let selection = try validateDataFolder(at: path)
        let candidateScan = databaseCandidateReport(rootURL: selection.rootURL)
        var bestManifest: AppleNotesSyncManifest?
        var bestCandidateURL: URL?
        var bestVisibleEntryCount = -1
        var bestTotalEntryCount = -1
        var candidateReports: [AppleNotesDatabaseCandidateReport] = []

        for candidateURL in candidateScan.candidateURLs {
            let candidateSelection = AppleNotesDataFolderSelection(
                rootURL: selection.rootURL,
                databaseURL: candidateURL
            )
            let candidateResult = try withDatabaseSnapshot(from: candidateSelection) { database, schema in
                let folderContext = try loadFolderContext(database: database, schema: schema)
                let noteTitleColumn = try schema.preferredTextColumn(
                    database: database,
                    entityID: try schema.entityID(named: "ICNote"),
                    preferredColumns: ["ztitle1", "ztitle"],
                    prefixes: ["ztitle"]
                )
                let manifest = try loadManifest(
                    database: database,
                    schema: schema,
                    folderContext: folderContext,
                    noteTitleColumn: noteTitleColumn
                )
                let visibleEntryCount = manifest.entries.filter { !$0.passwordProtected && !$0.trashed }.count
                let report = AppleNotesDatabaseCandidateReport(
                    rootURL: selection.rootURL,
                    databaseURL: candidateURL,
                    folderCount: manifest.folders.count,
                    totalNoteCount: manifest.entries.count,
                    documentCount: visibleEntryCount,
                    skippedLockedNotes: manifest.skippedLockedNotes,
                    folderTitleColumn: folderContext.folderTitleColumn,
                    noteTitleColumn: noteTitleColumn,
                    noteFolderColumn: folderContext.noteFolderColumn,
                    folderReferenceStats: []
                )
                return (manifest, report, visibleEntryCount)
            }

            let manifest = candidateResult.0
            let report = candidateResult.1
            let visibleEntryCount = candidateResult.2
            let totalEntryCount = manifest.entries.count
            candidateReports.append(report)
            AppLog.appleNotes.debug("Candidate manifest report: \(report.summary, privacy: .public)")
            if visibleEntryCount > bestVisibleEntryCount
                || (visibleEntryCount == bestVisibleEntryCount && totalEntryCount > bestTotalEntryCount)
            {
                bestManifest = manifest
                bestCandidateURL = candidateURL
                bestVisibleEntryCount = visibleEntryCount
                bestTotalEntryCount = totalEntryCount
            }
        }

        guard var bestManifest else {
            throw AppleNotesSyncDataSourceError.noteStoreNotFound
        }

        bestManifest.sourceDiagnostics = candidateReports.map(\.summary).joined(separator: " | ")
        bestManifest.selectedDatabaseRelativePath = bestCandidateURL.map {
            databaseRelativePath(rootURL: selection.rootURL, databaseURL: $0)
        }
        return bestManifest
    }

    func loadDocuments(
        fromDataFolder path: String,
        noteIDs: Set<Int64>,
        preferredDatabaseRelativePath: String? = nil
    ) throws -> AppleNotesSyncSnapshot {
        AppLog.appleNotes.info("Loading \(noteIDs.count) Apple Notes document(s) from data folder: \(path, privacy: .public)")
        guard !noteIDs.isEmpty else {
            let manifest = try loadManifest(fromDataFolder: path)
            return AppleNotesSyncSnapshot(
                folders: manifest.folders,
                documents: [],
                skippedLockedNotes: manifest.skippedLockedNotes,
                skippedLockedNotesByFolder: manifest.skippedLockedNotesByFolder,
                sourceDiagnostics: manifest.sourceDiagnostics
            )
        }

        let selection = try validateDataFolder(at: path)
        let candidateScan = databaseCandidateReport(rootURL: selection.rootURL)
        let candidateURLs = targetedLoadCandidateURLs(
            rootURL: selection.rootURL,
            candidateScan: candidateScan,
            preferredDatabaseRelativePath: preferredDatabaseRelativePath
        )
        var bestSnapshot: AppleNotesSyncSnapshot?
        var bestDocumentCount = -1
        var candidateReports: [AppleNotesDatabaseCandidateReport] = []

        for candidateURL in candidateURLs {
            let candidateSelection = AppleNotesDataFolderSelection(
                rootURL: selection.rootURL,
                databaseURL: candidateURL
            )
            let candidateResult = try withDatabaseSnapshot(from: candidateSelection) { database, schema in
                let folderContext = try loadFolderContext(database: database, schema: schema)
                let noteTitleColumn = try schema.preferredTextColumn(
                    database: database,
                    entityID: try schema.entityID(named: "ICNote"),
                    preferredColumns: ["ztitle1", "ztitle"],
                    prefixes: ["ztitle"]
                )
                let noteReferenceMap = try loadNoteReferenceMap(
                    database: database,
                    schema: schema,
                    noteTitleColumn: noteTitleColumn
                )
                let documentsResult = try loadDocuments(
                    database: database,
                    schema: schema,
                    selection: candidateSelection,
                    folderContext: folderContext,
                    noteReferenceMap: noteReferenceMap,
                    noteTitleColumn: noteTitleColumn,
                    noteIDs: noteIDs
                )

                let snapshot = AppleNotesSyncSnapshot(
                    folders: folderContext.summaries,
                    documents: documentsResult.documents,
                    skippedLockedNotes: documentsResult.skippedLockedNotes,
                    skippedLockedNotesByFolder: documentsResult.skippedLockedNotesByFolder,
                    failedTableDecodes: documentsResult.failedTableDecodes,
                    failedScanDecodes: documentsResult.failedScanDecodes,
                    partialScanPageFailures: documentsResult.partialScanPageFailures,
                    sourceDiagnostics: nil
                )
                let report = AppleNotesDatabaseCandidateReport(
                    rootURL: selection.rootURL,
                    databaseURL: candidateURL,
                    folderCount: snapshot.folders.count,
                    totalNoteCount: folderContext.summaries.reduce(0) { $0 + $1.noteCount },
                    documentCount: snapshot.documents.count,
                    skippedLockedNotes: snapshot.skippedLockedNotes,
                    folderTitleColumn: folderContext.folderTitleColumn,
                    noteTitleColumn: noteTitleColumn,
                    noteFolderColumn: folderContext.noteFolderColumn,
                    folderReferenceStats: documentsResult.folderReferenceStats
                )
                return (snapshot, report)
            }

            let snapshot = candidateResult.0
            let report = candidateResult.1
            candidateReports.append(report)
            AppLog.appleNotes.debug("Candidate targeted document report: \(report.summary, privacy: .public)")
            if snapshot.documents.count > bestDocumentCount {
                bestSnapshot = snapshot
                bestDocumentCount = snapshot.documents.count
            }
        }

        guard var bestSnapshot else {
            throw AppleNotesSyncDataSourceError.noteStoreNotFound
        }

        bestSnapshot.sourceDiagnostics = candidateReports.map(\.summary).joined(separator: " | ")
        return bestSnapshot
    }

    func loadSnapshot(fromDataFolder path: String) throws -> AppleNotesSyncSnapshot {
        AppLog.appleNotes.info("Loading Apple Notes snapshot from data folder: \(path, privacy: .public)")
        let selection = try validateDataFolder(at: path)
        let candidateScan = databaseCandidateReport(rootURL: selection.rootURL)
        var bestSnapshot: AppleNotesSyncSnapshot?
        var bestDocumentCount = -1
        var bestTotalNoteCount = -1
        var candidateReports: [AppleNotesDatabaseCandidateReport] = []

        for candidateURL in candidateScan.candidateURLs {
            let candidateSelection = AppleNotesDataFolderSelection(
                rootURL: selection.rootURL,
                databaseURL: candidateURL
            )
            let candidateResult = try withDatabaseSnapshot(from: candidateSelection) { database, schema in
                let folderContext = try loadFolderContext(database: database, schema: schema)
                let noteTitleColumn = try schema.preferredTextColumn(
                    database: database,
                    entityID: try schema.entityID(named: "ICNote"),
                    preferredColumns: ["ztitle1", "ztitle"],
                    prefixes: ["ztitle"]
                )
                let noteReferenceMap = try loadNoteReferenceMap(
                    database: database,
                    schema: schema,
                    noteTitleColumn: noteTitleColumn
                )
                let documentsResult = try loadDocuments(
                    database: database,
                    schema: schema,
                    selection: candidateSelection,
                    folderContext: folderContext,
                    noteReferenceMap: noteReferenceMap,
                    noteTitleColumn: noteTitleColumn,
                    noteIDs: nil
                )

                let snapshot = AppleNotesSyncSnapshot(
                    folders: folderContext.summaries,
                    documents: documentsResult.documents,
                    skippedLockedNotes: documentsResult.skippedLockedNotes,
                    skippedLockedNotesByFolder: documentsResult.skippedLockedNotesByFolder,
                    failedTableDecodes: documentsResult.failedTableDecodes,
                    failedScanDecodes: documentsResult.failedScanDecodes,
                    partialScanPageFailures: documentsResult.partialScanPageFailures,
                    sourceDiagnostics: nil
                )
                let report = AppleNotesDatabaseCandidateReport(
                    rootURL: selection.rootURL,
                    databaseURL: candidateURL,
                    folderCount: snapshot.folders.count,
                    totalNoteCount: snapshot.folders.reduce(0) { $0 + $1.noteCount },
                    documentCount: snapshot.documents.count,
                    skippedLockedNotes: snapshot.skippedLockedNotes,
                    folderTitleColumn: folderContext.folderTitleColumn,
                    noteTitleColumn: noteTitleColumn,
                    noteFolderColumn: folderContext.noteFolderColumn,
                    folderReferenceStats: documentsResult.folderReferenceStats
                )
                return (snapshot, report)
            }
            let snapshot = candidateResult.0
            let report = candidateResult.1

            let documentCount = snapshot.documents.count
            let totalNoteCount = snapshot.folders.reduce(0) { $0 + $1.noteCount }
            candidateReports.append(report)
            AppLog.appleNotes.debug("Candidate database report: \(report.summary, privacy: .public)")
            if documentCount > bestDocumentCount
                || (documentCount == bestDocumentCount && totalNoteCount > bestTotalNoteCount)
            {
                bestSnapshot = snapshot
                bestDocumentCount = documentCount
                bestTotalNoteCount = totalNoteCount
            }
        }

        guard let bestSnapshot else {
            throw AppleNotesSyncDataSourceError.noteStoreNotFound
        }

        let diagnosticsText = makeDiagnosticsText(
            rootURL: selection.rootURL,
            candidateReports: candidateReports,
            candidateScan: candidateScan
        )
        print(diagnosticsText)
        AppLog.appleNotes.info("Apple Notes diagnostics: \(diagnosticsText, privacy: .public)")

        if bestSnapshot.documents.isEmpty,
           candidateReports.contains(where: { $0.folderCount > 0 || $0.totalNoteCount > 0 })
        {
            throw AppleNotesSyncDataSourceError.noteBodiesUnavailable(
                "Apple Notes sync could not find readable note content in the selected data folder. \(diagnosticsText)"
            )
        }

        if bestSnapshot.documents.isEmpty,
           bestSnapshot.folders.isEmpty,
           candidateScan.candidateURLs.count == 1,
           candidateScan.rootCandidatePresent
        {
            let details = candidateScan.accountsEnumerationError.map { " Accounts scan failed: \($0)" } ?? ""
            throw AppleNotesSyncDataSourceError.noteBodiesUnavailable(
                "Apple Notes sync only found an empty root NoteStore.sqlite and could not see the account databases that contain your notes.\(details) Re-choose the Apple Notes data folder in Settings and sync again."
            )
        }

        var resolvedSnapshot = bestSnapshot
        resolvedSnapshot.sourceDiagnostics = candidateReports.map(\.summary).joined(separator: " | ")
        AppLog.appleNotes.info(
            "Resolved Apple Notes snapshot with \(resolvedSnapshot.folders.count) folder(s), \(resolvedSnapshot.documents.count) document(s), \(resolvedSnapshot.skippedLockedNotes) locked note(s)."
        )
        return resolvedSnapshot
    }
}

extension AppleNotesDatabaseSyncSource {
    func snapshotRootDirectory(fileManager: FileManager = .default) throws -> URL {
        let rootDirectory = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("NotesBridge", isDirectory: true)
        .appendingPathComponent("AppleNotesSnapshots", isDirectory: true)

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        return rootDirectory
    }
}

private extension AppleNotesDatabaseSyncSource {
    func makeSnapshotDirectory(fileManager: FileManager = .default) throws -> URL {
        let snapshotDirectory = try snapshotRootDirectory(fileManager: fileManager)
            .appendingPathComponent("NotesBridge-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        } catch {
            throw AppleNotesSyncDataSourceError.snapshotStagingFailed(
                source: "n/a",
                destinationDirectory: snapshotDirectory.path,
                underlying: error.localizedDescription
            )
        }
        return snapshotDirectory
    }
    
    func inspectionCandidateReports(
        rootURL: URL,
        candidateScan: AppleNotesDatabaseCandidateScan
    ) -> [AppleNotesDatabaseCandidateReport] {
        let hasAccountDatabase = candidateScan.candidateURLs.contains { $0.path.contains("/Accounts/") }
        guard candidateScan.rootCandidatePresent, !hasAccountDatabase else {
            return []
        }

        let selection = AppleNotesDataFolderSelection(
            rootURL: rootURL,
            databaseURL: rootURL.appendingPathComponent("NoteStore.sqlite", isDirectory: false)
        )

        do {
            let report = try withDatabaseSnapshot(from: selection) { database, schema in
                let folderContext = try loadFolderContext(database: database, schema: schema)
                let noteTitleColumn = try schema.preferredTextColumn(
                    database: database,
                    entityID: try schema.entityID(named: "ICNote"),
                    preferredColumns: ["ztitle1", "ztitle"],
                    prefixes: ["ztitle"]
                )
                let noteReferenceMap = try loadNoteReferenceMap(
                    database: database,
                    schema: schema,
                    noteTitleColumn: noteTitleColumn
                )
                let documentsResult = try loadDocuments(
                    database: database,
                    schema: schema,
                    selection: selection,
                    folderContext: folderContext,
                    noteReferenceMap: noteReferenceMap,
                    noteTitleColumn: noteTitleColumn,
                    noteIDs: nil
                )

                return AppleNotesDatabaseCandidateReport(
                    rootURL: rootURL,
                    databaseURL: selection.databaseURL,
                    folderCount: folderContext.summaries.count,
                    totalNoteCount: folderContext.summaries.reduce(0) { $0 + $1.noteCount },
                    documentCount: documentsResult.documents.count,
                    skippedLockedNotes: documentsResult.skippedLockedNotes,
                    folderTitleColumn: folderContext.folderTitleColumn,
                    noteTitleColumn: noteTitleColumn,
                    noteFolderColumn: folderContext.noteFolderColumn,
                    folderReferenceStats: documentsResult.folderReferenceStats
                )
            }
            return [report]
        } catch {
            AppLog.appleNotes.error(
                "Failed to inspect root Apple Notes candidate at \(selection.databaseURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    func targetedLoadCandidateURLs(
        rootURL: URL,
        candidateScan: AppleNotesDatabaseCandidateScan,
        preferredDatabaseRelativePath: String?
    ) -> [URL] {
        guard let preferredDatabaseRelativePath,
              !preferredDatabaseRelativePath.isEmpty
        else {
            return candidateScan.candidateURLs
        }

        let preferredURL = rootURL.appendingPathComponent(preferredDatabaseRelativePath, isDirectory: false)
        if candidateScan.candidateURLs.contains(preferredURL) {
            AppLog.appleNotes.info(
                "Using manifest-selected Apple Notes database for targeted load: \(preferredDatabaseRelativePath, privacy: .public)"
            )
            return [preferredURL]
        }

        AppLog.appleNotes.warning(
            "Manifest-selected Apple Notes database is no longer visible for targeted load: \(preferredDatabaseRelativePath, privacy: .public). Falling back to all candidates."
        )
        return candidateScan.candidateURLs
    }

    func databaseRelativePath(rootURL: URL, databaseURL: URL) -> String {
        databaseURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
    }

    func databaseCandidateReport(rootURL: URL) -> AppleNotesDatabaseCandidateScan {
        var candidates: [URL] = []
        let fileManager = FileManager.default
        let rootCandidate = rootURL.appendingPathComponent("NoteStore.sqlite", isDirectory: false)
        let rootCandidatePresent = fileManager.fileExists(atPath: rootCandidate.path)
        if rootCandidatePresent {
            candidates.append(rootCandidate)
        }

        let localAccountCandidate = rootURL
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent("LocalAccount", isDirectory: true)
            .appendingPathComponent("NoteStore.sqlite", isDirectory: false)
        let localAccountCandidatePresent = fileManager.fileExists(atPath: localAccountCandidate.path)
        if localAccountCandidatePresent {
            candidates.append(localAccountCandidate)
        }

        let accountsURL = rootURL.appendingPathComponent("Accounts", isDirectory: true)
        var accountsEnumerationError: String?
        var accountsIsDirectory = ObjCBool(false)
        let accountsDirectoryExists = fileManager.fileExists(atPath: accountsURL.path, isDirectory: &accountsIsDirectory)
        let rootEntries: [String]
        do {
            rootEntries = try fileManager.contentsOfDirectory(atPath: rootURL.path).sorted()
        } catch {
            AppLog.appleNotes.error(
                "Failed to enumerate Apple Notes root directory at \(rootURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            rootEntries = []
        }
        var accountDirectoryNames: [String] = []
        var accountSubpaths: [String] = []
        do {
            let accountDirectories = try fileManager.contentsOfDirectory(
                at: accountsURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: []
            )
            accountDirectoryNames = accountDirectories.map { accountDirectory in
                let hiddenFlag = (try? accountDirectory.resourceValues(forKeys: [.isHiddenKey]).isHidden) == true
                return hiddenFlag ? "\(accountDirectory.lastPathComponent){hidden}" : accountDirectory.lastPathComponent
            }
            .sorted()
            for accountDirectory in accountDirectories {
                let candidate = accountDirectory.appendingPathComponent("NoteStore.sqlite", isDirectory: false)
                if fileManager.fileExists(atPath: candidate.path),
                   !candidates.contains(candidate)
                {
                    candidates.append(candidate)
                }
            }
        } catch {
            if accountsDirectoryExists {
                accountsEnumerationError = error.localizedDescription
                AppLog.appleNotes.error(
                    "Failed to enumerate Apple Notes Accounts directory at \(accountsURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        if accountsDirectoryExists {
            do {
                accountSubpaths = try fileManager.subpathsOfDirectory(atPath: accountsURL.path)
                    .sorted()
            } catch {
                if accountsEnumerationError == nil {
                    accountsEnumerationError = error.localizedDescription
                }
                AppLog.appleNotes.error(
                    "Failed to read Apple Notes Accounts subpaths at \(accountsURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        let candidatePaths = candidates.map(\.path).joined(separator: ", ")
        AppLog.appleNotes.info(
            """
            Apple Notes directory scan:
            root=\(rootURL.path, privacy: .public)
            rootEntries=\(rootEntries.joined(separator: ","), privacy: .public)
            rootNoteStoreVisible=\(rootCandidatePresent)
            localAccountNoteStoreVisible=\(localAccountCandidatePresent)
            accountsPath=\(accountsURL.path, privacy: .public)
            accountsExists=\(accountsDirectoryExists)
            accountsIsDirectory=\(accountsIsDirectory.boolValue)
            accountsEntries=\(accountDirectoryNames.joined(separator: ","), privacy: .public)
            accountsSubpaths=\(accountSubpaths.joined(separator: ","), privacy: .public)
            accountsEnumerationError=\(accountsEnumerationError ?? "none", privacy: .public)
            """
        )
        AppLog.appleNotes.debug(
            "Candidate database URLs under \(rootURL.path, privacy: .public): \(candidatePaths, privacy: .public)"
        )
        return AppleNotesDatabaseCandidateScan(
            candidateURLs: candidates,
            rootCandidatePresent: rootCandidatePresent,
            accountsDirectoryExists: accountsDirectoryExists,
            accountsIsDirectory: accountsIsDirectory.boolValue,
            localAccountCandidatePresent: localAccountCandidatePresent,
            rootEntries: rootEntries,
            accountDirectoryNames: accountDirectoryNames,
            accountsEnumerationError: accountsEnumerationError
        )
    }

    func makeDiagnosticsText(
        rootURL: URL,
        candidateReports: [AppleNotesDatabaseCandidateReport],
        candidateScan: AppleNotesDatabaseCandidateScan
    ) -> String {
        let candidateSummary = candidateReports.isEmpty
            ? "No candidate NoteStore.sqlite files found."
            : candidateReports
                .map(\.summary)
                .joined(separator: " | ")
        let scanSummary = [
            "rootEntries=\(candidateScan.rootEntries.joined(separator: ","))",
            candidateScan.accountsDirectoryExists ? "accountsDir=present" : "accountsDir=missing",
            "accountsIsDirectory=\(candidateScan.accountsIsDirectory)",
            "localAccountVisible=\(candidateScan.localAccountCandidatePresent)",
            candidateScan.accountDirectoryNames.isEmpty ? "accountsEntries=none" : "accountsEntries=\(candidateScan.accountDirectoryNames.joined(separator: ","))",
            candidateScan.accountsEnumerationError.map { "accountsError=\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: "; ")
        return "Apple Notes data folder: \(rootURL.path). Candidate databases: \(candidateSummary)\(scanSummary.isEmpty ? "" : ". \(scanSummary)")"
    }

    func withDatabaseSnapshot<T>(
        from selection: AppleNotesDataFolderSelection,
        _ body: (SQLiteDatabase, AppleNotesDatabaseSchema) throws -> T
    ) throws -> T {
        let fileManager = FileManager.default
        let snapshotDirectory = try makeSnapshotDirectory(fileManager: fileManager)

        defer {
            try? fileManager.removeItem(at: snapshotDirectory)
        }

        let clonedDatabaseURL = snapshotDirectory.appendingPathComponent(selection.databaseURL.lastPathComponent)
        do {
            try fileManager.copyItem(at: selection.databaseURL, to: clonedDatabaseURL)
        } catch {
            throw AppleNotesSyncDataSourceError.snapshotStagingFailed(
                source: selection.databaseURL.path,
                destinationDirectory: snapshotDirectory.path,
                underlying: error.localizedDescription
            )
        }

        for suffix in ["-wal", "-shm"] {
            let source = URL(fileURLWithPath: selection.databaseURL.path + suffix)
            let destination = URL(fileURLWithPath: clonedDatabaseURL.path + suffix)
            if fileManager.fileExists(atPath: source.path) {
                do {
                    try fileManager.copyItem(at: source, to: destination)
                } catch {
                    throw AppleNotesSyncDataSourceError.snapshotStagingFailed(
                        source: source.path,
                        destinationDirectory: snapshotDirectory.path,
                        underlying: error.localizedDescription
                    )
                }
            }
        }

        let database = try SQLiteDatabase(url: clonedDatabaseURL)
        let schema = try AppleNotesDatabaseSchema(database: database)
        return try body(database, schema)
    }

    func loadFolderContext(
        database: SQLiteDatabase,
        schema: AppleNotesDatabaseSchema
    ) throws -> AppleNotesFolderContext {
        let accounts = try loadAccounts(database: database, schema: schema)
        let folderEntityID = try schema.entityID(named: "ICFolder")
        let noteEntityID = try schema.entityID(named: "ICNote")
        let folderTitleColumn = try schema.preferredTextColumn(
            database: database,
            entityID: folderEntityID,
            preferredColumns: ["ztitle2", "ztitle", "zname"],
            prefixes: ["ztitle", "zname"]
        )
        let folderRows = try database.rows(
            """
            SELECT
                z_pk AS pk,
                \(schema.selectedColumnExpression(folderTitleColumn, alias: "title", defaultValue: "''")),
                \(schema.columnExpression("zparent", alias: "parentID")),
                \(schema.columnExpression("zfoldertype", alias: "folderType", defaultValue: "0")),
                \(schema.columnExpression("zowner", alias: "ownerID", defaultValue: "0")),
                \(schema.columnExpression("zidentifier", alias: "identifier", defaultValue: "''"))
            FROM ziccloudsyncingobject
            WHERE z_ent = ?
            ORDER BY title COLLATE NOCASE
            """,
            bindings: [.int(folderEntityID)]
        )

        let folders = folderRows.compactMap { row -> AppleNotesResolvedFolder? in
            let folderType = Int(row.int("folderType") ?? 0)
            guard folderType != AppleNotesFolderType.smart.rawValue else { return nil }

            return AppleNotesResolvedFolder(
                databaseID: row.int("pk") ?? 0,
                title: row.string("title") ?? "",
                parentID: row.int("parentID"),
                folderType: folderType,
                ownerID: row.int("ownerID"),
                identifier: row.string("identifier") ?? ""
            )
        }
        let folderByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.databaseID, $0) })
        let noteFolderColumn = try schema.preferredReferenceColumn(
            database: database,
            entityID: noteEntityID,
            preferredColumns: ["zfolder", "zcontainer", "zparent"],
            targetValues: Array(folderByID.keys),
            prefixes: ["zfolder", "zcontainer", "zparent"]
        )
        let noteCountRows: [SQLiteRow]
        if let noteFolderColumn {
            noteCountRows = try database.rows(
                """
                SELECT
                    \(noteFolderColumn) AS folderID,
                    COUNT(*) AS noteCount
                FROM ziccloudsyncingobject
                WHERE z_ent = ?
                GROUP BY \(noteFolderColumn)
                """,
                bindings: [.int(noteEntityID)]
            )
        } else {
            noteCountRows = []
        }
        let noteCounts = Dictionary(uniqueKeysWithValues: noteCountRows.map { row in
            (row.int("folderID") ?? 0, Int(row.int("noteCount") ?? 0))
        })
        let multiAccount = accounts.count > 1

        let summaries = folders.compactMap { folder -> AppleNotesFolder? in
            guard folder.folderType != AppleNotesFolderType.trash.rawValue else { return nil }
            let accountName = folder.ownerID.flatMap { ownerID in
                multiAccount ? accounts[ownerID]?.name : nil
            }
            let displayName = resolvedFolderDisplayName(
                for: folder.databaseID,
                foldersByID: folderByID
            )
            let relativePath = resolvedFolderRelativePath(
                for: folder.databaseID,
                foldersByID: folderByID,
                accountsByID: accounts,
                includeAccountName: multiAccount
            )
            return AppleNotesFolder(
                id: "apple-notes-db://folder/\(folder.databaseID)",
                name: displayName,
                accountName: accountName,
                noteCount: noteCounts[folder.databaseID] ?? 0,
                relativePath: relativePath
            )
        }
        .sorted { left, right in
            left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
        }

        return AppleNotesFolderContext(
            summaries: summaries,
            foldersByID: folderByID,
            summariesByDatabaseID: Dictionary(uniqueKeysWithValues: summaries.compactMap { summary in
                guard let id = Int64(summary.id.replacingOccurrences(of: "apple-notes-db://folder/", with: "")) else {
                    return nil
                }
                return (id, summary)
            }),
            accountsByID: accounts,
            folderTitleColumn: folderTitleColumn,
            noteFolderColumn: noteFolderColumn
        )
    }

    func loadAccounts(
        database: SQLiteDatabase,
        schema: AppleNotesDatabaseSchema
    ) throws -> [Int64: AppleNotesResolvedAccount] {
        let rows = try database.rows(
            """
            SELECT
                z_pk AS pk,
                \(schema.columnExpression("zname", alias: "name", defaultValue: "''")),
                \(schema.columnExpression("zidentifier", alias: "identifier", defaultValue: "''"))
            FROM ziccloudsyncingobject
            WHERE z_ent = ?
            """,
            bindings: [.int(schema.entityID(named: "ICAccount"))]
        )

        return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            guard let pk = row.int("pk") else { return nil }
            return (
                pk,
                AppleNotesResolvedAccount(
                    databaseID: pk,
                    name: row.string("name") ?? "Apple Notes",
                    identifier: row.string("identifier") ?? ""
                )
            )
        })
    }

    func resolvedFolderDisplayName(
        for databaseID: Int64,
        foldersByID: [Int64: AppleNotesResolvedFolder]
    ) -> String {
        guard let folder = foldersByID[databaseID] else {
            return "Notes"
        }

        let baseTitle = resolvedFolderTitle(folder)

        guard let parentID = folder.parentID, parentID != 0 else {
            return baseTitle
        }

        let parent = resolvedFolderDisplayName(for: parentID, foldersByID: foldersByID)
        return "\(parent) / \(baseTitle)"
    }

    func resolvedFolderRelativePath(
        for databaseID: Int64,
        foldersByID: [Int64: AppleNotesResolvedFolder],
        accountsByID: [Int64: AppleNotesResolvedAccount],
        includeAccountName: Bool
    ) -> String {
        guard let folder = foldersByID[databaseID] else {
            return "Notes"
        }

        let baseTitle = resolvedFolderTitle(folder)
        let shouldSkipOwnName = folder.identifier.hasPrefix("DefaultFolder")
        guard let parentID = folder.parentID, parentID != 0 else {
            let accountPrefix = includeAccountName
                ? folder.ownerID.flatMap { accountsByID[$0]?.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .flatMap { $0.isEmpty ? nil : $0 }
                : nil
            return [accountPrefix, shouldSkipOwnName ? nil : baseTitle]
                .compactMap { $0 }
                .joined(separator: "/")
        }

        let parent = resolvedFolderRelativePath(
            for: parentID,
            foldersByID: foldersByID,
            accountsByID: accountsByID,
            includeAccountName: includeAccountName
        )
        return [Optional(parent), shouldSkipOwnName ? nil : baseTitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    func resolvedFolderTitle(_ folder: AppleNotesResolvedFolder) -> String {
        let trimmedTitle = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        if folder.identifier.hasPrefix("DefaultFolder") {
            return "Notes"
        }
        return "Untitled Folder"
    }

    func loadNoteReferenceMap(
        database: SQLiteDatabase,
        schema: AppleNotesDatabaseSchema,
        noteTitleColumn: String?
    ) throws -> [String: AppleNotesResolvedNoteReference] {
        let rows = try database.rows(
            """
            SELECT
                z_pk AS pk,
                zidentifier AS identifier,
                \(schema.selectedColumnExpression(noteTitleColumn, alias: "title", defaultValue: "''"))
            FROM ziccloudsyncingobject
            WHERE z_ent = ?
            """,
            bindings: [.int(schema.entityID(named: "ICNote"))]
        )

        return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            guard let identifier = row.string("identifier")
            else {
                return nil
            }

            let normalizedIdentifier = AppleNotesSyncDocument.normalizedSourceIdentifier(identifier)
            let title = row.string("title")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (
                normalizedIdentifier,
                AppleNotesResolvedNoteReference(
                    databaseNoteID: row.int("pk"),
                    sourceIdentifier: normalizedIdentifier,
                    displayText: title.isEmpty ? "Untitled Note" : title
                )
            )
        })
    }

    func loadDocuments(
        database: SQLiteDatabase,
        schema: AppleNotesDatabaseSchema,
        selection: AppleNotesDataFolderSelection,
        folderContext: AppleNotesFolderContext,
        noteReferenceMap: [String: AppleNotesResolvedNoteReference],
        noteTitleColumn: String?,
        noteIDs: Set<Int64>?
    ) throws -> AppleNotesDocumentLoadResult {
        let noteFolderReferenceColumns = schema.presentColumns(["zfolder", "zcontainer", "zparent"])
        let noteFolderExpressions = noteFolderReferenceColumns.enumerated().map { index, column in
            schema.columnExpression(column, tableAlias: "n", alias: "folderRef\(index)")
        }
        let selectColumns = joinedSelectClause(
            documentSelectColumns(
                schema: schema,
                noteTitleColumn: noteTitleColumn,
                noteFolderExpressions: noteFolderExpressions
            )
        )
        let noteIDBindings = noteIDs?.sorted().map(SQLiteBinding.int) ?? []
        let noteIDFilterClause = noteIDBindings.isEmpty
            ? ""
            : " AND n.z_pk IN (\(Array(repeating: "?", count: noteIDBindings.count).joined(separator: ", ")))"
        let rows = try database.rows(
            """
            SELECT
                \(selectColumns)
            FROM zicnotedata AS nd
            JOIN ziccloudsyncingobject AS n ON n.z_pk = nd.znote
            WHERE n.z_ent = ?
            \(noteIDFilterClause)
            ORDER BY title COLLATE NOCASE
            """,
            bindings: [.int(schema.entityID(named: "ICNote"))] + noteIDBindings
        )

        var documents: [AppleNotesSyncDocument] = []
        var skippedLockedNotes = 0
        var skippedLockedNotesByFolder: [String: Int] = [:]
        var renderDiagnostics = AppleNotesRenderDiagnostics()
        var folderReferenceStats = noteFolderReferenceColumns.enumerated().map { index, column in
            AppleNotesFolderReferenceStat(columnName: column, nonNullCount: 0, matchedFolderCount: 0)
        }

        for row in rows {
            guard let noteID = row.int("pk") else { continue }
            for index in 0 ..< folderReferenceStats.count {
                if let candidateID = row.int("folderRef\(index)") {
                    folderReferenceStats[index].nonNullCount += 1
                    if folderContext.foldersByID[candidateID] != nil {
                        folderReferenceStats[index].matchedFolderCount += 1
                    }
                }
            }
            let folderDatabaseID = resolvedFolderDatabaseID(
                in: row,
                candidateColumnCount: noteFolderReferenceColumns.count,
                knownFolders: folderContext.foldersByID
            )
            let folderSummary = folderDatabaseID
                .flatMap { folderContext.summariesByDatabaseID[$0] }
            let folderName = folderSummary?.displayName ?? "Notes"
            let folderPath = folderSummary?.exportRelativePath
            if let folderDatabaseID,
               let folder = folderContext.foldersByID[folderDatabaseID],
               folder.folderType == AppleNotesFolderType.trash.rawValue
            {
                continue
            }

            if row.bool("passwordProtected") {
                skippedLockedNotes += 1
                skippedLockedNotesByFolder[folderPath ?? folderName, default: 0] += 1
                continue
            }

            guard let compressedData = row.data("data") else {
                continue
            }

            let decodedNote = try decoder.decodeDocument(from: compressedData)
            let resolvedTitle = resolvedNoteTitle(
                databaseTitle: row.string("title"),
                noteText: decodedNote.noteText
            )
            let ownerID = row.int("ownerID")
                ?? folderDatabaseID.flatMap { folderContext.foldersByID[$0]?.ownerID }
            let rendered = try renderer.render(note: decodedNote) { attachmentInfo in
                try resolveAttachmentReference(
                    attachmentInfo,
                    database: database,
                    schema: schema,
                    selection: selection,
                    ownerID: ownerID,
                    noteReferenceMap: noteReferenceMap
                )
            }
            renderDiagnostics.merge(rendered.diagnostics)

            documents.append(
                AppleNotesSyncDocument(
                    databaseNoteID: noteID,
                    sourceNoteIdentifier: row.string("sourceIdentifier"),
                    folderDatabaseID: folderDatabaseID,
                    name: resolvedTitle,
                    folder: folderName,
                    folderPath: folderPath,
                    createdAt: decodeAppleNotesTime(
                        row.double("createdAt3")
                            ?? row.double("createdAt2")
                            ?? row.double("createdAt1")
                    ),
                    updatedAt: decodeAppleNotesTime(row.double("updatedAt")),
                    shared: row.bool("shared"),
                    passwordProtected: false,
                    markdownTemplate: rendered.markdownTemplate,
                    internalLinks: rendered.internalLinks,
                    attachments: rendered.attachments
                )
            )
        }

        return AppleNotesDocumentLoadResult(
            documents: documents,
            skippedLockedNotes: skippedLockedNotes,
            skippedLockedNotesByFolder: skippedLockedNotesByFolder,
            folderReferenceStats: folderReferenceStats,
            failedTableDecodes: renderDiagnostics.failedTableDecodes,
            failedScanDecodes: renderDiagnostics.failedScanDecodes,
            partialScanPageFailures: renderDiagnostics.partialScanPageFailures
        )
    }

    func loadManifest(
        database: SQLiteDatabase,
        schema: AppleNotesDatabaseSchema,
        folderContext: AppleNotesFolderContext,
        noteTitleColumn: String?
    ) throws -> AppleNotesSyncManifest {
        let noteFolderReferenceColumns = schema.presentColumns(["zfolder", "zcontainer", "zparent"])
        let noteFolderExpressions = noteFolderReferenceColumns.enumerated().map { index, column in
            schema.columnExpression(column, tableAlias: "n", alias: "folderRef\(index)")
        }
        var columns = [
            "n.z_pk AS pk",
            schema.columnExpression("zidentifier", tableAlias: "n", alias: "sourceIdentifier", defaultValue: "''"),
            schema.selectedColumnExpression(noteTitleColumn, tableAlias: "n", alias: "title", defaultValue: "''"),
        ]
        columns.append(contentsOf: noteFolderExpressions)
        columns.append(contentsOf: [
            schema.columnExpression("zmodificationdate1", tableAlias: "n", alias: "updatedAt"),
            schema.columnExpression("zispasswordprotected", tableAlias: "n", alias: "passwordProtected", defaultValue: "0"),
        ])
        let rows = try database.rows(
            manifestSelectSQL(columns: columns),
            bindings: [.int(schema.entityID(named: "ICNote"))]
        )

        var entries: [AppleNotesSyncManifestEntry] = []
        var skippedLockedNotes = 0
        var skippedLockedNotesByFolder: [String: Int] = [:]

        for row in rows {
            guard let noteID = row.int("pk") else {
                continue
            }

            let folderDatabaseID = resolvedFolderDatabaseID(
                in: row,
                candidateColumnCount: noteFolderReferenceColumns.count,
                knownFolders: folderContext.foldersByID
            )
            let folderSummary = folderDatabaseID
                .flatMap { folderContext.summariesByDatabaseID[$0] }
            let folderName = folderSummary?.displayName ?? "Notes"
            let folderPath = folderSummary?.exportRelativePath
            let isTrashed = folderDatabaseID
                .flatMap { folderContext.foldersByID[$0] }
                .map { $0.folderType == AppleNotesFolderType.trash.rawValue }
                ?? false
            let isPasswordProtected = row.bool("passwordProtected")

            if isPasswordProtected {
                skippedLockedNotes += 1
                skippedLockedNotesByFolder[folderPath ?? folderName, default: 0] += 1
            }

            entries.append(
                AppleNotesSyncManifestEntry(
                    databaseNoteID: noteID,
                    sourceNoteIdentifier: row.string("sourceIdentifier"),
                    folderDatabaseID: folderDatabaseID,
                    name: row.string("title")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    folder: folderName,
                    folderPath: folderPath,
                    updatedAt: decodeAppleNotesTime(row.double("updatedAt")),
                    passwordProtected: isPasswordProtected,
                    trashed: isTrashed
                )
            )
        }

        return AppleNotesSyncManifest(
            folders: folderContext.summaries,
            entries: entries,
            skippedLockedNotes: skippedLockedNotes,
            skippedLockedNotesByFolder: skippedLockedNotesByFolder,
            sourceDiagnostics: nil
        )
    }

    func resolvedNoteTitle(databaseTitle: String?, noteText: String) -> String {
        let trimmedDatabaseTitle = databaseTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDatabaseTitle.isEmpty {
            return trimmedDatabaseTitle
        }

        let firstNonEmptyLine = noteText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? ""
        if !firstNonEmptyLine.isEmpty {
            return String(firstNonEmptyLine.prefix(120))
        }

        return "Untitled Note"
    }

    func documentSelectColumns(
        schema: AppleNotesDatabaseSchema,
        noteTitleColumn: String?,
        noteFolderExpressions: [String]
    ) -> [String] {
        var columns = [
            "nd.znote AS pk",
            "nd.zdata AS data",
            schema.columnExpression("zidentifier", tableAlias: "n", alias: "sourceIdentifier", defaultValue: "''"),
            schema.selectedColumnExpression(noteTitleColumn, tableAlias: "n", alias: "title", defaultValue: "''"),
        ]
        columns.append(contentsOf: noteFolderExpressions)
        columns.append(contentsOf: [
            schema.columnExpression("zcreationdate1", tableAlias: "n", alias: "createdAt1"),
            schema.columnExpression("zcreationdate2", tableAlias: "n", alias: "createdAt2"),
            schema.columnExpression("zcreationdate3", tableAlias: "n", alias: "createdAt3"),
            schema.columnExpression("zmodificationdate1", tableAlias: "n", alias: "updatedAt"),
            schema.columnExpression("zispasswordprotected", tableAlias: "n", alias: "passwordProtected", defaultValue: "0"),
            schema.columnExpression("zshared", tableAlias: "n", alias: "shared", defaultValue: "0"),
            schema.columnExpression("zowner", tableAlias: "n", alias: "ownerID", defaultValue: "0"),
        ])
        return columns
    }

    func resolvedFolderDatabaseID(
        in row: SQLiteRow,
        candidateColumnCount: Int,
        knownFolders: [Int64: AppleNotesResolvedFolder]
    ) -> Int64? {
        for index in 0 ..< candidateColumnCount {
            guard let candidateID = row.int("folderRef\(index)"),
                  knownFolders[candidateID] != nil
            else {
                continue
            }
            return candidateID
        }
        return nil
    }

    func resolveAttachmentReference(
        _ attachmentInfo: AppleNotesDecodedAttachmentInfo,
        database: SQLiteDatabase,
        schema: AppleNotesDatabaseSchema,
        selection: AppleNotesDataFolderSelection,
        ownerID: Int64?,
        noteReferenceMap: [String: AppleNotesResolvedNoteReference]
    ) throws -> AppleNotesAttachmentResolution {
        switch attachmentInfo.typeUti {
        case AppleNotesInlineAttachmentType.hashtag.rawValue, AppleNotesInlineAttachmentType.mention.rawValue:
            let row = try database.row(
                """
                SELECT \(schema.columnExpression("zalttext", alias: "altText", defaultValue: "''"))
                FROM ziccloudsyncingobject
                WHERE zidentifier = ?
                LIMIT 1
                """,
                bindings: [.text(attachmentInfo.attachmentIdentifier)]
            )
            return .inlineText(row?.string("altText") ?? "")

        case AppleNotesInlineAttachmentType.internalLink.rawValue:
            let row = try database.row(
                """
                SELECT \(schema.columnExpression("ztokencontentidentifier", alias: "token", defaultValue: "''"))
                FROM ziccloudsyncingobject
                WHERE zidentifier = ?
                LIMIT 1
                """,
                bindings: [.text(attachmentInfo.attachmentIdentifier)]
            )
            guard let token = row?.string("token"),
                  let identifier = token.appleNotesInternalLinkIdentifier
            else {
                return .inlineText("(unknown note link)")
            }
            let displayText = noteReferenceMap[identifier]?.displayText ?? "linked note"
            return .internalLink(
                AppleNotesSyncInternalLink(
                    token: attachmentInfo.attachmentIdentifier,
                    targetSourceIdentifier: identifier,
                    displayText: displayText
                )
            )

        case AppleNotesInlineAttachmentType.urlCard.rawValue:
            let row = try database.row(
                """
                SELECT
                    \(schema.columnExpression("ztitle", alias: "title", defaultValue: "''")),
                    \(schema.columnExpression("zurlstring", alias: "url", defaultValue: "''"))
                FROM ziccloudsyncingobject
                WHERE zidentifier = ?
                LIMIT 1
                """,
                bindings: [.text(attachmentInfo.attachmentIdentifier)]
            )
            let title = row?.string("title")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = row?.string("url")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if title.isEmpty {
                return .inlineText(url)
            }
            return .inlineText("[**\(title)**](\(url))")

        case AppleNotesInlineAttachmentType.table.rawValue:
            return try resolveTableAttachmentReference(
                attachmentInfo,
                database: database,
                schema: schema,
                selection: selection,
                ownerID: ownerID,
                noteReferenceMap: noteReferenceMap
            )

        case AppleNotesInlineAttachmentType.scan.rawValue:
            return try resolveScanAttachmentReference(
                attachmentInfo,
                database: database,
                schema: schema,
                selection: selection,
                ownerID: ownerID,
                noteReferenceMap: noteReferenceMap
            )

        case AppleNotesInlineAttachmentType.modifiedScan.rawValue,
             AppleNotesInlineAttachmentType.drawing.rawValue,
             AppleNotesInlineAttachmentType.drawingLegacy.rawValue,
             AppleNotesInlineAttachmentType.drawingLegacy2.rawValue:
            let row = try database.row(
                """
                SELECT z_pk AS pk
                FROM ziccloudsyncingobject
                WHERE zidentifier = ?
                LIMIT 1
                """,
                bindings: [.text(attachmentInfo.attachmentIdentifier)]
            )
            guard let attachmentRowID = row?.int("pk"),
                  let attachment = try resolvePhysicalAttachment(
                      attachmentRowID: attachmentRowID,
                      uti: attachmentInfo.typeUti,
                      database: database,
                      schema: schema,
                      selection: selection,
                      ownerID: ownerID
                  )
            else {
                return .inlineText("**(error reading attachment)**")
            }
            return .attachment(attachment, isBlock: true)

        default:
            let row = try database.row(
                """
                SELECT \(schema.columnExpression("zmedia", alias: "mediaID"))
                FROM ziccloudsyncingobject
                WHERE zidentifier = ?
                LIMIT 1
                """,
                bindings: [.text(attachmentInfo.attachmentIdentifier)]
            )
            guard let mediaID = row?.int("mediaID"),
                  let attachment = try resolvePhysicalAttachment(
                      attachmentRowID: mediaID,
                      uti: attachmentInfo.typeUti,
                      database: database,
                      schema: schema,
                      selection: selection,
                      ownerID: ownerID
                  )
            else {
                return .inlineText("**(unknown attachment: \(attachmentInfo.typeUti))**")
            }
            return .attachment(attachment, isBlock: !attachmentInfo.typeUti.contains("com.apple.notes.inlinetextattachment"))
        }
    }

    func resolvePhysicalAttachment(
        attachmentRowID: Int64,
        uti: String,
        database: SQLiteDatabase,
        schema: AppleNotesDatabaseSchema,
        selection: AppleNotesDataFolderSelection,
        ownerID: Int64?
    ) throws -> AppleNotesSyncAttachment? {
        switch uti {
        case AppleNotesInlineAttachmentType.scan.rawValue:
            let row = try database.row(
                """
                SELECT
                    \(schema.columnExpression("zidentifier", alias: "identifier", defaultValue: "''")),
                    \(schema.columnExpression("zsizeheight", alias: "height", defaultValue: "0")),
                    \(schema.columnExpression("zsizewidth", alias: "width", defaultValue: "0")),
                    \(schema.columnExpression("zmodificationdate", alias: "modifiedAt"))
                FROM ziccloudsyncingobject
                WHERE z_ent = ?
                  AND z_pk = ?
                LIMIT 1
                """,
                bindings: [
                    .int(schema.entityID(named: "ICAttachment")),
                    .int(attachmentRowID),
                ]
            )
            guard let identifier = row?.string("identifier"),
                  let width = row?.int("width"),
                  let height = row?.int("height")
            else {
                return nil
            }
            let sourcePath = "Previews/\(identifier)-1-\(width)x\(height)-0.jpeg"
            return makeAttachment(
                logicalIdentifier: "attachment-\(attachmentRowID)",
                sourcePath: sourcePath,
                preferredFilename: "Scan Page.jpg",
                uti: "public.image",
                selection: selection,
                ownerID: ownerID,
                modifiedAt: decodeAppleNotesTime(row?.double("modifiedAt"))
            )

        case AppleNotesInlineAttachmentType.modifiedScan.rawValue:
            let row = try database.row(
                """
                SELECT
                    \(schema.columnExpression("zidentifier", alias: "identifier", defaultValue: "''")),
                    \(schema.columnExpression("zfallbackpdfgeneration", alias: "generation", defaultValue: "''")),
                    \(schema.columnExpression("zmodificationdate", alias: "modifiedAt"))
                FROM ziccloudsyncingobject
                WHERE z_ent = ?
                  AND z_pk = ?
                LIMIT 1
                """,
                bindings: [
                    .int(schema.entityID(named: "ICAttachment")),
                    .int(attachmentRowID),
                ]
            )
            guard let identifier = row?.string("identifier") else { return nil }
            let generation = row?.string("generation") ?? ""
            let sourcePath = ["FallbackPDFs", identifier, generation, "FallbackPDF.pdf"]
                .filter { !$0.isEmpty }
                .joined(separator: "/")
            return makeAttachment(
                logicalIdentifier: "attachment-\(attachmentRowID)",
                sourcePath: sourcePath,
                preferredFilename: "Scan.pdf",
                uti: "com.adobe.pdf",
                selection: selection,
                ownerID: ownerID,
                modifiedAt: decodeAppleNotesTime(row?.double("modifiedAt"))
            )

        case AppleNotesInlineAttachmentType.drawing.rawValue,
             AppleNotesInlineAttachmentType.drawingLegacy.rawValue,
             AppleNotesInlineAttachmentType.drawingLegacy2.rawValue:
            let row = try database.row(
                """
                SELECT
                    \(schema.columnExpression("zidentifier", alias: "identifier", defaultValue: "''")),
                    \(schema.columnExpression("zfallbackimagegeneration", alias: "generation", defaultValue: "''")),
                    \(schema.columnExpression("zmodificationdate", alias: "modifiedAt"))
                FROM ziccloudsyncingobject
                WHERE z_ent = ?
                  AND z_pk = ?
                LIMIT 1
                """,
                bindings: [
                    .int(schema.entityID(named: "ICAttachment")),
                    .int(attachmentRowID),
                ]
            )
            guard let identifier = row?.string("identifier") else { return nil }
            let generation = row?.string("generation") ?? ""
            let sourcePath: String
            let preferredFilename: String
            if generation.isEmpty {
                sourcePath = "FallbackImages/\(identifier).jpg"
                preferredFilename = "Drawing.jpg"
            } else {
                sourcePath = "FallbackImages/\(identifier)/\(generation)/FallbackImage.png"
                preferredFilename = "Drawing.png"
            }
            return makeAttachment(
                logicalIdentifier: "attachment-\(attachmentRowID)",
                sourcePath: sourcePath,
                preferredFilename: preferredFilename,
                uti: "public.image",
                selection: selection,
                ownerID: ownerID,
                modifiedAt: decodeAppleNotesTime(row?.double("modifiedAt"))
            )

        default:
            let row = try database.row(
                """
                SELECT
                    media.z_pk AS mediaID,
                    \(schema.columnExpression("zidentifier", tableAlias: "media", alias: "identifier", defaultValue: "''")),
                    \(schema.columnExpression("zfilename", tableAlias: "media", alias: "filename", defaultValue: "''")),
                    \(schema.columnExpression("zgeneration1", tableAlias: "media", alias: "generation", defaultValue: "''")),
                    \(schema.columnExpression("zmodificationdate", tableAlias: "linkRow", alias: "modifiedAt")),
                    \(schema.columnExpression("znote", tableAlias: "linkRow", alias: "noteID"))
                FROM ziccloudsyncingobject AS media
                LEFT JOIN ziccloudsyncingobject AS linkRow ON linkRow.zmedia = media.z_pk
                WHERE media.z_ent = ?
                  AND media.z_pk = ?
                LIMIT 1
                """,
                bindings: [
                    .int(schema.entityID(named: "ICMedia")),
                    .int(attachmentRowID),
                ]
            )
            guard let identifier = row?.string("identifier"),
                  let filename = row?.string("filename"),
                  !filename.isEmpty
            else {
                return nil
            }

            let generation = row?.string("generation") ?? ""
            let sourcePath = ["Media", identifier, generation, filename]
                .filter { !$0.isEmpty }
                .joined(separator: "/")
            let resolvedOwnerID = row?.int("noteID").flatMap { _ in ownerID } ?? ownerID
            return makeAttachment(
                logicalIdentifier: "media-\(row?.int("mediaID") ?? attachmentRowID)",
                sourcePath: sourcePath,
                preferredFilename: filename,
                uti: uti,
                selection: selection,
                ownerID: resolvedOwnerID,
                modifiedAt: decodeAppleNotesTime(row?.double("modifiedAt"))
            )
        }
    }

    func resolveTableAttachmentReference(
        _ attachmentInfo: AppleNotesDecodedAttachmentInfo,
        database: SQLiteDatabase,
        schema: AppleNotesDatabaseSchema,
        selection: AppleNotesDataFolderSelection,
        ownerID: Int64?,
        noteReferenceMap: [String: AppleNotesResolvedNoteReference]
    ) throws -> AppleNotesAttachmentResolution {
        let row = try database.row(
            """
            SELECT \(schema.columnExpression("zmergeabledata1", alias: "mergeableData"))
            FROM ziccloudsyncingobject
            WHERE zidentifier = ?
            LIMIT 1
            """,
            bindings: [.text(attachmentInfo.attachmentIdentifier)]
        )
        guard let mergeableData = row?.data("mergeableData") else {
            return .fragment(
                AppleNotesRenderedFragment(
                    markdownTemplate: "\n**(error decoding Apple Notes table)**\n",
                    internalLinks: [],
                    attachments: [],
                    isBlock: true,
                    diagnostics: AppleNotesRenderDiagnostics(failedTableDecodes: 1)
                )
            )
        }

        do {
            let decoded = try mergeableDataDecoder.decode(from: mergeableData)
            let converter = AppleNotesTableConverter(mergeableData: decoded, renderer: renderer)
            guard let baseFragment = try converter.renderFragment(attachmentResolver: { nestedAttachmentInfo in
                try resolveAttachmentReference(
                    nestedAttachmentInfo,
                    database: database,
                    schema: schema,
                    selection: selection,
                    ownerID: ownerID,
                    noteReferenceMap: noteReferenceMap
                )
            }) else {
                throw AppleNotesNoteDecodingError.invalidProtobuf
            }
            return .fragment(baseFragment)
        } catch {
            AppLog.appleNotes.error(
                "Failed to decode Apple Notes table attachment \(attachmentInfo.attachmentIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return .fragment(
                AppleNotesRenderedFragment(
                    markdownTemplate: "\n**(error decoding Apple Notes table)**\n",
                    internalLinks: [],
                    attachments: [],
                    isBlock: true,
                    diagnostics: AppleNotesRenderDiagnostics(failedTableDecodes: 1)
                )
            )
        }
    }

    func resolveScanAttachmentReference(
        _ attachmentInfo: AppleNotesDecodedAttachmentInfo,
        database: SQLiteDatabase,
        schema: AppleNotesDatabaseSchema,
        selection: AppleNotesDataFolderSelection,
        ownerID: Int64?,
        noteReferenceMap _: [String: AppleNotesResolvedNoteReference]
    ) throws -> AppleNotesAttachmentResolution {
        let row = try database.row(
            """
            SELECT \(schema.columnExpression("zmergeabledata1", alias: "mergeableData"))
            FROM ziccloudsyncingobject
            WHERE zidentifier = ?
            LIMIT 1
            """,
            bindings: [.text(attachmentInfo.attachmentIdentifier)]
        )
        guard let mergeableData = row?.data("mergeableData") else {
            return .fragment(
                AppleNotesRenderedFragment(
                    markdownTemplate: "\n**(error decoding Apple Notes scan)**\n",
                    internalLinks: [],
                    attachments: [],
                    isBlock: true,
                    diagnostics: AppleNotesRenderDiagnostics(failedScanDecodes: 1)
                )
            )
        }

        do {
            let decoded = try mergeableDataDecoder.decode(from: mergeableData)
            let converter = AppleNotesScanGalleryConverter(mergeableData: decoded)
            let pageIdentifiers = converter.pageAttachmentIdentifiers()
            guard !pageIdentifiers.isEmpty else {
                throw AppleNotesNoteDecodingError.invalidProtobuf
            }

            var attachments: [AppleNotesSyncAttachment] = []
            var lines: [String] = []
            var failedPageCount = 0

            for pageIdentifier in pageIdentifiers {
                let pageRow = try database.row(
                    """
                    SELECT
                        z_pk AS pk,
                        \(schema.columnExpression("zmedia", alias: "mediaID")),
                        \(schema.columnExpression("ztypeuti", alias: "typeUti", defaultValue: "''"))
                    FROM ziccloudsyncingobject
                    WHERE zidentifier = ?
                    LIMIT 1
                    """,
                    bindings: [.text(pageIdentifier)]
                )
                let pageAttachment: AppleNotesSyncAttachment?
                if let attachmentRowID = pageRow?.int("pk") {
                    pageAttachment = try resolvePhysicalAttachment(
                        attachmentRowID: attachmentRowID,
                        uti: AppleNotesInlineAttachmentType.scan.rawValue,
                        database: database,
                        schema: schema,
                        selection: selection,
                        ownerID: ownerID
                    )
                } else {
                    pageAttachment = nil
                }

                let fallbackAttachment: AppleNotesSyncAttachment?
                if pageAttachment == nil,
                   let mediaID = pageRow?.int("mediaID"),
                   let typeUti = pageRow?.string("typeUti"),
                   !typeUti.isEmpty
                {
                    fallbackAttachment = try resolvePhysicalAttachment(
                        attachmentRowID: mediaID,
                        uti: typeUti,
                        database: database,
                        schema: schema,
                        selection: selection,
                        ownerID: ownerID
                    )
                } else {
                    fallbackAttachment = nil
                }

                if let resolvedAttachment = pageAttachment ?? fallbackAttachment {
                    attachments.append(resolvedAttachment)
                    lines.append("{{attachment:\(resolvedAttachment.token)}}")
                } else {
                    failedPageCount += 1
                    lines.append("**(error decoding scan page)**")
                }
            }

            if attachments.isEmpty {
                return .fragment(
                    AppleNotesRenderedFragment(
                        markdownTemplate: "\n**(error decoding Apple Notes scan)**\n",
                        internalLinks: [],
                        attachments: [],
                        isBlock: true,
                        diagnostics: AppleNotesRenderDiagnostics(failedScanDecodes: 1)
                    )
                )
            }

            var diagnostics = AppleNotesRenderDiagnostics()
            if failedPageCount > 0 {
                diagnostics.partialScanPageFailures = failedPageCount
            }

            return .fragment(
                AppleNotesRenderedFragment(
                    markdownTemplate: "\n" + lines.joined(separator: "\n") + "\n",
                    internalLinks: [],
                    attachments: attachments,
                    isBlock: true,
                    diagnostics: diagnostics
                )
            )
        } catch {
            AppLog.appleNotes.error(
                "Failed to decode Apple Notes scan attachment \(attachmentInfo.attachmentIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return .fragment(
                AppleNotesRenderedFragment(
                    markdownTemplate: "\n**(error decoding Apple Notes scan)**\n",
                    internalLinks: [],
                    attachments: [],
                    isBlock: true,
                    diagnostics: AppleNotesRenderDiagnostics(failedScanDecodes: 1)
                )
            )
        }
    }

    func makeAttachment(
        logicalIdentifier: String,
        sourcePath: String,
        preferredFilename: String,
        uti: String,
        selection: AppleNotesDataFolderSelection,
        ownerID: Int64?,
        modifiedAt: Date?
    ) -> AppleNotesSyncAttachment? {
        let candidateURLs = attachmentCandidateURLs(
            relativePath: sourcePath,
            selection: selection,
            ownerID: ownerID
        )
        guard let sourceURL = candidateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return nil
        }

        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey]
        let fileSize = (try? sourceURL.resourceValues(forKeys: resourceKeys).fileSize).map(Int64.init)
        return AppleNotesSyncAttachment(
            token: logicalIdentifier.replacingOccurrences(of: "/", with: "-"),
            logicalIdentifier: logicalIdentifier,
            sourceURL: sourceURL,
            preferredFilename: preferredFilename,
            renderStyle: renderStyle(for: uti, preferredFilename: preferredFilename),
            modifiedAt: modifiedAt,
            fileSize: fileSize
        )
    }

    func attachmentCandidateURLs(
        relativePath: String,
        selection: AppleNotesDataFolderSelection,
        ownerID: Int64?
    ) -> [URL] {
        let normalizedRelativePath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var urls: [URL] = []
        let accountsRootURL = selection.rootURL.appendingPathComponent("Accounts", isDirectory: true)
        if let accountDirectories = try? FileManager.default.contentsOfDirectory(
            at: accountsRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            urls.append(contentsOf: accountDirectories.map {
                $0.appendingPathComponent(normalizedRelativePath, isDirectory: false)
            })
        }
        urls.append(selection.rootURL.appendingPathComponent(normalizedRelativePath, isDirectory: false))
        return urls
    }

    func renderStyle(for uti: String, preferredFilename: String) -> AppleNotesAttachmentRenderStyle {
        let loweredUTI = uti.lowercased()
        let fileExtension = URL(fileURLWithPath: preferredFilename).pathExtension.lowercased()

        if loweredUTI.hasPrefix("public.image")
            || loweredUTI.hasPrefix("public.audio")
            || loweredUTI.hasPrefix("public.movie")
            || loweredUTI == "com.adobe.pdf"
            || ["png", "jpg", "jpeg", "gif", "heic", "pdf", "mp3", "m4a", "wav", "mov", "mp4"].contains(fileExtension)
        {
            return .embed
        }

        return .link
    }

    func decodeAppleNotesTime(_ value: Double?) -> Date? {
        guard let value, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value + 978_307_200)
    }
}

extension AppleNotesDatabaseSyncSource {
    func joinedSelectClause(_ columns: [String]) -> String {
        columns.joined(separator: ",\n                ")
    }
}

private struct AppleNotesDatabaseSchema {
    let entityKeys: [String: Int64]
    let cloudColumns: Set<String>

    init(entityKeys: [String: Int64], cloudColumns: Set<String>) {
        self.entityKeys = entityKeys
        self.cloudColumns = cloudColumns
    }

    init(database: SQLiteDatabase) throws {
        let entityRows = try database.rows("SELECT z_ent AS entityID, z_name AS name FROM z_primarykey")
        self.entityKeys = Dictionary(uniqueKeysWithValues: entityRows.compactMap { row in
            guard let name = row.string("name"), let entityID = row.int("entityID") else { return nil }
            return (name, entityID)
        })
        self.cloudColumns = Set(try database.columnNames(in: "ziccloudsyncingobject").map { $0.lowercased() })
    }

    func entityID(named name: String) throws -> Int64 {
        guard let entityID = entityKeys[name] else {
            throw AppleNotesSyncDataSourceError.missingDatabaseEntity(name)
        }
        return entityID
    }

    func columnExpression(
        _ column: String,
        tableAlias: String? = nil,
        alias: String,
        defaultValue: String = "NULL"
    ) -> String {
        guard cloudColumns.contains(column.lowercased()) else {
            return "\(defaultValue) AS \(alias)"
        }
        if let tableAlias {
            return "\(tableAlias).\(column) AS \(alias)"
        }
        return "\(column) AS \(alias)"
    }

    func selectedColumnExpression(
        _ column: String?,
        tableAlias: String? = nil,
        alias: String,
        defaultValue: String = "NULL"
    ) -> String {
        guard let column else {
            return "\(defaultValue) AS \(alias)"
        }
        return columnExpression(column, tableAlias: tableAlias, alias: alias, defaultValue: defaultValue)
    }

    func bestTextColumn(
        database: SQLiteDatabase,
        entityID: Int64,
        prefixes: [String]
    ) throws -> String? {
        let candidates = matchingColumns(prefixes: prefixes)
        guard !candidates.isEmpty else { return nil }

        var bestColumn: String?
        var bestCount = -1

        for candidate in candidates {
            let row = try database.row(
                """
                SELECT COUNT(*) AS matchCount
                FROM ziccloudsyncingobject
                WHERE z_ent = ?
                  AND TRIM(COALESCE(\(candidate), '')) != ''
                """,
                bindings: [.int(entityID)]
            )
            let count = Int(row?.int("matchCount") ?? 0)
            if count > bestCount {
                bestCount = count
                bestColumn = candidate
            }
        }

        return bestColumn ?? candidates.first
    }

    func preferredTextColumn(
        database: SQLiteDatabase,
        entityID: Int64,
        preferredColumns: [String],
        prefixes: [String]
    ) throws -> String? {
        for candidate in preferredColumns where cloudColumns.contains(candidate.lowercased()) {
            let row = try database.row(
                """
                SELECT COUNT(*) AS matchCount
                FROM ziccloudsyncingobject
                WHERE z_ent = ?
                  AND TRIM(COALESCE(\(candidate), '')) != ''
                """,
                bindings: [.int(entityID)]
            )
            if (row?.int("matchCount") ?? 0) > 0 {
                return candidate
            }
        }

        return try bestTextColumn(
            database: database,
            entityID: entityID,
            prefixes: prefixes
        )
    }

    func bestReferenceColumn(
        database: SQLiteDatabase,
        entityID: Int64,
        targetValues: [Int64],
        prefixes: [String]
    ) throws -> String? {
        let candidates = matchingColumns(prefixes: prefixes)
        guard !candidates.isEmpty, !targetValues.isEmpty else { return nil }

        let placeholders = Array(repeating: "?", count: targetValues.count).joined(separator: ", ")
        var bestColumn: String?
        var bestCount = -1

        for candidate in candidates {
            let row = try database.row(
                """
                SELECT COUNT(*) AS matchCount
                FROM ziccloudsyncingobject
                WHERE z_ent = ?
                  AND \(candidate) IN (\(placeholders))
                """,
                bindings: [.int(entityID)] + targetValues.map(SQLiteBinding.int)
            )
            let count = Int(row?.int("matchCount") ?? 0)
            if count > bestCount {
                bestCount = count
                bestColumn = candidate
            }
        }

        return bestCount > 0 ? bestColumn : nil
    }

    func preferredReferenceColumn(
        database: SQLiteDatabase,
        entityID: Int64,
        preferredColumns: [String],
        targetValues: [Int64],
        prefixes: [String]
    ) throws -> String? {
        guard !targetValues.isEmpty else { return nil }

        let placeholders = Array(repeating: "?", count: targetValues.count).joined(separator: ", ")
        for candidate in preferredColumns where cloudColumns.contains(candidate.lowercased()) {
            let row = try database.row(
                """
                SELECT COUNT(*) AS matchCount
                FROM ziccloudsyncingobject
                WHERE z_ent = ?
                  AND \(candidate) IN (\(placeholders))
                """,
                bindings: [.int(entityID)] + targetValues.map(SQLiteBinding.int)
            )
            if (row?.int("matchCount") ?? 0) > 0 {
                return candidate
            }
        }

        return try bestReferenceColumn(
            database: database,
            entityID: entityID,
            targetValues: targetValues,
            prefixes: prefixes
        )
    }

    func existingColumns(
        preferredColumns: [String],
        prefixes: [String]
    ) -> [String] {
        let preferredMatches = preferredColumns.filter { cloudColumns.contains($0.lowercased()) }
        let remainingMatches = matchingColumns(prefixes: prefixes).filter { column in
            !preferredMatches.contains(column)
        }
        return preferredMatches + remainingMatches
    }

    func presentColumns(_ columns: [String]) -> [String] {
        columns.filter { cloudColumns.contains($0.lowercased()) }
    }

    private func matchingColumns(prefixes: [String]) -> [String] {
        cloudColumns
            .filter { column in
                prefixes.contains { prefix in
                    column.hasPrefix(prefix)
                }
            }
            .sorted()
    }
}

private struct AppleNotesFolderContext {
    var summaries: [AppleNotesFolder]
    var foldersByID: [Int64: AppleNotesResolvedFolder]
    var summariesByDatabaseID: [Int64: AppleNotesFolder]
    var accountsByID: [Int64: AppleNotesResolvedAccount]
    var folderTitleColumn: String?
    var noteFolderColumn: String?
}

private struct AppleNotesResolvedFolder {
    var databaseID: Int64
    var title: String
    var parentID: Int64?
    var folderType: Int
    var ownerID: Int64?
    var identifier: String
}

private struct AppleNotesResolvedAccount {
    var databaseID: Int64
    var name: String
    var identifier: String
}

private struct AppleNotesDocumentLoadResult {
    var documents: [AppleNotesSyncDocument]
    var skippedLockedNotes: Int
    var skippedLockedNotesByFolder: [String: Int]
    var folderReferenceStats: [AppleNotesFolderReferenceStat]
    var failedTableDecodes: Int
    var failedScanDecodes: Int
    var partialScanPageFailures: Int
}

struct AppleNotesFolderReferenceStat {
    var columnName: String
    var nonNullCount: Int
    var matchedFolderCount: Int
}

struct AppleNotesDatabaseCandidateScan {
    var candidateURLs: [URL]
    var rootCandidatePresent: Bool
    var accountsDirectoryExists: Bool
    var accountsIsDirectory: Bool
    var localAccountCandidatePresent: Bool
    var rootEntries: [String]
    var accountDirectoryNames: [String]
    var accountsEnumerationError: String?
}

private struct AppleNotesResolvedNoteReference {
    var databaseNoteID: Int64?
    var sourceIdentifier: String
    var displayText: String
}

struct AppleNotesDatabaseCandidateReport {
    var rootURL: URL
    var databaseURL: URL
    var folderCount: Int
    var totalNoteCount: Int
    var documentCount: Int
    var skippedLockedNotes: Int
    var folderTitleColumn: String?
    var noteTitleColumn: String?
    var noteFolderColumn: String?
    var folderReferenceStats: [AppleNotesFolderReferenceStat]

    var summary: String {
        let relativePath = databaseURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        let referenceSummary = folderReferenceStats.isEmpty
            ? "none"
            : folderReferenceStats
                .map { "\($0.columnName)=\($0.matchedFolderCount)/\($0.nonNullCount)" }
                .joined(separator: ";")
        return "\(relativePath) [folders=\(folderCount), notes=\(totalNoteCount), docs=\(documentCount), locked=\(skippedLockedNotes), folderTitle=\(folderTitleColumn ?? "nil"), noteTitle=\(noteTitleColumn ?? "nil"), noteFolder=\(noteFolderColumn ?? "nil"), refs=\(referenceSummary)]"
    }

    var containsVisibleNotes: Bool {
        documentCount > 0 || totalNoteCount > 0 || folderCount > 0
    }
}

private enum AppleNotesFolderType: Int {
    case `default` = 0
    case trash = 1
    case smart = 3
}

private enum AppleNotesInlineAttachmentType: String {
    case hashtag = "com.apple.notes.inlinetextattachment.hashtag"
    case mention = "com.apple.notes.inlinetextattachment.mention"
    case internalLink = "com.apple.notes.inlinetextattachment.link"
    case modifiedScan = "com.apple.paper.doc.scan"
    case scan = "com.apple.notes.gallery"
    case table = "com.apple.notes.table"
    case drawing = "com.apple.paper"
    case drawingLegacy = "com.apple.drawing"
    case drawingLegacy2 = "com.apple.drawing.2"
    case urlCard = "public.url"
}
