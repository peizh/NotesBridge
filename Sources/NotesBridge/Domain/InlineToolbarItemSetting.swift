import Foundation

struct InlineToolbarItemSetting: Codable, Equatable, Identifiable, Sendable {
    let command: FormattingCommand
    var isVisible: Bool

    var id: FormattingCommand { command }

    static let defaultVisibleCommands: [FormattingCommand] = [
        .title,
        .heading,
        .subheading,
        .body,
        .bold,
        .strikethrough,
        .insertLink,
        .checklist,
        .bulletedList,
        .dashedList,
        .numberedList,
    ]

    static let defaultOrder: [FormattingCommand] = [
        .title,
        .heading,
        .subheading,
        .body,
        .bold,
        .strikethrough,
        .insertLink,
        .checklist,
        .bulletedList,
        .dashedList,
        .numberedList,
        .quote,
        .monostyled,
        .table,
    ]

    static var `default`: [InlineToolbarItemSetting] {
        defaultOrder.map { command in
            InlineToolbarItemSetting(
                command: command,
                isVisible: defaultVisibleCommands.contains(command)
            )
        }
    }

    static func normalized(_ items: [InlineToolbarItemSetting]) -> [InlineToolbarItemSetting] {
        var seen: Set<FormattingCommand> = []
        var normalizedItems: [InlineToolbarItemSetting] = []

        for item in items where defaultOrder.contains(item.command) {
            guard seen.insert(item.command).inserted else { continue }
            normalizedItems.append(item)
        }

        for command in defaultOrder where !seen.contains(command) {
            normalizedItems.append(
                InlineToolbarItemSetting(
                    command: command,
                    isVisible: defaultVisibleCommands.contains(command)
                )
            )
        }

        return normalizedItems
    }
}
