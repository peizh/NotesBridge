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

    @Test
    func preservesParagraphBreaksAndLineBreaks() {
        let html = """
        <div>First line<br>Second line</div>
        <div><br></div>
        <div>Third line</div>
        <p>Fourth line</p>
        """

        let markdown = transformer.htmlToMarkdown(html)

        #expect(markdown.contains("First line\nSecond line"))
        #expect(markdown.contains("Second line\n\nThird line"))
        #expect(markdown.contains("Third line\n\nFourth line"))
    }

    @Test
    func preservesListsQuotesAndCodeBlocks() {
        let html = """
        <blockquote><div>Quoted line</div></blockquote>
        <ul><li>One</li><li><strong>Two</strong></li></ul>
        <pre><code>let answer = 42\nprint(answer)</code></pre>
        """

        let markdown = transformer.htmlToMarkdown(html)

        #expect(markdown.contains("> Quoted line"))
        #expect(markdown.contains("- One"))
        #expect(markdown.contains("- **Two**"))
        #expect(markdown.contains("```\nlet answer = 42\nprint(answer)\n```"))
    }

    @Test
    func fallsBackToPlaintextWhenHTMLCannotBeParsed() {
        let markdown = transformer.htmlToMarkdown("", fallbackPlaintext: "Line one\nLine two")

        #expect(markdown == "Line one\nLine two")
    }
}
