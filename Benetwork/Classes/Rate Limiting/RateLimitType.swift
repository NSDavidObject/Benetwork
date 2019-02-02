import Foundation

public enum RateLimitType {
    // no rate limiting required
    case none
    // seconds delay between requests
    case timed(TimedLimiter)
}

extension RateLimitType {

    public func execute(_ block: @escaping () -> Void, onQueue queue: DispatchQueue) {
        switch self {
        case .none:
            queue.async { block() }
        case .timed(let timedLimiter):
            timedLimiter.execute(block, onQueue: queue)
        }
    }
}
