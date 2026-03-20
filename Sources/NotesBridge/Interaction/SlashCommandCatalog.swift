import Foundation

struct SlashCommandEntry: Identifiable, Equatable, Sendable {
    let command: FormattingCommand
    let primaryAlias: String
    let aliases: [String]

    var id: FormattingCommand { command }
    var token: String { "/\(primaryAlias)" }

    func localizedTitle(using localization: AppLocalization) -> String {
        localization.text(command.titleKey)
    }
}

struct SlashCommandCatalog: Sendable {
    static let defaultEntries: [SlashCommandEntry] = [
        SlashCommandEntry(command: .title, primaryAlias: "title", aliases: ["title", "h1"]),
        SlashCommandEntry(command: .heading, primaryAlias: "heading", aliases: ["heading", "h2"]),
        SlashCommandEntry(command: .subheading, primaryAlias: "subheading", aliases: ["subheading", "h3"]),
        SlashCommandEntry(command: .body, primaryAlias: "body", aliases: ["body"]),
        SlashCommandEntry(command: .bold, primaryAlias: "bold", aliases: ["bold"]),
        SlashCommandEntry(command: .strikethrough, primaryAlias: "strikethrough", aliases: ["strikethrough", "strike"]),
        SlashCommandEntry(command: .insertLink, primaryAlias: "link", aliases: ["link"]),
        SlashCommandEntry(command: .monostyled, primaryAlias: "monostyled", aliases: ["monostyled", "code"]),
        SlashCommandEntry(command: .checklist, primaryAlias: "checklist", aliases: ["checklist"]),
        SlashCommandEntry(command: .bulletedList, primaryAlias: "bulletedlist", aliases: ["bulletedlist"]),
        SlashCommandEntry(command: .dashedList, primaryAlias: "dashedlist", aliases: ["dashedlist"]),
        SlashCommandEntry(command: .numberedList, primaryAlias: "numberedlist", aliases: ["numberedlist"]),
        SlashCommandEntry(command: .quote, primaryAlias: "quote", aliases: ["quote", "blockquote"]),
        SlashCommandEntry(command: .table, primaryAlias: "table", aliases: ["table"]),
    ]
    let entries: [SlashCommandEntry]

    init(entries: [SlashCommandEntry] = SlashCommandCatalog.defaultEntries) {
        self.entries = entries
    }

    init(itemSettings: [SlashCommandItemSetting]) {
        let entryByCommand = Dictionary(uniqueKeysWithValues: Self.defaultEntries.map { ($0.command, $0) })
        self.entries = SlashCommandItemSetting.normalized(itemSettings).compactMap { item in
            guard item.isVisible else { return nil }
            return entryByCommand[item.command]
        }
    }

    static func token(for command: FormattingCommand) -> String {
        defaultEntries.first(where: { $0.command == command })?.token ?? ""
    }

    func suggestions(for query: String) -> [SlashCommandEntry] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else {
            return entries
        }

        return entries.filter { entry in
            entry.aliases.contains { alias in
                normalize(alias).hasPrefix(normalizedQuery)
            }
        }
    }

    func exactMatch(for token: String) -> SlashCommandEntry? {
        let normalizedToken = normalize(token)
        return entries.first { entry in
            entry.aliases.contains { alias in
                normalize(alias) == normalizedToken
            }
        }
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
