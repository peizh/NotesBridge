import Foundation

struct SlashCommandItemSetting: Codable, Equatable, Identifiable, Sendable {
    let command: FormattingCommand
    var isVisible: Bool

    var id: FormattingCommand { command }

    static let defaultOrder: [FormattingCommand] = [
        .title,
        .heading,
        .subheading,
        .body,
        .monostyled,
        .checklist,
        .bulletedList,
        .dashedList,
        .numberedList,
        .quote,
        .table,
    ]

    static let defaultVisibleCommands = defaultOrder

    static var `default`: [SlashCommandItemSetting] {
        defaultOrder.map { command in
            SlashCommandItemSetting(
                command: command,
                isVisible: defaultVisibleCommands.contains(command)
            )
        }
    }

    static func normalized(_ items: [SlashCommandItemSetting]) -> [SlashCommandItemSetting] {
        var seen: Set<FormattingCommand> = []
        var normalizedItems: [SlashCommandItemSetting] = []

        for item in items where defaultOrder.contains(item.command) {
            guard seen.insert(item.command).inserted else { continue }
            normalizedItems.append(item)
        }

        for command in defaultOrder where !seen.contains(command) {
            normalizedItems.append(
                SlashCommandItemSetting(
                    command: command,
                    isVisible: defaultVisibleCommands.contains(command)
                )
            )
        }

        return normalizedItems
    }
}
