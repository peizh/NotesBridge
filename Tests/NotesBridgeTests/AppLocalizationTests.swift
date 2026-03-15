import Testing
@testable import NotesBridge

struct AppLocalizationTests {
    @Test
    func simplifiedChineseTranslatesCoreSettingsLabels() {
        let localization = AppLocalization(language: .simplifiedChinese)

        #expect(localization.text("NotesBridge Settings") == "NotesBridge 设置")
        #expect(localization.text("Sync All Notes to Obsidian") == "同步全部笔记到 Obsidian")
    }

    @Test
    func frenchFormatsProgressSummary() {
        let localization = AppLocalization(language: .french)
        let progress = SyncProgress(
            completedNotes: 3,
            totalNotes: 10,
            completedFolders: 1,
            totalFolders: 2,
            currentFolderName: "Inbox",
            skippedNotes: 0
        )

        #expect(progress.localizedSummaryText(using: localization) == "30% • 3/10 notes • 1/2 dossiers")
        #expect(progress.localizedCurrentFolderText(using: localization) == "Dossier actuel : Inbox")
    }

    @Test
    func slashCommandTitlesAreLocalizedWithoutChangingTokens() throws {
        let chinese = AppLocalization(language: .simplifiedChinese)
        let entry = try #require(SlashCommandCatalog().entries.first { $0.primaryAlias == "title" })

        #expect(entry.localizedTitle(using: chinese) == "标题")
        #expect(entry.token == "/title")
    }
}
