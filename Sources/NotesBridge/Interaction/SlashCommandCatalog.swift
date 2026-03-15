import Foundation

struct SlashCommandEntry: Identifiable, Equatable, Sendable {
    let command: FormattingCommand
    let primaryAlias: String
    let aliases: [String]
    let titleKey: String

    var id: FormattingCommand { command }
    var token: String { "/\(primaryAlias)" }

    func localizedTitle(using localization: AppLocalization) -> String {
        localization.text(titleKey)
    }
}

struct SlashCommandCatalog: Sendable {
    let entries: [SlashCommandEntry] = [
        SlashCommandEntry(command: .title, primaryAlias: "title", aliases: ["title", "h1"], titleKey: "Title"),
        SlashCommandEntry(command: .heading, primaryAlias: "heading", aliases: ["heading", "h2"], titleKey: "Heading"),
        SlashCommandEntry(command: .subheading, primaryAlias: "subheading", aliases: ["subheading", "h3"], titleKey: "Subheading"),
        SlashCommandEntry(command: .body, primaryAlias: "body", aliases: ["body"], titleKey: "Body"),
        SlashCommandEntry(command: .monostyled, primaryAlias: "monostyled", aliases: ["monostyled", "code"], titleKey: "Monostyled"),
        SlashCommandEntry(command: .checklist, primaryAlias: "checklist", aliases: ["checklist"], titleKey: "Checklist"),
        SlashCommandEntry(command: .bulletedList, primaryAlias: "bulletedlist", aliases: ["bulletedlist"], titleKey: "Bulleted List"),
        SlashCommandEntry(command: .dashedList, primaryAlias: "dashedlist", aliases: ["dashedlist"], titleKey: "Dashed List"),
        SlashCommandEntry(command: .numberedList, primaryAlias: "numberedlist", aliases: ["numberedlist"], titleKey: "Numbered List"),
        SlashCommandEntry(command: .quote, primaryAlias: "quote", aliases: ["quote", "blockquote"], titleKey: "Block Quote"),
        SlashCommandEntry(command: .table, primaryAlias: "table", aliases: ["table"], titleKey: "Table"),
    ]

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
