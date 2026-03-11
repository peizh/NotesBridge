import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteDatabaseError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(message),
             let .prepareFailed(message),
             let .stepFailed(message),
             let .bindFailed(message):
            message
        }
    }
}

enum SQLiteBinding: Sendable {
    case int(Int64)
    case double(Double)
    case text(String)
    case null
}

enum SQLiteValue: Sendable {
    case int(Int64)
    case double(Double)
    case text(String)
    case data(Data)
    case null
}

struct SQLiteRow: Sendable {
    private var values: [String: SQLiteValue]

    init(values: [String: SQLiteValue]) {
        self.values = values
    }

    subscript(_ key: String) -> SQLiteValue? {
        values[key]
    }

    func int(_ key: String) -> Int64? {
        switch values[key] {
        case let .int(value):
            value
        case let .double(value):
            Int64(value)
        case let .text(value):
            Int64(value)
        default:
            nil
        }
    }

    func double(_ key: String) -> Double? {
        switch values[key] {
        case let .double(value):
            value
        case let .int(value):
            Double(value)
        case let .text(value):
            Double(value)
        default:
            nil
        }
    }

    func string(_ key: String) -> String? {
        switch values[key] {
        case let .text(value):
            value
        case let .int(value):
            String(value)
        case let .double(value):
            String(value)
        default:
            nil
        }
    }

    func bool(_ key: String) -> Bool {
        switch values[key] {
        case let .int(value):
            value != 0
        case let .double(value):
            value != 0
        case let .text(value):
            (Int64(value) ?? 0) != 0
        default:
            false
        }
    }

    func data(_ key: String) -> Data? {
        switch values[key] {
        case let .data(value):
            value
        default:
            nil
        }
    }
}

final class SQLiteDatabase {
    private let handle: OpaquePointer

    init(url: URL) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        if sqlite3_open_v2(url.path, &database, flags, nil) != SQLITE_OK || database == nil {
            let message = database.flatMap { sqlite3_errmsg($0).flatMap { String(cString: $0) } } ?? "Could not open SQLite database."
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteDatabaseError.openFailed(message)
        }

        self.handle = database!
    }

    deinit {
        sqlite3_close(handle)
    }

    func rows(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement)

        var rows: [SQLiteRow] = []
        while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                rows.append(makeRow(from: statement))
            case SQLITE_DONE:
                return rows
            default:
                throw SQLiteDatabaseError.stepFailed(lastErrorMessage())
            }
        }
    }

    func row(_ sql: String, bindings: [SQLiteBinding] = []) throws -> SQLiteRow? {
        try rows(sql, bindings: bindings).first
    }

    func columnNames(in tableName: String) throws -> Set<String> {
        let rows = try rows("PRAGMA table_info(\(tableName.sqlIdentifier));")
        return Set(rows.compactMap { $0.string("name") })
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK || statement == nil {
            throw SQLiteDatabaseError.prepareFailed(lastErrorMessage())
        }

        return statement!
    }

    private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer) throws {
        for (index, binding) in bindings.enumerated() {
            let parameterIndex = Int32(index + 1)
            let status: Int32

            switch binding {
            case let .int(value):
                status = sqlite3_bind_int64(statement, parameterIndex, value)
            case let .double(value):
                status = sqlite3_bind_double(statement, parameterIndex, value)
            case let .text(value):
                status = sqlite3_bind_text(statement, parameterIndex, value, -1, SQLITE_TRANSIENT)
            case .null:
                status = sqlite3_bind_null(statement, parameterIndex)
            }

            guard status == SQLITE_OK else {
                throw SQLiteDatabaseError.bindFailed(lastErrorMessage())
            }
        }
    }

    private func makeRow(from statement: OpaquePointer) -> SQLiteRow {
        var values: [String: SQLiteValue] = [:]
        let columnCount = sqlite3_column_count(statement)

        for index in 0 ..< columnCount {
            let name = String(cString: sqlite3_column_name(statement, index))
            let type = sqlite3_column_type(statement, index)

            switch type {
            case SQLITE_INTEGER:
                values[name] = .int(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT:
                values[name] = .double(sqlite3_column_double(statement, index))
            case SQLITE_TEXT:
                values[name] = .text(String(cString: sqlite3_column_text(statement, index)))
            case SQLITE_BLOB:
                let count = Int(sqlite3_column_bytes(statement, index))
                if let pointer = sqlite3_column_blob(statement, index) {
                    values[name] = .data(Data(bytes: pointer, count: count))
                } else {
                    values[name] = .data(Data())
                }
            default:
                values[name] = .null
            }
        }

        return SQLiteRow(values: values)
    }

    private func lastErrorMessage() -> String {
        sqlite3_errmsg(handle).map(String.init(cString:)) ?? "SQLite query failed."
    }
}

private extension String {
    var sqlIdentifier: String {
        "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
