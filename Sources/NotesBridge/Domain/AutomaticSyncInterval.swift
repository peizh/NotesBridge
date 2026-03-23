import Foundation

enum AutomaticSyncInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    var id: Int { rawValue }

    var minutes: Int { rawValue }
}
