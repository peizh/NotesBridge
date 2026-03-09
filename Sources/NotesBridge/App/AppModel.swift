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

        isSyncing = true
        statusMessage = "Syncing Apple Notes to Obsidian..."

        defer {
            isSyncing = false
        }

        do {
            let result = try await Task.detached(priority: .utility) {
                let folders = try notesClient.fetchFolders()
                var records: [SyncRecord] = []

                for folder in folders {
                    let summaries = try notesClient.fetchNoteSummaries(inFolderID: folder.id)
                    for summary in summaries where !summary.passwordProtected {
                        let document = try notesClient.fetchDocument(id: summary.id)
                        let markdown = transformer.htmlToMarkdown(document.htmlBody)
                        let record = try syncEngine.sync(document: document, markdown: markdown, settings: settings)
                        records.append(record)
                    }
                }

                return FullSyncResult(
                    folders: folders,
                    records: records
                )
            }.value

            folderSummaries = result.folders.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            for record in result.records {
                syncIndex.records[record.noteID] = record
            }
            syncIndex.lastFullSyncAt = Date()
            syncIndex.lastFullSyncNoteCount = result.records.count
            syncIndex.lastFullSyncFolderCount = result.folders.count
            try persistence.saveSyncIndex(syncIndex)
            statusMessage = "Synced \(result.records.count) note(s) across \(result.folders.count) folder(s)."
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
        errorMessage = error.localizedDescription.isEmpty ? fallback : error.localizedDescription
        statusMessage = fallback
    }

    private func presentMessage(_ message: String) {
        errorMessage = message
        statusMessage = message
    }
}

private struct FullSyncResult {
    var folders: [AppleNotesFolder]
    var records: [SyncRecord]
}
