import Testing
@testable import NotesBridge

struct SlashCommandKeyboardActionTests {
    @Test
    func mapsNavigationAndCommitKeys() {
        #expect(SlashCommandKeyboardAction(keyCode: 126) == .moveUp)
        #expect(SlashCommandKeyboardAction(keyCode: 125) == .moveDown)
        #expect(SlashCommandKeyboardAction(keyCode: 36) == .commit)
        #expect(SlashCommandKeyboardAction(keyCode: 48) == .commit)
        #expect(SlashCommandKeyboardAction(keyCode: 76) == .commit)
        #expect(SlashCommandKeyboardAction(keyCode: 53) == .dismiss)
    }

    @Test
    func ignoresUnrelatedKeys() {
        #expect(SlashCommandKeyboardAction(keyCode: 0) == nil)
        #expect(SlashCommandKeyboardAction(keyCode: 49) == nil)
    }
}
