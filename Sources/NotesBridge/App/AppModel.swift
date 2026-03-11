import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            persistSettings()
            notesContextMonitor.updateSettings(settings)
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
        permissionsManager: PermissionsManager = PermissionsManager(),
        statusObserver: (@MainActor @Sendable (String) -> Void)? = nil,
        startImmediately: Bool = true
    ) {
        self.notesClient = notesClient
        self.appleNotesSyncDataSource = appleNotesSyncDataSource
        self.appleNotesDataFolderSelector = appleNotesDataFolderSelector
        self.syncEngine = syncEngine
        self.vaultClient = vaultClient
        self.bundledAppLauncher = bundledAppLauncher
        self.persistence = persistence
        self.permissionsManager = permissionsManager
        self.buildFlavor = BuildFlavor.current

        let loadedSettings = persistence.loadSettings()
        let loadedSyncIndex = persistence.loadSyncIndex()
        let notesContextMonitor = NotesContextMonitor(
            buildFlavor: BuildFlavor.current,
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
        self.interactionAvailability = .default(for: BuildFlavor.current)
        self.slashCommandEngine.onKeyboardNavigationAvailabilityChanged = { [weak self] isAvailable in
            self?.slashKeyboardNavigationAvailable = isAvailable
        }
        self.slashCommandEngine.onDiagnosticsChanged = { [weak self] diagnostics in
            self?.slashDiagnostics = diagnostics
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

    var syncedNoteCount: Int {
        syncIndex.records.count
    }

    var isRunningBundledApp: Bool {
        bundledAppLauncher.isRunningBundledApp
    }

    var lastFullSyncLabel: String {
        guard let lastFullSyncAt = syncIndex.lastFullSyncAt else { return "Never" }
        return lastFullSyncAt.formatted(date: .abbreviated, time: .shortened)
    }

    var indexedFolderCount: Int {
        syncIndex.lastFullSyncFolderCount ?? folderSummaries.count
    }

    var selectionSummary: String {
        guard let selectionContext, selectionContext.hasSelection else {
            return "No text selected"
        }

        let snippet = selectionContext.selectedText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return snippet.isEmpty ? "Selected text ready" : snippet
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
            return "Slash commands are unavailable in the Mac App Store build."
        }
        if !settings.enableInlineEnhancements {
            return "Slash commands are disabled with inline enhancements."
        }
        if !settings.enableSlashCommands {
            return "Slash commands are turned off in Settings."
        }
        if !interactionAvailability.accessibilityGranted {
            if isRunningBundledApp {
                return "Accessibility permission is required for slash commands. If NotesBridge is already checked in Accessibility, remove and re-add the current app bundle once."
            }
            return "Accessibility permission is required for slash commands."
        }
        if !interactionAvailability.notesIsFrontmost {
            return "Bring Apple Notes to the front to use slash commands."
        }
        if !interactionAvailability.editableFocus {
            return "Focus the Apple Notes editor to use slash commands."
        }
        if !interactionAvailability.inputMonitoringGranted {
            return "Slash commands are active. Keyboard navigation is unavailable; use the mouse or exact command + Space."
        }
        if !slashKeyboardNavigationAvailable {
            return "Slash commands are active. Keyboard navigation is unavailable; use the mouse."
        }
        return "Type / for suggestions, or complete a slash command and press Space."
    }

    var inlineEnhancementsSummary: String {
        if !buildFlavor.supportsInlineEnhancements {
            return "Inline enhancements are disabled in the Mac App Store build."
        }
        if isRunningBundledApp && !interactionAvailability.accessibilityGranted {
            return "Grant Accessibility to NotesBridge. If it is already checked, remove and re-add the current app bundle once."
        }
        if !isRunningBundledApp && !interactionAvailability.inputMonitoringGranted {
            return "Inline enhancements are active. Launch as a bundled app if you want macOS to offer Input Monitoring for slash menu keyboard navigation."
        }
        return interactionAvailability.summary
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

    func requestAccessibilityPermission() {
        statusMessage = "Requesting Accessibility permission for NotesBridge..."
        permissionsManager.requestAccessibilityPermission()
        notesContextMonitor.updateSettings(settings)
        if interactionAvailability.accessibilityGranted {
            statusMessage = "Accessibility is already granted for NotesBridge."
        } else if isRunningBundledApp {
            _ = permissionsManager.openAccessibilitySettings()
            statusMessage = "Open Privacy & Security > Accessibility and enable NotesBridge. If it is missing, add ~/Library/Application Support/NotesBridge/NotesBridge.app manually."
        } else {
            _ = permissionsManager.openAccessibilitySettings()
            statusMessage = "Open Privacy & Security > Accessibility and enable NotesBridge."
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

        statusMessage = "Requesting Input Monitoring permission for slash menu keyboard navigation..."
        permissionsManager.requestInputMonitoringPermission()
        notesContextMonitor.updateSettings(settings)
        if interactionAvailability.inputMonitoringGranted {
            statusMessage = "Input Monitoring is already granted for NotesBridge."
        } else {
            _ = permissionsManager.openInputMonitoringSettings()
            statusMessage = "Open Privacy & Security > Input Monitoring to enable slash menu keyboard navigation for NotesBridge."
        }
    }

    func openInputMonitoringSettings() {
        permissionsManager.openInputMonitoringSettings()
    }

    func relaunchAsBundledApp(requestInputMonitoringOnLaunch: Bool = false) {
        statusMessage = requestInputMonitoringOnLaunch
            ? "Relaunching NotesBridge as a bundled app so macOS can grant Input Monitoring..."
            : "Relaunching NotesBridge as a bundled app..."

        bundledAppLauncher.relaunchCurrentExecutableAsBundledApp(
            requestInputMonitoringOnLaunch: requestInputMonitoringOnLaunch
        ) { [weak self] result in
            switch result {
            case .success:
                NSApplication.shared.terminate(nil)
            case let .failure(error):
                self?.present(error, fallback: "Failed to relaunch NotesBridge as a bundled app.")
            }
        }
    }

    func chooseVaultDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Obsidian vault"
        panel.prompt = "Use Vault"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.vaultPath = url.path
        statusMessage = "Obsidian vault set to \(url.lastPathComponent)."
    }

    func chooseAppleNotesDataFolder() {
        guard let url = appleNotesDataFolderSelector.chooseAppleNotesDataFolder() else {
            return
        }

        do {
            let selection = try appleNotesSyncDataSource.validateDataFolder(at: url.path)
            settings.appleNotesDataPath = selection.rootURL.path
            statusMessage = "Apple Notes data folder set to \(selection.rootURL.lastPathComponent)."
        } catch {
            present(error, fallback: "Failed to access Apple Notes data folder.")
        }
    }

    func revealVault() {
        guard let vaultPath = settings.vaultPath else { return }
        vaultClient.revealVault(at: vaultPath)
    }

    private func ensureAppleNotesDataFolderSelectionForSync() -> AppleNotesDataFolderSelection? {
        if let appleNotesDataPath = settings.appleNotesDataPath,
           !appleNotesDataPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            do {
                return try appleNotesSyncDataSource.validateDataFolder(at: appleNotesDataPath)
            } catch {
                settings.appleNotesDataPath = nil
            }
        }

        guard let selectedURL = appleNotesDataFolderSelector.chooseAppleNotesDataFolder() else {
            presentMessage("Sync cancelled. Choose the Apple Notes data folder to continue.")
            return nil
        }

        do {
            let selection = try appleNotesSyncDataSource.validateDataFolder(at: selectedURL.path)
            settings.appleNotesDataPath = selection.rootURL.path
            statusMessage = "Apple Notes data folder set to \(selection.rootURL.lastPathComponent)."
            return selection
        } catch {
            present(error, fallback: "Failed to access Apple Notes data folder.")
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
        isRefreshingFolders = true
        statusMessage = "Refreshing Apple Notes folders..."

        defer {
            isRefreshingFolders = false
        }

        do {
            let fetchedFolders = try await Task.detached(priority: .userInitiated) {
                if let appleNotesDataPath, !appleNotesDataPath.isEmpty {
                    return try appleNotesSyncDataSource.fetchFolders(fromDataFolder: appleNotesDataPath)
                }
                return try notesClient.fetchFolders()
            }.value

            folderSummaries = fetchedFolders.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            statusMessage = "Loaded \(folderSummaries.count) Apple Notes folders."
        } catch {
            present(error, fallback: "Failed to refresh Apple Notes folders.")
        }
    }

    func syncAllNotes() async {
        guard hasVaultConfigured else {
            presentMessage("Choose an Obsidian vault before syncing.")
            return
        }

        guard let dataFolderSelection = ensureAppleNotesDataFolderSelectionForSync() else {
            return
        }

        let appleNotesSyncDataSource = self.appleNotesSyncDataSource
        let syncEngine = self.syncEngine
        let vaultClient = self.vaultClient
        let settings = self.settings
        let existingRecords = self.syncIndex.records
        let progressReporter = makeSyncProgressReporter()

        isSyncing = true
        startSyncAnimation()
        syncProgress = nil
        errorMessage = nil
        statusMessage = "Syncing Apple Notes to Obsidian..."

        defer {
            isSyncing = false
            stopSyncAnimation()
            syncProgress = nil
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

                let loadSnapshotStart = Date()
                let snapshot = try appleNotesSyncDataSource.loadSnapshot(fromDataFolder: dataFolderSelection.rootURL.path)
                timings.loadSnapshot = Date().timeIntervalSince(loadSnapshotStart)

                let scanExistingStart = Date()
                let indexedRelativePaths = try vaultClient.indexExistingNotes(settings: settings)
                timings.scanExisting = Date().timeIntervalSince(scanExistingStart)

                let folders = snapshot.folders.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                diagnostics.skippedNotes = snapshot.skippedLockedNotes
                diagnostics.sourceDiagnostics = snapshot.sourceDiagnostics
                let (exportGroups, fallbackDocumentCount) = buildExportGroups(
                    folders: folders,
                    documents: snapshot.documents,
                    skippedNotesByFolder: snapshot.skippedLockedNotesByFolder
                )
                diagnostics.fallbackGroupedDocuments = fallbackDocumentCount
                var records: [SyncRecord] = []
                var migratedLegacyIDs: Set<String> = []
                var progress = SyncProgress(
                    completedNotes: 0,
                    totalNotes: folders.reduce(0) { $0 + $1.noteCount },
                    completedFolders: 0,
                    totalFolders: max(exportGroups.count, 1),
                    currentFolderName: nil,
                    skippedNotes: 0
                )
                await progressReporter.publish(progress)

                for group in exportGroups {
                    progress.enterFolder(group.displayName)
                    await progressReporter.publish(progress)

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
                        let exportStart = Date()
                        let record = try syncEngine.sync(
                            document: document,
                            settings: settings,
                            existingRelativePath: existingRelativePath
                        )
                        timings.export += Date().timeIntervalSince(exportStart)
                        records.append(record)
                        progress.markProcessedNotes()
                        await progressReporter.publish(progress)
                    }

                    progress.markSkippedNotes(group.skippedCount)
                    progress.markCompletedFolder()
                    await progressReporter.publish(progress)
                }

                if exportGroups.isEmpty && !snapshot.documents.isEmpty {
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
                    exportedFolderCount: exportGroups.count,
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
            statusMessage = "Synced \(result.records.count) note(s) across \(result.exportedFolderCount) folder(s). \(timingSummary)\(diagnosticsSummary.isEmpty ? "" : " \(diagnosticsSummary)")"
        } catch {
            present(error, fallback: "Failed to sync Apple Notes to Obsidian.")
        }
    }

    func persistSettings() {
        do {
            try persistence.saveSettings(settings)
        } catch {
            present(error, fallback: "Failed to save app settings.")
        }
    }

    private func bindInteractionState() {
        notesContextMonitor.$availability
            .receive(on: RunLoop.main)
            .sink { [weak self] availability in
                guard let self else { return }
                self.interactionAvailability = availability
                self.formattingBarController.update(
                    selectionContext: self.selectionContext,
                    availability: availability
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
                    availability: self.interactionAvailability
                )
            }
            .store(in: &cancellables)
    }

    private func start() {
        notesContextMonitor.start()
        if buildFlavor.supportsInlineEnhancements {
            markdownTriggerEngine.start()
            slashCommandEngine.start()
        }

        scheduleAccessibilityPromptIfNeeded()

        Task {
            await refreshFolderSummaries()
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
    case noDocumentsMatchedFolders(String)

    var errorDescription: String? {
        switch self {
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

        return parts.joined(separator: " ")
    }
}

private struct FolderExportGroup: Sendable {
    var displayName: String
    var documents: [AppleNotesSyncDocument]
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
