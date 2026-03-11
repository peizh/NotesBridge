import Foundation

struct AppleNotesMergeableDataProtoDecoder {
    private let noteDecoder = AppleNotesNoteProtoDecoder()

    func decode(from compressedData: Data) throws -> AppleNotesMergeableData {
        let data = try Gzip.inflate(compressedData)
        var reader = ProtobufReader(data: data)

        while let field = try reader.nextField() {
            switch field.number {
            case 2:
                return try decodeMergeableDataObject(from: reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        throw AppleNotesNoteDecodingError.invalidProtobuf
    }

    private func decodeMergeableDataObject(from data: Data) throws -> AppleNotesMergeableData {
        var reader = ProtobufReader(data: data)

        while let field = try reader.nextField() {
            switch field.number {
            case 3:
                return try decodeMergeableDataObjectData(from: reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        throw AppleNotesNoteDecodingError.invalidProtobuf
    }

    private func decodeMergeableDataObjectData(from data: Data) throws -> AppleNotesMergeableData {
        var reader = ProtobufReader(data: data)
        var entries: [AppleNotesMergeableObjectEntry] = []
        var keys: [String] = []
        var types: [String] = []
        var uuids: [String] = []

        while let field = try reader.nextField() {
            switch field.number {
            case 3:
                entries.append(try decodeMergeableDataObjectEntry(from: reader.readLengthDelimited()))
            case 4:
                keys.append(try reader.readString())
            case 5:
                types.append(try reader.readString())
            case 6:
                uuids.append(try reader.readLengthDelimited().hexString)
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesMergeableData(entries: entries, keys: keys, types: types, uuids: uuids)
    }

    private func decodeMergeableDataObjectEntry(from data: Data) throws -> AppleNotesMergeableObjectEntry {
        var reader = ProtobufReader(data: data)
        var registerLatest: AppleNotesMergeableObjectID?
        var dictionary: [AppleNotesMergeableDictionaryElement] = []
        var note: AppleNotesDecodedNote?
        var customMap: AppleNotesMergeableCustomMap?
        var orderedSet: AppleNotesMergeableOrderedSet?

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                registerLatest = try decodeRegisterLatest(from: reader.readLengthDelimited())
            case 6:
                dictionary = try decodeDictionary(from: reader.readLengthDelimited())
            case 10:
                note = try noteDecoder.decodeNoteMessage(from: reader.readLengthDelimited())
            case 13:
                customMap = try decodeCustomMap(from: reader.readLengthDelimited())
            case 16:
                orderedSet = try decodeOrderedSet(from: reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesMergeableObjectEntry(
            registerLatest: registerLatest,
            dictionary: dictionary,
            note: note,
            customMap: customMap,
            orderedSet: orderedSet
        )
    }

    private func decodeRegisterLatest(from data: Data) throws -> AppleNotesMergeableObjectID? {
        var reader = ProtobufReader(data: data)

        while let field = try reader.nextField() {
            switch field.number {
            case 2:
                return try decodeObjectID(from: reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return nil
    }

    private func decodeDictionary(from data: Data) throws -> [AppleNotesMergeableDictionaryElement] {
        var reader = ProtobufReader(data: data)
        var elements: [AppleNotesMergeableDictionaryElement] = []

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                elements.append(try decodeDictionaryElement(from: reader.readLengthDelimited()))
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return elements
    }

    private func decodeDictionaryElement(from data: Data) throws -> AppleNotesMergeableDictionaryElement {
        var reader = ProtobufReader(data: data)
        var key: AppleNotesMergeableObjectID?
        var value: AppleNotesMergeableObjectID?

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                key = try decodeObjectID(from: reader.readLengthDelimited())
            case 2:
                value = try decodeObjectID(from: reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesMergeableDictionaryElement(key: key, value: value)
    }

    private func decodeObjectID(from data: Data) throws -> AppleNotesMergeableObjectID {
        var reader = ProtobufReader(data: data)
        var unsignedIntegerValue: UInt64?
        var stringValue: String?
        var objectIndex: Int?

        while let field = try reader.nextField() {
            switch field.number {
            case 2:
                unsignedIntegerValue = try reader.readVarint()
            case 4:
                stringValue = try reader.readString()
            case 6:
                objectIndex = Int(try reader.readInt32())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesMergeableObjectID(
            unsignedIntegerValue: unsignedIntegerValue,
            stringValue: stringValue,
            objectIndex: objectIndex
        )
    }

    private func decodeCustomMap(from data: Data) throws -> AppleNotesMergeableCustomMap {
        var reader = ProtobufReader(data: data)
        var type = 0
        var entries: [AppleNotesMergeableMapEntry] = []

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                type = Int(try reader.readInt32())
            case 3:
                entries.append(try decodeMapEntry(from: reader.readLengthDelimited()))
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesMergeableCustomMap(type: type, entries: entries)
    }

    private func decodeMapEntry(from data: Data) throws -> AppleNotesMergeableMapEntry {
        var reader = ProtobufReader(data: data)
        var key = 0
        var value = AppleNotesMergeableObjectID()

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                key = Int(try reader.readInt32())
            case 2:
                value = try decodeObjectID(from: reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesMergeableMapEntry(key: key, value: value)
    }

    private func decodeOrderedSet(from data: Data) throws -> AppleNotesMergeableOrderedSet {
        var reader = ProtobufReader(data: data)
        var ordering = AppleNotesMergeableOrderedSetOrdering()

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                ordering = try decodeOrderedSetOrdering(from: reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesMergeableOrderedSet(ordering: ordering)
    }

    private func decodeOrderedSetOrdering(from data: Data) throws -> AppleNotesMergeableOrderedSetOrdering {
        var reader = ProtobufReader(data: data)
        var attachments: [AppleNotesMergeableOrderedSetAttachment] = []
        var contents: [AppleNotesMergeableDictionaryElement] = []

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                attachments = try decodeOrderedSetOrderingArray(from: reader.readLengthDelimited())
            case 2:
                contents = try decodeDictionary(from: reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesMergeableOrderedSetOrdering(attachments: attachments, contents: contents)
    }

    private func decodeOrderedSetOrderingArray(from data: Data) throws -> [AppleNotesMergeableOrderedSetAttachment] {
        var reader = ProtobufReader(data: data)
        var attachments: [AppleNotesMergeableOrderedSetAttachment] = []

        while let field = try reader.nextField() {
            switch field.number {
            case 2:
                attachments.append(try decodeOrderedSetAttachment(from: reader.readLengthDelimited()))
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return attachments
    }

    private func decodeOrderedSetAttachment(from data: Data) throws -> AppleNotesMergeableOrderedSetAttachment {
        var reader = ProtobufReader(data: data)
        var index = 0
        var uuid = ""

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                index = Int(try reader.readInt32())
            case 2:
                uuid = try reader.readLengthDelimited().hexString
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesMergeableOrderedSetAttachment(index: index, uuid: uuid)
    }
}

struct AppleNotesMergeableData {
    var entries: [AppleNotesMergeableObjectEntry]
    var keys: [String]
    var types: [String]
    var uuids: [String]
}

struct AppleNotesMergeableObjectEntry {
    var registerLatest: AppleNotesMergeableObjectID?
    var dictionary: [AppleNotesMergeableDictionaryElement]
    var note: AppleNotesDecodedNote?
    var customMap: AppleNotesMergeableCustomMap?
    var orderedSet: AppleNotesMergeableOrderedSet?
}

struct AppleNotesMergeableObjectID {
    var unsignedIntegerValue: UInt64?
    var stringValue: String?
    var objectIndex: Int?
}

struct AppleNotesMergeableDictionaryElement {
    var key: AppleNotesMergeableObjectID?
    var value: AppleNotesMergeableObjectID?
}

struct AppleNotesMergeableCustomMap {
    var type: Int
    var entries: [AppleNotesMergeableMapEntry]
}

struct AppleNotesMergeableMapEntry {
    var key: Int
    var value: AppleNotesMergeableObjectID
}

struct AppleNotesMergeableOrderedSet {
    var ordering: AppleNotesMergeableOrderedSetOrdering
}

struct AppleNotesMergeableOrderedSetOrdering {
    var attachments: [AppleNotesMergeableOrderedSetAttachment] = []
    var contents: [AppleNotesMergeableDictionaryElement] = []
}

struct AppleNotesMergeableOrderedSetAttachment {
    var index: Int
    var uuid: String
}

struct AppleNotesTableConverter {
    let mergeableData: AppleNotesMergeableData
    let renderer: AppleNotesMarkdownRenderer

    func renderFragment(
        attachmentResolver: (AppleNotesDecodedAttachmentInfo) throws -> AppleNotesAttachmentResolution
    ) throws -> AppleNotesRenderedFragment? {
        guard let table = try parseTable(attachmentResolver: attachmentResolver) else {
            return nil
        }
        var markdown = "\n"
        for (index, row) in table.rows.enumerated() {
            markdown.append("| \(row.joined(separator: " | ")) |\n")
            if index == 0 {
                markdown.append("|\(Array(repeating: " -- ", count: row.count).joined(separator: "|"))|\n")
            }
        }
        markdown.append("\n")

        return AppleNotesRenderedFragment(
            markdownTemplate: markdown,
            internalLinks: table.internalLinks,
            attachments: table.attachments,
            isBlock: true,
            diagnostics: table.diagnostics
        )
    }

    private func parseTable(
        attachmentResolver: (AppleNotesDecodedAttachmentInfo) throws -> AppleNotesAttachmentResolution
    ) throws -> AppleNotesParsedTable? {
        guard let root = mergeableData.entries.first(where: {
            guard let customMap = $0.customMap else { return false }
            guard customMap.type >= 0, customMap.type < mergeableData.types.count else { return false }
            let typeName = mergeableData.types[customMap.type]
            return typeName == "com.apple.notes.ICTable" || typeName == "com.apple.notes.CRTable"
        }) else {
            return nil
        }

        var rowLocations: [String: Int] = [:]
        var rowCount = 0
        var columnLocations: [String: Int] = [:]
        var columnCount = 0
        var cellData: AppleNotesMergeableObjectEntry?

        for entry in root.customMap?.entries ?? [] {
            guard entry.key >= 0, entry.key < mergeableData.keys.count else { continue }
            let keyName = mergeableData.keys[entry.key]
            guard let objectIndex = entry.value.objectIndex,
                  mergeableData.entries.indices.contains(objectIndex)
            else {
                continue
            }
            let object = mergeableData.entries[objectIndex]

            switch keyName {
            case "crRows":
                (rowLocations, rowCount) = findLocations(object)
            case "crColumns":
                (columnLocations, columnCount) = findLocations(object)
            case "cellColumns":
                cellData = object
            default:
                continue
            }
        }

        guard let cellData, rowCount > 0, columnCount > 0 else {
            return nil
        }

        var result = Array(
            repeating: Array(repeating: "", count: columnCount),
            count: rowCount
        )
        var internalLinks: [AppleNotesSyncInternalLink] = []
        var attachments: [AppleNotesSyncAttachment] = []
        var diagnostics = AppleNotesRenderDiagnostics()

        for column in cellData.dictionary {
            guard let columnKey = column.key,
                  let columnValue = column.value,
                  let columnUUID = targetUUID(for: columnKey),
                  let columnLocation = columnLocations[columnUUID],
                  let rowObjectIndex = columnValue.objectIndex,
                  mergeableData.entries.indices.contains(rowObjectIndex)
            else {
                continue
            }

            let rowData = mergeableData.entries[rowObjectIndex]
            for row in rowData.dictionary {
                guard let rowKey = row.key,
                      let rowValue = row.value,
                      let rowUUID = targetUUID(for: rowKey),
                      let rowLocation = rowLocations[rowUUID],
                      result.indices.contains(rowLocation),
                      result[rowLocation].indices.contains(columnLocation),
                      let contentIndex = rowValue.objectIndex,
                      mergeableData.entries.indices.contains(contentIndex),
                      let note = mergeableData.entries[contentIndex].note
                else {
                    continue
                }

                let rendered = try renderer.render(
                    note: note,
                    options: .tableCell,
                    attachmentResolver: attachmentResolver
                )
                let uniqued = uniquedCellRender(
                    rendered,
                    nextInternalLinkIndex: internalLinks.count + 1,
                    nextAttachmentIndex: attachments.count + 1
                )
                internalLinks.append(contentsOf: uniqued.internalLinks)
                attachments.append(contentsOf: uniqued.attachments)
                diagnostics.merge(uniqued.diagnostics)
                result[rowLocation][columnLocation] = uniqued.markdownTemplate
            }
        }

        return AppleNotesParsedTable(
            rows: result,
            internalLinks: internalLinks,
            attachments: attachments,
            diagnostics: diagnostics
        )
    }

    private func uniquedCellRender(
        _ rendered: AppleNotesRenderedNote,
        nextInternalLinkIndex: Int,
        nextAttachmentIndex: Int
    ) -> AppleNotesRenderedNote {
        var markdownTemplate = rendered.markdownTemplate
        let internalLinks = rendered.internalLinks.enumerated().map { offset, link in
            let newToken = "table-note-link-\(nextInternalLinkIndex + offset)"
            markdownTemplate = markdownTemplate.replacingOccurrences(
                of: "{{note-link:\(link.token)}}",
                with: "{{note-link:\(newToken)}}"
            )
            return AppleNotesSyncInternalLink(
                token: newToken,
                targetSourceIdentifier: link.targetSourceIdentifier,
                displayText: link.displayText
            )
        }
        let attachments = rendered.attachments.enumerated().map { offset, attachment in
            let newToken = "table-attachment-\(nextAttachmentIndex + offset)"
            markdownTemplate = markdownTemplate.replacingOccurrences(
                of: "{{attachment:\(attachment.token)}}",
                with: "{{attachment:\(newToken)}}"
            )
            return AppleNotesSyncAttachment(
                token: newToken,
                logicalIdentifier: attachment.logicalIdentifier,
                sourceURL: attachment.sourceURL,
                preferredFilename: attachment.preferredFilename,
                renderStyle: attachment.renderStyle,
                modifiedAt: attachment.modifiedAt,
                fileSize: attachment.fileSize
            )
        }

        return AppleNotesRenderedNote(
            markdownTemplate: markdownTemplate,
            internalLinks: internalLinks,
            attachments: attachments,
            diagnostics: rendered.diagnostics
        )
    }

    private func findLocations(_ object: AppleNotesMergeableObjectEntry) -> ([String: Int], Int) {
        let ordering = object.orderedSet?.ordering.attachments
            .sorted { $0.index < $1.index }
            .map(\.uuid) ?? []
        var indices: [String: Int] = [:]

        for element in object.orderedSet?.ordering.contents ?? [] {
            guard let key = element.key,
                  let value = element.value,
                  let keyUUID = targetUUID(for: key),
                  let valueUUID = targetUUID(for: value),
                  let location = ordering.firstIndex(of: keyUUID)
            else {
                continue
            }
            indices[valueUUID] = location
        }

        return (indices, ordering.count)
    }

    private func targetUUID(for objectID: AppleNotesMergeableObjectID) -> String? {
        guard let objectIndex = objectID.objectIndex,
              mergeableData.entries.indices.contains(objectIndex),
              let customMap = mergeableData.entries[objectIndex].customMap,
              let firstValue = customMap.entries.first?.value.unsignedIntegerValue,
              mergeableData.uuids.indices.contains(Int(firstValue))
        else {
            return nil
        }

        return mergeableData.uuids[Int(firstValue)]
    }
}

private struct AppleNotesParsedTable {
    var rows: [[String]]
    var internalLinks: [AppleNotesSyncInternalLink]
    var attachments: [AppleNotesSyncAttachment]
    var diagnostics: AppleNotesRenderDiagnostics
}

struct AppleNotesScanGalleryConverter {
    let mergeableData: AppleNotesMergeableData

    func pageAttachmentIdentifiers() -> [String] {
        mergeableData.entries.compactMap { entry in
            entry.customMap?.entries.first?.value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
