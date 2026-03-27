import AppKit
import Combine
import Foundation
import OSLog

typealias AppleNotesDataFolderAccessSessionFactory = @Sendable (String?, Data?) -> AppleNotesDataFolderAccessSession?

struct AppleNotesDataFolderAccessSession {
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

func makeAppleNotesDataFolderAccessSession(
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
            scheduleAutomaticSyncIfNeeded()
            formattingBarController.update(
                selectionContext: interactionState.selectionContext,
                availability: interactionState.availability,
                commands: visibleInlineToolbarCommands,
                localization: localization
            )
        }
    }

    @Published private(set) var buildFlavor: BuildFlavor
    @Published private(set) var interactionState: InteractionState
    @Published private(set) var folderSummaries: [AppleNotesFolder] = []
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
    private let incrementalSyncPlanner: IncrementalSyncPlanner
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
    private let appleNotesDataFolderAccessSessionFactory: AppleNotesDataFolderAccessSessionFactory
    private var syncIndex: SyncIndex
    private var syncAnimationCancellable: AnyCancellable?
    private var automaticSyncCancellable: AnyCancellable?
    private let notesDatabaseWatcher: NotesDatabaseWatcher
    private var watcherAccessSession: AppleNotesDataFolderAccessSession?
    private var pendingOnChangeSyncTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        notesClient: any AppleNotesClient = AppleNotesScriptClient(),
        appleNotesSyncDataSource: any AppleNotesSyncDataSourcing = AppleNotesDatabaseSyncSource(),
        appleNotesDataFolderSelector: any AppleNotesDataFolderSelecting = AppleNotesDataFolderSelector(),
        incrementalSyncPlanner: IncrementalSyncPlanner = IncrementalSyncPlanner(),
        syncEngine: any Syncing = SyncEngine(),
        vaultClient: ObsidianVaultClient = ObsidianVaultClient(),
        bundledAppLauncher: BundledAppLauncher = BundledAppLauncher(),
        persistence: any PersistenceStoring = PersistenceStore(),
        buildFlavor: BuildFlavor = .current,
        appUpdater: (any AppUpdating)? = nil,
        permissionsManager: PermissionsManager = PermissionsManager(),
        statusObserver: (@MainActor @Sendable (String) -> Void)? = nil,
        appleNotesDataFolderAccessSessionFactory: @escaping AppleNotesDataFolderAccessSessionFactory = makeAppleNotesDataFolderAccessSession,
        startImmediately: Bool = true
    ) {
        let resolvedBuildFlavor = buildFlavor
        self.notesClient = notesClient
        self.appleNotesSyncDataSource = appleNotesSyncDataSource
        self.appleNotesDataFolderSelector = appleNotesDataFolderSelector
        self.incrementalSyncPlanner = incrementalSyncPlanner
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
        self.appleNotesDataFolderAccessSessionFactory = appleNotesDataFolderAccessSessionFactory
        self.interactionState = InteractionState(
            selectionContext: nil,
            availability: .default(for: resolvedBuildFlavor)
        )
        self.notesDatabaseWatcher = NotesDatabaseWatcher()
        self.notesDatabaseWatcher.onChange = { [weak self] in
            self?.handleDatabaseChange()
        }
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

    var appManagementPermissionLabel: String {
        t("Recommended")
    }

    var appManagementPermissionSummary: String {
        t("Enable App Management for NotesBridge to let direct-download updates replace the installed app automatically.")
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

    var lastSyncLabel: String {
        guard let lastSyncAt = syncIndex.lastSyncAt else { return t("Never") }
        return lastSyncAt.formatted(date: .abbreviated, time: .shortened)
    }

    var automaticSyncEnabled: Bool {
        settings.automaticSyncEnabled
    }

    var automaticSyncInterval: AutomaticSyncInterval {
        settings.automaticSyncInterval
    }

    var knownFolderCount: Int {
        if !folderSummaries.isEmpty {
            return folderSummaries.count
        }

        return syncIndex.knownFolderCount ?? syncIndex.lastFullSyncFolderCount ?? 0
    }

    var selectionSummary: String {
        guard let selectionContext = interactionState.selectionContext, selectionContext.hasSelection else {
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
        if interactionState.availability.canShowFormattingBar {
            return "text.cursor"
        }
        if interactionState.availability.supportsInlineEnhancements && !interactionState.availability.accessibilityGranted {
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
        if !interactionState.availability.accessibilityGranted {
            if isRunningBundledApp {
                return t("Accessibility permission is required for slash commands. If NotesBridge is already checked in Accessibility, remove and re-add the current app bundle once.")
            }
            return t("Accessibility permission is required for slash commands.")
        }
        if !interactionState.availability.notesIsFrontmost {
            return t("Bring Apple Notes to the front to use slash commands.")
        }
        if !interactionState.availability.editableFocus {
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
        if isRunningBundledApp && !interactionState.availability.accessibilityGranted {
            return t("Grant Accessibility to NotesBridge. If it is already checked, remove and re-add the current app bundle once.")
        }
        return t(interactionState.availability.summary)
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
        if interactionState.availability.accessibilityGranted {
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
        if interactionState.availability.inputMonitoringGranted {
            statusMessage = t("Input Monitoring is already granted for NotesBridge.")
        } else {
            _ = permissionsManager.openInputMonitoringSettings()
            statusMessage = t("Open Privacy & Security > Input Monitoring to enable slash menu keyboard navigation for NotesBridge.")
        }
    }

    func openInputMonitoringSettings() {
        permissionsManager.openInputMonitoringSettings()
    }

    func requestAppManagementPermission() {
        statusMessage = t("Open Privacy & Security > App Management and enable NotesBridge so direct-download updates can replace the installed app.")
        permissionsManager.requestAppManagementPermission()
    }

    func openAppManagementSettings() {
        permissionsManager.openAppManagementSettings()
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
                appleNotesDataFolderAccessSessionFactory(selectedURL.path, bookmarkData)
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
        let accessSessionFactory = self.appleNotesDataFolderAccessSessionFactory
        isRefreshingFolders = true
        statusMessage = t("Refreshing Apple Notes folders...")

        defer {
            isRefreshingFolders = false
        }

        do {
            let fetchedFolders = try await Task.detached(priority: .userInitiated) {
                if let accessSession = accessSessionFactory(appleNotesDataPath, appleNotesDataBookmark) {
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
            syncIndex.knownFolderCount = folderSummaries.count
            try persistence.saveSyncIndex(syncIndex)
            statusMessage = tf("Loaded %lld Apple Notes folders.", folderSummaries.count)
        } catch {
            present(error, fallback: t("Failed to refresh Apple Notes folders."))
        }
    }

    func syncChangedNotes() async {
        await runIncrementalSync(trigger: .incremental)
    }

    private func runIncrementalSync(trigger: SyncRunMode) async {
        guard hasVaultConfigured else {
            presentMessage(t("Choose an Obsidian vault before syncing."))
            return
        }
        guard !isSyncing else {
            return
        }
        guard let dataFolderAccess = ensureAppleNotesDataFolderSelectionForSync() else {
            return
        }

        let dataFolderSelection = dataFolderAccess.selection
        let appleNotesSyncDataSource = self.appleNotesSyncDataSource
        let incrementalSyncPlanner = self.incrementalSyncPlanner
        let syncEngine = self.syncEngine
        let vaultClient = self.vaultClient
        let settings = self.settings
        let dataFolderBookmark = self.settings.appleNotesDataBookmark
        let accessSessionFactory = self.appleNotesDataFolderAccessSessionFactory
        let syncIndexSnapshot = self.syncIndex
        let progressReporter = makeSyncProgressReporter()

        isSyncing = true
        startSyncAnimation()
        syncProgress = nil
        errorMessage = nil
        if trigger == .automatic {
            statusMessage = t("Checking Apple Notes for changes...")
        } else {
            statusMessage = t("Syncing changed Apple Notes to Obsidian...")
        }

        defer {
            isSyncing = false
            stopSyncAnimation()
            syncProgress = nil
            dataFolderAccess.accessSession?.stopAccessing()
        }

        do {
            let result = try await Task.detached(priority: .utility) {
                let totalStart = Date()
                var timings = IncrementalSyncTimings()
                var updatedSyncIndex = syncIndexSnapshot

                func pathAliasIdentifiers(for document: AppleNotesSyncDocument) -> [String] {
                    [
                        document.id,
                        document.sourceNoteIdentifierRaw,
                        document.appleNotesDeepLink ?? "",
                        document.legacyNoteID ?? "",
                    ]
                }

                for record in updatedSyncIndex.records.values {
                    updatedSyncIndex.rememberPath(record.relativePath, for: [record.noteID])
                }

                let loadManifestStart = Date()
                let manifest = try {
                    if let accessSession = accessSessionFactory(dataFolderSelection.rootURL.path, dataFolderBookmark) {
                        defer { accessSession.stopAccessing() }
                        return try appleNotesSyncDataSource.loadManifest(fromDataFolder: accessSession.url.path)
                    }
                    return try appleNotesSyncDataSource.loadManifest(fromDataFolder: dataFolderSelection.rootURL.path)
                }()
                timings.loadManifest = Date().timeIntervalSince(loadManifestStart)

                let indexedRelativePaths: [String: String]
                if updatedSyncIndex.pathAliases.isEmpty {
                    let scanExistingStart = Date()
                    indexedRelativePaths = try vaultClient.indexExistingNotes(settings: settings)
                    timings.scanExisting = Date().timeIntervalSince(scanExistingStart)
                    updatedSyncIndex.mergePathAliases(indexedRelativePaths)
                } else {
                    indexedRelativePaths = [:]
                }

                let plan = incrementalSyncPlanner.plan(
                    manifest: manifest,
                    syncIndex: updatedSyncIndex,
                    indexedRelativePaths: indexedRelativePaths,
                    settings: settings
                )

                let noteIDsToLoad = Set(plan.exports.map(\.manifestEntry.databaseNoteID))
                let loadDocumentsStart = Date()
                let changedSnapshot = try {
                    if let accessSession = accessSessionFactory(dataFolderSelection.rootURL.path, dataFolderBookmark) {
                        defer { accessSession.stopAccessing() }
                        return try appleNotesSyncDataSource.loadDocuments(
                            fromDataFolder: accessSession.url.path,
                            noteIDs: noteIDsToLoad,
                            preferredDatabaseRelativePath: manifest.selectedDatabaseRelativePath
                        )
                    }
                    return try appleNotesSyncDataSource.loadDocuments(
                        fromDataFolder: dataFolderSelection.rootURL.path,
                        noteIDs: noteIDsToLoad,
                        preferredDatabaseRelativePath: manifest.selectedDatabaseRelativePath
                    )
                }()
                timings.loadChangedDocuments = Date().timeIntervalSince(loadDocumentsStart)
                let changedDocumentsByID = Dictionary(
                    uniqueKeysWithValues: changedSnapshot.documents.map { ($0.id, $0) }
                )

                var missingDocumentIDs: [String] = []
                for plannedExport in plan.exports where changedDocumentsByID[plannedExport.manifestEntry.id] == nil {
                    missingDocumentIDs.append(plannedExport.manifestEntry.id)
                }
                if !missingDocumentIDs.isEmpty {
                    AppLog.sync.warning(
                        "Incremental sync could not load \(missingDocumentIDs.count) changed note(s) by ID: \(missingDocumentIDs.joined(separator: ", "), privacy: .public)"
                    )
                    throw IncrementalSyncExecutionError.missingChangedDocuments(
                        missingDocumentIDs
                    )
                }

                var updatedRecords = syncIndexSnapshot.records
                var addedNoteCount = 0
                var updatedNoteCount = 0
                var exportedUnchangedNoteCount = 0
                var unresolvedInternalLinks = 0
                let groupedExports = Dictionary(grouping: plan.exports) { $0.manifestEntry.folderDisplayName }
                    .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                let progress = SyncProgress(
                    completedNotes: 0,
                    totalNotes: plan.exports.count,
                    completedFolders: 0,
                    totalFolders: max(groupedExports.count, 1),
                    currentFolderName: nil,
                    skippedNotes: 0
                )
                var mutableProgress = progress
                if !plan.exports.isEmpty {
                    await progressReporter.publish(mutableProgress)
                }

                for (folderName, exports) in groupedExports {
                    mutableProgress.enterFolder(folderName)
                    await progressReporter.publish(mutableProgress)

                    for plannedExport in exports {
                        guard let document = changedDocumentsByID[plannedExport.manifestEntry.id] else {
                            continue
                        }
                        let exportStart = Date()
                        let syncResult = try syncEngine.sync(
                            document: document,
                            settings: settings,
                            existingRelativePath: plannedExport.existingRelativePath,
                            plannedRelativePath: plannedExport.plannedRelativePath,
                            plannedRelativePathsBySourceIdentifier: plan.plannedRelativePathsBySourceIdentifier
                        )
                        timings.export += Date().timeIntervalSince(exportStart)
                        updatedRecords[syncResult.record.noteID] = syncResult.record
                        updatedSyncIndex.rememberPath(
                            syncResult.record.relativePath,
                            for: pathAliasIdentifiers(for: document)
                        )
                        switch syncResult.changeKind {
                        case .created:
                            addedNoteCount += 1
                        case .updated:
                            updatedNoteCount += 1
                        case .unchanged:
                            exportedUnchangedNoteCount += 1
                        }
                        unresolvedInternalLinks += syncResult.unresolvedInternalLinkCount
                        mutableProgress.markProcessedNotes()
                        await progressReporter.publish(mutableProgress)
                    }

                    mutableProgress.markCompletedFolder()
                    await progressReporter.publish(mutableProgress)
                }

                let removeDeletedStart = Date()
                var movedRemovedNotes = 0
                for removedRecord in plan.removedRecords {
                    if try vaultClient.moveExportedNoteToRemoved(
                        relativePath: removedRecord.relativePath,
                        settings: settings
                    ) != nil {
                        movedRemovedNotes += 1
                    }
                    updatedSyncIndex.removePathAliases(forRelativePath: removedRecord.relativePath)
                    updatedSyncIndex.removePathAliases(for: [removedRecord.noteID])
                    updatedRecords.removeValue(forKey: removedRecord.noteID)
                }
                timings.removeDeleted = Date().timeIntervalSince(removeDeletedStart)
                timings.total = Date().timeIntervalSince(totalStart)

                return IncrementalSyncResult(
                    folders: plan.folders,
                    updatedRecords: updatedRecords,
                    processedNoteCount: plan.processedNoteCount,
                    addedNoteCount: addedNoteCount,
                    updatedNoteCount: updatedNoteCount,
                    removedNoteCount: movedRemovedNotes,
                    unchangedNoteCount: plan.unchangedNoteCount + exportedUnchangedNoteCount,
                    pathAliases: updatedSyncIndex.pathAliases,
                    timings: timings,
                    diagnostics: IncrementalSyncDiagnostics(
                        skippedNotes: plan.skippedLockedNotes,
                        unresolvedInternalLinks: unresolvedInternalLinks
                    )
                )
            }.value

            folderSummaries = result.folders.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            syncIndex.knownFolderCount = folderSummaries.count
            syncIndex.records = result.updatedRecords
            syncIndex.pathAliases = result.pathAliases
            let persistStart = Date()
            let now = Date()
            syncIndex.lastSyncAt = now
            syncIndex.lastSyncMode = trigger
            syncIndex.lastIncrementalSyncAt = now
            if trigger == .automatic {
                syncIndex.lastAutomaticSyncAt = now
            }
            try persistence.saveSyncIndex(syncIndex)
            let persistDuration = Date().timeIntervalSince(persistStart)
            let timingSummary = result.timings.summary(persistIndex: persistDuration)
            let diagnosticsSummary = result.diagnostics.summary

            if result.addedNoteCount == 0 && result.updatedNoteCount == 0 && result.removedNoteCount == 0 {
                if trigger != .automatic {
                    statusMessage = "\(tf("Processed %lld note(s) and found no changes.", result.processedNoteCount)) \(timingSummary)"
                }
                return
            }

            statusMessage = "\(tf("Processed %lld note(s): updated %lld, added %lld, moved %lld to _Removed, and left %lld unchanged.", result.processedNoteCount, result.updatedNoteCount, result.addedNoteCount, result.removedNoteCount, result.unchangedNoteCount)) \(timingSummary)\(diagnosticsSummary.isEmpty ? "" : " \(diagnosticsSummary)")"
        } catch let error as IncrementalSyncExecutionError {
            if error.shouldFallbackToFullSync {
                isSyncing = false
                stopSyncAnimation()
                syncProgress = nil
                dataFolderAccess.accessSession?.stopAccessing()
                await runFullSync(context: .incrementalFallback(missingCount: error.missingDocumentCount))
                return
            }
            present(error, fallback: t("Failed to sync changed Apple Notes to Obsidian."))
        } catch {
            present(error, fallback: t("Failed to sync changed Apple Notes to Obsidian."))
        }
    }

    func syncAllNotes() async {
        await runFullSync()
    }

    func runFullSync(context: FullSyncRunContext = .direct) async {
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
        let accessSessionFactory = self.appleNotesDataFolderAccessSessionFactory
        let syncIndexSnapshot = self.syncIndex
        let progressReporter = makeSyncProgressReporter()

        isSyncing = true
        startSyncAnimation()
        syncProgress = nil
        errorMessage = nil
        statusMessage = context.initialStatusMessage(localize: t)

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
                var updatedSyncIndex = syncIndexSnapshot

                func pathAliasIdentifiers(for document: AppleNotesSyncDocument) -> [String] {
                    [
                        document.id,
                        document.sourceNoteIdentifierRaw,
                        document.appleNotesDeepLink ?? "",
                        document.legacyNoteID ?? "",
                    ]
                }

                for record in updatedSyncIndex.records.values {
                    updatedSyncIndex.rememberPath(record.relativePath, for: [record.noteID])
                }

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
                    syncIndexSnapshot.records[noteID]?.relativePath
                        ?? updatedSyncIndex.pathAliases[noteID]
                        ?? indexedRelativePaths[noteID]
                }

                func legacyIdentifier(
                    for databaseNoteID: Int64,
                    indexedRelativePaths: [String: String]
                ) -> String? {
                    let legacySuffix = "/ICNote/p\(databaseNoteID)"
                    if let syncIndexMatch = syncIndexSnapshot.records.keys.first(where: { $0.hasSuffix(legacySuffix) }) {
                        return syncIndexMatch
                    }
                    if let aliasMatch = updatedSyncIndex.pathAliases.keys.first(where: { $0.hasSuffix(legacySuffix) }) {
                        return aliasMatch
                    }
                    if let recoveredMatch = indexedRelativePaths.keys.first(where: { $0.hasSuffix(legacySuffix) }) {
                        return recoveredMatch
                    }
                    return nil
                }

                func buildOccupiedRelativePaths(
                    indexedRelativePaths: [String: String]
                ) -> Set<String> {
                    var occupiedRelativePaths = updatedSyncIndex.occupiedRelativePaths
                    occupiedRelativePaths.formUnion(indexedRelativePaths.values)
                    return occupiedRelativePaths
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
                    var occupiedRelativePaths = buildOccupiedRelativePaths(indexedRelativePaths: indexedRelativePaths)
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
                    if let accessSession = accessSessionFactory(dataFolderSelection.rootURL.path, dataFolderBookmark) {
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

                let indexedRelativePaths: [String: String]
                if updatedSyncIndex.pathAliases.isEmpty {
                    let scanExistingStart = Date()
                    indexedRelativePaths = try vaultClient.indexExistingNotes(settings: settings)
                    timings.scanExisting = Date().timeIntervalSince(scanExistingStart)
                    updatedSyncIndex.mergePathAliases(indexedRelativePaths)
                    AppLog.sync.info("Indexed \(indexedRelativePaths.count) existing synced note path(s).")
                } else {
                    indexedRelativePaths = [:]
                }

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
                var addedNoteCount = 0
                var updatedNoteCount = 0
                var unchangedNoteCount = 0
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
                        updatedSyncIndex.rememberPath(
                            syncResult.record.relativePath,
                            for: pathAliasIdentifiers(for: plannedDocument.document)
                        )
                        switch syncResult.changeKind {
                        case .created:
                            addedNoteCount += 1
                        case .updated:
                            updatedNoteCount += 1
                        case .unchanged:
                            unchangedNoteCount += 1
                        }
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
                    processedNoteCount: snapshot.documents.count,
                    addedNoteCount: addedNoteCount,
                    updatedNoteCount: updatedNoteCount,
                    unchangedNoteCount: unchangedNoteCount,
                    records: records,
                    pathAliases: updatedSyncIndex.pathAliases,
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
            syncIndex.pathAliases = result.pathAliases
            let persistStart = Date()
            let now = Date()
            syncIndex.knownFolderCount = result.folders.count
            syncIndex.lastSyncAt = now
            syncIndex.lastSyncMode = .full
            syncIndex.lastFullSyncAt = now
            syncIndex.lastFullSyncNoteCount = result.records.count
            syncIndex.lastFullSyncFolderCount = result.folders.count
            try persistence.saveSyncIndex(syncIndex)
            let persistDuration = Date().timeIntervalSince(persistStart)
            let timingSummary = result.timings.summary(persistIndex: persistDuration)
            let diagnosticsSummary = result.diagnostics.summary
            print("Sync timings: \(timingSummary)")
            let resultSummary = "\(tf("Processed %lld note(s) across %lld folder(s): updated %lld, added %lld, and left %lld unchanged.", result.processedNoteCount, result.exportedFolderCount, result.updatedNoteCount, result.addedNoteCount, result.unchangedNoteCount)) \(timingSummary)\(diagnosticsSummary.isEmpty ? "" : " \(diagnosticsSummary)")"
            statusMessage = context.finalStatusMessage(
                resultSummary: resultSummary,
                localize: t,
                format: tf
            )
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

        notesContextMonitor.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.interactionState = state
                self.formattingBarController.update(
                    selectionContext: state.selectionContext,
                    availability: state.availability,
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

        scheduleAutomaticSyncIfNeeded()
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
              !interactionState.availability.accessibilityGranted
        else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self,
                  self.isRunningBundledApp,
                  self.buildFlavor.supportsInlineEnhancements,
                  self.settings.enableInlineEnhancements,
                  !self.interactionState.availability.accessibilityGranted
            else {
                return
            }
            self.requestAccessibilityPermission()
        }
    }

    private func scheduleAutomaticSyncIfNeeded() {
        automaticSyncCancellable?.cancel()
        automaticSyncCancellable = nil
        notesDatabaseWatcher.stop()
        watcherAccessSession?.stopAccessing()
        watcherAccessSession = nil
        pendingOnChangeSyncTask?.cancel()
        pendingOnChangeSyncTask = nil

        guard settings.automaticSyncEnabled else {
            return
        }

        switch settings.automaticSyncTrigger {
        case .periodic:
            automaticSyncCancellable = Timer.publish(
                every: TimeInterval(settings.automaticSyncInterval.minutes * 60),
                on: .main,
                in: .common
            )
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.runAutomaticSyncIfNeeded()
                }
            }
        case .onChange:
            if let accessSession = resolveAppleNotesDataFolderAccessSession() {
                watcherAccessSession = accessSession
                notesDatabaseWatcher.start(dataFolderURL: accessSession.url)
            }
        }
    }

    private func handleDatabaseChange() {
        pendingOnChangeSyncTask?.cancel()
        pendingOnChangeSyncTask = Task {
            // Debounce 5 seconds
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            if Task.isCancelled { return }
            await runAutomaticSyncIfNeeded()
        }
    }

    private func runAutomaticSyncIfNeeded() async {
        guard settings.automaticSyncEnabled,
              hasVaultConfigured,
              hasAppleNotesDataFolderConfigured,
              !isSyncing
        else {
            return
        }

        await runIncrementalSync(trigger: .automatic)
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
        appleNotesDataFolderAccessSessionFactory(settings.appleNotesDataPath, settings.appleNotesDataBookmark)
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
    var processedNoteCount: Int
    var addedNoteCount: Int
    var updatedNoteCount: Int
    var unchangedNoteCount: Int
    var records: [SyncRecord]
    var pathAliases: [String: String]
    var timings: SyncTimings
    var diagnostics: SyncDiagnostics
    var migratedLegacyIDs: Set<String>
}

private struct IncrementalSyncResult {
    var folders: [AppleNotesFolder]
    var updatedRecords: [String: SyncRecord]
    var processedNoteCount: Int
    var addedNoteCount: Int
    var updatedNoteCount: Int
    var removedNoteCount: Int
    var unchangedNoteCount: Int
    var pathAliases: [String: String]
    var timings: IncrementalSyncTimings
    var diagnostics: IncrementalSyncDiagnostics
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

private enum IncrementalSyncExecutionError: LocalizedError {
    case missingChangedDocuments([String])

    var errorDescription: String? {
        switch self {
        case let .missingChangedDocuments(noteIDs):
            return "Incremental sync could not load \(noteIDs.count) changed note(s) by ID: \(noteIDs.joined(separator: ", "))"
        }
    }

    var shouldFallbackToFullSync: Bool {
        switch self {
        case .missingChangedDocuments:
            true
        }
    }

    var missingDocumentCount: Int {
        switch self {
        case let .missingChangedDocuments(noteIDs):
            return noteIDs.count
        }
    }
}

enum FullSyncRunContext {
    case direct
    case incrementalFallback(missingCount: Int)

    func initialStatusMessage(localize: (String) -> String) -> String {
        switch self {
        case .direct:
            return localize("Running a full Apple Notes sync...")
        case let .incrementalFallback(missingCount):
            return String(
                format: localize("Incremental sync could not load %lld changed note(s) by ID, so it fell back to a full sync."),
                locale: .current,
                missingCount
            )
        }
    }

    func finalStatusMessage(
        resultSummary: String,
        localize: (String) -> String,
        format: (String, CVarArg...) -> String
    ) -> String {
        switch self {
        case .direct:
            return format("Full sync: %@", resultSummary)
        case let .incrementalFallback(missingCount):
            return format(
                "Incremental sync could not load %lld changed note(s) by ID, so it fell back to a full sync. %@",
                missingCount,
                format("Full sync: %@", resultSummary)
            )
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

private struct IncrementalSyncTimings: Sendable {
    var loadManifest: TimeInterval = 0
    var loadChangedDocuments: TimeInterval = 0
    var scanExisting: TimeInterval = 0
    var removeDeleted: TimeInterval = 0
    var export: TimeInterval = 0
    var total: TimeInterval = 0

    func summary(persistIndex: TimeInterval) -> String {
        let totalDuration = total + persistIndex
        return "Total \(totalDuration.formattedDuration); manifest \(loadManifest.formattedDuration); changed \(loadChangedDocuments.formattedDuration); index \(scanExisting.formattedDuration); removed \(removeDeleted.formattedDuration); export \(export.formattedDuration); persist \(persistIndex.formattedDuration)."
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

private struct IncrementalSyncDiagnostics: Sendable {
    var skippedNotes = 0
    var unresolvedInternalLinks = 0

    var summary: String {
        var parts: [String] = []

        if skippedNotes > 0 {
            parts.append("Skipped \(skippedNotes) locked note(s).")
        }

        if unresolvedInternalLinks > 0 {
            parts.append("Left \(unresolvedInternalLinks) internal note link(s) as plain text because their targets were not exported.")
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
