import CoreGraphics
import Foundation

struct SelectionContext: Equatable, Sendable {
    var selectedText: String
    var selectedRange: NSRange
    var selectionRect: CGRect?
    var noteTitle: String?
    var folderName: String?

    var hasSelection: Bool {
        selectedRange.length > 0 && !selectedText.isEmpty
    }
}
