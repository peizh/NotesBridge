import CoreGraphics
import Foundation

enum SlashCommandKeyboardAction: Sendable {
    case moveUp
    case moveDown
    case commit
    case dismiss

    init?(keyCode: UInt16) {
        switch CGKeyCode(keyCode) {
        case 125:
            self = .moveDown
        case 126:
            self = .moveUp
        case 36, 48, 76:
            self = .commit
        case 53:
            self = .dismiss
        default:
            return nil
        }
    }
}
