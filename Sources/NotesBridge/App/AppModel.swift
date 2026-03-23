import AppKit
import Combine
import Foundation
import OSLog

private struct AppleNotesDataFolderAccessSession {
    let url: URL
    private let stopAccessingImpl: @Sendable () -> Void

    init(url: URL, stopAccessingImpl: @escaping @Sendable () -> Void) {
        self.url = url
        self.stopAccessingImpl = stopAccessingImpl
    }

    func stopAccessing() {
        stopAccessingImpl()
    }
}

private func makeAppleNotesDataFolderAccessSession(
    path: String?,
    bookmarkData: Data?
) -> AppleNotesDataFolderAccessSession? {
    if let bookmarkData {
        AppLog.access.debug("Resolving Apple Notes bookmark. bytes=\(bookmarkData.count)")
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            AppLog.access.info(
                "Resolved Apple Notes bookmark to \(url.path, privacy: .public); stale=\(isStale)"
            )
            let startedAccessing = url.startAccessingSecurityScopedResource()
            AppLog.access.info(
                "startAccessingSecurityScopedResource(bookmark) for \(url.path, privacy: .public) -> \(startedAccessing)"
            )
            return AppleNotesDataFolderAccessSession(url: url) {
                if startedAccessing {
                    url.stopAccessingSecurityScopedResource()
                    AppLog.access.debug(
                        "Stopped Apple Notes security-scoped access for \(url.path, privacy: .public)"
                    )
                }
            }
        } catch {
            AppLog.access.error(
                "Failed to resolve Apple Notes bookmark: \(error.localizedDescription, privacy: .public)"
            )
            // Fall through to path-based access below.
        }
    }

    guard let path,
          !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        return nil
    }

    let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    let startedAccessing = url.startAccessingSecurityScopedResource()
    AppLog.access.info(
        "Using path-based Apple Notes access for \(url.path, privacy: .public); startAccessingSecurityScopedResource -> \(startedAccessing)"
    )
    return AppleNotesDataFolderAccessSession(url: url) {
        if startedAccessing {
            url.stopAccessingSecurityScopedResource()
            AppLog.access.debug(
                "Stopped path-based Apple Notes access for \(url.path, privacy: .public)"
            )
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            persistSettings()
            notesContextMonitor.updateSettings(settings)
            refreshAppleNotesDataAccessStatus()
            formattingBarController.update(
                selectionContext: selectionContext,
                availability: interactionAvailability,
                commands: visibleInlineToolbarCommands,
                localization: localization
            )
        }
    }

    @Published private(set) var buildFlavor: BuildFlavor
    @Published private(set) var interactionAvailability: InteractionAvailability
    @Published private(set) var folderSummaries: [AppleNotesFolder] = []
    @Published private(set) var selectionContext: SelectionContext?
    @Published private(set) var isRefreshingFolders = false
    @Published private(set) var isSyncing = false
    @Published private(set) var menuBarSyncFrameIndex = 0
    @Published private(set) var syncProgress: SyncProgress?
    @Published private(set) var slashKeyboardNavigationAvailable = true
    @Published private(set) var slashDiagnostics: [String] = []
    @Published private(set) var appleNotesDataAccessStatus: AppleNotesDataFolderAccessStatus?
    @Published private(set) var updateState: AppUpdateState
    @Published var errorMessage: String?
    @Published var statusMessage = "Ready" {
        didSet {
            statusObserver?(statusMessage)
        }
    }

    private let notesClient: any AppleNotesClient
    private let appleNotesSyncDataSource: any AppleNotesSyncDataSourcing
    private let appleNotesDataFolderSelector: any AppleNotesDataFolderSelecting
    private let syncEngine: any Syncing
    private let vaultClient: ObsidianVaultClient
    private let bundledAppLauncher: BundledAppLauncher
    private let persistence: any PersistenceStoring
    private let appUpdater: any AppUpdating
    private let permissionsManager: PermissionsManager
    private let notesContextMonitor: NotesContextMonitor
    private let formattingCommandExecutor: FormattingCommandExecutor
    private let markdownTriggerEngine: MarkdownTriggerEngine
    private let slashCommandEngine: SlashCommandEngine
    private let formattingBarController: FloatingFormattingBarController
    private let statusObserver: (@MainActor @Sendable (String) -> Void)?
    private var syncIndex: SyncIndex
    private var syncAnimationCancellable: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []

    init(
        notesClient: any AppleNotesClient = AppleNotesScriptClient(),
        appleNotesSyncDataSource: any AppleNotesSyncDataSourcing = AppleNotesDatabaseSyncSource(),
        appleNotesDataFolderSelector: any AppleNotesDataFolderSelecting = AppleNotesDataFolderSelector(),
        syncEngine: any Syncing = SyncEngine(),
        vaultClient: ObsidianVaultClient = ObsidianVaultClient(),
        bundledAppLauncher: BundledAppLauncher = BundledAppLauncher(),
        persistence: any PersistenceStoring = PersistenceStore(),
        buildFlavor: BuildFlavor = .current,
        appUpdater: (any AppUpdating)? = nil,
        permissionsManager: PermissionsManager = PermissionsManager(),
        statusObserver: (@MainActor @Sendable (String) -> Void)? = nil,
        startImmediately: Bool = true
    ) {
        let resolvedBuildFlavor = buildFlavor
        self.notesClient = notesClient
        self.appleNotesSyncDataSource = appleNotesSyncDataSource
        self.appleNotesDataFolderSelector = appleNotesDataFolderSelector
        self.syncEngine = syncEngine
        self.vaultClient = vaultClient
        self.bundledAppLauncher = bundledAppLauncher
        self.persistence = persistence
        let resolvedAppUpdater = appUpdater ?? AppUpdaterFactory.make(buildFlavor: resolvedBuildFlavor)
        self.appUpdater = resolvedAppUpdater
        self.permissionsManager = permissionsManager
        self.buildFlavor = resolvedBuildFlavor
        self.updateState = resolvedAppUpdater.currentState

        let loadedSettings = persistence.loadSettings()
        let loadedSyncIndex = persistence.loadSyncIndex()
        let notesContextMonitor = NotesContextMonitor(
            buildFlavor: resolvedBuildFlavor,
            permissionsManager: permissionsManager,
            settings: loadedSettings
        )
        let formattingCommandExecutor = FormattingCommandExecutor()
        let markdownTriggerEngine = MarkdownTriggerEngine(
            contextMonitor: notesContextMonitor,
            executor: formattingCommandExecutor
        )
        let slashCommandEngine = SlashCommandEngine(
            contextMonitor: notesContextMonitor,
            executor: formattingCommandExecutor
        )
        let formattingBarController = FloatingFormattingBarController(executor: formattingCommandExecutor)

        self.settings = loadedSettings
        self.syncIndex = loadedSyncIndex
        self.notesContextMonitor = notesContextMonitor
        self.formattingCommandExecutor = formattingCommandExecutor
        self.markdownTriggerEngine = markdownTriggerEngine
        self.slashCommandEngine = slashCommandEngine
        self.formattingBarController = formattingBarController
        self.statusObserver = statusObserver
        self.interactionAvailability = .default(for: resolvedBuildFlavor)
        self.slashCommandEngine.onKeyboardNavigationAvailabilityChanged = { [weak self] isAvailable in
            self?.slashKeyboardNavigationAvailable = isAvailable
        }
        self.slashCommandEngine.onDiagnosticsChanged = { [weak self] diagnostics in
            self?.slashDiagnostics = diagnostics
        }
        self.slashCommandEngine.localizationProvider = { [weak self] in
            self?.localization ?? AppLocalization(language: .system)
        }
        self.slashCommandEngine.catalogProvider = { [weak self] in
            self?.visibleSlashCommandCatalog ?? SlashCommandCatalog()
        }

        bindInteractionState()
        self.statusObserver?(statusMessage)
        if startImmediately {
            start()
        }
    }

    var hasVaultConfigured: Bool {
        settings.hasValidVaultPath
    }

    var hasAppleNotesDataFolderConfigured: Bool {
        guard let appleNotesDataPath = settings.appleNotesDataPath else { return false }
        return !appleNotesDataPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var appleNotesDataAccessLabel: String {
        switch appleNotesDataAccessStatus?.level {
        case .accessible:
            return t("Accessible")
        case .limited:
            return t("Limited")
        case .invalid:
            return t("Invalid")
        case nil:
            return t("Not configured")
        }
    }

    var localizedBuildFlavorTitle: String {
        t(buildFlavor.title)
    }

    var showsAppUpdateSettings: Bool {
        updateState.isEnabled
    }

    var currentAppVersion: String {
        updateState.currentVersion.shortVersionString
    }

    var currentAppBuildNumber: String {
        updateState.currentVersion.buildNumber
    }

    var currentAppVersionDisplay: String {
        let buildNumber = currentAppBuildNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !buildNumber.isEmpty else {
            return currentAppVersion
        }
        return "\(currentAppVersion) (\(buildNumber))"
    }

    var canCheckForUpdates: Bool {
        updateState.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        updateState.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        updateState.automaticallyDownloadsUpdates
    }

    var syncedNoteCount: Int {
        syncIndex.records.count
    }

    var isRunningBundledApp: Bool {
        bundledAppLauncher.isRunningBundledApp
    }

    var lastFullSyncLabel: String {
        guard let lastFullSyncAt = syncIndex.lastFullSyncAt else { return t("Never") }
        return lastFullSyncAt.formatted(date: .abbreviated, time: .shortened)
    }

    var indexedFolderCount: Int {
        syncIndex.lastFullSyncFolderCount ?? folderSummaries.count
    }

    var selectionSummary: String {
        guard let selectionContext, selectionContext.hasSelection else {
            return t("No text selected")
        }

        let snippet = selectionContext.selectedText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return snippet.isEmpty ? t("Selected text ready") : snippet
    }

    var visibleInlineToolbarCommands: [FormattingCommand] {
        settings.inlineToolbarItems
            .filter(\.isVisible)
            .map(\.command)
    }

    var visibleSlashCommandCatalog: SlashCommandCatalog {
        SlashCommandCatalog(itemSettings: settings.slashCommandItems)
    }

    var menuBarSymbolName: String {
        if isSyncing {
            return "arrow.triangle.2.circlepath"
        }
        if interactionAvailability.canShowFormattingBar {
            return "text.cursor"
        }
        if interactionAvailability.supportsInlineEnhancements && !interactionAvailability.accessibilityGranted {
            return "exclamationmark.circle"
        }
        return "note.text.badge.plus"
    }

    var slashCommandsSummary: String {
        if !buildFlavor.supportsInlineEnhancements {
            return t("Slash commands are unavailable in the Mac App Store build.")
        }
        if !settings.enableInlineEnhancements {
            return t("Slash commands are disabled with inline enhancements.")
        }
        if !settings.enableSlashCommands {
            return t("Slash commands are turned off in Settings.")
        }
        if visibleSlashCommandCatalog.entries.isEmpty {
            return t("No slash commands are enabled in Settings.")
        }
        if !interactionAvailability.accessibilityGranted {
            if isRunningBundledApp {
                return t("Accessibility permission is required for slash commands. If NotesBridge is already checked in Accessibility, remove and re-add the current app bundle once.")
            }
            return t("Accessibility permission is required for slash commands.")
        }
        if !interactionAvailability.notesIsFrontmost {
            return t("Bring Apple Notes to the front to use slash commands.")
        }
        if !interactionAvailability.editableFocus {
            return t("Focus the Apple Notes editor to use slash commands.")
        }
        if !slashKeyboardNavigationAvailable {
            return t("Slash commands are active. Use the mouse, or complete an exact slash command and press Space.")
        }
        return t("Type / for suggestions, or complete a slash command and press Space.")
    }

    var inlineEnhancementsSummary: String {
        if !buildFlavor.supportsInlineEnhancements {
            return t("Inline enhancements are disabled in the Mac App Store build.")
        }
        if isRunningBundledApp && !interactionAvailability.accessibilityGranted {
            return t("Grant Accessibility to NotesBridge. If it is already checked, remove and re-add the current app bundle once.")
        }
        return t(interactionAvailability.summary)
    }

    var attachmentStorageBasePath: String {
        attachmentStorage.baseRelativePath
    }

    var attachmentStorageSourceDescription: String {
        attachmentStorage.sourceDescription
    }

    var attachmentStorageWarning: String? {
        attachmentStorage.warning
    }

    var localization: AppLocalization {
        AppLocalization(language: settings.appLanguage)
    }

    func t(_ key: String) -> String {
        localization.text(key)
    }

    func tf(_ key: String, _ arguments: CVarArg...) -> String {
        localization.text(key, arguments: arguments)
    }

    func languageDisplayName(for language: AppLanguage) -> String {
        localization.languageDisplayName(for: language)
    }

    func resetInlineToolbarItems() {
        settings.inlineToolbarItems = InlineToolbarItemSetting.default
    }

    func resetSlashCommandItems() {
        settings.slashCommandItems = SlashCommandItemSetting.default
    }

    func checkForUpdates() {
        appUpdater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        appUpdater.setAutomaticallyChecksForUpdates(enabled)
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        appUpdater.setAutomaticallyDownloadsUpdates(enabled)
    }

    func requestAccessibilityPermission() {
        statusMessage = t("Requesting Accessibility permission for NotesBridge...")
        permissionsManager.requestAccessibilityPermission()
        notesContextMonitor.updateSettings(settings)
        if interactionAvailability.accessibilityGranted {
            statusMessage = t("Accessibility is already granted for NotesBridge.")
        } else if isRunningBundledApp {
            _ = permissionsManager.openAccessibilitySettings()
            statusMessage = t("Open Privacy & Security > Accessibility and enable NotesBridge. If it is missing, add ~/Library/Application Support/NotesBridge/NotesBridge.app manually.")
        } else {
            _ = permissionsManager.openAccessibilitySettings()
            statusMessage = t("Open Privacy & Security > Accessibility and enable NotesBridge.")
        }
    }

    func openAccessibilitySettings() {
        permissionsManager.openAccessibilitySettings()
    }

    func revealCurrentAppInFinder() {
        guard isRunningBundledApp else { return }
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func requestInputMonitoringPermission() {
        guard isRunningBundledApp else {
            relaunchAsBundledApp(requestInputMonitoringOnLaunch: true)
            return
        }

        statusMessage = t("Requesting Input Monitoring permission for slash menu keyboard navigation...")
        permissionsManager.requestInputMonitoringPermission()
        notesContextMonitor.updateSettings(settings)
        if interactionAvailability.inputMonitoringGranted {
            statusMessage = t("Input Monitoring is already granted for NotesBridge.")
        } else {
            _ = permissionsManager.openInputMonitoringSettings()
            statusMessage = t("Open Privacy & Security > Input Monitoring to enable slash menu keyboard navigation for NotesBridge.")
        }
    }

    func openInputMonitoringSettings() {
        permissionsManager.openInputMonitoringSettings()
    }

    func relaunchAsBundledApp(requestInputMonitoringOnLaunch: Bool = false) {
        statusMessage = requestInputMonitoringOnLaunch
            ? t("Relaunching NotesBridge as a bundled app so macOS can grant Input Monitoring...")
            : t("Relaunching NotesBridge as a bundled app...")

        bundledAppLauncher.relaunchCurrentExecutableAsBundledApp(
            requestInputMonitoringOnLaunch: requestInputMonitoringOnLaunch
        ) { [weak self] result in
            switch result {
            case .success:
                NSApplication.shared.terminate(nil)
            case let .failure(error):
                self?.present(error, fallback: self?.t("Failed to relaunch NotesBridge as a bundled app.") ?? "Failed to relaunch NotesBridge as a bundled app.")
            }
        }
    }

    func chooseVaultDirectory() {
        let panel = NSOpenPanel()
        panel.title = t("Choose an Obsidian vault")
        panel.prompt = t("Use Vault")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.vaultPath = url.path
        statusMessage = tf("Obsidian vault set to %@.", url.lastPathComponent)
    }

    func chooseAppleNotesDataFolder() {
        guard let url = appleNotesDataFolderSelector.chooseAppleNotesDataFolder() else {
            return
        }

        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            AppLog.access.info(
                "User selected Apple Notes data folder: \(url.path, privacy: .public); bookmarkBytes=\(bookmarkData.count)"
            )
            let selection = try appleNotesSyncDataSource.validateDataFolder(at: url.path)
            settings.appleNotesDataPath = selection.rootURL.path
            settings.appleNotesDataBookmark = bookmarkData
            refreshAppleNotesDataAccessStatus()
            statusMessage = tf("Apple Notes data folder set to %@.", selection.rootURL.lastPathComponent)
        } catch {
            AppLog.access.error(
                "Failed to select Apple Notes data folder: \(error.localizedDescription, privacy: .public)"
            )
            present(error, fallback: t("Failed to access Apple Notes data folder."))
        }
    }

    func revealVault() {
        guard let vaultPath = settings.vaultPath else { return }
        vaultClient.revealVault(at: vaultPath)
    }

    private func ensureAppleNotesDataFolderSelectionForSync() -> (selection: AppleNotesDataFolderSelection, accessSession: AppleNotesDataFolderAccessSession?)? {
        if let accessSession = resolveAppleNotesDataFolderAccessSession() {
            do {
                let selection = try appleNotesSyncDataSource.validateDataFolder(at: accessSession.url.path)
                refreshAppleNotesDataAccessStatus()
                return (selection, accessSession)
            } catch {
                accessSession.stopAccessing()
                settings.appleNotesDataPath = nil
                settings.appleNotesDataBookmark = nil
                refreshAppleNotesDataAccessStatus()
            }
        }

        guard let selectedURL = appleNotesDataFolderSelector.chooseAppleNotesDataFolder() else {
            presentMessage(t("Sync cancelled. Choose the Apple Notes data folder to continue."))
            return nil
        }

        do {
            let bookmarkData = try selectedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let selection = try appleNotesSyncDataSource.validateDataFolder(at: selectedURL.path)
            settings.appleNotesDataPath = selection.rootURL.path
            settings.appleNotesDataBookmark = bookmarkData
            refreshAppleNotesDataAccessStatus()
            statusMessage = tf("Apple Notes data folder set to %@.", selection.rootURL.lastPathComponent)
            return (
                selection,
                makeAppleNotesDataFolderAccessSession(
                    path: selectedURL.path,
                    bookmarkData: bookmarkData
                )
            )
        } catch {
            present(error, fallback: t("Failed to access Apple Notes data folder."))
            return nil
        }
    }

    func openAppleNotes() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
    }

    private var attachmentStorage: ObsidianAttachmentStorageResolution {
        vaultClient.attachmentStorageResolution(settings: settings)
    }

    func refreshFolderSummaries() async {
        let notesClient = self.notesClient
        let appleNotesSyncDataSource = self.appleNotesSyncDataSource
        let appleNotesDataPath = self.settings.appleNotesDataPath
        let appleNotesDataBookmark = self.settings.appleNotesDataBookmark
        isRefreshingFolders = true
        statusMessage = t("Refreshing Apple Notes folders...")

        defer {
            isRefreshingFolders = false
        }

        do {
            let fetchedFolders = try await Task.detached(priority: .userInitiated) {
                if let accessSession = makeAppleNotesDataFolderAccessSession(
                    path: appleNotesDataPath,
                    bookmarkData: appleNotesDataBookmark
                ) {
                    defer {
                        accessSession.stopAccessing()
                    }
                    return try appleNotesSyncDataSource.fetchFolders(fromDataFolder: accessSession.url.path)
                }
                return try notesClient.fetchFolders()
            }.value

            folderSummaries = fetchedFolders.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            statusMessage = tf("Loaded %lld Apple Notes folders.", folderSummaries.count)
        } catch {
            present(error, fallback: t("Failed to refresh Apple Notes folders."))
        }
    }

    func syncAllNotes() async {
        guard hasVaultConfigured else {
            presentMessage(t("Choose an Obsidian vault before syncing."))
            return
        }

        guard let dataFolderAccess = ensureAppleNotesDataFolderSelectionForSync() else {
            return
        }
        let dataFolderSelection = dataFolderAccess.selection

        let appleNotesSyncDataSource = self.appleNotesSyncDataSource
        let syncEngine = self.syncEngine
        let vaultClient = self.vaultClient
        let settings = self.settings
        let dataFolderBookmark = self.settings.appleNotesDataBookmark
        let existingRecords = self.syncIndex.records
        let progressReporter = makeSyncProgressReporter()

        isSyncing = true
        startSyncAnimation()
        syncProgress = nil
        errorMessage = nil
        statusMessage = t("Syncing Apple Notes to Obsidian...")

        defer {
            isSyncing = false
            stopSyncAnimation()
            syncProgress = nil
            dataFolderAccess.accessSession?.stopAccessing()
        }

        do {
            let result = try await Task.detached(priority: .utility) {
                let totalStart = Date()
                var timings = SyncTimings()
                var diagnostics = SyncDiagnostics()

                func sortedDocuments(_ documents: [AppleNotesSyncDocument]) -> [AppleNotesSyncDocument] {
                    documents.sorted {
                        let nameComparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                        if nameComparison != .orderedSame {
                            return nameComparison == .orderedAscending
                        }
                        return $0.id < $1.id
                    }
                }

                func folderDatabaseID(for folder: AppleNotesFolder) -> Int64? {
                    Int64(folder.id.replacingOccurrences(of: "apple-notes-db://folder/", with: ""))
                }

                func existingRelativePath(
                    for noteID: String,
                    indexedRelativePaths: [String: String]
                ) -> String? {
                    existingRecords[noteID]?.relativePath ?? indexedRelativePaths[noteID]
                }

                func legacyIdentifier(
                    for databaseNoteID: Int64,
                    indexedRelativePaths: [String: String]
                ) -> String? {
                    let legacySuffix = "/ICNote/p\(databaseNoteID)"
                    if let syncIndexMatch = existingRecords.keys.first(where: { $0.hasSuffix(legacySuffix) }) {
                        return syncIndexMatch
                    }
                    return indexedRelativePaths.keys.first(where: { $0.hasSuffix(legacySuffix) })
                }

                func buildExportGroups(
                    folders: [AppleNotesFolder],
                    documents: [AppleNotesSyncDocument],
                    skippedNotesByFolder: [String: Int]
                ) -> ([FolderExportGroup], Int) {
                    let documentsByFolderID = Dictionary(
                        grouping: documents.compactMap { document in
                            document.folderDatabaseID.map { ($0, document) }
                        },
                        by: { $0.0 }
                    )
                    .mapValues { pairs in
                        sortedDocuments(pairs.map(\.1))
                    }
                    let documentsByFolderName = Dictionary(grouping: documents) { $0.folder }
                        .mapValues(sortedDocuments)
                    let documentsByFolderPath = Dictionary(grouping: documents) { $0.exportFolderPath }
                        .mapValues(sortedDocuments)

                    var usedDocumentIDs: Set<String> = []
                    var groups: [FolderExportGroup] = []

                    for folder in folders {
                        let documents = folderDatabaseID(for: folder)
                            .flatMap { documentsByFolderID[$0] }
                            ?? documentsByFolderPath[folder.exportRelativePath]
                            ?? documentsByFolderName[folder.displayName]
                            ?? []
                        if documents.isEmpty {
                            continue
                        }

                        usedDocumentIDs.formUnion(documents.map(\.id))
                        groups.append(
                            FolderExportGroup(
                                displayName: folder.displayName,
                                documents: documents,
                                skippedCount: skippedNotesByFolder[folder.exportRelativePath] ?? 0,
                                isFallback: false
                            )
                        )
                    }

                    let unmatchedDocuments = documents.filter { !usedDocumentIDs.contains($0.id) }
                    let fallbackGroups = Dictionary(grouping: unmatchedDocuments) { document in
                        document.exportFolderPath
                    }
                    .map { (key: $0.key, value: $0.value) }
                    .sorted(by: { (left: (key: String, value: [AppleNotesSyncDocument]), right: (key: String, value: [AppleNotesSyncDocument])) in
                        let leftName = left.value.first?.folderDisplayName ?? left.key
                        let rightName = right.value.first?.folderDisplayName ?? right.key
                        return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
                    })

                    for (folderPath, documents) in fallbackGroups {
                        groups.append(
                            FolderExportGroup(
                                displayName: documents.first?.folderDisplayName ?? (folderPath.isEmpty ? "Notes" : folderPath),
                                documents: sortedDocuments(documents),
                                skippedCount: skippedNotesByFolder[folderPath] ?? 0,
                                isFallback: true
                            )
                        )
                    }

                    return (groups, unmatchedDocuments.count)
                }

                func planExports(
                    groups: [FolderExportGroup],
                    indexedRelativePaths: [String: String]
                ) -> ([PlannedFolderExportGroup], [String: String], Set<String>) {
                    var occupiedRelativePaths = Set(indexedRelativePaths.values)
                    var plannedRelativePathsBySourceIdentifier: [String: String] = [:]
                    var migratedLegacyIDs: Set<String> = []
                    var plannedGroups: [PlannedFolderExportGroup] = []

                    for group in groups {
                        var plannedDocuments: [PlannedDocumentExport] = []

                        for var document in group.documents {
                            if let legacyID = legacyIdentifier(
                                for: document.databaseNoteID,
                                indexedRelativePaths: indexedRelativePaths
                            ),
                            document.legacyNoteID == nil,
                            legacyID != document.id
                            {
                                document.legacyNoteID = legacyID
                                migratedLegacyIDs.insert(legacyID)
                            }

                            let existingRelativePath = existingRelativePath(
                                for: document.id,
                                indexedRelativePaths: indexedRelativePaths
                            ) ?? document.legacyNoteID.flatMap {
                                existingRelativePath(for: $0, indexedRelativePaths: indexedRelativePaths)
                            }

                            let plannedRelativePath = vaultClient.plannedRelativePath(
                                for: document,
                                settings: settings,
                                existingRelativePath: existingRelativePath,
                                occupiedRelativePaths: occupiedRelativePaths
                            )

                            if let existingRelativePath,
                               existingRelativePath != plannedRelativePath
                            {
                                occupiedRelativePaths.remove(existingRelativePath)
                            }
                            occupiedRelativePaths.insert(plannedRelativePath)
                            plannedRelativePathsBySourceIdentifier[document.sourceNoteIdentifier] = plannedRelativePath
                            plannedRelativePathsBySourceIdentifier[document.id] = plannedRelativePath
                            plannedDocuments.append(
                                PlannedDocumentExport(
                                    document: document,
                                    existingRelativePath: existingRelativePath,
                                    plannedRelativePath: plannedRelativePath
                                )
                            )
                        }

                        plannedGroups.append(
                            PlannedFolderExportGroup(
                                displayName: group.displayName,
                                documents: plannedDocuments,
                                skippedCount: group.skippedCount,
                                isFallback: group.isFallback
                            )
                        )
                    }

                    return (plannedGroups, plannedRelativePathsBySourceIdentifier, migratedLegacyIDs)
                }

                let loadSnapshotStart = Date()
                let snapshot = try {
                    if let accessSession = makeAppleNotesDataFolderAccessSession(
                        path: dataFolderSelection.rootURL.path,
                        bookmarkData: dataFolderBookmark
                    ) {
                        defer {
                            accessSession.stopAccessing()
                        }
                        return try appleNotesSyncDataSource.loadSnapshot(fromDataFolder: accessSession.url.path)
                    }
                    return try appleNotesSyncDataSource.loadSnapshot(fromDataFolder: dataFolderSelection.rootURL.path)
                }()
                timings.loadSnapshot = Date().timeIntervalSince(loadSnapshotStart)
                let totalSnapshotNotes = snapshot.folders.reduce(0) { $0 + $1.noteCount }
                AppLog.sync.info(
                    "Loaded snapshot with \(snapshot.folders.count) folder(s), \(snapshot.documents.count) document(s), \(snapshot.skippedLockedNotes) locked note(s), totalNoteCount=\(totalSnapshotNotes)."
                )

                if snapshot.documents.isEmpty,
                   totalSnapshotNotes > snapshot.skippedLockedNotes
                {
                    throw FullSyncExecutionError.emptySnapshot(
                        "Loaded 0 documents from the Apple Notes snapshot even though \(totalSnapshotNotes - snapshot.skippedLockedNotes) note(s) appear syncable. \(snapshot.sourceDiagnostics ?? "")"
                    )
                }

                let scanExistingStart = Date()
                let indexedRelativePaths = try vaultClient.indexExistingNotes(settings: settings)
                timings.scanExisting = Date().timeIntervalSince(scanExistingStart)
                AppLog.sync.info("Indexed \(indexedRelativePaths.count) existing synced note path(s).")

                let folders = snapshot.folders.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                diagnostics.skippedNotes = snapshot.skippedLockedNotes
                diagnostics.failedTableDecodes = snapshot.failedTableDecodes
                diagnostics.failedScanDecodes = snapshot.failedScanDecodes
                diagnostics.partialScanPageFailures = snapshot.partialScanPageFailures
                diagnostics.sourceDiagnostics = snapshot.sourceDiagnostics
                let (exportGroups, fallbackDocumentCount) = buildExportGroups(
                    folders: folders,
                    documents: snapshot.documents,
                    skippedNotesByFolder: snapshot.skippedLockedNotesByFolder
                )
                diagnostics.fallbackGroupedDocuments = fallbackDocumentCount
                AppLog.sync.info(
                    "Built \(exportGroups.count) export group(s) from \(snapshot.documents.count) document(s); fallbackGroupedDocuments=\(fallbackDocumentCount)."
                )
                let (plannedGroups, plannedRelativePathsBySourceIdentifier, migratedLegacyIDs) = planExports(
                    groups: exportGroups,
                    indexedRelativePaths: indexedRelativePaths
                )
                AppLog.sync.info(
                    "Planned \(plannedGroups.count) folder export group(s), \(plannedRelativePathsBySourceIdentifier.count) note path mapping(s), migratedLegacyIDs=\(migratedLegacyIDs.count)."
                )
                var records: [SyncRecord] = []
                var progress = SyncProgress(
                    completedNotes: 0,
                    totalNotes: folders.reduce(0) { $0 + $1.noteCount },
                    completedFolders: 0,
                    totalFolders: max(plannedGroups.count, 1),
                    currentFolderName: nil,
                    skippedNotes: 0
                )
                await progressReporter.publish(progress)

                for group in plannedGroups {
                    progress.enterFolder(group.displayName)
                    await progressReporter.publish(progress)

                    for plannedDocument in group.documents {
                        let exportStart = Date()
                        let syncResult = try syncEngine.sync(
                            document: plannedDocument.document,
                            settings: settings,
                            existingRelativePath: plannedDocument.existingRelativePath,
                            plannedRelativePath: plannedDocument.plannedRelativePath,
                            plannedRelativePathsBySourceIdentifier: plannedRelativePathsBySourceIdentifier
                        )
                        timings.export += Date().timeIntervalSince(exportStart)
                        records.append(syncResult.record)
                        diagnostics.unresolvedInternalLinks += syncResult.unresolvedInternalLinkCount
                        AppLog.export.debug(
                            "Exported note \(plannedDocument.document.id, privacy: .public) to \(syncResult.record.relativePath, privacy: .public); unresolvedInternalLinks=\(syncResult.unresolvedInternalLinkCount)."
                        )
                        progress.markProcessedNotes()
                        await progressReporter.publish(progress)
                    }

                    progress.markSkippedNotes(group.skippedCount)
                    progress.markCompletedFolder()
                    await progressReporter.publish(progress)
                }

                if plannedGroups.isEmpty && !snapshot.documents.isEmpty {
                    let folderSummary = folders
                        .map { folder in
                            let folderID = folderDatabaseID(for: folder).map(String.init) ?? "nil"
                            return "\(folder.displayName){id=\(folderID)}"
                        }
                        .joined(separator: ", ")
                    let documentSummary = snapshot.documents.prefix(5)
                        .map { document in
                            "\(document.displayName){folderID=\(document.folderDatabaseID.map(String.init) ?? "nil"), folder=\(document.folder)}"
                        }
                        .joined(separator: ", ")
                    throw FullSyncExecutionError.noDocumentsMatchedFolders(
                        "Loaded \(snapshot.documents.count) document(s), but none matched the exported folder mapping. Folders: \(folderSummary). Sample documents: \(documentSummary)"
                    )
                }

                timings.total = Date().timeIntervalSince(totalStart)

                return FullSyncResult(
                    folders: folders,
                    exportedFolderCount: plannedGroups.count,
                    records: records,
                    timings: timings,
                    diagnostics: diagnostics,
                    migratedLegacyIDs: migratedLegacyIDs
                )
            }.value

            folderSummaries = result.folders.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            for legacyID in result.migratedLegacyIDs {
                syncIndex.records.removeValue(forKey: legacyID)
            }
            for record in result.records {
                syncIndex.records[record.noteID] = record
            }
            let persistStart = Date()
            syncIndex.lastFullSyncAt = Date()
            syncIndex.lastFullSyncNoteCount = result.records.count
            syncIndex.lastFullSyncFolderCount = result.exportedFolderCount
            try persistence.saveSyncIndex(syncIndex)
            let persistDuration = Date().timeIntervalSince(persistStart)
            let timingSummary = result.timings.summary(persistIndex: persistDuration)
            let diagnosticsSummary = result.diagnostics.summary
            print("Sync timings: \(timingSummary)")
            statusMessage = "\(tf("Synced %lld note(s) across %lld folder(s).", result.records.count, result.exportedFolderCount)) \(timingSummary)\(diagnosticsSummary.isEmpty ? "" : " \(diagnosticsSummary)")"
        } catch {
            present(error, fallback: t("Failed to sync Apple Notes to Obsidian."))
        }
    }

    func persistSettings() {
        do {
            try persistence.saveSettings(settings)
        } catch {
            present(error, fallback: t("Failed to save app settings."))
        }
    }

    private func bindInteractionState() {
        appUpdater.statePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateState = state
            }
            .store(in: &cancellables)

        notesContextMonitor.$availability
            .receive(on: RunLoop.main)
            .sink { [weak self] availability in
                guard let self else { return }
                self.interactionAvailability = availability
                self.formattingBarController.update(
                    selectionContext: self.selectionContext,
                    availability: availability,
                    commands: self.visibleInlineToolbarCommands,
                    localization: self.localization
                )
            }
            .store(in: &cancellables)

        notesContextMonitor.$selectionContext
            .receive(on: RunLoop.main)
            .sink { [weak self] selectionContext in
                guard let self else { return }
                self.selectionContext = selectionContext
                self.formattingBarController.update(
                    selectionContext: selectionContext,
                    availability: self.interactionAvailability,
                    commands: self.visibleInlineToolbarCommands,
                    localization: self.localization
                )
            }
            .store(in: &cancellables)
    }

    private func start() {
        refreshAppleNotesDataAccessStatus()
        notesContextMonitor.start()
        if buildFlavor.supportsInlineEnhancements {
            markdownTriggerEngine.start()
            slashCommandEngine.start()
        }

        scheduleAccessibilityPromptIfNeeded()
    }

    private func refreshAppleNotesDataAccessStatus() {
        guard hasAppleNotesDataFolderConfigured else {
            appleNotesDataAccessStatus = nil
            return
        }

        guard let accessSession = resolveAppleNotesDataFolderAccessSession() else {
            AppLog.access.error("Unable to restore saved Apple Notes data folder access session.")
            appleNotesDataAccessStatus = AppleNotesDataFolderAccessStatus(
                level: .invalid,
                message: "The saved Apple Notes folder access could not be restored. Re-choose the group.com.apple.notes folder."
            )
            return
        }
        defer {
            accessSession.stopAccessing()
        }

        AppLog.access.info(
            "Inspecting Apple Notes data folder access at \(accessSession.url.path, privacy: .public)"
        )
        appleNotesDataAccessStatus = appleNotesSyncDataSource.inspectDataFolder(at: accessSession.url.path)
        if let appleNotesDataAccessStatus {
            AppLog.access.info(
                "Apple Notes data access status: \(appleNotesDataAccessStatus.level.rawValue, privacy: .public) - \(appleNotesDataAccessStatus.message, privacy: .public)"
            )
        }
    }

    private func scheduleAccessibilityPromptIfNeeded() {
        guard buildFlavor.supportsInlineEnhancements,
              settings.enableInlineEnhancements,
              isRunningBundledApp,
              !interactionAvailability.accessibilityGranted
        else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self,
                  self.isRunningBundledApp,
                  self.buildFlavor.supportsInlineEnhancements,
                  self.settings.enableInlineEnhancements,
                  !self.interactionAvailability.accessibilityGranted
            else {
                return
            }
            self.requestAccessibilityPermission()
        }
    }

    private func present(_ error: Error, fallback: String) {
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = detail.isEmpty || detail == fallback ? fallback : "\(fallback) \(detail)"
        errorMessage = message
        statusMessage = message
    }

    private func presentMessage(_ message: String) {
        errorMessage = message
        statusMessage = message
    }

    private func makeSyncProgressReporter() -> SyncProgressReporter {
        SyncProgressReporter { [weak self] progress in
            self?.syncProgress = progress
        }
    }

    private func resolveAppleNotesDataFolderAccessSession() -> AppleNotesDataFolderAccessSession? {
        makeAppleNotesDataFolderAccessSession(
            path: settings.appleNotesDataPath,
            bookmarkData: settings.appleNotesDataBookmark
        )
    }

    private func startSyncAnimation() {
        stopSyncAnimation()
        menuBarSyncFrameIndex = 0

        syncAnimationCancellable = Timer.publish(every: 0.075, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.menuBarSyncFrameIndex = (self.menuBarSyncFrameIndex + 1) % 12
            }
    }

    private func stopSyncAnimation() {
        syncAnimationCancellable?.cancel()
        syncAnimationCancellable = nil
        menuBarSyncFrameIndex = 0
    }
}

private struct FullSyncResult {
    var folders: [AppleNotesFolder]
    var exportedFolderCount: Int
    var records: [SyncRecord]
    var timings: SyncTimings
    var diagnostics: SyncDiagnostics
    var migratedLegacyIDs: Set<String>
}

private enum FullSyncExecutionError: LocalizedError {
    case emptySnapshot(String)
    case noDocumentsMatchedFolders(String)

    var errorDescription: String? {
        switch self {
        case let .emptySnapshot(details):
            details
        case let .noDocumentsMatchedFolders(details):
            details
        }
    }
}

private struct SyncTimings: Sendable {
    var loadSnapshot: TimeInterval = 0
    var scanExisting: TimeInterval = 0
    var export: TimeInterval = 0
    var total: TimeInterval = 0

    func summary(persistIndex: TimeInterval) -> String {
        let totalDuration = total + persistIndex
        return "Total \(totalDuration.formattedDuration); snapshot \(loadSnapshot.formattedDuration); index \(scanExisting.formattedDuration); export \(export.formattedDuration); persist \(persistIndex.formattedDuration)."
    }
}

private struct SyncDiagnostics: Sendable {
    var skippedNotes = 0
    var fallbackGroupedDocuments = 0
    var unresolvedInternalLinks = 0
    var failedTableDecodes = 0
    var failedScanDecodes = 0
    var partialScanPageFailures = 0
    var sourceDiagnostics: String?

    var summary: String {
        var parts: [String] = []

        if skippedNotes > 0 {
            parts.append("Skipped \(skippedNotes) locked note(s).")
        }

        if fallbackGroupedDocuments > 0 {
            parts.append("Exported \(fallbackGroupedDocuments) note(s) with fallback folder grouping.")
            if let sourceDiagnostics, !sourceDiagnostics.isEmpty {
                parts.append("Source diagnostics: \(sourceDiagnostics)")
            }
        }

        if unresolvedInternalLinks > 0 {
            parts.append("Left \(unresolvedInternalLinks) internal note link(s) as plain text because their targets were not exported.")
        }

        if failedTableDecodes > 0 {
            parts.append("Failed to fully decode \(failedTableDecodes) Apple Notes table attachment(s).")
        }

        if failedScanDecodes > 0 {
            parts.append("Failed to fully decode \(failedScanDecodes) Apple Notes scan attachment(s).")
        }

        if partialScanPageFailures > 0 {
            parts.append("Fell back on \(partialScanPageFailures) Apple Notes scan page(s) that could not be resolved cleanly.")
        }

        return parts.joined(separator: " ")
    }
}

private struct FolderExportGroup: Sendable {
    var displayName: String
    var documents: [AppleNotesSyncDocument]
    var skippedCount: Int
    var isFallback: Bool
}

private struct PlannedDocumentExport: Sendable {
    var document: AppleNotesSyncDocument
    var existingRelativePath: String?
    var plannedRelativePath: String
}

private struct PlannedFolderExportGroup: Sendable {
    var displayName: String
    var documents: [PlannedDocumentExport]
    var skippedCount: Int
    var isFallback: Bool
}

private final class SyncProgressReporter: @unchecked Sendable {
    private let update: @MainActor @Sendable (SyncProgress) -> Void

    init(update: @escaping @MainActor @Sendable (SyncProgress) -> Void) {
        self.update = update
    }

    func publish(_ progress: SyncProgress) async {
        await update(progress)
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        String(format: "%.2fs", self)
    }
}
