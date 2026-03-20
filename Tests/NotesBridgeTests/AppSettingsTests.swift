import Foundation
import Testing
@testable import NotesBridge

struct AppSettingsTests {
    @Test
    func defaultsIncludeNormalizedInlineToolbarItems() {
        let settings = AppSettings.default

        #expect(settings.inlineToolbarItems.count == InlineToolbarItemSetting.defaultOrder.count)
        #expect(settings.inlineToolbarItems.filter(\.isVisible).map(\.command) == InlineToolbarItemSetting.defaultVisibleCommands)
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
}
