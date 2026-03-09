import AppKit
import Foundation

@MainActor
final class SlashCommandEngine {
    private let contextMonitor: NotesContextMonitor
    private let executor: FormattingCommandExecutor
    private let parser = SlashCommandParser()
    var onKeyboardNavigationAvailabilityChanged: ((Bool) -> Void)?

    private lazy var menuController = SlashCommandMenuController(
        onHoverIndex: { [weak self] index in
            self?.updateSelection(index)
        },
        onSelectIndex: { [weak self] index in
            self?.commitSelection(at: index)
        }
    )

    private lazy var keyboardInterceptor = SlashCommandKeyboardInterceptor { [weak self] action in
        self?.handleKeyboardAction(action)
    }

    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var pendingEvaluation: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var menuMatch: SlashCommandMenuMatch?
    private var selectedIndex = 0
    private var currentEditingContext: EditingContext?
    private var keyboardNavigationAvailable = true

    init(contextMonitor: NotesContextMonitor, executor: FormattingCommandExecutor) {
        self.contextMonitor = contextMonitor
        self.executor = executor
    }

    func start() {
        stop()

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDown(event)
            }
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleEvaluation(triggeredBySpace: false, delay: .milliseconds(120))
            }
        }
    }

    func stop() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }

        globalKeyMonitor = nil
        globalMouseMonitor = nil
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
        stopRefreshTimer()
        hideMenu()
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard contextMonitor.availability.canRunSlashCommands else {
            hideMenu()
            return
        }

        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            scheduleEvaluation(triggeredBySpace: false, delay: .milliseconds(40))
            return
        }

        let triggeredBySpace = event.characters == " "
        let delay: Duration = triggeredBySpace ? .milliseconds(55) : .milliseconds(40)
        scheduleEvaluation(triggeredBySpace: triggeredBySpace, delay: delay)
    }

    private func scheduleEvaluation(triggeredBySpace: Bool, delay: Duration) {
        pendingEvaluation?.cancel()
        pendingEvaluation = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.evaluateState(triggeredBySpace: triggeredBySpace)
        }
    }

    private func evaluateState(triggeredBySpace: Bool) {
        guard contextMonitor.availability.canRunSlashCommands,
              let snapshot = contextMonitor.editingSnapshot(includeValue: true),
              snapshot.selectedRange.length == 0,
              let value = snapshot.value
        else {
            hideMenu()
            return
        }

        if triggeredBySpace,
           let commitMatch = parser.commitMatchBeforeSpace(in: value, caretLocation: snapshot.selectedRange.location)
        {
            hideMenu()
            Task {
                await executor.applySlashCommand(
                    replacementRange: commitMatch.replacementRange,
                    command: commitMatch.entry.command,
                    in: snapshot
                )
            }
            return
        }

        presentMenuIfNeeded(snapshot: snapshot, value: value)
    }

    private func presentMenuIfNeeded(snapshot: EditingContext, value: String) {
        guard let menuMatch = parser.menuMatch(in: value, caretLocation: snapshot.selectedRange.location) else {
            hideMenu()
            return
        }

        currentEditingContext = snapshot

        let shouldResetSelection = self.menuMatch?.token.range != menuMatch.token.range
            || self.menuMatch?.entries != menuMatch.entries
        self.menuMatch = menuMatch
        if shouldResetSelection {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, max(0, menuMatch.entries.count - 1))
        }

        menuController.update(
            entries: menuMatch.entries,
            selectedIndex: selectedIndex,
            anchorRect: snapshot.selectionRect
        )
        startRefreshTimer()
        updateKeyboardNavigationAvailability(keyboardInterceptor.start())
    }

    private func hideMenu() {
        menuMatch = nil
        currentEditingContext = nil
        selectedIndex = 0
        keyboardInterceptor.stop()
        menuController.hide()
        stopRefreshTimer()
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateState(triggeredBySpace: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func handleKeyboardAction(_ action: SlashCommandKeyboardAction) {
        guard let menuMatch else { return }

        switch action {
        case .moveUp:
            selectedIndex = (selectedIndex - 1 + menuMatch.entries.count) % menuMatch.entries.count
            menuController.update(
                entries: menuMatch.entries,
                selectedIndex: selectedIndex,
                anchorRect: currentEditingContext?.selectionRect
            )
        case .moveDown:
            selectedIndex = (selectedIndex + 1) % menuMatch.entries.count
            menuController.update(
                entries: menuMatch.entries,
                selectedIndex: selectedIndex,
                anchorRect: currentEditingContext?.selectionRect
            )
        case .commit:
            commitSelection(at: selectedIndex)
        case .dismiss:
            hideMenu()
        }
    }

    private func updateSelection(_ index: Int) {
        guard let menuMatch, menuMatch.entries.indices.contains(index) else { return }
        selectedIndex = index
        menuController.update(
            entries: menuMatch.entries,
            selectedIndex: selectedIndex,
            anchorRect: currentEditingContext?.selectionRect
        )
    }

    private func commitSelection(at index: Int) {
        guard let menuMatch,
              let currentEditingContext,
              menuMatch.entries.indices.contains(index)
        else {
            hideMenu()
            return
        }

        let entry = menuMatch.entries[index]
        let replacementRange = menuMatch.token.range
        hideMenu()

        Task {
            await executor.applySlashCommand(
                replacementRange: replacementRange,
                command: entry.command,
                in: currentEditingContext
            )
        }
    }

    private func updateKeyboardNavigationAvailability(_ isAvailable: Bool) {
        guard keyboardNavigationAvailable != isAvailable else { return }
        keyboardNavigationAvailable = isAvailable
        onKeyboardNavigationAvailabilityChanged?(isAvailable)
    }
}
