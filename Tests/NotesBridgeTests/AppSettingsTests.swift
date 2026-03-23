import Foundation
import Testing
@testable import NotesBridge

struct AppSettingsTests {
    @Test
    func defaultsIncludeNormalizedInlineToolbarItems() {
        let settings = AppSettings.default

        #expect(settings.inlineToolbarItems.count == InlineToolbarItemSetting.defaultOrder.count)
        #expect(settings.inlineToolbarItems.filter(\.isVisible).map(\.command) == InlineToolbarItemSetting.defaultVisibleCommands)
        #expect(settings.slashCommandItems.count == SlashCommandItemSetting.defaultOrder.count)
        #expect(settings.slashCommandItems.filter(\.isVisible).map(\.command) == SlashCommandItemSetting.defaultVisibleCommands)
        #expect(settings.automaticSyncEnabled == false)
        #expect(settings.automaticSyncInterval == .fifteenMinutes)
    }

    @Test
    func decodingLegacySettingsFallsBackToDefaultInlineToolbarItems() throws {
        let data = """
        {
          "appLanguage": "system",
          "enableInlineEnhancements": true,
          "enableFormattingBar": true,
          "enableMarkdownTriggers": true,
          "enableSlashCommands": true,
          "syncDirection": "appleNotesToObsidian",
          "exportFolderName": "Apple Notes",
          "attachmentFolderName": "_attachments",
          "useObsidianAttachmentFolder": false,
          "autoSyncOnPush": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.inlineToolbarItems == InlineToolbarItemSetting.default)
        #expect(decoded.slashCommandItems == SlashCommandItemSetting.default)
        #expect(decoded.automaticSyncEnabled == false)
        #expect(decoded.automaticSyncInterval == .fifteenMinutes)
    }

    @Test
    func decodingInlineToolbarItemsNormalizesDuplicatesAndMissingCommands() throws {
        let data = """
        {
          "appLanguage": "system",
          "enableInlineEnhancements": true,
          "enableFormattingBar": true,
          "enableMarkdownTriggers": true,
          "enableSlashCommands": true,
          "syncDirection": "appleNotesToObsidian",
          "exportFolderName": "Apple Notes",
          "attachmentFolderName": "_attachments",
          "useObsidianAttachmentFolder": false,
          "autoSyncOnPush": true,
          "inlineToolbarItems": [
            { "command": "table", "isVisible": true },
            { "command": "table", "isVisible": false },
            { "command": "bold", "isVisible": false }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.inlineToolbarItems[0] == InlineToolbarItemSetting(command: .table, isVisible: true))
        #expect(decoded.inlineToolbarItems[1] == InlineToolbarItemSetting(command: .bold, isVisible: false))
        #expect(decoded.inlineToolbarItems.count == InlineToolbarItemSetting.defaultOrder.count)
        #expect(decoded.inlineToolbarItems.map(\.command).contains(.title))
    }

    @Test
    func decodingSlashCommandItemsNormalizesDuplicatesAndMissingCommands() throws {
        let data = """
        {
          "appLanguage": "system",
          "enableInlineEnhancements": true,
          "enableFormattingBar": true,
          "enableMarkdownTriggers": true,
          "enableSlashCommands": true,
          "syncDirection": "appleNotesToObsidian",
          "exportFolderName": "Apple Notes",
          "attachmentFolderName": "_attachments",
          "useObsidianAttachmentFolder": false,
          "autoSyncOnPush": true,
          "slashCommandItems": [
            { "command": "table", "isVisible": true },
            { "command": "table", "isVisible": false },
            { "command": "title", "isVisible": false }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.slashCommandItems[0] == SlashCommandItemSetting(command: .table, isVisible: true))
        #expect(decoded.slashCommandItems[1] == SlashCommandItemSetting(command: .title, isVisible: false))
        #expect(decoded.slashCommandItems.count == SlashCommandItemSetting.defaultOrder.count)
        #expect(decoded.slashCommandItems.map(\.command).contains(.heading))
    }
}
