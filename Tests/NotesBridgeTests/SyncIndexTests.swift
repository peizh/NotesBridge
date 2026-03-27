import Foundation
import Testing
@testable import NotesBridge

struct SyncIndexTests {
    @Test
    func defaultsPathAliasesToEmptyWhenDecodingOlderPayloads() throws {
        let json = """
        {
          "records": {},
          "lastSyncMode": "incremental"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SyncIndex.self, from: json)

        #expect(decoded.pathAliases.isEmpty)
    }

    @Test
    func roundTripsPathAliasesThroughCodable() throws {
        let index = SyncIndex(
            records: [:],
            pathAliases: [
                "apple-notes-db://note/42": "Apple Notes/Inbox/Roadmap.md",
                "x-coredata://legacy/ICNote/p42": "Apple Notes/Inbox/Roadmap.md",
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(index)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SyncIndex.self, from: data)

        #expect(decoded.pathAliases == index.pathAliases)
    }
}
