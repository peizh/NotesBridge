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
        guard isAppleNotesFrontmost,
              let notesPID = appleNotesProcessID
        else {
            return
        }
        if performViaMenuItem(command) {
            return
        }
        postShortcut(command.shortcut, to: notesPID)
    }

    func applyMarkdownTrigger(literalLength: Int, command: FormattingCommand) async {
        guard isAppleNotesFrontmost,
              let notesPID = appleNotesProcessID
        else {
            return
        }

        deleteBackward(count: literalLength, to: notesPID)
        try? await Task.sleep(for: .milliseconds(45))
        perform(command)
    }

    func applySlashCommand(replacementRange: NSRange, command: FormattingCommand, in context: EditingContext) async {
        guard isAppleNotesFrontmost else { return }
        guard replaceText(in: context.element, range: replacementRange, with: "") else { return }

        try? await Task.sleep(for: .milliseconds(45))
        perform(command)
    }

    func forwardKeyEventToAppleNotes(_ event: NSEvent) {
        guard let notesPID = appleNotesProcessID,
              let keyDown = event.cgEvent?.copy(),
              let keyUp = keyDown.copy()
        else {
            return
        }

        keyDown.setIntegerValueField(.eventSourceUserData, value: 0)
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

    private func performViaMenuItem(_ command: FormattingCommand) -> Bool {
        guard let invocation = menuInvocation(for: command) else {
            return false
        }

        let script = """
        tell application "System Events"
          tell process "Notes"
            click menu item \(appleScriptStringLiteral(invocation.menuItem)) of menu 1 of menu bar item \(appleScriptStringLiteral(invocation.menuBarItem)) of menu bar 1
          end tell
        end tell
        """

        do {
            _ = try runner.run(executable: "/usr/bin/osascript", arguments: ["-e", script])
            return true
        } catch {
            return false
        }
    }

    private func menuInvocation(for command: FormattingCommand) -> (menuBarItem: String, menuItem: String)? {
        switch command {
        case .title:
            ("Format", "Title")
        case .heading:
            ("Format", "Heading")
        case .subheading:
            ("Format", "Subheading")
        case .body:
            ("Format", "Body")
        case .checklist:
            ("Format", "Checklist")
        case .bulletedList:
            ("Format", "Bulleted List")
        case .dashedList:
            ("Format", "Dashed List")
        case .numberedList:
            ("Format", "Numbered List")
        case .quote:
            ("Format", "Block Quote")
        case .monostyled:
            ("Format", "Monostyled")
        case .table:
            ("Format", "Table")
        case .insertLink:
            ("Edit", "Add Link…")
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
