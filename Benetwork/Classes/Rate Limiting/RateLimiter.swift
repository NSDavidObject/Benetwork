import Foundation

public final class TimedLimiter {

    private lazy var identifier: String = UUID().uuidString
    private lazy var timeOfLastExecution: Date = Date()


    // MARK: - Properties
    public let limit: TimeInterval
    public private(set) var lastExecutedAt: Date = .distantPast
    private let syncQueue = DispatchQueue(label: "com.benetwork.ratelimiter", attributes: [])

    // MARK: - Initializers
    public init(limit: TimeInterval) {
        self.limit = limit
    }

    // MARK: - Limiter
    public func execute(_ block: @escaping () -> Void, onQueue queue: DispatchQueue) {
        let completionBlock: () -> Void = { [weak self] in
            guard let strongSelf = self else { return }
            RateLimitingLogger.log("\(strongSelf.identifier) - Executing after \(strongSelf.lastExecutedAt.timeIntervalSinceNow) since last execution")
            strongSelf.timeOfLastExecution = Date()
            queue.async { block() }
        }
        syncQueue.async { [weak self] in
            guard let strongSelf = self else {
                completionBlock()
                return
            }

            let now = Date()
            let limit = strongSelf.limit
            let timeInterval = now.timeIntervalSince(strongSelf.lastExecutedAt)
            if timeInterval > limit {
                strongSelf.lastExecutedAt = now
                completionBlock()
                return
            }

            let timeSinceLastExecution = now.timeIntervalSince(strongSelf.lastExecutedAt)
            let delayBeforeExecutionInSeconds: TimeInterval = limit - timeSinceLastExecution
            strongSelf.lastExecutedAt = now.addingTimeInterval(delayBeforeExecutionInSeconds)
            strongSelf.syncQueue.asyncAfter(deadline: .now() + delayBeforeExecutionInSeconds, execute: completionBlock)
        }
    }

    public func reset() {
        syncQueue.sync {
            lastExecutedAt = .distantPast
        }
    }
}
