import AppKit
import Foundation
import SwiftSoup

struct MarkdownTransformer: Sendable {
    func htmlToMarkdown(_ html: String, fallbackPlaintext: String? = nil) -> String {
        guard !html.isEmpty else {
            return normalizePlaintextFallback(fallbackPlaintext ?? "")
        }

        do {
            let document = try SwiftSoup.parseBodyFragment(normalizeLineEndings(html))
            let body = document.body()
            let blocks = try MarkdownHTMLRenderer().renderBlocks(from: body?.getChildNodes() ?? [])
            let markdown = normalizeFinalMarkdown(blocks.joined(separator: "\n\n"))

            if markdown.isEmpty {
                return normalizePlaintextFallback(fallbackPlaintext ?? plaintext(fromHTML: html))
            }

            return markdown
        } catch {
            return normalizePlaintextFallback(fallbackPlaintext ?? plaintext(fromHTML: html))
        }
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

    private func normalizeLineEndings(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private func normalizePlaintextFallback(_ value: String) -> String {
        normalizeFinalMarkdown(normalizeLineEndings(value))
    }

    private func normalizeFinalMarkdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MarkdownHTMLRenderer {
    func renderBlocks(from nodes: [Node]) throws -> [String] {
        var blocks: [String] = []
        var inlineBuffer = ""

        func flushInlineBuffer() {
            let normalized = normalizeInlineMarkdown(inlineBuffer)
            if !normalized.isEmpty {
                blocks.append(normalized)
            }
            inlineBuffer = ""
        }

        for node in nodes {
            if let element = node as? Element {
                let tagName = element.tagName().lowercased()
                if isBlockElement(tagName) {
                    flushInlineBuffer()
                    let rendered = try renderBlock(element)
                    if !rendered.isEmpty {
                        blocks.append(rendered)
                    }
                } else {
                    inlineBuffer += try renderInline(node)
                }
            } else {
                inlineBuffer += try renderInline(node)
            }
        }

        flushInlineBuffer()
        return blocks
    }

    private func renderBlock(_ element: Element) throws -> String {
        switch element.tagName().lowercased() {
        case "h1":
            let content = normalizeInlineMarkdown(try renderInlineChildren(of: element))
            return content.isEmpty ? "" : "# \(content)"
        case "h2":
            let content = normalizeInlineMarkdown(try renderInlineChildren(of: element))
            return content.isEmpty ? "" : "## \(content)"
        case "h3":
            let content = normalizeInlineMarkdown(try renderInlineChildren(of: element))
            return content.isEmpty ? "" : "### \(content)"
        case "ul":
            return try renderList(element, ordered: false)
        case "ol":
            return try renderList(element, ordered: true)
        case "blockquote":
            let content = try renderBlocks(from: element.getChildNodes()).joined(separator: "\n\n")
            return prefixBlockquote(content)
        case "pre":
            let codeElement = element.getChildNodes().compactMap { $0 as? Element }.first { $0.tagName().lowercased() == "code" }
            let rawText = try extractRawText(from: codeElement ?? element)
            let trimmed = rawText
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .newlines)
            return trimmed.isEmpty ? "" : "```\n\(trimmed)\n```"
        case "img":
            return "> Apple Notes attachment omitted"
        default:
            return try renderBlocks(from: element.getChildNodes()).joined(separator: "\n\n")
        }
    }

    private func renderList(_ element: Element, ordered: Bool) throws -> String {
        let items = element.getChildNodes().compactMap { $0 as? Element }.filter { $0.tagName().lowercased() == "li" }
        return try items.enumerated().map { index, item in
            let prefix = ordered ? "\(index + 1). " : "- "
            return try renderListItem(item, prefix: prefix)
        }.joined(separator: "\n")
    }

    private func renderListItem(_ element: Element, prefix: String) throws -> String {
        let content = try renderBlocks(from: element.getChildNodes()).joined(separator: "\n")
        let normalized = normalizeInlineMarkdown(content)
        let lines = normalized.components(separatedBy: "\n")

        return lines.enumerated().map { index, line in
            if index == 0 {
                return prefix + line
            }

            if line.isEmpty {
                return ""
            }

            return String(repeating: " ", count: prefix.count) + line
        }.joined(separator: "\n")
    }

    private func renderInlineChildren(of element: Element) throws -> String {
        try element.getChildNodes().map { try renderInline($0) }.joined()
    }

    private func renderInline(_ node: Node) throws -> String {
        if let textNode = node as? TextNode {
            return normalizeTextNode(textNode.getWholeText())
        }

        guard let element = node as? Element else {
            return ""
        }

        switch element.tagName().lowercased() {
        case "br":
            return "\n"
        case "strong", "b":
            let content = normalizeInlineMarkdown(try renderInlineChildren(of: element))
            return content.isEmpty ? "" : "**\(content)**"
        case "em", "i":
            let content = normalizeInlineMarkdown(try renderInlineChildren(of: element))
            return content.isEmpty ? "" : "*\(content)*"
        case "code":
            let content = normalizeInlineMarkdown(try renderInlineChildren(of: element))
            return content.isEmpty ? "" : "`\(content)`"
        case "a":
            let content = normalizeInlineMarkdown(try renderInlineChildren(of: element))
            let href = try element.attr("href")
            if href.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
            return content.isEmpty ? href : "[\(content)](\(href))"
        case "img":
            return "Apple Notes attachment omitted"
        default:
            if isBlockElement(element.tagName().lowercased()) {
                return try renderBlocks(from: element.getChildNodes()).joined(separator: "\n\n")
            }
            return try renderInlineChildren(of: element)
        }
    }

    private func extractRawText(from node: Node) throws -> String {
        if let textNode = node as? TextNode {
            return textNode.getWholeText()
        }

        guard let element = node as? Element else {
            return ""
        }

        if element.tagName().lowercased() == "br" {
            return "\n"
        }

        return try element.getChildNodes().map { try extractRawText(from: $0) }.joined()
    }

    private func prefixBlockquote(_ value: String) -> String {
        value
            .components(separatedBy: "\n")
            .map { line in
                line.isEmpty ? ">" : "> \(line)"
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeTextNode(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
    }

    private func normalizeInlineMarkdown(_ value: String) -> String {
        let placeholder = "\u{000B}"
        let withPlaceholder = value.replacingOccurrences(of: "\n", with: placeholder)
        let collapsed = withPlaceholder.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        let restored = collapsed.replacingOccurrences(of: placeholder, with: "\n")
        let normalizedLines = restored
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        return normalizedLines.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isBlockElement(_ tagName: String) -> Bool {
        [
            "body",
            "div",
            "p",
            "section",
            "article",
            "blockquote",
            "ul",
            "ol",
            "li",
            "pre",
            "h1",
            "h2",
            "h3",
            "img",
        ].contains(tagName)
    }
}
