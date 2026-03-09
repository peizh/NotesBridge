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

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
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
