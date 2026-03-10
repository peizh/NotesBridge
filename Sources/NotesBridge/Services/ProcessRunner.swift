import Foundation

struct CommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ProcessRunnerError: LocalizedError {
    case executionFailed(command: String, stderr: String, exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case let .executionFailed(command, stderr, exitCode):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "\(command) failed with exit code \(exitCode)."
            }
            return "\(command) failed with exit code \(exitCode): \(trimmed)"
        }
    }
}

struct ProcessRunner: Sendable {
    func run(executable: String, arguments: [String], stdin: String? = nil) throws -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if stdin != nil {
            process.standardInput = stdinPipe
        }

        try process.run()

        if let stdin {
            stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
        }
        stdinPipe.fileHandleForWriting.closeFile()

        let stdoutReader = PipeReader(fileHandle: stdoutPipe.fileHandleForReading)
        let stderrReader = PipeReader(fileHandle: stderrPipe.fileHandleForReading)
        stdoutReader.start()
        stderrReader.start()

        process.waitUntilExit()
        let stdoutData = stdoutReader.finish()
        let stderrData = stderrReader.finish()
        let result = CommandResult(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            exitCode: process.terminationStatus
        )

        guard result.exitCode == 0 else {
            throw ProcessRunnerError.executionFailed(
                command: ([executable] + arguments).joined(separator: " "),
                stderr: result.stderr,
                exitCode: result.exitCode
            )
        }

        return result
    }
}

private final class PipeReader: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let queue = DispatchQueue(label: "NotesBridge.PipeReader", qos: .utility)
    private var result: Result<Data, Error>?

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func start() {
        queue.async { [fileHandle] in
            do {
                let data = try fileHandle.readToEnd() ?? Data()
                self.result = .success(data)
            } catch {
                self.result = .failure(error)
            }
        }
    }

    func finish() -> Data {
        queue.sync {
            switch result {
            case let .success(data):
                return data
            case .failure, .none:
                return Data()
            }
        }
    }
}
