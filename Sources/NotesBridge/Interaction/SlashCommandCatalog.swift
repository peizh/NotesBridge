import Foundation

struct SlashCommandEntry: Identifiable, Equatable, Sendable {
    let command: FormattingCommand
    let primaryAlias: String
    let aliases: [String]
    let title: String

    var id: FormattingCommand { command }
    var token: String { "/\(primaryAlias)" }
}

struct SlashCommandCatalog: Sendable {
    let entries: [SlashCommandEntry] = [
        SlashCommandEntry(command: .title, primaryAlias: "title", aliases: ["title", "h1"], title: "Title"),
        SlashCommandEntry(command: .heading, primaryAlias: "heading", aliases: ["heading", "h2"], title: "Heading"),
        SlashCommandEntry(command: .subheading, primaryAlias: "subheading", aliases: ["subheading", "h3"], title: "Subheading"),
        SlashCommandEntry(command: .body, primaryAlias: "body", aliases: ["body"], title: "Body"),
        SlashCommandEntry(command: .monostyled, primaryAlias: "monostyled", aliases: ["monostyled", "code"], title: "Monostyled"),
        SlashCommandEntry(command: .checklist, primaryAlias: "checklist", aliases: ["checklist"], title: "Checklist"),
        SlashCommandEntry(command: .bulletedList, primaryAlias: "bulletedlist", aliases: ["bulletedlist"], title: "Bulleted List"),
        SlashCommandEntry(command: .dashedList, primaryAlias: "dashedlist", aliases: ["dashedlist"], title: "Dashed List"),
        SlashCommandEntry(command: .numberedList, primaryAlias: "numberedlist", aliases: ["numberedlist"], title: "Numbered List"),
        SlashCommandEntry(command: .quote, primaryAlias: "quote", aliases: ["quote", "blockquote"], title: "Block Quote"),
        SlashCommandEntry(command: .table, primaryAlias: "table", aliases: ["table"], title: "Table"),
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
