import Foundation

protocol AppleNotesClient: Sendable {
    func fetchFolders() throws -> [AppleNotesFolder]
    func fetchNoteSummaries(inFolderID folderID: String) throws -> [AppleNoteSummary]
    func fetchDocument(id: String) throws -> AppleNoteDocument
    func updateNote(id: String, htmlBody: String) throws
}

enum AppleNotesError: LocalizedError {
    case noteNotFound(String)
    case lockedNote(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .noteNotFound(id):
            "Could not find Apple Note \(id)."
        case let .lockedNote(title):
            "\(title) is locked in Apple Notes."
        case .invalidResponse:
            "Apple Notes returned an invalid response."
        }
    }
}

struct AppleNotesScriptClient: AppleNotesClient {
    private let runner: ProcessRunner
    private let recordSeparator = "\u{001E}"
    private let fieldSeparator = "\u{001F}"

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    func fetchFolders() throws -> [AppleNotesFolder] {
        let script = """
        set fieldSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        set previousDelimiters to AppleScript's text item delimiters

        tell application "Notes"
          set payload to {}

          repeat with targetFolder in folders
            set accountName to ""
            try
              set accountName to name of container of targetFolder as text
            end try

            set end of payload to ((id of targetFolder as text) & fieldSeparator & (name of targetFolder as text) & fieldSeparator & accountName & fieldSeparator & ((count of notes of targetFolder) as text))
          end repeat
        end tell

        set AppleScript's text item delimiters to recordSeparator
        set outputText to payload as text
        set AppleScript's text item delimiters to previousDelimiters
        return outputText
        """

        return try parseRecords(from: runAppleScript(script)).map { fields in
            AppleNotesFolder(
                id: fields[safe: 0] ?? "",
                name: fields[safe: 1] ?? "",
                accountName: normalizedOptionalText(fields[safe: 2]),
                noteCount: Int(fields[safe: 3] ?? "") ?? 0
            )
        }
    }

    func fetchNoteSummaries(inFolderID folderID: String) throws -> [AppleNoteSummary] {
        let script = """
        on padNumber(valueNumber)
          if valueNumber < 10 then
            return "0" & (valueNumber as text)
          end if
          return valueNumber as text
        end padNumber

        on localISOText(targetDate)
          if targetDate is missing value then
            return ""
          end if

          return ((year of targetDate as integer) as text) & "-" & my padNumber(month of targetDate as integer) & "-" & my padNumber(day of targetDate) & "T" & my padNumber(hours of targetDate) & ":" & my padNumber(minutes of targetDate) & ":" & my padNumber(seconds of targetDate)
        end localISOText

        set fieldSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        set previousDelimiters to AppleScript's text item delimiters

        tell application "Notes"
          tell folder id \(appleScriptStringLiteral(folderID))
            set folderName to name as text
            set idsList to id of notes
            set namesList to name of notes
            set createdList to creation date of notes
            set updatedList to modification date of notes
            set sharedList to shared of notes
            set lockedList to password protected of notes
          end tell

          if class of idsList is not list then set idsList to {idsList}
          if class of namesList is not list then set namesList to {namesList}
          if class of createdList is not list then set createdList to {createdList}
          if class of updatedList is not list then set updatedList to {updatedList}
          if class of sharedList is not list then set sharedList to {sharedList}
          if class of lockedList is not list then set lockedList to {lockedList}

          set payload to {}
          repeat with indexValue from 1 to count of idsList
            set end of payload to ((item indexValue of idsList as text) & fieldSeparator & folderName & fieldSeparator & (item indexValue of namesList as text) & fieldSeparator & my localISOText(item indexValue of createdList) & fieldSeparator & my localISOText(item indexValue of updatedList) & fieldSeparator & (item indexValue of sharedList as text) & fieldSeparator & (item indexValue of lockedList as text))
          end repeat
        end tell

        set AppleScript's text item delimiters to recordSeparator
        set outputText to payload as text
        set AppleScript's text item delimiters to previousDelimiters
        return outputText
        """

        return try parseRecords(from: runAppleScript(script)).map { fields in
            AppleNoteSummary(
                id: fields[safe: 0] ?? "",
                name: fields[safe: 2] ?? "",
                folder: fields[safe: 1] ?? "Notes",
                createdAt: parseAppleScriptDate(fields[safe: 3]),
                updatedAt: parseAppleScriptDate(fields[safe: 4]),
                shared: parseBool(fields[safe: 5]),
                passwordProtected: parseBool(fields[safe: 6])
            )
        }
    }

    func fetchDocument(id: String) throws -> AppleNoteDocument {
        let script = """
        function safeString(value) {
          return value === null || value === undefined ? "" : String(value);
        }

        function isoString(value) {
          return value ? (new Date(value)).toISOString() : null;
        }

        const noteID = \(javaScriptStringLiteral(id));
        const Notes = Application("Notes");
        const note = Notes.notes().find((candidate) => candidate.id() === noteID);

        if (!note) {
          throw new Error("NOTE_NOT_FOUND");
        }

        if (Boolean(note.passwordProtected())) {
          throw new Error("LOCKED_NOTE");
        }

        let folderName = "Notes";
        try {
          const container = note.container();
          if (container) {
            folderName = safeString(container.name());
          }
        } catch (error) {}

        JSON.stringify({
          id: safeString(note.id()),
          name: safeString(note.name()),
          folder: folderName,
          createdAt: isoString(note.creationDate()),
          updatedAt: isoString(note.modificationDate()),
          shared: Boolean(note.shared()),
          passwordProtected: Boolean(note.passwordProtected()),
          plaintext: safeString(note.plaintext()),
          htmlBody: safeString(note.body())
        });
        """

        do {
            return try decodeJSON(AppleNoteDocument.self, from: runJXA(script))
        } catch let error as ProcessRunnerError {
            let message = error.localizedDescription
            if message.contains("LOCKED_NOTE") {
                throw AppleNotesError.lockedNote(id)
            }
            if message.contains("NOTE_NOT_FOUND") {
                throw AppleNotesError.noteNotFound(id)
            }
            throw error
        }
    }

    func updateNote(id: String, htmlBody: String) throws {
        let script = """
        const noteID = \(javaScriptStringLiteral(id));
        const newBody = \(javaScriptStringLiteral(htmlBody));
        const Notes = Application("Notes");
        const note = Notes.notes().find((candidate) => candidate.id() === noteID);

        if (!note) {
          throw new Error("NOTE_NOT_FOUND");
        }

        note.body = newBody;
        JSON.stringify({ success: true });
        """

        _ = try runJXA(script)
    }

    private func runJXA(_ script: String) throws -> String {
        try runner.run(
            executable: "/usr/bin/osascript",
            arguments: ["-l", "JavaScript"],
            stdin: script
        ).stdout
    }

    private func runAppleScript(_ script: String) throws -> String {
        try runner.run(
            executable: "/usr/bin/osascript",
            arguments: [],
            stdin: script
        ).stdout
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from source: String) throws -> T {
        let data = Data(source.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw AppleNotesError.invalidResponse
        }
    }

    private func javaScriptStringLiteral(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func parseRecords(from source: String) throws -> [[String]] {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return trimmed
            .components(separatedBy: recordSeparator)
            .filter { !$0.isEmpty }
            .map { $0.components(separatedBy: fieldSeparator) }
    }

    private func parseBool(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    private func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseAppleScriptDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: trimmed)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
