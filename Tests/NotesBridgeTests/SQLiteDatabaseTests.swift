import Testing
@testable import NotesBridge

struct SQLiteDatabaseTests {
    @Test
    func nullBooleanColumnsDefaultToFalse() {
        let row = SQLiteRow(values: [
            "passwordProtected": .null,
            "shared": .int(1),
        ])

        #expect(row.bool("passwordProtected") == false)
        #expect(row.bool("shared") == true)
    }
}
