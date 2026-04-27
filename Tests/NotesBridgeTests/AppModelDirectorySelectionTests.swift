import AppKit
import Foundation
import Testing
@testable import NotesBridge

struct AppModelDirectorySelectionTests {
    @MainActor
    @Test
    func vaultChooserPersistsSelectedPathAndStatusMessage() throws {
        let vaultURL = try makeTemporaryDirectory(named: "vault")
        defer { try? FileManager.default.removeItem(at: vaultURL.deletingLastPathComponent()) }

        let model = AppModel(
            appleNotesSyncDataSource: DirectorySelectionDataSource(),
            appleNotesDataFolderSelector: StubAppleNotesDataFolderSelector(url: nil),
            vaultDirectorySelector: StubVaultDirectorySelector(url: vaultURL),
            persistence: DirectorySelectionPersistenceStore(),
            appUpdater: NoOpAppUpdater(version: AppVersion(shortVersionString: "0.2.10", buildNumber: "1")),
            startImmediately: false
        )

        model.chooseVaultDirectory()

        #expect(model.settings.vaultPath == vaultURL.path)
        #expect(model.statusMessage == "Obsidian vault set to vault.")
    }

    @MainActor
    @Test
    func vaultChooserDoesNothingWhenSelectionIsCancelled() {
        let model = AppModel(
            appleNotesSyncDataSource: DirectorySelectionDataSource(),
            appleNotesDataFolderSelector: StubAppleNotesDataFolderSelector(url: nil),
            vaultDirectorySelector: StubVaultDirectorySelector(url: nil),
            persistence: DirectorySelectionPersistenceStore(),
            appUpdater: NoOpAppUpdater(version: AppVersion(shortVersionString: "0.2.10", buildNumber: "1")),
            startImmediately: false
        )

        model.chooseVaultDirectory()

        #expect(model.settings.vaultPath == nil)
        #expect(model.statusMessage == "Ready")
    }

    @MainActor
    @Test
    func appleNotesChooserPersistsValidatedSelectionAndBookmark() throws {
        let dataFolderURL = try makeTemporaryDirectory(named: "group.com.apple.notes")
        defer { try? FileManager.default.removeItem(at: dataFolderURL.deletingLastPathComponent()) }

        let model = AppModel(
            appleNotesSyncDataSource: DirectorySelectionDataSource(),
            appleNotesDataFolderSelector: StubAppleNotesDataFolderSelector(url: dataFolderURL),
            vaultDirectorySelector: StubVaultDirectorySelector(url: nil),
            persistence: DirectorySelectionPersistenceStore(),
            appUpdater: NoOpAppUpdater(version: AppVersion(shortVersionString: "0.2.10", buildNumber: "1")),
            startImmediately: false
        )

        model.chooseAppleNotesDataFolder()

        #expect(model.settings.appleNotesDataPath == dataFolderURL.path)
        #expect(model.settings.appleNotesDataBookmark != nil)
        #expect(model.statusMessage == "Apple Notes data folder set to group.com.apple.notes.")
    }

    @MainActor
    @Test
    func appleNotesChooserDoesNothingWhenSelectionIsCancelled() {
        let model = AppModel(
            appleNotesSyncDataSource: DirectorySelectionDataSource(),
            appleNotesDataFolderSelector: StubAppleNotesDataFolderSelector(url: nil),
            vaultDirectorySelector: StubVaultDirectorySelector(url: nil),
            persistence: DirectorySelectionPersistenceStore(),
            appUpdater: NoOpAppUpdater(version: AppVersion(shortVersionString: "0.2.10", buildNumber: "1")),
            startImmediately: false
        )

        model.chooseAppleNotesDataFolder()

        #expect(model.settings.appleNotesDataPath == nil)
        #expect(model.settings.appleNotesDataBookmark == nil)
        #expect(model.statusMessage == "Ready")
    }

    @MainActor
    @Test
    func directoryPanelTemporarilyPromotesAccessoryAppAndRestoresIt() {
        let application = RecordingDirectoryPanelApplication(initialPolicy: .accessory)
        let panel = AppKitDirectoryPanel(application: application) { _ in .cancel }

        _ = panel.chooseDirectory(
            title: "Choose Folder",
            prompt: "Use Folder",
            canCreateDirectories: false
        )

        #expect(application.events == [
            .setActivationPolicy(.regular),
            .activateIgnoringOtherApps,
            .bringDirectoryPanelParentWindowForward,
            .setActivationPolicy(.accessory),
        ])
    }

    @MainActor
    @Test
    func directoryPanelDoesNotRestorePolicyWhenAppIsAlreadyRegular() {
        let application = RecordingDirectoryPanelApplication(initialPolicy: .regular)
        let panel = AppKitDirectoryPanel(application: application) { _ in .cancel }

        _ = panel.chooseDirectory(
            title: "Choose Folder",
            prompt: "Use Folder",
            canCreateDirectories: false
        )

        #expect(application.events == [
            .activateIgnoringOtherApps,
            .bringDirectoryPanelParentWindowForward,
        ])
    }
}

private func makeTemporaryDirectory(named name: String) throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("NotesBridge-DirectorySelection-\(UUID().uuidString)", isDirectory: true)
    let directoryURL = rootURL.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

@MainActor
private struct StubVaultDirectorySelector: VaultDirectorySelecting {
    let url: URL?

    func chooseVaultDirectory(title: String, prompt: String) -> URL? {
        url
    }
}

@MainActor
private struct StubAppleNotesDataFolderSelector: AppleNotesDataFolderSelecting {
    let url: URL?

    func chooseAppleNotesDataFolder() -> URL? {
        url
    }
}

private struct DirectorySelectionPersistenceStore: PersistenceStoring {
    func loadSettings() -> AppSettings {
        AppSettings.default
    }

    func saveSettings(_ settings: AppSettings) throws {}

    func loadSyncIndex() -> SyncIndex {
        SyncIndex()
    }

    func saveSyncIndex(_ index: SyncIndex) throws {}
}

private struct DirectorySelectionDataSource: AppleNotesSyncDataSourcing {
    func validateDataFolder(at path: String) throws -> AppleNotesDataFolderSelection {
        .resolved(rootPath: path, databaseRelativePath: "NoteStore.sqlite")
    }

    func inspectDataFolder(at path: String) -> AppleNotesDataFolderAccessStatus {
        AppleNotesDataFolderAccessStatus(
            level: .accessible,
            message: "The configured Apple Notes data folder is readable."
        )
    }

    func fetchFolders(fromDataFolder path: String) throws -> [AppleNotesFolder] {
        []
    }

    func loadManifest(fromDataFolder path: String) throws -> AppleNotesSyncManifest {
        AppleNotesSyncManifest(
            folders: [],
            entries: [],
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:],
            sourceDiagnostics: nil,
            selectedDatabaseRelativePath: nil
        )
    }

    func loadDocuments(
        fromDataFolder path: String,
        noteIDs: Set<Int64>,
        preferredDatabaseRelativePath: String?
    ) throws -> AppleNotesSyncSnapshot {
        AppleNotesSyncSnapshot(
            folders: [],
            documents: [],
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:]
        )
    }

    func loadSnapshot(fromDataFolder path: String) throws -> AppleNotesSyncSnapshot {
        AppleNotesSyncSnapshot(
            folders: [],
            documents: [],
            skippedLockedNotes: 0,
            skippedLockedNotesByFolder: [:]
        )
    }
}

@MainActor
private final class RecordingDirectoryPanelApplication: AppKitDirectoryPanelApplication {
    private var policy: NSApplication.ActivationPolicy
    private(set) var events: [Event] = []

    init(initialPolicy: NSApplication.ActivationPolicy) {
        self.policy = initialPolicy
    }

    func currentActivationPolicy() -> NSApplication.ActivationPolicy {
        policy
    }

    @discardableResult
    func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) -> Bool {
        events.append(.setActivationPolicy(policy))
        self.policy = policy
        return true
    }

    func activateIgnoringOtherApps() {
        events.append(.activateIgnoringOtherApps)
    }

    func bringDirectoryPanelParentWindowForward() {
        events.append(.bringDirectoryPanelParentWindowForward)
    }

    enum Event: Equatable {
        case setActivationPolicy(NSApplication.ActivationPolicy)
        case activateIgnoringOtherApps
        case bringDirectoryPanelParentWindowForward
    }
}
