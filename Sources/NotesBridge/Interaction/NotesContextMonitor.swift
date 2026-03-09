import AppKit
import ApplicationServices
import Foundation

@MainActor
final class NotesContextMonitor: ObservableObject {
    @Published private(set) var selectionContext: SelectionContext?
    @Published private(set) var availability: InteractionAvailability

    private let permissionsManager: PermissionsManager
    private var settings: AppSettings
    private var timer: Timer?
    private let notesBundleIdentifier = "com.apple.Notes"

    init(buildFlavor: BuildFlavor, permissionsManager: PermissionsManager, settings: AppSettings) {
        self.permissionsManager = permissionsManager
        self.settings = settings
        self.availability = .default(for: buildFlavor)
    }

    func start() {
        stop()
        refreshNow()

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func updateSettings(_ settings: AppSettings) {
        self.settings = settings
        refreshNow()
    }

    func editingSnapshot(includeValue: Bool) -> EditingContext? {
        guard availability.supportsInlineEnhancements,
              permissionsManager.accessibilityGranted,
              isNotesFrontmost,
              let focusedElement = focusedUIElement,
              isEditable(element: focusedElement)
        else {
            return nil
        }

        let selectedRange = selectedRange(for: focusedElement)
        let selectedText = stringAttribute(kAXSelectedTextAttribute as CFString, from: focusedElement) ?? ""
        let selectionRect = boundsForRange(selectedRange, in: focusedElement)
        let value = includeValue ? stringAttribute(kAXValueAttribute as CFString, from: focusedElement) : nil

        return EditingContext(
            element: focusedElement,
            selectedRange: selectedRange,
            selectedText: selectedText,
            selectionRect: selectionRect,
            value: value
        )
    }

    private func refreshNow() {
        permissionsManager.refresh()

        let notesIsFrontmost = isNotesFrontmost
        let accessibilityGranted = permissionsManager.accessibilityGranted
        var editableFocus = false
        var nextSelectionContext: SelectionContext?

        if availability.supportsInlineEnhancements,
           accessibilityGranted,
           notesIsFrontmost,
           let snapshot = editingSnapshot(includeValue: false)
        {
            editableFocus = true

            if snapshot.selectedRange.length > 0 {
                nextSelectionContext = SelectionContext(
                    selectedText: snapshot.selectedText,
                    selectedRange: snapshot.selectedRange,
                    selectionRect: snapshot.selectionRect,
                    noteTitle: nil,
                    folderName: nil
                )
            }
        }

        selectionContext = nextSelectionContext
        availability = InteractionAvailability(
            buildFlavor: availability.buildFlavor,
            accessibilityGranted: accessibilityGranted,
            notesIsFrontmost: notesIsFrontmost,
            editableFocus: editableFocus,
            inlineEnhancementsEnabled: settings.enableInlineEnhancements,
            formattingBarEnabled: settings.enableFormattingBar,
            markdownTriggersEnabled: settings.enableMarkdownTriggers,
            slashCommandsEnabled: settings.enableSlashCommands
        )
    }

    private var isNotesFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == notesBundleIdentifier
    }

    private var focusedUIElement: AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func isEditable(element: AXUIElement) -> Bool {
        if let editable = boolAttribute("AXEditable" as CFString, from: element) {
            return editable
        }

        let role = stringAttribute(kAXRoleAttribute as CFString, from: element) ?? ""
        return role == kAXTextAreaRole as String || role == kAXTextFieldRole as String
    }

    private func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let number = value as? NSNumber
        else {
            return nil
        }
        return number.boolValue
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func selectedRange(for element: AXUIElement) -> NSRange {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let rangeValue = value
        else {
            return NSRange(location: 0, length: 0)
        }

        let axValue = unsafeDowncast(rangeValue, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange,
              AXValueGetValue(axValue, .cfRange, &range)
        else {
            return NSRange(location: 0, length: 0)
        }

        return NSRange(location: range.location, length: range.length)
    }

    private func boundsForRange(_ range: NSRange, in element: AXUIElement) -> CGRect? {
        guard range.location != NSNotFound else { return nil }

        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard result == .success, let value else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetType(axValue) == .cgRect,
              AXValueGetValue(axValue, .cgRect, &rect)
        else {
            return nil
        }
        return rect
    }
}

struct EditingContext {
    var element: AXUIElement
    var selectedRange: NSRange
    var selectedText: String
    var selectionRect: CGRect?
    var value: String?
}
