import AppKit
import Foundation

@MainActor
final class SlashCommandEngine {
    private let contextMonitor: NotesContextMonitor
    private let executor: FormattingCommandExecutor
    private let parser = SlashCommandParser()
    var onKeyboardNavigationAvailabilityChanged: ((Bool) -> Void)?
    var onDiagnosticsChanged: (([String]) -> Void)?

    private lazy var menuController = SlashCommandMenuController(
        onHoverIndex: { [weak self] index in
            self?.updateSelection(index)
        },
        onSelectIndex: { [weak self] index in
            self?.commitSelection(at: index)
        },
        onFrameUpdated: { [weak self] frame in
            self?.recordDiagnostic("menu frame: \(Self.describe(rect: frame))")
        },
        onKeyboardAction: { [weak self] action in
            self?.handleKeyboardAction(action)
        },
        onPassthroughKeyDown: { [weak self] event in
            self?.handlePassthroughKeyDown(event)
        }
    )

    private var refreshTimer: Timer?
    private var menuMatch: SlashCommandMenuMatch?
    private var selectedIndex = 0
    private var currentEditingContext: EditingContext?
    private var diagnostics: [String] = []
    private var lastCommittedSignature: String?
    private var dismissedTokenSignature: String?

    init(contextMonitor: NotesContextMonitor, executor: FormattingCommandExecutor) {
        self.contextMonitor = contextMonitor
        self.executor = executor
    }

    func start() {
        stop()
        updateKeyboardNavigationAvailability(false)
        evaluateState()

        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        hideMenu()
        lastCommittedSignature = nil
        dismissedTokenSignature = nil
        updateKeyboardNavigationAvailability(false)
    }

    private func evaluateState() {
        let hasActiveMenuSession = menuController.isVisible
            && menuController.isKeyWindow
            && currentEditingContext != nil

        let snapshot: EditingContext?
        if hasActiveMenuSession,
           let currentEditingContext
        {
            snapshot = contextMonitor.editingSnapshot(from: currentEditingContext.element, includeValue: true)
            recordDiagnostic("slash panel owns keyboard focus; refreshing from cached notes editor")
        } else {
            guard contextMonitor.availability.canRunSlashCommands else {
                recordDiagnostic("snapshot unavailable for slash evaluation")
                lastCommittedSignature = nil
                hideMenu()
                return
            }
            snapshot = contextMonitor.editingSnapshot(includeValue: true)
        }

        guard let snapshot,
              snapshot.selectedRange.length == 0,
              let value = snapshot.value
        else {
            recordDiagnostic("snapshot unavailable for slash evaluation")
            lastCommittedSignature = nil
            hideMenu()
            return
        }

        if let commitMatch = parser.commitMatchBeforeSpace(
            in: value,
            caretLocation: snapshot.selectedRange.location
        ) {
            let signature = "\(commitMatch.replacementRange.location):\(commitMatch.replacementRange.length):\(commitMatch.entry.id)"
            if lastCommittedSignature != signature {
                lastCommittedSignature = signature
                dismissedTokenSignature = nil
                hideMenu()
                Task {
                    await executor.applySlashCommand(
                        replacementRange: commitMatch.replacementRange,
                        command: commitMatch.entry.command,
                        in: snapshot
                    )
                }
            }
            return
        }

        lastCommittedSignature = nil

        guard let menuMatch = parser.menuMatch(in: value, caretLocation: snapshot.selectedRange.location) else {
            dismissedTokenSignature = nil
            recordDiagnostic(
                "no slash match caret=\(snapshot.selectedRange.location) suffix=\(Self.describe(value: value, caret: snapshot.selectedRange.location))"
            )
            hideMenu()
            return
        }

        let tokenSignature = Self.tokenSignature(for: menuMatch.token)
        if dismissedTokenSignature == tokenSignature {
            recordDiagnostic("menu suppressed for dismissed token \(menuMatch.token.rawValue)")
            return
        }
        dismissedTokenSignature = nil

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
            anchorRect: menuAnchorRect(for: snapshot)
        )
        updateKeyboardNavigationAvailability(true)
        recordDiagnostic(
            "menu update entries=\(menuMatch.entries.count) selected=\(selectedIndex) anchor=\(Self.describe(rect: menuAnchorRect(for: snapshot)))"
        )
    }

    private func hideMenu() {
        if menuMatch != nil {
            recordDiagnostic("menu hidden")
        }
        menuMatch = nil
        currentEditingContext = nil
        selectedIndex = 0
        menuController.hide()
        updateKeyboardNavigationAvailability(false)
    }

    private func updateSelection(_ index: Int) {
        guard let menuMatch, menuMatch.entries.indices.contains(index) else { return }
        selectedIndex = index
        menuController.update(
            entries: menuMatch.entries,
            selectedIndex: selectedIndex,
            anchorRect: currentEditingContext.flatMap(menuAnchorRect)
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

    private func handleKeyboardAction(_ action: SlashCommandKeyboardAction) {
        guard let menuMatch else { return }

        switch action {
        case .moveUp:
            selectedIndex = (selectedIndex - 1 + menuMatch.entries.count) % menuMatch.entries.count
            menuController.update(
                entries: menuMatch.entries,
                selectedIndex: selectedIndex,
                anchorRect: currentEditingContext.flatMap(menuAnchorRect)
            )
        case .moveDown:
            selectedIndex = (selectedIndex + 1) % menuMatch.entries.count
            menuController.update(
                entries: menuMatch.entries,
                selectedIndex: selectedIndex,
                anchorRect: currentEditingContext.flatMap(menuAnchorRect)
            )
        case .commit:
            commitSelection(at: selectedIndex)
        case .dismiss:
            dismissedTokenSignature = self.menuMatch.map { Self.tokenSignature(for: $0.token) }
            hideMenu()
        }
    }

    private func handlePassthroughKeyDown(_ event: NSEvent) {
        guard menuMatch != nil else { return }
        executor.forwardKeyEventToAppleNotes(event)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(45))
            self?.evaluateState()
        }
    }

    private func updateKeyboardNavigationAvailability(_ isAvailable: Bool) {
        onKeyboardNavigationAvailabilityChanged?(isAvailable)
    }

    private func menuAnchorRect(for snapshot: EditingContext) -> CGRect? {
        if let selectionRect = snapshot.selectionRect {
            return selectionRect
        }

        guard let elementRect = snapshot.elementRect else {
            return nil
        }

        return CGRect(
            x: elementRect.minX + 24,
            y: elementRect.minY + 18,
            width: 1,
            height: min(24, max(16, elementRect.height))
        )
    }

    private func recordDiagnostic(_ message: String) {
        guard diagnostics.last != message else { return }
        diagnostics.append(message)
        if diagnostics.count > 8 {
            diagnostics.removeFirst(diagnostics.count - 8)
        }
        onDiagnosticsChanged?(diagnostics)
    }

    private static func describe(value: String, caret: Int) -> String {
        let string = value as NSString
        let safeCaret = min(max(0, caret), string.length)
        let start = max(0, safeCaret - 20)
        let length = min(string.length - start, 40)
        let snippet = string.substring(with: NSRange(location: start, length: length))
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(snippet)\"@\(safeCaret)"
    }

    private static func describe(rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return String(
            format: "(x:%.1f y:%.1f w:%.1f h:%.1f)",
            rect.origin.x,
            rect.origin.y,
            rect.size.width,
            rect.size.height
        )
    }

    private static func tokenSignature(for token: SlashCommandToken) -> String {
        "\(token.range.location):\(token.range.length):\(token.rawValue)"
    }
}
