import Foundation

public struct CompressAttempt: Equatable, Sendable {
    public var parameter: Double
    public var byteSize: Int

    public init(parameter: Double, byteSize: Int) {
        self.parameter = parameter
        self.byteSize = byteSize
    }
}

public struct CompressSearchResult: Equatable, Sendable {
    public static let maxEncodes = 8

    public var chosen: CompressAttempt
    public var metTarget: Bool
    public var attempts: [CompressAttempt]
    public var notice: String?

    public init(chosen: CompressAttempt, metTarget: Bool, attempts: [CompressAttempt], notice: String?) {
        self.chosen = chosen
        self.metTarget = metTarget
        self.attempts = attempts
        self.notice = notice
    }
}

public enum CompressSearch {
    /// Binary search on a quality parameter where a higher value produces a larger file.
    /// Stops after `CompressSearchResult.maxEncodes` probes. Keeps the largest result that
    /// is still under the target. If none qualify, keeps the smallest attempt.
    public static func search(
        targetBytes: Int,
        low: Double = 0.05,
        high: Double = 0.95,
        probe: (Double) -> Int
    ) -> CompressSearchResult {
        var lo = min(low, high)
        var hi = max(low, high)
        var attempts: [CompressAttempt] = []
        var bestUnder: CompressAttempt?
        var smallest: CompressAttempt?

        let limit = max(1, CompressSearchResult.maxEncodes)
        for _ in 0..<limit {
            let mid = (lo + hi) / 2
            let size = probe(mid)
            let attempt = CompressAttempt(parameter: mid, byteSize: size)
            attempts.append(attempt)
            if smallest == nil || size < smallest!.byteSize {
                smallest = attempt
            }
            if size <= targetBytes {
                if bestUnder == nil || size > bestUnder!.byteSize {
                    bestUnder = attempt
                }
                lo = mid
            } else {
                hi = mid
            }
            if abs(hi - lo) < 0.004 {
                break
            }
        }

        if let bestUnder {
            return CompressSearchResult(chosen: bestUnder, metTarget: true, attempts: attempts, notice: nil)
        }
        let kept = smallest ?? CompressAttempt(parameter: lo, byteSize: 0)
        let notice = "Could not get under the target size. Kept the smallest attempt (\(kept.byteSize) bytes)."
        return CompressSearchResult(chosen: kept, metTarget: false, attempts: attempts, notice: notice)
    }
}
