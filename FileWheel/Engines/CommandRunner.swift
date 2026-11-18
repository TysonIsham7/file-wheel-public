import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct CommandResult: Equatable, Sendable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data

    public init(status: Int32, stdout: Data, stderr: Data) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutText: String { String(data: stdout, encoding: .utf8) ?? "" }
    public var stderrText: String { String(data: stderr, encoding: .utf8) ?? "" }
}

public protocol CommandRunning {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL?,
        standardInput: Data?,
        cancellation: CancellationFlag?
    ) throws -> CommandResult
}

public extension CommandRunning {
    func run(executable: URL, arguments: [String]) throws -> CommandResult {
        try run(executable: executable, arguments: arguments, currentDirectory: nil, standardInput: nil, cancellation: nil)
    }
}

public struct FoundationCommandRunner: CommandRunning {
    public init() {}

    public func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL?,
        standardInput: Data?,
        cancellation: CancellationFlag?
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe = Pipe()
        if standardInput != nil {
            process.standardInput = inPipe
        }
        let outBox = DataBox()
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if let standardInput {
            group.enter()
            DispatchQueue.global().async {
                inPipe.fileHandleForWriting.write(standardInput)
                try? inPipe.fileHandleForWriting.close()
                group.leave()
            }
        }
        do {
            try process.run()
        } catch {
            throw ToolError.message("Could not run \(executable.lastPathComponent).")
        }
        while process.isRunning {
            if cancellation?.isCancelled == true {
                process.terminate()
                let deadline = Date().addingTimeInterval(2)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
                group.wait()
                throw ToolError.cancelled
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        group.wait()
        return CommandResult(status: process.terminationStatus, stdout: outBox.data, stderr: errBox.data)
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

public enum ProcessText {
    public static func lastUsefulLine(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let useful = lines.reversed().first { line in
            let lower = line.lowercased()
            return !lower.hasPrefix("ffmpeg version")
                && !lower.contains("configuration:")
                && !lower.hasPrefix("built with")
                && line != "Press [q] to stop, [?] for help"
        }
        return useful ?? "The tool failed."
    }
}
