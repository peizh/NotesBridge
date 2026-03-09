import Foundation

enum BuildFlavor: String, Codable, Sendable {
    case directDownload
    case appStore

    static var current: BuildFlavor {
        ProcessInfo.processInfo.environment["NOTESBRIDGE_APPSTORE"] == "1" ? .appStore : .directDownload
    }

    var supportsInlineEnhancements: Bool {
        self == .directDownload
    }

    var title: String {
        switch self {
        case .directDownload:
            "Direct Download"
        case .appStore:
            "Mac App Store"
        }
    }
}
