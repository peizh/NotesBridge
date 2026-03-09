import Foundation

struct SlashCommandToken: Equatable, Sendable {
    let range: NSRange
    let rawValue: String
    let typedQuery: String
}

struct SlashCommandMenuMatch: Equatable, Sendable {
    let token: SlashCommandToken
    let entries: [SlashCommandEntry]
}

struct SlashCommandCommitMatch: Equatable, Sendable {
    let token: SlashCommandToken
    let entry: SlashCommandEntry
    let replacementRange: NSRange
    let removesTrailingSpace: Bool
}

struct SlashCommandParser: Sendable {
    private let whitespaceAndNewlines = CharacterSet.whitespacesAndNewlines

    func menuMatch(in value: String, caretLocation: Int) -> SlashCommandMenuMatch? {
        guard let token = activeToken(in: value, caretLocation: caretLocation) else {
            return nil
        }

        let entries = SlashCommandCatalog().suggestions(for: token.typedQuery)
        guard !entries.isEmpty else {
            return nil
        }

        return SlashCommandMenuMatch(token: token, entries: entries)
    }

    func commitMatchBeforeSpace(in value: String, caretLocation: Int) -> SlashCommandCommitMatch? {
        let string = value as NSString
        guard caretLocation > 0,
              caretLocation <= string.length,
              string.substring(with: NSRange(location: caretLocation - 1, length: 1)) == " "
        else {
            return nil
        }

        let tokenEnd = caretLocation - 1
        guard let tokenRange = tokenRange(in: string, containing: max(tokenEnd - 1, 0), allowCaretAtWhitespace: false) else {
            return nil
        }

        let tokenText = string.substring(with: tokenRange)
        guard let entry = SlashCommandCatalog().exactMatch(for: String(tokenText.dropFirst())) else {
            return nil
        }

        let typedQuery = String(tokenText.dropFirst())
        let token = SlashCommandToken(range: tokenRange, rawValue: tokenText, typedQuery: typedQuery)
        return SlashCommandCommitMatch(
            token: token,
            entry: entry,
            replacementRange: NSRange(location: tokenRange.location, length: tokenRange.length + 1),
            removesTrailingSpace: true
        )
    }

    private func activeToken(in value: String, caretLocation: Int) -> SlashCommandToken? {
        let string = value as NSString
        guard let tokenRange = tokenRange(in: string, containing: caretLocation, allowCaretAtWhitespace: false) else {
            return nil
        }

        let tokenText = string.substring(with: tokenRange)
        let queryLength = max(0, caretLocation - tokenRange.location - 1)
        let typedQueryRange = NSRange(location: tokenRange.location + 1, length: min(queryLength, max(0, tokenRange.length - 1)))
        let typedQuery = typedQueryRange.length > 0 ? string.substring(with: typedQueryRange) : ""

        return SlashCommandToken(range: tokenRange, rawValue: tokenText, typedQuery: typedQuery)
    }

    private func tokenRange(in string: NSString, containing caretLocation: Int, allowCaretAtWhitespace: Bool) -> NSRange? {
        guard string.length > 0 else { return nil }
        let safeCaret = max(0, min(caretLocation, string.length))

        if !allowCaretAtWhitespace,
           safeCaret < string.length,
           isWhitespace(string.character(at: safeCaret))
        {
            return nil
        }

        var start = safeCaret
        while start > 0, !isWhitespace(string.character(at: start - 1)) {
            start -= 1
        }

        var end = safeCaret
        while end < string.length, !isWhitespace(string.character(at: end)) {
            end += 1
        }

        guard end > start else { return nil }

        let range = NSRange(location: start, length: end - start)
        let tokenText = string.substring(with: range)
        guard tokenText.first == "/" else {
            return nil
        }

        if range.location > 0, !isWhitespace(string.character(at: range.location - 1)) {
            return nil
        }

        return range
    }

    private func isWhitespace(_ value: unichar) -> Bool {
        guard let scalar = UnicodeScalar(value) else { return false }
        return whitespaceAndNewlines.contains(scalar)
    }
}
