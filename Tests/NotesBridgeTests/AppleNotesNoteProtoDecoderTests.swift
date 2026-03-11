import Testing
import zlib
@testable import NotesBridge

struct AppleNotesNoteProtoDecoderTests {
    private let decoder = AppleNotesNoteProtoDecoder()

    @Test
    func decodesDirectDocumentPayload() throws {
        let noteText = "Hello from Apple Notes"
        let compressedPayload = try gzip(documentPayload(noteText: noteText))

        let decoded = try decoder.decodeDocument(from: compressedPayload)

        #expect(decoded.noteText == noteText)
        #expect(decoded.attributeRuns.count == 1)
        #expect(decoded.attributeRuns.first?.length == (noteText as NSString).length)
    }

    @Test
    func decodesDocumentWrappedInsideUnknownOuterMessage() throws {
        let noteText = "Wrapped note body"
        let document = documentPayload(noteText: noteText)
        let noteStoreProto = message(fieldNumber: 2, payload: document)
        let outerMessage = message(fieldNumber: 7, payload: noteStoreProto)
        let compressedPayload = try gzip(outerMessage)

        let decoded = try decoder.decodeDocument(from: compressedPayload)

        #expect(decoded.noteText == noteText)
        #expect(decoded.attributeRuns.count == 1)
        #expect(decoded.attributeRuns.first?.length == (noteText as NSString).length)
    }

    private func documentPayload(noteText: String) -> Data {
        let run = attributeRunPayload(length: (noteText as NSString).length)
        let note = message(
            fields: [
                (2, Data(noteText.utf8)),
                (5, run),
            ]
        )

        var document = Data()
        document.append(varintField(number: 2, value: 1))
        document.append(lengthDelimitedField(number: 3, payload: note))
        return document
    }

    private func attributeRunPayload(length: Int) -> Data {
        var payload = Data()
        payload.append(varintField(number: 1, value: UInt64(length)))
        return payload
    }

    private func message(fieldNumber: Int, payload: Data) -> Data {
        message(fields: [(fieldNumber, payload)])
    }

    private func message(fields: [(Int, Data)]) -> Data {
        var data = Data()
        for (fieldNumber, payload) in fields {
            data.append(lengthDelimitedField(number: fieldNumber, payload: payload))
        }
        return data
    }

    private func lengthDelimitedField(number: Int, payload: Data) -> Data {
        var data = Data()
        data.append(varint(UInt64((number << 3) | 2)))
        data.append(varint(UInt64(payload.count)))
        data.append(payload)
        return data
    }

    private func varintField(number: Int, value: UInt64) -> Data {
        var data = Data()
        data.append(varint(UInt64(number << 3)))
        data.append(varint(value))
        return data
    }

    private func varint(_ value: UInt64) -> Data {
        var remaining = value
        var data = Data()

        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 {
                byte |= 0x80
            }
            data.append(byte)
        } while remaining != 0

        return data
    }

    private func gzip(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        var stream = z_stream()
        let windowBits = 15 + 16
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            Int32(windowBits),
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw GzipTestError.deflateFailed
        }

        defer {
            deflateEnd(&stream)
        }

        return try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw GzipTestError.deflateFailed
            }

            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = UInt32(data.count)

            var output = Data()
            let chunkSize = 16_384

            repeat {
                var chunk = [UInt8](repeating: 0, count: chunkSize)
                let status = try chunk.withUnsafeMutableBytes { buffer -> Int32 in
                    guard let chunkAddress = buffer.baseAddress else {
                        throw GzipTestError.deflateFailed
                    }

                    stream.next_out = chunkAddress.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = UInt32(chunkSize)
                    return deflate(&stream, stream.avail_in == 0 ? Z_FINISH : Z_NO_FLUSH)
                }

                let produced = chunkSize - Int(stream.avail_out)
                output.append(contentsOf: chunk.prefix(produced))

                if status == Z_STREAM_END {
                    return output
                }

                guard status == Z_OK else {
                    throw GzipTestError.deflateFailed
                }
            } while true
        }
    }
}

private enum GzipTestError: Error {
    case deflateFailed
}
