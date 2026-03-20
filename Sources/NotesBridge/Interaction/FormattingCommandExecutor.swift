import AppKit
import CoreGraphics
import Foundation

@MainActor
final class FormattingCommandExecutor {
    private let notesBundleIdentifier = "com.apple.Notes"
    private let deleteKeyCode: CGKeyCode = 51
    private let runner: ProcessRunner

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    func perform(_ command: FormattingCommand) {
        Task {
            await performAsync(command)
        }
    }

    func performAsync(_ command: FormattingCommand) async {
        guard isAppleNotesFrontmost,
              let notesPID = appleNotesProcessID
        else {
            return
        }
        if await performViaMenuItem(command) {
            return
        }
        guard let shortcut = command.shortcut else {
            return
        }
        postShortcut(shortcut, to: notesPID)
    }

    func applyMarkdownTrigger(literalLength: Int, command: FormattingCommand) async {
        guard isAppleNotesFrontmost,
              let notesPID = appleNotesProcessID
        else {
            return
        }

        deleteBackward(count: literalLength, to: notesPID)
        try? await Task.sleep(for: .milliseconds(45))
        await performAsync(command)
    }

    func applySlashCommand(replacementRange: NSRange, command: FormattingCommand, in context: EditingContext) async {
        guard isAppleNotesFrontmost else { return }
        guard replaceText(in: context.element, range: replacementRange, with: "") else { return }

        try? await Task.sleep(for: .milliseconds(45))
        await performAsync(command)
    }

    func forwardKeyEventToAppleNotes(_ event: NSEvent) {
        guard let notesPID = appleNotesProcessID,
              let keyDown = event.cgEvent?.copy(),
              let keyUp = keyDown.copy()
        else {
            return
        }

        keyDown.setIntegerValueField(.eventSourceUserData, value: 0)
        keyUp.setIntegerValueField(.eventSourceUserData, value: 0)
        keyUp.type = .keyUp
        keyUp.flags = keyDown.flags
        keyDown.postToPid(notesPID)
        keyUp.postToPid(notesPID)
    }

    private var isAppleNotesFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == notesBundleIdentifier
    }

    private var appleNotesProcessID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: notesBundleIdentifier).first?.processIdentifier
    }

    private func performViaMenuItem(_ command: FormattingCommand) async -> Bool {
        guard let invocation = menuInvocation(for: command) else {
            return false
        }

        let script = """
        tell application "System Events"
          tell process "Notes"
            \(appleScriptClickStatement(for: invocation))
          end tell
        end tell
        """

        return await Task.detached(priority: .userInitiated) { [runner] in
            do {
                _ = try runner.run(executable: "/usr/bin/osascript", arguments: ["-e", script])
                return true
            } catch {
                return false
            }
        }.value
    }

    private func menuInvocation(for command: FormattingCommand) -> (menuBarItem: String, menuItems: [String])? {
        switch command {
        case .title:
            ("Format", ["Title"])
        case .heading:
            ("Format", ["Heading"])
        case .subheading:
            ("Format", ["Subheading"])
        case .body:
            ("Format", ["Body"])
        case .checklist:
            ("Format", ["Checklist"])
        case .bulletedList:
            ("Format", ["Bulleted List"])
        case .dashedList:
            ("Format", ["Dashed List"])
        case .numberedList:
            ("Format", ["Numbered List"])
        case .quote:
            ("Format", ["Block Quote"])
        case .monostyled:
            ("Format", ["Monostyled"])
        case .table:
            ("Format", ["Table"])
        case .insertLink:
            ("Edit", ["Add Link…"])
        case .strikethrough:
            ("Format", ["Font", "Strikethrough"])
        case .bold:
            nil
        }
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func appleScriptClickStatement(
        for invocation: (menuBarItem: String, menuItems: [String])
    ) -> String {
        guard let lastItem = invocation.menuItems.last else {
            return ""
        }

        var container = "menu 1 of menu bar item \(appleScriptStringLiteral(invocation.menuBarItem)) of menu bar 1"
        for item in invocation.menuItems.dropLast() {
            container = "menu 1 of menu item \(appleScriptStringLiteral(item)) of \(container)"
        }

        return "click menu item \(appleScriptStringLiteral(lastItem)) of \(container)"
    }

    private func deleteBackward(count: Int, to pid: pid_t) {
        guard count > 0 else { return }

        for _ in 0 ..< count {
            postKey(keyCode: deleteKeyCode, modifiers: [], to: pid)
        }
    }

    private func postShortcut(_ shortcut: KeyboardShortcutSpec, to pid: pid_t) {
        postKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, to: pid)
    }

    private func replaceText(in element: AXUIElement, range: NSRange, with replacement: String) -> Bool {
        guard range.location != NSNotFound, range.length >= 0 else {
            return false
        }

        var cfRange = CFRange(location: range.location, length: range.length)
        guard let selectedRangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return false
        }

        let selectionResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            selectedRangeValue
        )
        guard selectionResult == .success else {
            return false
        }

        let replaceResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFTypeRef
        )
        guard replaceResult == .success else {
            return false
        }

        var collapsedRange = CFRange(location: range.location + (replacement as NSString).length, length: 0)
        guard let collapsedRangeValue = AXValueCreate(.cfRange, &collapsedRange) else {
            return false
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            collapsedRangeValue
        ) == .success
    }

    private func postKey(keyCode: CGKeyCode, modifiers: CGEventFlags, to pid: pid_t) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
    }
}
