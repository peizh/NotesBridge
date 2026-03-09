import Foundation

enum SyncDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleNotesToObsidian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleNotesToObsidian:
            "Apple Notes -> Obsidian"
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var vaultPath: String?
    var exportFolderName: String
    var autoSyncOnPush: Bool
    var syncDirection: SyncDirection
    var enableInlineEnhancements: Bool
    var enableFormattingBar: Bool
    var enableMarkdownTriggers: Bool
    var enableSlashCommands: Bool

    static let `default` = AppSettings(
        vaultPath: nil,
        exportFolderName: "Apple Notes",
        autoSyncOnPush: true,
        syncDirection: .appleNotesToObsidian,
        enableInlineEnhancements: true,
        enableFormattingBar: true,
        enableMarkdownTriggers: true,
        enableSlashCommands: true
    )

    var hasValidVaultPath: Bool {
        guard let vaultPath else { return false }
        return !vaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case vaultPath
        case exportFolderName
        case autoSyncOnPush
        case syncDirection
        case enableInlineEnhancements
        case enableFormattingBar
        case enableMarkdownTriggers
        case enableSlashCommands
    }

    init(
        vaultPath: String?,
        exportFolderName: String,
        autoSyncOnPush: Bool,
        syncDirection: SyncDirection,
        enableInlineEnhancements: Bool,
        enableFormattingBar: Bool,
        enableMarkdownTriggers: Bool,
        enableSlashCommands: Bool
    ) {
        self.vaultPath = vaultPath
        self.exportFolderName = exportFolderName
        self.autoSyncOnPush = autoSyncOnPush
        self.syncDirection = syncDirection
        self.enableInlineEnhancements = enableInlineEnhancements
        self.enableFormattingBar = enableFormattingBar
        self.enableMarkdownTriggers = enableMarkdownTriggers
        self.enableSlashCommands = enableSlashCommands
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.vaultPath = try container.decodeIfPresent(String.self, forKey: .vaultPath)
        self.exportFolderName = try container.decodeIfPresent(String.self, forKey: .exportFolderName) ?? Self.default.exportFolderName
        self.autoSyncOnPush = try container.decodeIfPresent(Bool.self, forKey: .autoSyncOnPush) ?? Self.default.autoSyncOnPush
        self.syncDirection = try container.decodeIfPresent(SyncDirection.self, forKey: .syncDirection) ?? Self.default.syncDirection
        self.enableInlineEnhancements = try container.decodeIfPresent(Bool.self, forKey: .enableInlineEnhancements) ?? Self.default.enableInlineEnhancements
        self.enableFormattingBar = try container.decodeIfPresent(Bool.self, forKey: .enableFormattingBar) ?? Self.default.enableFormattingBar
        self.enableMarkdownTriggers = try container.decodeIfPresent(Bool.self, forKey: .enableMarkdownTriggers) ?? Self.default.enableMarkdownTriggers
        self.enableSlashCommands = try container.decodeIfPresent(Bool.self, forKey: .enableSlashCommands) ?? Self.default.enableSlashCommands
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(vaultPath, forKey: .vaultPath)
        try container.encode(exportFolderName, forKey: .exportFolderName)
        try container.encode(autoSyncOnPush, forKey: .autoSyncOnPush)
        try container.encode(syncDirection, forKey: .syncDirection)
        try container.encode(enableInlineEnhancements, forKey: .enableInlineEnhancements)
        try container.encode(enableFormattingBar, forKey: .enableFormattingBar)
        try container.encode(enableMarkdownTriggers, forKey: .enableMarkdownTriggers)
        try container.encode(enableSlashCommands, forKey: .enableSlashCommands)
    }
}
