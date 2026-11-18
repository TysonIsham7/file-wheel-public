import Foundation

public enum JobState: Equatable, Sendable {
    case waiting
    case running
    case finished
    case failed(String)
    case cancelled
}

public struct QueueItem: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var batchID: UUID
    public var title: String
    public var weight: JobWeight
    public var state: JobState
    public var progress: Double
    public var message: String
    public var outputs: [URL]

    public init(id: UUID, batchID: UUID, title: String, weight: JobWeight, state: JobState, progress: Double, message: String, outputs: [URL]) {
        self.id = id
        self.batchID = batchID
        self.title = title
        self.weight = weight
        self.state = state
        self.progress = progress
        self.message = message
        self.outputs = outputs
    }
}

public protocol JobQueueDelegate: AnyObject {
    func jobQueueDidChange(_ queue: JobQueue)
    func jobQueue(_ queue: JobQueue, batchSettled batchID: UUID, outputs: [URL], failures: [String])
}

public final class CancellationFlag {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

public final class Job {
    public let id: UUID
    public let batchID: UUID
    public let title: String
    public let weight: JobWeight
    public let cancellation: CancellationFlag
    public var state: JobState
    public var progress: Double
    public var message: String
    public var outputs: [URL]
    let work: (Job) throws -> ToolRunOutcome

    public init(
        id: UUID = UUID(),
        batchID: UUID,
        title: String,
        weight: JobWeight,
        work: @escaping (Job) throws -> ToolRunOutcome
    ) {
        self.id = id
        self.batchID = batchID
        self.title = title
        self.weight = weight
        self.cancellation = CancellationFlag()
        self.state = .waiting
        self.progress = 0
        self.message = ""
        self.outputs = []
        self.work = work
    }
}

public final class JobQueue {
    public weak var delegate: JobQueueDelegate?
    public var imageSlots = 2
    public var heavySlots = 1
    /// Tests run work on the calling thread so ordering is deterministic.
    public var executeInline = false

    private let lock = NSLock()
    private var jobs: [Job] = []
    private var isPausedFlag = false
    private var notifiedBatches = Set<UUID>()

    public init() {}

    public var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPausedFlag
    }

    public var outstandingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return jobs.filter { $0.state == .waiting || $0.state == .running }.count
    }

    public static func needsQuitConfirmation(outstanding: Int) -> Bool {
        outstanding > 0
    }

    public static let quitConfirmationTitle = "Quit File Wheel?"
    public static let quitConfirmationMessage = "A conversion is still running. Quit and cancel it?"

    @discardableResult
    public func enqueue(title: String, weight: JobWeight, batchID: UUID = UUID(), work: @escaping (Job) throws -> ToolRunOutcome) -> UUID {
        let job = Job(batchID: batchID, title: title, weight: weight, work: work)
        lock.lock()
        jobs.append(job)
        lock.unlock()
        schedule()
        return job.id
    }

    public func pause() {
        lock.lock()
        isPausedFlag = true
        lock.unlock()
        publish()
    }

    public func resume() {
        lock.lock()
        isPausedFlag = false
        lock.unlock()
        schedule()
    }

    public func cancel(_ id: UUID) {
        lock.lock()
        guard let job = jobs.first(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        job.cancellation.cancel()
        if job.state == .waiting {
            job.state = .cancelled
            job.message = ToolError.cancelled.message
        }
        lock.unlock()
        publish()
        settleBatches()
    }

    public func cancelAll() {
        let ids: [UUID]
        lock.lock()
        ids = jobs.map(\.id)
        lock.unlock()
        ids.forEach(cancel)
    }

    public func snapshot() -> [QueueItem] {
        lock.lock()
        defer { lock.unlock() }
        return jobs.map {
            QueueItem(
                id: $0.id,
                batchID: $0.batchID,
                title: $0.title,
                weight: $0.weight,
                state: $0.state,
                progress: $0.progress,
                message: $0.message,
                outputs: $0.outputs
            )
        }
    }

    private func schedule() {
        let inline = executeInline
        lock.lock()
        let paused = isPausedFlag
        var started: [Job] = []
        if !paused {
            var runningHeavy = jobs.filter { $0.state == .running && $0.weight == .heavy }.count
            var runningImage = jobs.filter { $0.state == .running && $0.weight == .image }.count
            for job in jobs where job.state == .waiting {
                if job.weight == .heavy {
                    if runningHeavy < heavySlots && runningImage == 0 {
                        job.state = .running
                        started.append(job)
                        runningHeavy += 1
                    } else {
                        break
                    }
                } else if runningHeavy == 0 && runningImage < imageSlots {
                    job.state = .running
                    started.append(job)
                    runningImage += 1
                } else {
                    break
                }
            }
        }
        lock.unlock()
        for job in started {
            if inline {
                run(job)
            } else {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.run(job)
                }
            }
        }
        publish()
    }

    private func run(_ job: Job) {
        do {
            let outcome = try job.work(job)
            lock.lock()
            if job.cancellation.isCancelled {
                job.state = .cancelled
                job.outputs = []
                job.message = ToolError.cancelled.message
            } else {
                job.state = .finished
                job.outputs = outcome.outputs
                job.progress = 1
                job.message = outcome.message ?? job.message
            }
            lock.unlock()
        } catch {
            lock.lock()
            if job.cancellation.isCancelled || (error as? ToolError) == ToolError.cancelled {
                job.state = .cancelled
                job.message = ToolError.cancelled.message
                job.outputs = []
            } else {
                let message = (error as? ToolError)?.message ?? error.localizedDescription
                job.state = .failed(message)
                job.message = message
            }
            lock.unlock()
        }
        schedule()
        settleBatches()
    }

    private func settleBatches() {
        let events: [(UUID, [URL], [String])]
        lock.lock()
        let batches = Set(jobs.map(\.batchID))
        var pending: [(UUID, [URL], [String])] = []
        for batch in batches where !notifiedBatches.contains(batch) {
            let members = jobs.filter { $0.batchID == batch }
            let done = members.allSatisfy { item in
                switch item.state {
                case .finished, .failed, .cancelled:
                    return true
                case .waiting, .running:
                    return false
                }
            }
            if done {
                notifiedBatches.insert(batch)
                let outputs = members.flatMap(\.outputs)
                let failures = members.compactMap { item -> String? in
                    if case .failed(let message) = item.state { return message }
                    return nil
                }
                pending.append((batch, outputs, failures))
            }
        }
        events = pending
        lock.unlock()
        for event in events {
            delegate?.jobQueue(self, batchSettled: event.0, outputs: event.1, failures: event.2)
        }
    }

    private func publish() {
        delegate?.jobQueueDidChange(self)
    }
}

public struct ToolRunOutcome: Equatable, Sendable {
    public var outputs: [URL]
    public var message: String?
    public var qrCodes: [String]
    public var metCompressTarget: Bool?

    public init(outputs: [URL], message: String? = nil, qrCodes: [String] = [], metCompressTarget: Bool? = nil) {
        self.outputs = outputs
        self.message = message
        self.qrCodes = qrCodes
        self.metCompressTarget = metCompressTarget
    }
}

public struct ToolError: Error, Equatable, LocalizedError {
    public var message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }

    public static func message(_ text: String) -> ToolError {
        ToolError(message: text)
    }

    public static let cancelled = ToolError(message: "Cancelled.")
    public static let passwordProtected = ToolError(message: "This PDF is password-protected.")
    public static let noCodeFound = ToolError(message: "No code found")
}
