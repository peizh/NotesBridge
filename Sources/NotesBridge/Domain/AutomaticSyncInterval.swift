import Foundation

enum AutomaticSyncInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
    case thirtyMinutes = 30
    case oneHour = 60
    case sixHours = 360
    case oneDay = 1440

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)

        switch rawValue {
        case 5, 15:
            self = .thirtyMinutes
        case 30:
            self = .thirtyMinutes
        case 60:
            self = .oneHour
        case 360:
            self = .sixHours
        case 1440:
            self = .oneDay
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported automatic sync interval: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var id: Int { rawValue }

    var minutes: Int { rawValue }

    var displayKey: String {
        switch self {
        case .thirtyMinutes:
            return "Every 30 minutes"
        case .oneHour:
            return "Every hour"
        case .sixHours:
            return "Every 6 hours"
        case .oneDay:
            return "Every day"
        }
    }
}
