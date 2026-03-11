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
    private var diagnostics: [String] = []

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
                self?.scheduleEvaluation(triggeredBySpace: false, preview: nil)
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
            recordDiagnostic(
                "keydown ignored: canRun=false frontmost=\(contextMonitor.availability.notesIsFrontmost) editable=\(contextMonitor.availability.editableFocus)"
            )
            hideMenu()
            return
        }

        recordDiagnostic(
            "keydown chars=\(event.characters ?? "<nil>") keyCode=\(event.keyCode) caret-eval scheduled"
        )

        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            scheduleEvaluation(triggeredBySpace: false, preview: nil)
            return
        }

        let triggeredBySpace = event.characters == " "
        scheduleEvaluation(
            triggeredBySpace: triggeredBySpace,
            preview: KeyEventPreview(characters: event.characters, keyCode: event.keyCode)
        )
    }

    private func scheduleEvaluation(triggeredBySpace: Bool, preview: KeyEventPreview? = nil) {
        pendingEvaluation?.cancel()
        pendingEvaluation = Task { @MainActor [weak self] in
            let delays: [Duration] = triggeredBySpace
                ? [.milliseconds(70)]
                : [.milliseconds(40), .milliseconds(120), .milliseconds(200)]

            for (index, delay) in delays.enumerated() {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }

                let didMatch = self?.evaluateState(
                    triggeredBySpace: triggeredBySpace,
                    preview: index == 0 ? preview : nil
                ) ?? false
                if triggeredBySpace || didMatch {
                    return
                }
            }
        }
    }

    @discardableResult
    private func evaluateState(triggeredBySpace: Bool, preview: KeyEventPreview?) -> Bool {
        guard contextMonitor.availability.canRunSlashCommands,
              let snapshot = contextMonitor.editingSnapshot(includeValue: true),
              let value = snapshot.value
        else {
            recordDiagnostic("snapshot unavailable for slash evaluation")
            hideMenu()
            return false
        }

        if let directResult = evaluateSnapshot(
            snapshot: snapshot,
            value: value,
            selectedRange: snapshot.selectedRange,
            triggeredBySpace: triggeredBySpace
        ) {
            recordDiagnostic(
                "evaluated current value caret=\(snapshot.selectedRange.location) len=\(snapshot.selectedRange.length) suffix=\(Self.describe(value: value, caret: snapshot.selectedRange.location))"
            )
            return directResult
        }

        let previewState = previewTextState(
            for: snapshot,
            currentValue: value,
            preview: preview
        )
        guard previewState.value != value || !NSEqualRanges(previewState.selectedRange, snapshot.selectedRange) else {
            recordDiagnostic(
                "no slash match caret=\(snapshot.selectedRange.location) suffix=\(Self.describe(value: value, caret: snapshot.selectedRange.location))"
            )
            hideMenu()
            return false
        }

        let matched = evaluateSnapshot(
            snapshot: snapshot,
            value: previewState.value,
            selectedRange: previewState.selectedRange,
            triggeredBySpace: triggeredBySpace
        ) ?? false
        recordDiagnostic(
            "evaluated preview caret=\(previewState.selectedRange.location) suffix=\(Self.describe(value: previewState.value, caret: previewState.selectedRange.location))"
        )
        return matched
    }

    @discardableResult
    private func presentMenuIfNeeded(snapshot: EditingContext, value: String, caretLocation: Int) -> Bool {
        guard let menuMatch = parser.menuMatch(in: value, caretLocation: caretLocation) else {
            hideMenu()
            return false
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
            anchorRect: menuAnchorRect(for: snapshot)
        )
        recordDiagnostic(
            "menu update entries=\(menuMatch.entries.count) selected=\(selectedIndex) anchor=\(Self.describe(rect: menuAnchorRect(for: snapshot)))"
        )
        startRefreshTimer()
        updateKeyboardNavigationAvailability(keyboardInterceptor.start())
        return true
    }

    private func hideMenu() {
        recordDiagnostic("menu hidden")
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
                self?.evaluateState(triggeredBySpace: false, preview: nil)
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
            hideMenu()
        }
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

    private func updateKeyboardNavigationAvailability(_ isAvailable: Bool) {
        guard keyboardNavigationAvailable != isAvailable else { return }
        keyboardNavigationAvailable = isAvailable
        recordDiagnostic("keyboard navigation available=\(isAvailable)")
        onKeyboardNavigationAvailabilityChanged?(isAvailable)
    }

    private func evaluateSnapshot(
        snapshot: EditingContext,
        value: String,
        selectedRange: NSRange,
        triggeredBySpace: Bool
    ) -> Bool? {
        guard selectedRange.length == 0 else {
            hideMenu()
            return false
        }

        if triggeredBySpace,
           let commitMatch = parser.commitMatchBeforeSpace(
            in: value,
            caretLocation: selectedRange.location
           )
        {
            hideMenu()
            Task {
                await executor.applySlashCommand(
                    replacementRange: commitMatch.replacementRange,
                    command: commitMatch.entry.command,
                    in: snapshot
                )
            }
            return true
        }

        if presentMenuIfNeeded(snapshot: snapshot, value: value, caretLocation: selectedRange.location) {
            return true
        }

        return nil
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

    private func previewTextState(
        for snapshot: EditingContext,
        currentValue: String,
        preview: KeyEventPreview?
    ) -> PreviewTextState {
        guard let preview else {
            return PreviewTextState(value: currentValue, selectedRange: snapshot.selectedRange)
        }

        let currentNSString = currentValue as NSString
        let clampedSelection = clamp(range: snapshot.selectedRange, toUTF16Length: currentNSString.length)

        if preview.keyCode == 51 {
            return previewDeletingBackward(in: currentNSString, selectedRange: clampedSelection)
        }

        guard let characters = preview.characters,
              isInsertablePreviewText(characters)
        else {
            return PreviewTextState(value: currentValue, selectedRange: clampedSelection)
        }

        let replacementLength = (characters as NSString).length
        let nextValue = currentNSString.replacingCharacters(in: clampedSelection, with: characters)
        return PreviewTextState(
            value: nextValue,
            selectedRange: NSRange(location: clampedSelection.location + replacementLength, length: 0)
        )
    }

    private func previewDeletingBackward(in value: NSString, selectedRange: NSRange) -> PreviewTextState {
        if selectedRange.length > 0 {
            let nextValue = value.replacingCharacters(in: selectedRange, with: "")
            return PreviewTextState(
                value: nextValue,
                selectedRange: NSRange(location: selectedRange.location, length: 0)
            )
        }

        guard selectedRange.location > 0 else {
            return PreviewTextState(value: value as String, selectedRange: selectedRange)
        }

        let deletionRange = NSRange(location: selectedRange.location - 1, length: 1)
        let nextValue = value.replacingCharacters(in: deletionRange, with: "")
        return PreviewTextState(
            value: nextValue,
            selectedRange: NSRange(location: deletionRange.location, length: 0)
        )
    }

    private func clamp(range: NSRange, toUTF16Length length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let maxLength = max(0, length - location)
        let clampedLength = min(max(0, range.length), maxLength)
        return NSRange(location: location, length: clampedLength)
    }

    private func isInsertablePreviewText(_ characters: String) -> Bool {
        guard !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy { scalar in
            scalar == " " || !CharacterSet.controlCharacters.contains(scalar)
        }
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
}

private struct KeyEventPreview {
    var characters: String?
    var keyCode: UInt16
}

private struct PreviewTextState {
    var value: String
    var selectedRange: NSRange
}
