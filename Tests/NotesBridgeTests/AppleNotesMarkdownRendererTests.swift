import Testing
@testable import NotesBridge

struct AppleNotesMarkdownRendererTests {
    private let renderer = AppleNotesMarkdownRenderer()

    @Test
    func rendersHeadingsListsQuotesCodeAndLinks() throws {
        let note = makeNote(
            segments: [
                segment("Release Notes\n", styleType: 0),
                segment("Overview\n", styleType: 1),
                segment("Details\n", styleType: 2),
                segment("Fast sync\n", styleType: 100),
                segment("Stable export\n", styleType: 100),
                segment("Task item\n", styleType: 103, checklistDone: true),
                segment("Quoted line\n", blockquote: true),
                segment("let answer = 42\nprint(answer)\n", styleType: 4),
                segment("Visit docs", link: "https://example.com"),
            ]
        )

        let rendered = try renderer.render(note: note) { _ in
            .inlineText("")
        }

        #expect(rendered.markdownTemplate.contains("# Release Notes"))
        #expect(rendered.markdownTemplate.contains("## Overview"))
        #expect(rendered.markdownTemplate.contains("### Details"))
        #expect(rendered.markdownTemplate.contains("- Fast sync"))
        #expect(rendered.markdownTemplate.contains("- Stable export"))
        #expect(rendered.markdownTemplate.contains("- [x] Task item"))
        #expect(rendered.markdownTemplate.contains("> Quoted line"))
        #expect(rendered.markdownTemplate.contains("```\nlet answer = 42\nprint(answer)\n```"))
        #expect(rendered.markdownTemplate.contains("[Visit docs](https://example.com)"))
    }

    @Test
    func injectsAttachmentTokensAndCollectsResolvedAttachments() throws {
        let note = makeNote(
            segments: [
                segment("Photo "),
                AppleNotesTestSegment(
                    fragment: "\u{FFFC}",
                    attachmentInfo: AppleNotesDecodedAttachmentInfo(
                        attachmentIdentifier: "attachment-1",
                        typeUti: "public.image"
                    )
                ),
                segment("\nDone"),
            ]
        )

        let rendered = try renderer.render(note: note) { info in
            .attachment(
                AppleNotesSyncAttachment(
                    token: "image-1",
                    logicalIdentifier: info.attachmentIdentifier,
                    sourceURL: URL(fileURLWithPath: "/tmp/image.png"),
                    preferredFilename: "image.png",
                    renderStyle: .embed,
                    modifiedAt: nil,
                    fileSize: nil
                ),
                isBlock: true
            )
        }

        #expect(rendered.markdownTemplate.contains("{{attachment:image-1}}"))
        #expect(rendered.attachments.count == 1)
        #expect(rendered.attachments.first?.preferredFilename == "image.png")
    }

    private func makeNote(segments: [AppleNotesTestSegment]) -> AppleNotesDecodedNote {
        let noteText = segments.map(\.fragment).joined()
        return AppleNotesDecodedNote(
            noteText: noteText,
            attributeRuns: segments.map { segment in
                AppleNotesDecodedAttributeRun(
                    length: (segment.fragment as NSString).length,
                    paragraphStyle: segment.paragraphStyle,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: segment.link,
                    attachmentInfo: segment.attachmentInfo
                )
            }
        )
    }

    private func segment(
        _ fragment: String,
        styleType: Int? = nil,
        checklistDone: Bool = false,
        blockquote: Bool = false,
        link: String? = nil
    ) -> AppleNotesTestSegment {
        AppleNotesTestSegment(
            fragment: fragment,
            paragraphStyle: AppleNotesDecodedParagraphStyle(
                styleType: styleType,
                indentAmount: 0,
                blockquote: blockquote,
                checklist: styleType == 103 ? AppleNotesDecodedChecklist(done: checklistDone) : nil
            ),
            link: link,
            attachmentInfo: nil
        )
    }
}

private struct AppleNotesTestSegment {
    var fragment: String
    var paragraphStyle: AppleNotesDecodedParagraphStyle? = nil
    var link: String? = nil
    var attachmentInfo: AppleNotesDecodedAttachmentInfo? = nil
}
