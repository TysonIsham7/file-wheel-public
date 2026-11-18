import Foundation

struct ProcessOutput: Equatable, Sendable {
    var status: Int32
    var reason: Process.TerminationReason
    var stdout: String
    var stderr: String
}

enum ProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        cancel: ConversionCancel?
    ) async throws -> ProcessOutput {
        if arguments.contains("/bin/sh") || arguments.contains("/bin/bash") || arguments.contains("-c") {
            throw ConversionError.failed("Refusing to invoke a shell")
        }
        if cancel?.isCancelled == true {
            throw ConversionError.cancelled
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                let gate = ResumeGate(continuation)

                cancel?.onCancel {
                    if process.isRunning {
                        process.terminate()
                    }
                }

                do {
                    try process.run()
                } catch {
                    gate.resume(throwing: error)
                    return
                }

                let group = DispatchGroup()
                let dataLock = NSLock()
                var outData = Data()
                var errData = Data()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    dataLock.lock()
                    outData = data
                    dataLock.unlock()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    dataLock.lock()
                    errData = data
                    dataLock.unlock()
                    group.leave()
                }
                process.waitUntilExit()
                group.wait()
                dataLock.lock()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                dataLock.unlock()
                gate.resume(
                    returning: ProcessOutput(
                        status: process.terminationStatus,
                        reason: process.terminationReason,
                        stdout: stdout,
                        stderr: stderr
                    )
                )
            }
        }
    }
}

final class ResumeGate<Success>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private var continuation: CheckedContinuation<Success, Error>?

    init(_ continuation: CheckedContinuation<Success, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Success) {
        lock.lock()
        let continuation = continuation
        if resumed {
            lock.unlock()
            return
        }
        resumed = true
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = continuation
        if resumed {
            lock.unlock()
            return
        }
        resumed = true
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}
