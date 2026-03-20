import CoreGraphics
import Foundation

struct KeyboardShortcutSpec: Sendable {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
}

enum FormattingCommand: String, CaseIterable, Codable, Identifiable, Sendable {
    case title
    case heading
    case subheading
    case body
    case bold
    case strikethrough
    case insertLink
    case checklist
    case bulletedList
    case dashedList
    case numberedList
    case quote
    case monostyled
    case table

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .title:
            "Title"
        case .heading:
            "Heading"
        case .subheading:
            "Subheading"
        case .body:
            "Body"
        case .bold:
            "Bold"
        case .strikethrough:
            "Strike"
        case .insertLink:
            "Link"
        case .checklist:
            "Task"
        case .bulletedList:
            "Bullets"
        case .dashedList:
            "Dashes"
        case .numberedList:
            "1."
        case .quote:
            "Quote"
        case .monostyled:
            "Mono"
        case .table:
            "Table"
        }
    }

    var titleKey: String {
        switch self {
        case .title:
            "Title"
        case .heading:
            "Heading"
        case .subheading:
            "Subheading"
        case .body:
            "Body"
        case .bold:
            "Bold"
        case .strikethrough:
            "Strikethrough"
        case .insertLink:
            "Link"
        case .checklist:
            "Checklist"
        case .bulletedList:
            "Bulleted List"
        case .dashedList:
            "Dashed List"
        case .numberedList:
            "Numbered List"
        case .quote:
            "Block Quote"
        case .monostyled:
            "Monostyled"
        case .table:
            "Table"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .title:
            "Apply Title"
        case .heading:
            "Apply Heading"
        case .subheading:
            "Apply Subheading"
        case .body:
            "Apply Body"
        case .bold:
            "Toggle Bold"
        case .strikethrough:
            "Toggle Strikethrough"
        case .insertLink:
            "Insert Link"
        case .checklist:
            "Create Checklist"
        case .bulletedList:
            "Create Bulleted List"
        case .dashedList:
            "Create Dashed List"
        case .numberedList:
            "Create Numbered List"
        case .quote:
            "Create Block Quote"
        case .monostyled:
            "Apply Monostyled"
        case .table:
            "Insert Table"
        }
    }

    var systemImage: String {
        switch self {
        case .title:
            "textformat.size.larger"
        case .heading:
            "textformat.size"
        case .subheading:
            "textformat"
        case .body:
            "paragraph"
        case .bold:
            "bold"
        case .strikethrough:
            "strikethrough"
        case .insertLink:
            "link"
        case .checklist:
            "checklist"
        case .bulletedList:
            "list.bullet"
        case .dashedList:
            "list.dash"
        case .numberedList:
            "list.number"
        case .quote:
            "text.quote"
        case .monostyled:
            "chevron.left.forwardslash.chevron.right"
        case .table:
            "tablecells"
        }
    }

    var shortcut: KeyboardShortcutSpec? {
        switch self {
        case .title:
            KeyboardShortcutSpec(keyCode: 17, modifiers: [.maskCommand, .maskShift])
        case .heading:
            KeyboardShortcutSpec(keyCode: 4, modifiers: [.maskCommand, .maskShift])
        case .subheading:
            KeyboardShortcutSpec(keyCode: 38, modifiers: [.maskCommand, .maskShift])
        case .body:
            KeyboardShortcutSpec(keyCode: 11, modifiers: [.maskCommand, .maskShift])
        case .bold:
            KeyboardShortcutSpec(keyCode: 11, modifiers: [.maskCommand])
        case .strikethrough:
            nil
        case .insertLink:
            KeyboardShortcutSpec(keyCode: 40, modifiers: [.maskCommand])
        case .checklist:
            KeyboardShortcutSpec(keyCode: 37, modifiers: [.maskCommand, .maskShift])
        case .bulletedList:
            KeyboardShortcutSpec(keyCode: 26, modifiers: [.maskCommand, .maskShift])
        case .dashedList:
            KeyboardShortcutSpec(keyCode: 28, modifiers: [.maskCommand, .maskShift])
        case .numberedList:
            KeyboardShortcutSpec(keyCode: 25, modifiers: [.maskCommand, .maskShift])
        case .quote:
            KeyboardShortcutSpec(keyCode: 39, modifiers: [.maskCommand])
        case .monostyled:
            KeyboardShortcutSpec(keyCode: 46, modifiers: [.maskCommand, .maskShift])
        case .table:
            KeyboardShortcutSpec(keyCode: 17, modifiers: [.maskCommand, .maskAlternate])
        }
    }
}
