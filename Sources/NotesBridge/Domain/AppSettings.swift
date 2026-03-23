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
    var appLanguage: AppLanguage
    var vaultPath: String?
    var appleNotesDataPath: String?
    var appleNotesDataBookmark: Data?
    var exportFolderName: String
    var attachmentFolderName: String
    var useObsidianAttachmentFolder: Bool
    var automaticSyncEnabled: Bool
    var automaticSyncInterval: AutomaticSyncInterval
    var syncDirection: SyncDirection
    var enableInlineEnhancements: Bool
    var enableFormattingBar: Bool
    var inlineToolbarItems: [InlineToolbarItemSetting]
    var enableMarkdownTriggers: Bool
    var enableSlashCommands: Bool
    var slashCommandItems: [SlashCommandItemSetting]

    static let `default` = AppSettings(
        appLanguage: .system,
        vaultPath: nil,
        appleNotesDataPath: nil,
        appleNotesDataBookmark: nil,
        exportFolderName: "Apple Notes",
        attachmentFolderName: "_attachments",
        useObsidianAttachmentFolder: false,
        automaticSyncEnabled: false,
        automaticSyncInterval: .fifteenMinutes,
        syncDirection: .appleNotesToObsidian,
        enableInlineEnhancements: true,
        enableFormattingBar: true,
        inlineToolbarItems: InlineToolbarItemSetting.default,
        enableMarkdownTriggers: true,
        enableSlashCommands: true,
        slashCommandItems: SlashCommandItemSetting.default
    )

    var hasValidVaultPath: Bool {
        guard let vaultPath else { return false }
        return !vaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case vaultPath
        case appLanguage
        case appleNotesDataPath
        case appleNotesDataBookmark
        case exportFolderName
        case attachmentFolderName
        case useObsidianAttachmentFolder
        case automaticSyncEnabled
        case automaticSyncInterval
        case autoSyncOnPush
        case syncDirection
        case enableInlineEnhancements
        case enableFormattingBar
        case inlineToolbarItems
        case enableMarkdownTriggers
        case enableSlashCommands
        case slashCommandItems
    }

    init(
        appLanguage: AppLanguage,
        vaultPath: String?,
        appleNotesDataPath: String?,
        appleNotesDataBookmark: Data?,
        exportFolderName: String,
        attachmentFolderName: String,
        useObsidianAttachmentFolder: Bool,
        automaticSyncEnabled: Bool,
        automaticSyncInterval: AutomaticSyncInterval,
        syncDirection: SyncDirection,
        enableInlineEnhancements: Bool,
        enableFormattingBar: Bool,
        inlineToolbarItems: [InlineToolbarItemSetting],
        enableMarkdownTriggers: Bool,
        enableSlashCommands: Bool,
        slashCommandItems: [SlashCommandItemSetting]
    ) {
        self.appLanguage = appLanguage
        self.vaultPath = vaultPath
        self.appleNotesDataPath = appleNotesDataPath
        self.appleNotesDataBookmark = appleNotesDataBookmark
        self.exportFolderName = exportFolderName
        self.attachmentFolderName = attachmentFolderName
        self.useObsidianAttachmentFolder = useObsidianAttachmentFolder
        self.automaticSyncEnabled = automaticSyncEnabled
        self.automaticSyncInterval = automaticSyncInterval
        self.syncDirection = syncDirection
        self.enableInlineEnhancements = enableInlineEnhancements
        self.enableFormattingBar = enableFormattingBar
        self.inlineToolbarItems = InlineToolbarItemSetting.normalized(inlineToolbarItems)
        self.enableMarkdownTriggers = enableMarkdownTriggers
        self.enableSlashCommands = enableSlashCommands
        self.slashCommandItems = SlashCommandItemSetting.normalized(slashCommandItems)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? Self.default.appLanguage
        self.vaultPath = try container.decodeIfPresent(String.self, forKey: .vaultPath)
        self.appleNotesDataPath = try container.decodeIfPresent(String.self, forKey: .appleNotesDataPath)
        self.appleNotesDataBookmark = try container.decodeIfPresent(Data.self, forKey: .appleNotesDataBookmark)
        self.exportFolderName = try container.decodeIfPresent(String.self, forKey: .exportFolderName) ?? Self.default.exportFolderName
        self.attachmentFolderName = try container.decodeIfPresent(String.self, forKey: .attachmentFolderName) ?? Self.default.attachmentFolderName
        self.useObsidianAttachmentFolder = try container.decodeIfPresent(Bool.self, forKey: .useObsidianAttachmentFolder) ?? Self.default.useObsidianAttachmentFolder
        self.automaticSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticSyncEnabled) ?? Self.default.automaticSyncEnabled
        self.automaticSyncInterval = try container.decodeIfPresent(AutomaticSyncInterval.self, forKey: .automaticSyncInterval) ?? Self.default.automaticSyncInterval
        self.syncDirection = try container.decodeIfPresent(SyncDirection.self, forKey: .syncDirection) ?? Self.default.syncDirection
        self.enableInlineEnhancements = try container.decodeIfPresent(Bool.self, forKey: .enableInlineEnhancements) ?? Self.default.enableInlineEnhancements
        self.enableFormattingBar = try container.decodeIfPresent(Bool.self, forKey: .enableFormattingBar) ?? Self.default.enableFormattingBar
        self.inlineToolbarItems = InlineToolbarItemSetting.normalized(
            try container.decodeIfPresent([InlineToolbarItemSetting].self, forKey: .inlineToolbarItems)
                ?? Self.default.inlineToolbarItems
        )
        self.enableMarkdownTriggers = try container.decodeIfPresent(Bool.self, forKey: .enableMarkdownTriggers) ?? Self.default.enableMarkdownTriggers
        self.enableSlashCommands = try container.decodeIfPresent(Bool.self, forKey: .enableSlashCommands) ?? Self.default.enableSlashCommands
        self.slashCommandItems = SlashCommandItemSetting.normalized(
            try container.decodeIfPresent([SlashCommandItemSetting].self, forKey: .slashCommandItems)
                ?? Self.default.slashCommandItems
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appLanguage, forKey: .appLanguage)
        try container.encodeIfPresent(vaultPath, forKey: .vaultPath)
        try container.encodeIfPresent(appleNotesDataPath, forKey: .appleNotesDataPath)
        try container.encodeIfPresent(appleNotesDataBookmark, forKey: .appleNotesDataBookmark)
        try container.encode(exportFolderName, forKey: .exportFolderName)
        try container.encode(attachmentFolderName, forKey: .attachmentFolderName)
        try container.encode(useObsidianAttachmentFolder, forKey: .useObsidianAttachmentFolder)
        try container.encode(automaticSyncEnabled, forKey: .automaticSyncEnabled)
        try container.encode(automaticSyncInterval, forKey: .automaticSyncInterval)
        try container.encode(syncDirection, forKey: .syncDirection)
        try container.encode(enableInlineEnhancements, forKey: .enableInlineEnhancements)
        try container.encode(enableFormattingBar, forKey: .enableFormattingBar)
        try container.encode(InlineToolbarItemSetting.normalized(inlineToolbarItems), forKey: .inlineToolbarItems)
        try container.encode(enableMarkdownTriggers, forKey: .enableMarkdownTriggers)
        try container.encode(enableSlashCommands, forKey: .enableSlashCommands)
        try container.encode(SlashCommandItemSetting.normalized(slashCommandItems), forKey: .slashCommandItems)
    }
}
