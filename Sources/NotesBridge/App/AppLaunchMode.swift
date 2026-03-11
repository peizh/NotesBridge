import Foundation

enum AppLaunchMode {
    case normal
    case uiTesting(UITestConfiguration)

    static let current = makeCurrent()

    var isUITesting: Bool {
        if case .uiTesting = self {
            return true
        }
        return false
    }

    var uiTestConfiguration: UITestConfiguration? {
        if case let .uiTesting(configuration) = self {
            return configuration
        }
        return nil
    }

    private static func makeCurrent() -> AppLaunchMode {
        guard let configuration = UITestConfiguration(environment: ProcessInfo.processInfo.environment) else {
            return .normal
        }
        return .uiTesting(configuration)
    }
}

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let launchMode: AppLaunchMode
    let appModel: AppModel
    let uiTestRecorder: UITestArtifactRecorder?

    private init() {
        let launchMode = AppLaunchMode.current
        let uiTestRecorder = launchMode.uiTestConfiguration.map(UITestArtifactRecorder.init)
        self.launchMode = launchMode
        self.uiTestRecorder = uiTestRecorder
        self.appModel = AppModelFactory.make(for: launchMode, uiTestRecorder: uiTestRecorder)
    }
}

struct UITestConfiguration: Sendable {
    let automationAction: UITestAutomationAction?
    let rootURL: URL
    let vaultURL: URL
    let appleNotesDataURL: URL
    let statusFileURL: URL
    let windowReadyFileURL: URL

    init?(environment: [String: String]) {
        guard environment["NOTESBRIDGE_UI_TEST_MODE"] == "1" else {
            return nil
        }

        let rootPath = environment["NOTESBRIDGE_UI_TEST_ROOT"]
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("NotesBridge-UITests", isDirectory: true)
                .path
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL

        self.automationAction = environment["NOTESBRIDGE_UI_TEST_AUTORUN"]
            .flatMap(UITestAutomationAction.init(rawValue:))
        self.rootURL = rootURL
        self.vaultURL = rootURL.appendingPathComponent("vault", isDirectory: true)
        self.appleNotesDataURL = rootURL.appendingPathComponent("group.com.apple.notes", isDirectory: true)
        self.statusFileURL = rootURL.appendingPathComponent("ui-test-status.txt", isDirectory: false)
        self.windowReadyFileURL = rootURL.appendingPathComponent("ui-test-window-ready", isDirectory: false)
    }

    var settings: AppSettings {
        var settings = AppSettings.default
        settings.vaultPath = vaultURL.path
        settings.appleNotesDataPath = appleNotesDataURL.path
        settings.enableInlineEnhancements = false
        settings.enableFormattingBar = false
        settings.enableMarkdownTriggers = false
        settings.enableSlashCommands = false
        return settings
    }
}

@MainActor
enum AppModelFactory {
    static func make(
        for launchMode: AppLaunchMode,
        uiTestRecorder: UITestArtifactRecorder?
    ) -> AppModel {
        switch launchMode {
        case .normal:
            AppModel()
        case let .uiTesting(configuration):
            AppModel(
                notesClient: UITestAppleNotesClient(),
                appleNotesSyncDataSource: UITestAppleNotesSyncDataSource(),
                appleNotesDataFolderSelector: UITestAppleNotesDataFolderSelector(
                    url: configuration.appleNotesDataURL
                ),
                syncEngine: SyncEngine(),
                persistence: UITestPersistenceStore(settings: configuration.settings),
                statusObserver: { statusMessage in
                    uiTestRecorder?.recordStatus(statusMessage)
                },
                startImmediately: true
            )
        }
    }
}

enum UITestAutomationAction: String, Sendable {
    case syncAllNotes = "sync-all-notes"
}

@MainActor
final class UITestArtifactRecorder {
    private let statusFileURL: URL
    private let windowReadyFileURL: URL

    init(configuration: UITestConfiguration) {
        self.statusFileURL = configuration.statusFileURL
        self.windowReadyFileURL = configuration.windowReadyFileURL
    }

    func recordWindowReady() {
        FileManager.default.createFile(atPath: windowReadyFileURL.path, contents: Data())
    }

    func recordStatus(_ statusMessage: String) {
        try? statusMessage.write(to: statusFileURL, atomically: true, encoding: .utf8)
    }
}

private struct UITestPersistenceStore: PersistenceStoring {
    let settings: AppSettings

    func loadSettings() -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) throws {}

    func loadSyncIndex() -> SyncIndex {
        SyncIndex()
    }

    func saveSyncIndex(_ index: SyncIndex) throws {}
}

@MainActor
private struct UITestAppleNotesDataFolderSelector: AppleNotesDataFolderSelecting {
    let url: URL

    func chooseAppleNotesDataFolder() -> URL? {
        url
    }
}

private struct UITestAppleNotesClient: AppleNotesClient {
    func fetchFolders() throws -> [AppleNotesFolder] {
        UITestFixtures.folders
    }

    func fetchNoteSummaries(inFolderID folderID: String) throws -> [AppleNoteSummary] {
        []
    }

    func fetchDocuments(inFolderID folderID: String) throws -> [AppleNoteDocument] {
        []
    }

    func fetchDocument(id noteID: String, inFolderID folderID: String) throws -> AppleNoteDocument {
        throw AppleNotesError.invalidResponse
    }

    func updateNote(id: String, htmlBody: String) throws {}
}

private struct UITestAppleNotesSyncDataSource: AppleNotesSyncDataSourcing {
    func validateDataFolder(at path: String) throws -> AppleNotesDataFolderSelection {
        AppleNotesDataFolderSelection.resolved(rootPath: path, databaseRelativePath: "NoteStore.sqlite")
    }

    func fetchFolders(fromDataFolder path: String) throws -> [AppleNotesFolder] {
        UITestFixtures.folders
    }

    func loadSnapshot(fromDataFolder path: String) throws -> AppleNotesSyncSnapshot {
        AppleNotesSyncSnapshot(
            folders: UITestFixtures.folders,
            documents: UITestFixtures.documents,
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:]
        )
    }
}

private enum UITestFixtures {
    static let inboxFolder = AppleNotesFolder(
        id: "apple-notes-db://folder/1",
        name: "Inbox",
        accountName: nil,
        noteCount: 2
    )

    static let specsFolder = AppleNotesFolder(
        id: "apple-notes-db://folder/2",
        name: "Specs",
        accountName: nil,
        noteCount: 1,
        relativePath: "Projects/Specs"
    )

    static let folders = [
        inboxFolder,
        specsFolder,
    ]

    static let documents = [
        AppleNotesSyncDocument(
            databaseNoteID: 101,
            folderDatabaseID: 1,
            name: "First Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "First body",
            attachments: []
        ),
        AppleNotesSyncDocument(
            databaseNoteID: 102,
            folderDatabaseID: 1,
            name: "Second Note",
            folder: "Inbox",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "Second body",
            attachments: []
        ),
        AppleNotesSyncDocument(
            databaseNoteID: 201,
            folderDatabaseID: 2,
            name: "Roadmap",
            folder: "Specs",
            folderPath: "Projects/Specs",
            createdAt: nil,
            updatedAt: nil,
            shared: false,
            passwordProtected: false,
            markdownTemplate: "Roadmap body",
            attachments: []
        ),
    ]
}
