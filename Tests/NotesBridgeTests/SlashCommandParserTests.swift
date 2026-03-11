import Testing
@testable import NotesBridge

struct SlashCommandParserTests {
    private let parser = SlashCommandParser()

    @Test
    func menuShowsAllEntriesForBareSlash() {
        let value = "/"

        let match = parser.menuMatch(in: value, caretLocation: value.count)

        #expect(match?.token.rawValue == "/")
        #expect(match?.entries.count == SlashCommandCatalog().entries.count)
        #expect(match?.entries.first?.command == .title)
    }

    @Test
    func menuMatchesAliasesCaseInsensitively() {
        let value = "Start /Co"

        let match = parser.menuMatch(in: value, caretLocation: value.count)

        #expect(match?.token.rawValue == "/Co")
        #expect(match?.entries.map(\.command) == [.monostyled])
    }

    @Test
    func menuMatchesSlashCommandsInMiddleOfParagraphAfterWhitespace() {
        let value = "Intro /h"

        let match = parser.menuMatch(in: value, caretLocation: value.count)

        #expect(match?.entries.map(\.command) == [.title, .heading, .subheading])
        #expect(match?.token.range.location == 6)
        #expect(match?.token.range.length == 2)
    }

    @Test
    func menuMatchesWhenCaretIsBeforeTrailingNewline() {
        let value = "Intro\n/\nNext"

        let match = parser.menuMatch(in: value, caretLocation: 7)

        #expect(match?.token.rawValue == "/")
        #expect(match?.entries.count == SlashCommandCatalog().entries.count)
    }

    @Test
    func menuIgnoresSlashInsideWords() {
        let value = "hello/title"

        let match = parser.menuMatch(in: value, caretLocation: value.count)

        #expect(match == nil)
    }

    @Test
    func menuIgnoresUnrecognizedPathLikeTokens() {
        let value = "/Users/pete"

        let match = parser.menuMatch(in: value, caretLocation: value.count)

        #expect(match == nil)
    }

    @Test
    func menuIgnoresURLs() {
        let value = "Visit https://example.com"

        let match = parser.menuMatch(in: value, caretLocation: value.count)

        #expect(match == nil)
    }

    @Test
    func commitMatchRemovesTokenAndTrailingSpaceForTable() {
        let value = "/table "

        let match = parser.commitMatchBeforeSpace(in: value, caretLocation: value.count)

        #expect(match?.entry.command == .table)
        #expect(match?.token.range.location == 0)
        #expect(match?.token.range.length == 6)
        #expect(match?.replacementRange.location == 0)
        #expect(match?.replacementRange.length == 7)
        #expect(match?.removesTrailingSpace == true)
    }

    @Test
    func commitMatchSupportsCaseInsensitiveAliases() {
        let value = "/CoDe "

        let match = parser.commitMatchBeforeSpace(in: value, caretLocation: value.count)

        #expect(match?.entry.command == .monostyled)
        #expect(match?.replacementRange.location == 0)
        #expect(match?.replacementRange.length == 6)
    }

    @Test
    func commitMatchWorksInMiddleOfParagraph() {
        let value = "Before /title "

        let match = parser.commitMatchBeforeSpace(in: value, caretLocation: value.count)

        #expect(match?.entry.command == .title)
        #expect(match?.token.range.location == 7)
        #expect(match?.token.range.length == 6)
        #expect(match?.replacementRange.location == 7)
        #expect(match?.replacementRange.length == 7)
    }

    @Test
    func commitMatchRejectsUnknownCommands() {
        let value = "Before /unknown "

        let match = parser.commitMatchBeforeSpace(in: value, caretLocation: value.count)

        #expect(match == nil)
    }
}
