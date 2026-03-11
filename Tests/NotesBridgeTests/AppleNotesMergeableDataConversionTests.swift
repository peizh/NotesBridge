import Testing
@testable import NotesBridge

struct AppleNotesMergeableDataConversionTests {
    @Test
    func convertsTableIntoMarkdownAndPreservesNestedLinks() throws {
        let renderer = AppleNotesMarkdownRenderer()
        let converter = AppleNotesTableConverter(
            mergeableData: makeTwoByTwoTable(),
            renderer: renderer
        )

        let rendered = try #require(
            converter.renderFragment { attachmentInfo in
                if attachmentInfo.typeUti == "com.apple.notes.inlinetextattachment.link" {
                    return .internalLink(
                        AppleNotesSyncInternalLink(
                            token: "roadmap-link",
                            targetSourceIdentifier: "TARGET-NOTE",
                            displayText: "Roadmap"
                        )
                    )
                }
                return .inlineText("")
            }
        )

        #expect(rendered.markdownTemplate.contains("| Name | Status |"))
        #expect(rendered.markdownTemplate.contains("| {{note-link:table-note-link-1}} | Line 1<br>Line 2 &#124; Value |"))
        #expect(rendered.markdownTemplate.contains("Line 1<br>Line 2 &#124; Value"))
        #expect(rendered.markdownTemplate.contains("{{note-link:table-note-link-1}}"))
        #expect(rendered.internalLinks.count == 1)
        #expect(rendered.internalLinks.first?.displayText == "Roadmap")
    }

    @Test
    func extractsScanPageIdentifiersFromGalleryObjects() {
        let converter = AppleNotesScanGalleryConverter(
            mergeableData: AppleNotesMergeableData(
                entries: [
                    AppleNotesMergeableObjectEntry(
                        registerLatest: nil,
                        dictionary: [],
                        note: nil,
                        customMap: AppleNotesMergeableCustomMap(
                            type: 0,
                            entries: [
                                AppleNotesMergeableMapEntry(
                                    key: 0,
                                    value: AppleNotesMergeableObjectID(
                                        unsignedIntegerValue: nil,
                                        stringValue: "PAGE-1",
                                        objectIndex: nil
                                    )
                                ),
                            ]
                        ),
                        orderedSet: nil
                    ),
                    AppleNotesMergeableObjectEntry(
                        registerLatest: nil,
                        dictionary: [],
                        note: nil,
                        customMap: AppleNotesMergeableCustomMap(
                            type: 0,
                            entries: [
                                AppleNotesMergeableMapEntry(
                                    key: 0,
                                    value: AppleNotesMergeableObjectID(
                                        unsignedIntegerValue: nil,
                                        stringValue: "PAGE-2",
                                        objectIndex: nil
                                    )
                                ),
                            ]
                        ),
                        orderedSet: nil
                    ),
                ],
                keys: [],
                types: [],
                uuids: []
            )
        )

        #expect(converter.pageAttachmentIdentifiers() == ["PAGE-1", "PAGE-2"])
    }
}

private extension AppleNotesMergeableDataConversionTests {
    func makeTwoByTwoTable() -> AppleNotesMergeableData {
        let uuids = (0 ..< 8).map { "uuid-\($0)" }
        var entries = Array(
            repeating: AppleNotesMergeableObjectEntry(
                registerLatest: nil,
                dictionary: [],
                note: nil,
                customMap: nil,
                orderedSet: nil
            ),
            count: 20
        )

        entries[0] = AppleNotesMergeableObjectEntry(
            registerLatest: nil,
            dictionary: [],
            note: nil,
            customMap: AppleNotesMergeableCustomMap(
                type: 0,
                entries: [
                    .init(key: 0, value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 1)),
                    .init(key: 1, value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 2)),
                    .init(key: 2, value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 3)),
                ]
            ),
            orderedSet: nil
        )

        entries[1] = AppleNotesMergeableObjectEntry(
            registerLatest: nil,
            dictionary: [],
            note: nil,
            customMap: nil,
            orderedSet: AppleNotesMergeableOrderedSet(
                ordering: AppleNotesMergeableOrderedSetOrdering(
                    attachments: [
                        .init(index: 0, uuid: uuids[0]),
                        .init(index: 1, uuid: uuids[1]),
                    ],
                    contents: [
                        .init(key: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 4), value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 6)),
                        .init(key: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 5), value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 7)),
                    ]
                )
            )
        )

        entries[2] = AppleNotesMergeableObjectEntry(
            registerLatest: nil,
            dictionary: [],
            note: nil,
            customMap: nil,
            orderedSet: AppleNotesMergeableOrderedSet(
                ordering: AppleNotesMergeableOrderedSetOrdering(
                    attachments: [
                        .init(index: 0, uuid: uuids[2]),
                        .init(index: 1, uuid: uuids[3]),
                    ],
                    contents: [
                        .init(key: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 8), value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 10)),
                        .init(key: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 9), value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 11)),
                    ]
                )
            )
        )

        entries[3] = AppleNotesMergeableObjectEntry(
            registerLatest: nil,
            dictionary: [
                .init(key: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 10), value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 12)),
                .init(key: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 11), value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 13)),
            ],
            note: nil,
            customMap: nil,
            orderedSet: nil
        )

        entries[4] = uuidReferenceEntry(uuidIndex: 0)
        entries[5] = uuidReferenceEntry(uuidIndex: 1)
        entries[6] = uuidReferenceEntry(uuidIndex: 4)
        entries[7] = uuidReferenceEntry(uuidIndex: 5)
        entries[8] = uuidReferenceEntry(uuidIndex: 2)
        entries[9] = uuidReferenceEntry(uuidIndex: 3)
        entries[10] = uuidReferenceEntry(uuidIndex: 6)
        entries[11] = uuidReferenceEntry(uuidIndex: 7)

        entries[12] = AppleNotesMergeableObjectEntry(
            registerLatest: nil,
            dictionary: [
                .init(key: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 6), value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 14)),
                .init(key: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 7), value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 18)),
            ],
            note: nil,
            customMap: nil,
            orderedSet: nil
        )
        entries[13] = AppleNotesMergeableObjectEntry(
            registerLatest: nil,
            dictionary: [
                .init(key: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 6), value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 16)),
                .init(key: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 7), value: .init(unsignedIntegerValue: nil, stringValue: nil, objectIndex: 19)),
            ],
            note: nil,
            customMap: nil,
            orderedSet: nil
        )

        entries[14] = noteEntry("Name")
        entries[16] = noteEntry("Status")
        entries[18] = noteEntryWithInternalLink("Roadmap")
        entries[19] = noteEntry("Line 1\nLine 2 | Value")

        return AppleNotesMergeableData(
            entries: entries,
            keys: ["crRows", "crColumns", "cellColumns"],
            types: ["com.apple.notes.ICTable"],
            uuids: uuids
        )
    }

    func uuidReferenceEntry(uuidIndex: UInt64) -> AppleNotesMergeableObjectEntry {
        AppleNotesMergeableObjectEntry(
            registerLatest: nil,
            dictionary: [],
            note: nil,
            customMap: AppleNotesMergeableCustomMap(
                type: 0,
                entries: [
                    .init(
                        key: 0,
                        value: AppleNotesMergeableObjectID(
                            unsignedIntegerValue: uuidIndex,
                            stringValue: nil,
                            objectIndex: nil
                        )
                    ),
                ]
            ),
            orderedSet: nil
        )
    }

    func noteEntry(_ text: String) -> AppleNotesMergeableObjectEntry {
        AppleNotesMergeableObjectEntry(
            registerLatest: nil,
            dictionary: [],
            note: AppleNotesDecodedNote(
                noteText: text,
                attributeRuns: [
                    AppleNotesDecodedAttributeRun(
                        length: (text as NSString).length,
                        paragraphStyle: nil,
                        fontWeight: nil,
                        underlined: false,
                        strikethrough: false,
                        superscript: nil,
                        link: nil,
                        attachmentInfo: nil
                    ),
                ]
            ),
            customMap: nil,
            orderedSet: nil
        )
    }

    func noteEntryWithInternalLink(_ text: String) -> AppleNotesMergeableObjectEntry {
        AppleNotesMergeableObjectEntry(
            registerLatest: nil,
            dictionary: [],
            note: AppleNotesDecodedNote(
                noteText: text,
                attributeRuns: [
                    AppleNotesDecodedAttributeRun(
                        length: (text as NSString).length,
                        paragraphStyle: nil,
                        fontWeight: nil,
                        underlined: false,
                        strikethrough: false,
                        superscript: nil,
                        link: "applenotes:note/target-note",
                        attachmentInfo: nil
                    ),
                ]
            ),
            customMap: nil,
            orderedSet: nil
        )
    }
}
