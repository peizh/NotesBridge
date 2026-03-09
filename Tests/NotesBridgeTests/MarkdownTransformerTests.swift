import Testing
@testable import NotesBridge

struct MarkdownTransformerTests {
    private let transformer = MarkdownTransformer()

    @Test
    func convertsHTMLToMarkdown() {
        let html = """
        <h1>Release Notes</h1>
        <div><strong>Highlights</strong></div>
        <ul><li>Fast sync</li><li>Markdown preview</li></ul>
        """

        let markdown = transformer.htmlToMarkdown(html)

        #expect(markdown.contains("# Release Notes"))
        #expect(markdown.contains("**Highlights**"))
        #expect(markdown.contains("- Fast sync"))
        #expect(markdown.contains("- Markdown preview"))
    }

    @Test
    func convertsMarkdownToHTML() {
        let markdown = """
        # Daily Note

        - shipped sync
        - improved preview

        Use **bold** and `code`.
        """

        let html = transformer.markdownToHTML(markdown)

        #expect(html.contains("<h1>Daily Note</h1>"))
        #expect(html.contains("<li>shipped sync</li>"))
        #expect(html.contains("<b>bold</b>"))
        #expect(html.contains("<code>code</code>"))
    }

    @Test
    func stripsHTMLToPlaintext() {
        let html = """
        <div>Hello <b>NotesBridge</b></div>
        <div><br></div>
        <div>Second line</div>
        """

        let plain = transformer.plaintext(fromHTML: html)

        #expect(plain.contains("Hello NotesBridge"))
        #expect(plain.contains("Second line"))
    }
}
