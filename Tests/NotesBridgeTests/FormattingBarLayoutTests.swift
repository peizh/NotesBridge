import CoreGraphics
import Testing
@testable import NotesBridge

struct FormattingBarLayoutTests {
    @Test
    func groupsPreserveCommandOrderAcrossStyleTransitions() {
        let commands: [FormattingCommand] = [
            .bold,
            .title,
            .insertLink,
            .numberedList,
            .quote,
        ]

        let groups = FormattingBarLayout.groups(for: commands)

        #expect(groups.count == 5)
        #expect(groups.flatMap { $0 } == commands)
    }

    @Test
    func defaultVisibleCommandsCollapseIntoStableVisualClusters() {
        let groups = FormattingBarLayout.groups(for: InlineToolbarItemSetting.defaultVisibleCommands)
        let expected: [[FormattingCommand]] = [
            [.title, .heading, .subheading, .body],
            [.bold, .strikethrough, .insertLink],
            [.checklist, .bulletedList, .dashedList, .numberedList],
        ]

        #expect(groups == expected)
    }

    @Test
    func preferredSizeShrinksForCompactSetsAndCapsWideSets() {
        let compact = FormattingBarLayout.preferredSize(for: [.bold, .insertLink])
        let standard = FormattingBarLayout.preferredSize(for: InlineToolbarItemSetting.defaultVisibleCommands)
        let expanded = FormattingBarLayout.preferredSize(for: FormattingCommand.allCases)

        #expect(compact.width == FormattingBarLayout.minimumWidth)
        #expect(compact.height == FormattingBarLayout.height)

        #expect(standard.width == FormattingBarLayout.maximumWidth)
        #expect(standard.height == FormattingBarLayout.height)

        #expect(expanded.width == FormattingBarLayout.maximumWidth)
        #expect(expanded.height == FormattingBarLayout.height)
        #expect(compact.width < standard.width)
    }

    @Test
    func preferredSizeIncludesOuterRenderingInsetAroundVisibleSurface() {
        let commands: [FormattingCommand] = [.bold, .insertLink]
        let surfaceSize = FormattingBarLayout.surfaceSize(for: commands)
        let preferredSize = FormattingBarLayout.preferredSize(for: commands)

        #expect(preferredSize.width == surfaceSize.width + (FormattingBarLayout.outerPadding * 2))
        #expect(preferredSize.height == surfaceSize.height + (FormattingBarLayout.outerPadding * 2))
    }
}
