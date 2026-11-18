import Foundation

struct CapturedOutput {
    var status: Int32
    var stdout: Data
    var stderr: Data

    var stderrText: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }

    /// The last non-empty line of stderr, for the progress window.
    var lastUsefulStderrLine: String? {
        stderrText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
            .map { String($0) }
    }
}

/// Runs a tool with an argument array. Never a shell string.
enum CapturedProcess {
    static func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        standardOutput: URL? = nil
    ) async throws -> CapturedOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "XAI_API_KEY")
        process.environment = environment

        let scratch = FileManager.default.temporaryDirectory
        let stdoutURL = standardOutput ?? scratch.appendingPathComponent("filewheel-out-\(UUID().uuidString)")
        let stderrURL = scratch.appendingPathComponent("filewheel-err-\(UUID().uuidString)")
        let ownsStdout = standardOutput == nil
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        let gate = CaptureResumeGate()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CapturedOutput, Error>) in
                process.terminationHandler = { finished in
                    try? stdoutHandle.close()
                    try? stderrHandle.close()
                    let stdout = ownsStdout ? (try? Data(contentsOf: stdoutURL)) ?? Data() : Data()
                    let stderr = (try? Data(contentsOf: stderrURL)) ?? Data()
                    if ownsStdout { try? FileManager.default.removeItem(at: stdoutURL) }
                    try? FileManager.default.removeItem(at: stderrURL)
                    gate.resume(continuation, returning: CapturedOutput(status: finished.terminationStatus, stdout: stdout, stderr: stderr))
                }
                do {
                    try process.run()
                } catch {
                    try? stdoutHandle.close()
                    try? stderrHandle.close()
                    gate.resume(continuation, throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    static func requireZero(_ output: CapturedOutput, fallback: String) throws {
        guard output.status == 0 else {
            throw FileWheelError(output.lastUsefulStderrLine ?? fallback)
        }
    }
}

private final class CaptureResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<CapturedOutput, Error>, returning value: CapturedOutput) {
        lock.lock()
        let already = resumed
        resumed = true
        lock.unlock()
        if !already { continuation.resume(returning: value) }
    }

    func resume(_ continuation: CheckedContinuation<CapturedOutput, Error>, throwing error: Error) {
        lock.lock()
        let already = resumed
        resumed = true
        lock.unlock()
        if !already { continuation.resume(throwing: error) }
    }
}
