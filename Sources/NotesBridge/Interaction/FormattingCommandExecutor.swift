import AppKit
import CoreGraphics
import Foundation

@MainActor
final class FormattingCommandExecutor {
    private let notesBundleIdentifier = "com.apple.Notes"
    private let deleteKeyCode: CGKeyCode = 51

    func perform(_ command: FormattingCommand) {
        guard isAppleNotesFrontmost else { return }
        postShortcut(command.shortcut)
    }

    func applyMarkdownTrigger(literalLength: Int, command: FormattingCommand) async {
        guard isAppleNotesFrontmost else { return }

        deleteBackward(count: literalLength)
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

    private func deleteBackward(count: Int) {
        guard count > 0 else { return }

        for _ in 0 ..< count {
            postKey(keyCode: deleteKeyCode, modifiers: [])
        }
    }

    private func postShortcut(_ shortcut: KeyboardShortcutSpec) {
        postKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
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

    private func postKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
