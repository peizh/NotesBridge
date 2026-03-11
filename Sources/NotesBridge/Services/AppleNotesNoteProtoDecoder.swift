import Foundation
import zlib

struct AppleNotesDecodedNote: Sendable {
    var noteText: String
    var attributeRuns: [AppleNotesDecodedAttributeRun]
}

struct AppleNotesDecodedAttributeRun: Sendable {
    var length: Int
    var paragraphStyle: AppleNotesDecodedParagraphStyle?
    var fontWeight: Int?
    var underlined: Bool
    var strikethrough: Bool
    var superscript: Int?
    var link: String?
    var attachmentInfo: AppleNotesDecodedAttachmentInfo?
}

struct AppleNotesDecodedParagraphStyle: Sendable {
    var styleType: Int?
    var indentAmount: Int
    var blockquote: Bool
    var checklist: AppleNotesDecodedChecklist?
}

struct AppleNotesDecodedChecklist: Sendable {
    var done: Bool
}

struct AppleNotesDecodedAttachmentInfo: Sendable {
    var attachmentIdentifier: String
    var typeUti: String
}

enum AppleNotesAttachmentResolution: Sendable {
    case inlineText(String)
    case attachment(AppleNotesSyncAttachment, isBlock: Bool)
}

struct AppleNotesRenderedNote: Sendable {
    var markdownTemplate: String
    var attachments: [AppleNotesSyncAttachment]
}

private struct AppleNotesDecodedNoteMatch {
    var note: AppleNotesDecodedNote
    var fieldPath: [Int]
}

enum AppleNotesNoteDecodingError: LocalizedError {
    case invalidGzipData
    case invalidProtobuf

    var errorDescription: String? {
        switch self {
        case .invalidGzipData:
            "Apple Notes note data could not be decompressed."
        case .invalidProtobuf:
            "Apple Notes note data could not be decoded."
        }
    }
}

struct AppleNotesNoteProtoDecoder {
    func decodeDocument(from compressedData: Data) throws -> AppleNotesDecodedNote {
        let data = try Gzip.inflate(compressedData)
        let directDocument = try decodeDocumentMessage(from: data)
        if !directDocument.isEmpty {
            return directDocument
        }

        let wrappedDocument = try decodeNoteStoreProtoMessage(from: data)
        if !wrappedDocument.isEmpty {
            return wrappedDocument
        }

        if let recursiveDocument = try searchForDocument(in: data, remainingDepth: 6)?.note,
           !recursiveDocument.isEmpty
        {
            return recursiveDocument
        }

        return directDocument
    }

    private func decodeDocumentMessage(from data: Data) throws -> AppleNotesDecodedNote {
        var reader = ProtobufReader(data: data)
        var decodedNote = AppleNotesDecodedNote(noteText: "", attributeRuns: [])

        while let field = try reader.nextField() {
            switch field.number {
            case 3:
                decodedNote = try decodeNoteMessage(from: try reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return decodedNote
    }

    private func decodeNoteStoreProtoMessage(from data: Data) throws -> AppleNotesDecodedNote {
        var reader = ProtobufReader(data: data)
        var decodedNote = AppleNotesDecodedNote(noteText: "", attributeRuns: [])

        while let field = try reader.nextField() {
            switch field.number {
            case 2:
                decodedNote = try decodeDocumentMessage(from: try reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return decodedNote
    }

    private func searchForDocument(
        in data: Data,
        remainingDepth: Int,
        fieldPath: [Int] = []
    ) throws -> AppleNotesDecodedNoteMatch? {
        guard remainingDepth > 0, !data.isEmpty else {
            return nil
        }

        let directDocument = try decodeDocumentMessage(from: data)
        if !directDocument.isEmpty {
            return AppleNotesDecodedNoteMatch(note: directDocument, fieldPath: fieldPath)
        }

        var reader = ProtobufReader(data: data)
        while let field = try reader.nextField() {
            guard field.wireType == 2 else {
                try reader.skipField(wireType: field.wireType)
                continue
            }

            let nestedData = try reader.readLengthDelimited()
            let nestedPath = fieldPath + [field.number]
            if let nestedMatch = try searchForDocument(
                in: nestedData,
                remainingDepth: remainingDepth - 1,
                fieldPath: nestedPath
            ) {
                return nestedMatch
            }
        }

        let directNote = try decodeNoteMessage(from: data)
        if !directNote.isEmpty {
            return AppleNotesDecodedNoteMatch(note: directNote, fieldPath: fieldPath)
        }

        return nil
    }

    private func decodeNoteMessage(from data: Data) throws -> AppleNotesDecodedNote {
        var reader = ProtobufReader(data: data)
        var noteText = ""
        var attributeRuns: [AppleNotesDecodedAttributeRun] = []

        while let field = try reader.nextField() {
            switch field.number {
            case 2:
                noteText = try reader.readString()
            case 5:
                attributeRuns.append(try decodeAttributeRunMessage(from: try reader.readLengthDelimited()))
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesDecodedNote(noteText: noteText, attributeRuns: attributeRuns)
    }

    private func decodeAttributeRunMessage(from data: Data) throws -> AppleNotesDecodedAttributeRun {
        var reader = ProtobufReader(data: data)
        var run = AppleNotesDecodedAttributeRun(
            length: 0,
            paragraphStyle: nil,
            fontWeight: nil,
            underlined: false,
            strikethrough: false,
            superscript: nil,
            link: nil,
            attachmentInfo: nil
        )

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                run.length = Int(try reader.readInt32())
            case 2:
                run.paragraphStyle = try decodeParagraphStyleMessage(from: try reader.readLengthDelimited())
            case 5:
                run.fontWeight = Int(try reader.readInt32())
            case 6:
                run.underlined = try reader.readInt32() != 0
            case 7:
                run.strikethrough = try reader.readInt32() != 0
            case 8:
                run.superscript = Int(try reader.readInt32())
            case 9:
                run.link = try reader.readString()
            case 12:
                run.attachmentInfo = try decodeAttachmentInfoMessage(from: try reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return run
    }

    private func decodeParagraphStyleMessage(from data: Data) throws -> AppleNotesDecodedParagraphStyle {
        var reader = ProtobufReader(data: data)
        var paragraphStyle = AppleNotesDecodedParagraphStyle(
            styleType: nil,
            indentAmount: 0,
            blockquote: false,
            checklist: nil
        )

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                paragraphStyle.styleType = Int(try reader.readInt32())
            case 4:
                paragraphStyle.indentAmount = Int(try reader.readInt32())
            case 5:
                paragraphStyle.checklist = try decodeChecklistMessage(from: try reader.readLengthDelimited())
            case 8:
                paragraphStyle.blockquote = try reader.readInt32() != 0
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return paragraphStyle
    }

    private func decodeChecklistMessage(from data: Data) throws -> AppleNotesDecodedChecklist {
        var reader = ProtobufReader(data: data)
        var done = false

        while let field = try reader.nextField() {
            switch field.number {
            case 2:
                done = try reader.readInt32() != 0
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesDecodedChecklist(done: done)
    }

    private func decodeAttachmentInfoMessage(from data: Data) throws -> AppleNotesDecodedAttachmentInfo {
        var reader = ProtobufReader(data: data)
        var attachmentIdentifier = ""
        var typeUti = ""

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                attachmentIdentifier = try reader.readString()
            case 2:
                typeUti = try reader.readString()
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesDecodedAttachmentInfo(
            attachmentIdentifier: attachmentIdentifier,
            typeUti: typeUti
        )
    }
}

private extension AppleNotesDecodedNote {
    var isEmpty: Bool {
        noteText.isEmpty && attributeRuns.isEmpty
    }
}

struct AppleNotesMarkdownRenderer {
    func render(
        note: AppleNotesDecodedNote,
        attachmentResolver: (AppleNotesDecodedAttachmentInfo) throws -> AppleNotesAttachmentResolution
    ) throws -> AppleNotesRenderedNote {
        var state = RenderState()
        let noteText = note.noteText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let string = noteText as NSString
        var offset = 0

        for run in note.attributeRuns {
            let fragment = string.safeSubstring(location: offset, length: run.length)
            offset += run.length
            try state.append(
                fragment: fragment,
                run: run,
                attachmentResolver: attachmentResolver
            )
        }

        state.finish()
        return AppleNotesRenderedNote(
            markdownTemplate: state.output.trimmingCharacters(in: .whitespacesAndNewlines),
            attachments: state.attachments
        )
    }
}

private extension AppleNotesMarkdownRenderer {
    struct RenderState {
        var output = ""
        var attachments: [AppleNotesSyncAttachment] = []
        var isAtLineStart = true
        var listNumber = 0
        var listIndent = 0
        var insideMonospacedBlock = false

        mutating func append(
            fragment: String,
            run: AppleNotesDecodedAttributeRun,
            attachmentResolver: (AppleNotesDecodedAttachmentInfo) throws -> AppleNotesAttachmentResolution
        ) throws {
            let styleType = run.paragraphStyle?.styleType ?? AppleNotesStyleType.default.rawValue
            transitionMonospacedBlock(for: styleType)

            if let attachmentInfo = run.attachmentInfo {
                try appendAttachment(attachmentInfo, run: run, attachmentResolver: attachmentResolver)
                return
            }

            for segment in fragment.splitIncludingSeparator("\n") {
                if segment == "\n" {
                    output.append("\n")
                    isAtLineStart = true
                    continue
                }

                transitionMonospacedBlock(for: styleType)
                if insideMonospacedBlock {
                    output.append(segment)
                    isAtLineStart = false
                    continue
                }

                if isAtLineStart {
                    output.append(paragraphPrefix(for: run))
                }

                output.append(formattedText(segment, run: run))
                isAtLineStart = false
            }
        }

        mutating func finish() {
            if insideMonospacedBlock {
                if !output.hasSuffix("\n") {
                    output.append("\n")
                }
                output.append("```")
                insideMonospacedBlock = false
            }
        }

        private mutating func appendAttachment(
            _ attachmentInfo: AppleNotesDecodedAttachmentInfo,
            run: AppleNotesDecodedAttributeRun,
            attachmentResolver: (AppleNotesDecodedAttachmentInfo) throws -> AppleNotesAttachmentResolution
        ) throws {
            switch try attachmentResolver(attachmentInfo) {
            case let .inlineText(text):
                if isAtLineStart && !insideMonospacedBlock {
                    output.append(paragraphPrefix(for: run))
                }
                output.append(text)
                isAtLineStart = false

            case let .attachment(attachment, isBlock):
                attachments.append(attachment)
                let token = "{{attachment:\(attachment.token)}}"

                if isBlock {
                    if !output.isEmpty, !output.hasSuffix("\n") {
                        output.append("\n")
                    }
                    if isAtLineStart && !insideMonospacedBlock {
                        output.append(paragraphPrefix(for: run))
                    }
                    output.append(token)
                    if !output.hasSuffix("\n") {
                        output.append("\n")
                    }
                    isAtLineStart = true
                } else {
                    if isAtLineStart && !insideMonospacedBlock {
                        output.append(paragraphPrefix(for: run))
                    }
                    output.append(token)
                    isAtLineStart = false
                }
            }
        }

        private mutating func transitionMonospacedBlock(for styleType: Int) {
            if styleType == AppleNotesStyleType.monospaced.rawValue {
                guard !insideMonospacedBlock else { return }
                if !output.isEmpty, !output.hasSuffix("\n") {
                    output.append("\n")
                }
                output.append("```\n")
                insideMonospacedBlock = true
                return
            }

            guard insideMonospacedBlock else { return }
            if !output.hasSuffix("\n") {
                output.append("\n")
            }
            output.append("```\n")
            insideMonospacedBlock = false
            isAtLineStart = true
        }

        private mutating func paragraphPrefix(for run: AppleNotesDecodedAttributeRun) -> String {
            let paragraphStyle = run.paragraphStyle
            let styleType = paragraphStyle?.styleType ?? AppleNotesStyleType.default.rawValue
            let indentAmount = max(0, paragraphStyle?.indentAmount ?? 0)
            let indent = String(repeating: "\t", count: indentAmount)
            let prelude = paragraphStyle?.blockquote == true ? "> " : ""

            if listNumber != 0,
               (styleType != AppleNotesStyleType.numberedList.rawValue || listIndent != indentAmount)
            {
                listIndent = indentAmount
                listNumber = 0
            }

            switch styleType {
            case AppleNotesStyleType.title.rawValue:
                return prelude + "# "
            case AppleNotesStyleType.heading.rawValue:
                return prelude + "## "
            case AppleNotesStyleType.subheading.rawValue:
                return prelude + "### "
            case AppleNotesStyleType.dottedList.rawValue, AppleNotesStyleType.dashedList.rawValue:
                return prelude + indent + "- "
            case AppleNotesStyleType.numberedList.rawValue:
                listNumber += 1
                return prelude + indent + "\(listNumber). "
            case AppleNotesStyleType.checkbox.rawValue:
                let checked = paragraphStyle?.checklist?.done == true ? "[x]" : "[ ]"
                return prelude + indent + "- \(checked) "
            default:
                return prelude
            }
        }

        private func formattedText(_ fragment: String, run: AppleNotesDecodedAttributeRun) -> String {
            guard fragment.contains(where: { !$0.isWhitespace }) else {
                return fragment
            }

            var formatted = fragment.replacingOccurrences(of: "[", with: "\\[")
            formatted = formatted.replacingOccurrences(of: "]", with: "\\]")

            switch run.fontWeight {
            case 1:
                formatted = "**\(formatted)**"
            case 2:
                formatted = "*\(formatted)*"
            case 3:
                formatted = "***\(formatted)***"
            default:
                break
            }

            if run.strikethrough {
                formatted = "~~\(formatted)~~"
            }

            if let link = run.link, link != fragment {
                if link.lowercased().hasPrefix("applenotes:note/") {
                    formatted = "[\(formatted)](\(link))"
                } else {
                    formatted = "[\(formatted)](\(link))"
                }
            }

            return formatted
        }
    }
}

private enum AppleNotesStyleType: Int {
    case `default` = -1
    case title = 0
    case heading = 1
    case subheading = 2
    case monospaced = 4
    case dottedList = 100
    case dashedList = 101
    case numberedList = 102
    case checkbox = 103
}

private struct ProtobufField {
    var number: Int
    var wireType: Int
}

private struct ProtobufReader {
    private let data: Data
    private var index = 0

    init(data: Data) {
        self.data = data
    }

    mutating func nextField() throws -> ProtobufField? {
        guard index < data.count else { return nil }
        let key = try readVarint()
        return ProtobufField(number: Int(key >> 3), wireType: Int(key & 0x07))
    }

    mutating func readLengthDelimited() throws -> Data {
        let length = Int(try readVarint())
        guard length >= 0, index + length <= data.count else {
            throw AppleNotesNoteDecodingError.invalidProtobuf
        }

        defer { index += length }
        return data.subdata(in: index ..< index + length)
    }

    mutating func readString() throws -> String {
        let bytes = try readLengthDelimited()
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw AppleNotesNoteDecodingError.invalidProtobuf
        }

        return string
    }

    mutating func readInt32() throws -> Int32 {
        let value = try readVarint()
        return Int32(bitPattern: UInt32(truncatingIfNeeded: value))
    }

    mutating func skipField(wireType: Int) throws {
        switch wireType {
        case 0:
            _ = try readVarint()
        case 1:
            guard index + 8 <= data.count else { throw AppleNotesNoteDecodingError.invalidProtobuf }
            index += 8
        case 2:
            _ = try readLengthDelimited()
        case 5:
            guard index + 4 <= data.count else { throw AppleNotesNoteDecodingError.invalidProtobuf }
            index += 4
        default:
            throw AppleNotesNoteDecodingError.invalidProtobuf
        }
    }

    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while index < data.count {
            let byte = data[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }

            shift += 7
            if shift >= 64 {
                break
            }
        }

        throw AppleNotesNoteDecodingError.invalidProtobuf
    }
}

private enum Gzip {
    static func inflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        var stream = z_stream()
        let status = inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else {
            throw AppleNotesNoteDecodingError.invalidGzipData
        }

        defer {
            inflateEnd(&stream)
        }

        return try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw AppleNotesNoteDecodingError.invalidGzipData
            }

            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = UInt32(data.count)

            var output = Data()
            let chunkSize = 16_384

            repeat {
                var chunk = [UInt8](repeating: 0, count: chunkSize)
                let outputChunkCount = chunk.count
                let inflateStatus: Int32 = try chunk.withUnsafeMutableBytes { buffer in
                    guard let baseAddress = buffer.baseAddress else {
                        throw AppleNotesNoteDecodingError.invalidGzipData
                    }

                    stream.next_out = baseAddress.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = UInt32(outputChunkCount)
                    let status = zlib.inflate(&stream, Z_NO_FLUSH)
                    if status != Z_OK && status != Z_STREAM_END {
                        throw AppleNotesNoteDecodingError.invalidGzipData
                    }
                    return status
                }

                let produced = outputChunkCount - Int(stream.avail_out)
                output.append(contentsOf: chunk.prefix(produced))

                if inflateStatus == Z_STREAM_END {
                    return output
                }
            } while stream.avail_out == 0

            return output
        }
    }
}

private extension NSString {
    func safeSubstring(location: Int, length: Int) -> String {
        guard location < self.length else { return "" }
        let resolvedLength = max(0, min(length, self.length - location))
        return substring(with: NSRange(location: location, length: resolvedLength))
    }
}

private extension String {
    func splitIncludingSeparator(_ separator: Character) -> [String] {
        var pieces: [String] = []
        var current = ""

        for character in self {
            if character == separator {
                if !current.isEmpty {
                    pieces.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                pieces.append(String(character))
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            pieces.append(current)
        }

        return pieces
    }
}
