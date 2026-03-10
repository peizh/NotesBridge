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
    @Published private(set) var slashKeyboardNavigationAvailable = true
    @Published var errorMessage: String?
    @Published var statusMessage = "Ready"

    private let notesClient: any AppleNotesClient
    private let transformer: MarkdownTransformer
    private let syncEngine: SyncEngine
    private let vaultClient: ObsidianVaultClient
    private let persistence: PersistenceStore
    private let permissionsManager: PermissionsManager
    private let notesContextMonitor: NotesContextMonitor
    private let formattingCommandExecutor: FormattingCommandExecutor
    private let markdownTriggerEngine: MarkdownTriggerEngine
    private let slashCommandEngine: SlashCommandEngine
    private let formattingBarController: FloatingFormattingBarController
    private var syncIndex: SyncIndex
    private var cancellables: Set<AnyCancellable> = []

    init(
        notesClient: any AppleNotesClient = AppleNotesScriptClient(),
        transformer: MarkdownTransformer = MarkdownTransformer(),
        syncEngine: SyncEngine = SyncEngine(),
        vaultClient: ObsidianVaultClient = ObsidianVaultClient(),
        persistence: PersistenceStore = PersistenceStore(),
        permissionsManager: PermissionsManager = PermissionsManager()
    ) {
        self.notesClient = notesClient
        self.transformer = transformer
        self.syncEngine = syncEngine
        self.vaultClient = vaultClient
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
        self.interactionAvailability = .default(for: BuildFlavor.current)
        self.slashCommandEngine.onKeyboardNavigationAvailabilityChanged = { [weak self] isAvailable in
            self?.slashKeyboardNavigationAvailable = isAvailable
        }

        bindInteractionState()
        start()
    }

    var hasVaultConfigured: Bool {
        settings.hasValidVaultPath
    }

    var syncedNoteCount: Int {
        syncIndex.records.count
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
            return "arrow.triangle.2.circlepath.circle.fill"
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
            return "Accessibility permission is required for slash commands."
        }
        if !slashKeyboardNavigationAvailable {
            return "Slash commands are active. Keyboard navigation is unavailable; use the mouse or an exact command plus Space."
        }
        return "Type / for suggestions, or complete a slash command and press Space."
    }

    func requestAccessibilityPermission() {
        permissionsManager.requestAccessibilityPermission()
        notesContextMonitor.updateSettings(settings)
    }

    func openAccessibilitySettings() {
        permissionsManager.openAccessibilitySettings()
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

    func revealVault() {
        guard let vaultPath = settings.vaultPath else { return }
        vaultClient.revealVault(at: vaultPath)
    }

    func openAppleNotes() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
    }

    func refreshFolderSummaries() async {
        let notesClient = self.notesClient
        isRefreshingFolders = true
        statusMessage = "Refreshing Apple Notes folders..."

        defer {
            isRefreshingFolders = false
        }

        do {
            let fetchedFolders = try await Task.detached(priority: .userInitiated) {
                try notesClient.fetchFolders()
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

        let notesClient = self.notesClient
        let transformer = self.transformer
        let syncEngine = self.syncEngine
        let settings = self.settings
        let existingRecords = self.syncIndex.records

        isSyncing = true
        statusMessage = "Syncing Apple Notes to Obsidian..."

        defer {
            isSyncing = false
        }

        do {
            let result = try await Task.detached(priority: .utility) {
                let totalStart = Date()
                var timings = SyncTimings()
                var diagnostics = SyncDiagnostics()

                let fetchFoldersStart = Date()
                let folders = try notesClient.fetchFolders()
                timings.fetchFolders = Date().timeIntervalSince(fetchFoldersStart)
                var records: [SyncRecord] = []

                for folder in folders {
                    let fetchResult = try FolderDocumentFetcher.fetchDocuments(
                        for: folder,
                        using: notesClient,
                        timings: &timings
                    )
                    diagnostics.incrementalFolders += fetchResult.mode == .incremental ? 1 : 0
                    diagnostics.skippedNotes += fetchResult.skippedCount

                    for document in fetchResult.documents {
                        let transformStart = Date()
                        let markdown = transformer.htmlToMarkdown(
                            document.htmlBody,
                            fallbackPlaintext: document.plaintext
                        )
                        timings.transform += Date().timeIntervalSince(transformStart)

                        let exportStart = Date()
                        let record = try syncEngine.sync(
                            document: document,
                            markdown: markdown,
                            settings: settings,
                            existingRelativePath: existingRecords[document.id]?.relativePath
                        )
                        timings.export += Date().timeIntervalSince(exportStart)
                        records.append(record)
                    }
                }

                timings.total = Date().timeIntervalSince(totalStart)

                return FullSyncResult(
                    folders: folders,
                    records: records,
                    timings: timings,
                    diagnostics: diagnostics
                )
            }.value

            folderSummaries = result.folders.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            for record in result.records {
                syncIndex.records[record.noteID] = record
            }
            let persistStart = Date()
            syncIndex.lastFullSyncAt = Date()
            syncIndex.lastFullSyncNoteCount = result.records.count
            syncIndex.lastFullSyncFolderCount = result.folders.count
            try persistence.saveSyncIndex(syncIndex)
            let persistDuration = Date().timeIntervalSince(persistStart)
            let timingSummary = result.timings.summary(persistIndex: persistDuration)
            let diagnosticsSummary = result.diagnostics.summary
            print("Sync timings: \(timingSummary)")
            statusMessage = "Synced \(result.records.count) note(s) across \(result.folders.count) folder(s). \(timingSummary)\(diagnosticsSummary.isEmpty ? "" : " \(diagnosticsSummary)")"
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

        Task {
            await refreshFolderSummaries()
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
}

private struct FullSyncResult {
    var folders: [AppleNotesFolder]
    var records: [SyncRecord]
    var timings: SyncTimings
    var diagnostics: SyncDiagnostics
}

private struct SyncTimings: Sendable {
    var fetchFolders: TimeInterval = 0
    var fetchDocuments: TimeInterval = 0
    var transform: TimeInterval = 0
    var export: TimeInterval = 0
    var total: TimeInterval = 0

    func summary(persistIndex: TimeInterval) -> String {
        let totalDuration = total + persistIndex
        return "Total \(totalDuration.formattedDuration); folders \(fetchFolders.formattedDuration); documents \(fetchDocuments.formattedDuration); transform \(transform.formattedDuration); export \(export.formattedDuration); persist \(persistIndex.formattedDuration)."
    }
}

private struct SyncDiagnostics: Sendable {
    var incrementalFolders = 0
    var skippedNotes = 0

    var summary: String {
        var parts: [String] = []

        if incrementalFolders > 0 {
            parts.append("Incremental fetch used for \(incrementalFolders) folder(s).")
        }

        if skippedNotes > 0 {
            parts.append("Skipped \(skippedNotes) locked or missing note(s).")
        }

        return parts.joined(separator: " ")
    }
}

private enum FolderDocumentFetchMode: Sendable {
    case batch
    case incremental
}

private struct FolderDocumentFetchResult: Sendable {
    var documents: [AppleNoteDocument]
    var mode: FolderDocumentFetchMode
    var skippedCount: Int = 0
}

private enum FolderDocumentFetcher {
    private static let maxBatchDocumentCount = 25

    static func fetchDocuments(
        for folder: AppleNotesFolder,
        using notesClient: any AppleNotesClient,
        timings: inout SyncTimings
    ) throws -> FolderDocumentFetchResult {
        if folder.noteCount <= maxBatchDocumentCount {
            let batchStart = Date()
            do {
                let documents = try notesClient.fetchDocuments(inFolderID: folder.id)
                timings.fetchDocuments += Date().timeIntervalSince(batchStart)
                return FolderDocumentFetchResult(
                    documents: sortedDocuments(documents),
                    mode: .batch
                )
            } catch {
                timings.fetchDocuments += Date().timeIntervalSince(batchStart)
                print("Falling back to incremental note fetch for \(folder.displayName): \(error.localizedDescription)")
            }
        }

        let summariesStart = Date()
        let summaries = try notesClient.fetchNoteSummaries(inFolderID: folder.id)
        timings.fetchDocuments += Date().timeIntervalSince(summariesStart)

        var documents: [AppleNoteDocument] = []
        var skippedCount = 0

        for summary in sortedSummaries(summaries) {
            if summary.passwordProtected {
                skippedCount += 1
                continue
            }

            let documentStart = Date()
            do {
                documents.append(try notesClient.fetchDocument(id: summary.id, inFolderID: folder.id))
            } catch let error as AppleNotesError {
                switch error {
                case .lockedNote, .noteNotFound:
                    skippedCount += 1
                    print("Skipping \(summary.displayName) in \(folder.displayName): \(error.localizedDescription)")
                case .invalidResponse:
                    throw error
                }
            }
            timings.fetchDocuments += Date().timeIntervalSince(documentStart)
        }

        return FolderDocumentFetchResult(
            documents: sortedDocuments(documents),
            mode: .incremental,
            skippedCount: skippedCount
        )
    }

    private static func sortedDocuments(_ documents: [AppleNoteDocument]) -> [AppleNoteDocument] {
        documents.sorted {
            let nameComparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return $0.id < $1.id
        }
    }

    private static func sortedSummaries(_ summaries: [AppleNoteSummary]) -> [AppleNoteSummary] {
        summaries.sorted {
            let nameComparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return $0.id < $1.id
        }
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        String(format: "%.2fs", self)
    }
}
