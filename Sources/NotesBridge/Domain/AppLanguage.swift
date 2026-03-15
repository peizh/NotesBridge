import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese
    case french

    var id: String { rawValue }
}
