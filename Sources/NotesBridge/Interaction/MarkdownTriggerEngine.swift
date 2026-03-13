import AppKit
import Foundation

@MainActor
final class MarkdownTriggerEngine {
    private let contextMonitor: NotesContextMonitor
    private let executor: FormattingCommandExecutor
    private var timer: Timer?
    private var lastAppliedSignature: String?

    init(contextMonitor: NotesContextMonitor, executor: FormattingCommandExecutor) {
        self.contextMonitor = contextMonitor
        self.executor = executor
    }

    func start() {
        stop()
        evaluatePendingTrigger()

        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluatePendingTrigger()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastAppliedSignature = nil
    }

    private func evaluatePendingTrigger() {
        guard contextMonitor.availability.canRunMarkdownTriggers,
              let snapshot = contextMonitor.editingSnapshot(includeValue: true),
              snapshot.selectedRange.length == 0,
              let value = snapshot.value
        else {
            return
        }

        let prefix = currentLinePrefix(in: value, caretLocation: snapshot.selectedRange.location)
        guard let match = MarkdownTriggerMatch.matching(prefix: prefix) else {
            lastAppliedSignature = nil
            return
        }

        let signature = "\(snapshot.selectedRange.location):\(match.literal)"
        guard lastAppliedSignature != signature else { return }
        lastAppliedSignature = signature

        Task {
            await executor.applyMarkdownTrigger(literalLength: match.literal.count, command: match.command)
        }
    }

    private func currentLinePrefix(in value: String, caretLocation: Int) -> String {
        let characters = Array(value)
        let safeCaret = max(0, min(caretLocation, characters.count))
        let prefixCharacters = characters[..<safeCaret]
        let lastNewlineIndex = prefixCharacters.lastIndex(of: "\n")
        let lineStart = lastNewlineIndex.map { characters.index(after: $0) } ?? characters.startIndex
        return String(characters[lineStart..<safeCaret])
    }
}

private struct MarkdownTriggerMatch {
    let literal: String
    let command: FormattingCommand

    static func matching(prefix: String) -> MarkdownTriggerMatch? {
        let matches: [MarkdownTriggerMatch] = [
            MarkdownTriggerMatch(literal: "### ", command: .subheading),
            MarkdownTriggerMatch(literal: "## ", command: .heading),
            MarkdownTriggerMatch(literal: "# ", command: .title),
            MarkdownTriggerMatch(literal: "[] ", command: .checklist),
            MarkdownTriggerMatch(literal: "``` ", command: .monostyled),
            MarkdownTriggerMatch(literal: "> ", command: .quote),
            MarkdownTriggerMatch(literal: "- ", command: .dashedList),
            MarkdownTriggerMatch(literal: "* ", command: .bulletedList),
            MarkdownTriggerMatch(literal: "1. ", command: .numberedList),
        ]

        return matches.first(where: { prefix == $0.literal })
    }
}
