import AppKit
import Foundation

struct MarkdownTransformer: Sendable {
    func htmlToMarkdown(_ html: String) -> String {
        guard !html.isEmpty else { return "" }

        var output = html.replacingOccurrences(of: "\r\n", with: "\n")
        output = output.replacingOccurrences(of: "\r", with: "\n")

        output = replacing(
            pattern: "(?is)<img\\b[^>]*>",
            in: output,
            with: "\n> Apple Notes attachment omitted\n"
        )

        output = replace(
            pattern: "(?is)<a\\b[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>",
            in: output
        ) { captures in
            "[\(decodeHTML(captures[1]))](\(decodeHTML(captures[0])))"
        }

        output = replace(
            pattern: "(?is)<(strong|b)\\b[^>]*>(.*?)</\\1>",
            in: output
        ) { captures in
            let content = decodeHTML(stripTags(from: captures[1])).trimmingCharacters(in: .whitespacesAndNewlines)
            return "**\(content)**"
        }

        output = replace(
            pattern: "(?is)<(em|i)\\b[^>]*>(.*?)</\\1>",
            in: output
        ) { captures in
            let content = decodeHTML(stripTags(from: captures[1])).trimmingCharacters(in: .whitespacesAndNewlines)
            return "*\(content)*"
        }

        output = replace(
            pattern: "(?is)<code\\b[^>]*>(.*?)</code>",
            in: output
        ) { captures in
            "`\(decodeHTML(stripTags(from: captures[0])))`"
        }

        for level in 1 ... 3 {
            output = replace(
                pattern: "(?is)<h\(level)\\b[^>]*>(.*?)</h\(level)>",
                in: output
            ) { captures in
                "\(String(repeating: "#", count: level)) \(decodeHTML(stripTags(from: captures[0])).trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            }
        }

        output = replace(
            pattern: "(?is)<li\\b[^>]*>(.*?)</li>",
            in: output
        ) { captures in
            "- \(decodeHTML(stripTags(from: captures[0])).trimmingCharacters(in: .whitespacesAndNewlines))\n"
        }

        output = replacing(pattern: "(?is)</?(ul|ol)\\b[^>]*>", in: output, with: "\n")
        output = replacing(pattern: "(?is)<br\\s*/?>", in: output, with: "\n")
        output = replacing(pattern: "(?is)</?(div|p|section|article|blockquote)\\b[^>]*>", in: output, with: "\n")
        output = replacing(pattern: "(?is)<[^>]+>", in: output, with: "")
        output = decodeHTML(output)
        output = output.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func plaintext(fromHTML html: String) -> String {
        let attributed = htmlAttributedString(from: html)
        let plain = attributed?.string ?? stripTags(from: html)
        return plain.replacingOccurrences(of: "\u{FFFC}", with: " ")
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func markdownToHTML(_ markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var htmlBlocks: [String] = []
        var listItems: [String] = []
        var codeLines: [String] = []
        var inCodeBlock = false

        func flushList() {
            guard !listItems.isEmpty else { return }
            htmlBlocks.append("<ul>\(listItems.joined())</ul>")
            listItems.removeAll()
        }

        func flushCodeBlock() {
            guard !codeLines.isEmpty else { return }
            let code = escapeHTML(codeLines.joined(separator: "\n"))
            htmlBlocks.append("<pre><code>\(code)</code></pre>")
            codeLines.removeAll()
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    flushCodeBlock()
                    inCodeBlock = false
                } else {
                    flushList()
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            if let listPrefix = ["- ", "* "].first(where: { trimmed.hasPrefix($0) }) {
                let content = String(trimmed.dropFirst(listPrefix.count))
                listItems.append("<li>\(inlineMarkdownToHTML(content))</li>")
                continue
            }

            flushList()

            if trimmed.isEmpty {
                htmlBlocks.append("<div><br></div>")
                continue
            }

            if let heading = headingHTML(for: trimmed) {
                htmlBlocks.append(heading)
                continue
            }

            htmlBlocks.append("<div>\(inlineMarkdownToHTML(trimmed))</div>")
        }

        flushList()
        if inCodeBlock {
            flushCodeBlock()
        }

        return htmlBlocks.joined(separator: "\n")
    }

    func preview(for markdown: String) -> AttributedString {
        if let parsed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return parsed
        }

        return AttributedString(markdown)
    }

    private func inlineMarkdownToHTML(_ line: String) -> String {
        var html = escapeHTML(line)

        html = replace(
            pattern: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)",
            in: html
        ) { captures in
            "<a href=\"\(escapeHTMLAttribute(captures[1]))\">\(captures[0])</a>"
        }

        html = replace(pattern: "`([^`]+)`", in: html) { captures in
            "<code>\(captures[0])</code>"
        }

        html = replace(pattern: "\\*\\*([^*]+)\\*\\*", in: html) { captures in
            "<b>\(captures[0])</b>"
        }

        html = replace(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)", in: html) { captures in
            "<i>\(captures[0])</i>"
        }

        html = replace(pattern: "_([^_]+)_", in: html) { captures in
            "<i>\(captures[0])</i>"
        }

        return html
    }

    private func headingHTML(for line: String) -> String? {
        let prefixes = [(3, "### "), (2, "## "), (1, "# ")]
        for (level, prefix) in prefixes where line.hasPrefix(prefix) {
            let content = line.dropFirst(prefix.count)
            return "<h\(level)>\(inlineMarkdownToHTML(String(content)))</h\(level)>"
        }
        return nil
    }

    private func htmlAttributedString(from html: String) -> NSAttributedString? {
        guard let data = html.data(using: .utf8) else { return nil }
        return try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        )
    }

    private func decodeHTML(_ value: String) -> String {
        htmlAttributedString(from: value)?.string ?? value
    }

    private func stripTags(from value: String) -> String {
        replacing(pattern: "(?is)<[^>]+>", in: value, with: "")
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeHTMLAttribute(_ value: String) -> String {
        escapeHTML(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func replacing(pattern: String, in text: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    private func replace(pattern: String, in text: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text

        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let captures = (1 ..< match.numberOfRanges).compactMap { index -> String? in
                guard let captureRange = Range(match.range(at: index), in: result) else { return nil }
                return String(result[captureRange])
            }
            result.replaceSubrange(range, with: transform(captures))
        }

        return result
    }
}
