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
    func backfillsMissingParagraphStyleForLeadingCodeBlockCharacter() throws {
        let noteText = "Keep these backup codes somewhere safe but accessible.\n1\n"
        let note = AppleNotesDecodedNote(
            noteText: noteText,
            attributeRuns: [
                AppleNotesDecodedAttributeRun(
                    length: 1,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: nil,
                    attachmentInfo: nil
                ),
                AppleNotesDecodedAttributeRun(
                    length: (noteText as NSString).length - 1,
                    paragraphStyle: AppleNotesDecodedParagraphStyle(
                        styleType: 4,
                        indentAmount: 0,
                        blockquote: false,
                        checklist: nil
                    ),
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: nil,
                    attachmentInfo: nil
                ),
            ]
        )

        let rendered = try renderer.render(note: note) { _ in
            .inlineText("")
        }

        #expect(rendered.markdownTemplate == "```\n\(noteText)```")
    }

    @Test
    func preservesMonospacedRunBoundariesWhenNoteTextContainsCRLF() throws {
        let noteText = "\r\nKeep these backup codes somewhere safe but accessible.\r\n"
        let note = AppleNotesDecodedNote(
            noteText: noteText,
            attributeRuns: [
                AppleNotesDecodedAttributeRun(
                    length: ("\r\n" as NSString).length,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: nil,
                    attachmentInfo: nil
                ),
                AppleNotesDecodedAttributeRun(
                    length: ("Keep these backup codes somewhere safe but accessible.\r\n" as NSString).length,
                    paragraphStyle: AppleNotesDecodedParagraphStyle(
                        styleType: 4,
                        indentAmount: 0,
                        blockquote: false,
                        checklist: nil
                    ),
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: nil,
                    attachmentInfo: nil
                ),
            ]
        )

        let rendered = try renderer.render(note: note) { _ in
            .inlineText("")
        }

        #expect(!rendered.markdownTemplate.contains("\nK\n```"))
        #expect(rendered.markdownTemplate.contains("Keep these backup codes somewhere safe but accessible."))
        #expect(!rendered.markdownTemplate.contains("\r"))
    }

    @Test
    func mergesAdjacentMailtoAndStrikethroughRunsBeforeMarkdownFormatting() throws {
        let note = AppleNotesDecodedNote(
            noteText: "alternative email: p@peizh.live\njgznkr1rmep",
            attributeRuns: [
                AppleNotesDecodedAttributeRun(
                    length: ("alternative email: " as NSString).length,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: nil,
                    attachmentInfo: nil
                ),
                AppleNotesDecodedAttributeRun(
                    length: ("p@" as NSString).length,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: "mailto:p@peizh.live",
                    attachmentInfo: nil
                ),
                AppleNotesDecodedAttributeRun(
                    length: ("p" as NSString).length,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: "mailto:p@peizh.live",
                    attachmentInfo: nil
                ),
                AppleNotesDecodedAttributeRun(
                    length: ("ei" as NSString).length,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: "mailto:p@peizh.live",
                    attachmentInfo: nil
                ),
                AppleNotesDecodedAttributeRun(
                    length: ("zh" as NSString).length,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: "mailto:p@peizh.live",
                    attachmentInfo: nil
                ),
                AppleNotesDecodedAttributeRun(
                    length: ("." as NSString).length,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: "mailto:p@peizh.live",
                    attachmentInfo: nil
                ),
                AppleNotesDecodedAttributeRun(
                    length: ("live" as NSString).length,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: "mailto:p@peizh.live",
                    attachmentInfo: nil
                ),
                AppleNotesDecodedAttributeRun(
                    length: ("\n" as NSString).length,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: false,
                    superscript: nil,
                    link: nil,
                    attachmentInfo: nil
                ),
                AppleNotesDecodedAttributeRun(
                    length: ("jgzn" as NSString).length,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: true,
                    superscript: nil,
                    link: nil,
                    attachmentInfo: nil
                ),
                AppleNotesDecodedAttributeRun(
                    length: ("kr1r" as NSString).length,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: true,
                    superscript: nil,
                    link: nil,
                    attachmentInfo: nil
                ),
                AppleNotesDecodedAttributeRun(
                    length: ("mep" as NSString).length,
                    paragraphStyle: nil,
                    fontWeight: nil,
                    underlined: false,
                    strikethrough: true,
                    superscript: nil,
                    link: nil,
                    attachmentInfo: nil
                ),
            ]
        )

        let rendered = try renderer.render(note: note) { _ in
            .inlineText("")
        }

        #expect(rendered.markdownTemplate == "alternative email: [p@peizh.live](mailto:p@peizh.live)\n~~jgznkr1rmep~~")
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

        #expect(rendered.markdownTemplate.contains("{{attachment:image-1-1}}"))
        #expect(rendered.attachments.count == 1)
        #expect(rendered.attachments.first?.preferredFilename == "image.png")
    }

    @Test
    func convertsAppleNotesTextLinksIntoInternalLinkTokens() throws {
        let note = makeNote(
            segments: [
                segment(
                    "9/3/2025",
                    link: "applenotes:note/109a8649-4591-47a2-961d-55352a9c25fe?ownerIdentifier=test"
                ),
            ]
        )

        let rendered = try renderer.render(note: note) { _ in
            .inlineText("")
        }

        #expect(rendered.markdownTemplate == "{{note-link:note-link-1}}")
        #expect(rendered.internalLinks.count == 1)
        #expect(rendered.internalLinks.first?.displayText == "9/3/2025")
        #expect(rendered.internalLinks.first?.targetSourceIdentifier == "109A8649-4591-47A2-961D-55352A9C25FE")
    }

    @Test
    func convertsAppleNotesXCoreDataLinksIntoInternalLinkTokens() throws {
        let note = makeNote(
            segments: [
                segment(
                    "Roadmap Q3",
                    link: "applenotes:note/x-coredata://625E753D-DB29-4635-93F4-C869C2726CCF/ICNote/p5916"
                ),
            ]
        )

        let rendered = try renderer.render(note: note) { _ in
            .inlineText("")
        }

        #expect(rendered.markdownTemplate == "{{note-link:note-link-1}}")
        #expect(rendered.internalLinks.count == 1)
        #expect(
            rendered.internalLinks.first?.targetSourceIdentifier
                == "X-COREDATA://625E753D-DB29-4635-93F4-C869C2726CCF/ICNOTE/P5916"
        )
    }

    @Test
    func insertsBlankLineBetweenChecklistAndFollowingLinkParagraph() throws {
        let note = makeNote(
            segments: [
                segment("Confirm source\n", styleType: 103),
                segment("Open reference", link: "https://example.com"),
            ]
        )

        let rendered = try renderer.render(note: note) { _ in
            .inlineText("")
        }

        #expect(rendered.markdownTemplate == "- [ ] Confirm source\n\n[Open reference](https://example.com)")
    }

    @Test
    func collectsInternalLinksReturnedFromAttachmentResolver() throws {
        let note = makeNote(
            segments: [
                AppleNotesTestSegment(
                    fragment: "\u{FFFC}",
                    attachmentInfo: AppleNotesDecodedAttachmentInfo(
                        attachmentIdentifier: "note-link-attachment",
                        typeUti: "com.apple.notes.inlinetextattachment.link"
                    )
                ),
            ]
        )

        let rendered = try renderer.render(note: note) { _ in
            .internalLink(
                AppleNotesSyncInternalLink(
                    token: "journal-link",
                    targetSourceIdentifier: "TARGET-NOTE",
                    displayText: "9/3/2025"
                )
            )
        }

        #expect(rendered.markdownTemplate == "{{note-link:journal-link}}")
        #expect(rendered.internalLinks.count == 1)
        #expect(rendered.internalLinks.first?.displayText == "9/3/2025")
    }

    @Test
    func tableCellModeNormalizesNewlinesAndPipes() throws {
        let note = makeNote(
            segments: [
                segment("Line 1\nLine 2 | Value"),
            ]
        )

        let rendered = try renderer.render(note: note, options: .tableCell) { _ in
            .inlineText("")
        }

        #expect(rendered.markdownTemplate == "Line 1<br>Line 2 &#124; Value")
    }

    @Test
    func mergesRenderedFragmentsFromAttachmentResolver() throws {
        let note = makeNote(
            segments: [
                AppleNotesTestSegment(
                    fragment: "\u{FFFC}",
                    attachmentInfo: AppleNotesDecodedAttachmentInfo(
                        attachmentIdentifier: "table-1",
                        typeUti: "com.apple.notes.table"
                    )
                ),
            ]
        )

        let rendered = try renderer.render(note: note) { _ in
            .fragment(
                AppleNotesRenderedFragment(
                    markdownTemplate: "{{note-link:child-link}} {{attachment:child-attachment}}",
                    internalLinks: [
                        AppleNotesSyncInternalLink(
                            token: "child-link",
                            targetSourceIdentifier: "TARGET-NOTE",
                            displayText: "Roadmap"
                        ),
                    ],
                    attachments: [
                        AppleNotesSyncAttachment(
                            token: "child-attachment",
                            logicalIdentifier: "child-attachment",
                            sourceURL: URL(fileURLWithPath: "/tmp/photo.png"),
                            preferredFilename: "photo.png",
                            renderStyle: .embed,
                            modifiedAt: nil,
                            fileSize: nil
                        ),
                    ],
                    isBlock: true
                )
            )
        }

        #expect(rendered.markdownTemplate.contains("{{note-link:child-link-1}}"))
        #expect(rendered.markdownTemplate.contains("{{attachment:child-attachment-1}}"))
        #expect(rendered.internalLinks.count == 1)
        #expect(rendered.attachments.count == 1)
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
