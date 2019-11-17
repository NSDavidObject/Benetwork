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
            NetworkLogger.rateLimiting.log("\(strongSelf.identifier) - Executing after \(strongSelf.lastExecutedAt.timeIntervalSinceNow) since last execution")
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

            // Last execution in the past
            if now > strongSelf.lastExecutedAt {
              let timeInterval = now.timeIntervalSince(strongSelf.lastExecutedAt)
              if timeInterval > limit {
                strongSelf.lastExecutedAt = now
                completionBlock()
                return
              } else {
                let delay = limit - abs(timeInterval)
                let newTime = now.addingTimeInterval(delay)
                strongSelf.lastExecutedAt = newTime
                strongSelf.syncQueue.asyncAfter(deadline: .now() + delay, execute: completionBlock)
              }
            } else {
              let newTime = strongSelf.lastExecutedAt.addingTimeInterval(limit)
              let delay = newTime.timeIntervalSince(now)
              strongSelf.lastExecutedAt = newTime
              strongSelf.syncQueue.asyncAfter(deadline: .now() + delay, execute: completionBlock)
            }
        }
    }

    public func reset() {
        syncQueue.sync {
            lastExecutedAt = .distantPast
        }
    }
}
