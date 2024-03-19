import CommonUtilities

public enum RateLimitType {
  // no rate limiting required
  case none
  // seconds delay between requests
  case timed(TimedLimiter)
  // only fire once after wait time, timer resets on each execution
  case singleFutureLimiter(SingleFutureLimiter)
  // only permit certain number of requests for a given frequency
  case perFrequency(FrequencyRateLimiter)
}

extension RateLimitType {
  
  public func reset() {
    switch self {
    case .none: break
    case .timed(let timer):
      timer.reset()
    case .singleFutureLimiter(let limiter):
      limiter.cancel()
    case .perFrequency(let limiter):
      limiter.reset()
    }
  }
  
  public func execute(_ block: @escaping () -> Void, onQueue queue: DispatchQueue) {
    switch self {
    case .none:
      queue.async { block() }
    case .timed(let timedLimiter):
      timedLimiter.execute(block, onQueue: queue)
    case .singleFutureLimiter(let limiter):
      limiter.execute({ queue.async { block() } })
    case .perFrequency(let limiter):
      limiter.execute({ block() }, onQueue: queue)
    }
  }
  
  public func informRateLimitHit() {
    switch self {
    case .none, .timed, .singleFutureLimiter: break
    case .perFrequency(let frequencyRateLimiter):
      frequencyRateLimiter.informRateLimitHit()
    }
  }
  
  public func informSuccessfulCompletion() {
    switch self {
    case .none, .timed, .singleFutureLimiter: break
    case .perFrequency(let frequencyRateLimiter):
      frequencyRateLimiter.informSuccessfulCompletion()
    }
  }
}

public class FrequencyRateLimiter {
  public enum Frequency {
    case perMinute
    case perSecond
    var intervalInSeconds: TimeInterval {
      switch self {
      case .perMinute:
        return 60
      case .perSecond:
        return 1
      }
    }
  }
  
  private enum RateLimitAdjustmentState {
    case enabled(hits: Int = 0)
    case disabled
  }
  
  private let syncQueue = DispatchQueue(label: "com.watchioapikit.tmdbapi")
  private let requestsPerInterval: Int
  private lazy var currentRateLimit: Int = requestsPerInterval
  
  private let interval: TimeInterval // Interval in seconds
  private var requestTimestamps: [Date] = []
  
  // Rate limit adaptation
  private var dynamicAdjustState: RateLimitAdjustmentState = .enabled()
  
  public init(requestsPerFrequency: Int, frequency: Frequency) {
    self.requestsPerInterval = requestsPerFrequency
    self.interval = frequency.intervalInSeconds
  }
  
  public func execute(_ block: @escaping () -> Void, onQueue queue: DispatchQueue) {
    syncQueue.async { [weak self] in
      guard let self = self else { return }
      
      let now = Date.now
      self.cleanupOldRequests(now)
      
      if self.requestTimestamps.count >= self.currentRateLimit, let earliestNextRequest = self.requestTimestamps.first?.addingTimeInterval(self.interval) {
        let delay = max(0, earliestNextRequest.timeIntervalSince(now))
        syncQueue.asyncAfter(deadline: .now() + delay) {
          self.execute(block, onQueue: queue) // Retry executing the block after the delay
        }
      } else {
        queue.async { block() }
        self.requestTimestamps.append(now) // Update request timestamps
      }
    }
  }
  
  public func reset() {
    syncQueue.async { [weak self] in
      self?.requestTimestamps.removeAll()
    }
  }
  
  public func informSuccessfulCompletion() {
    syncQueue.async { [weak self] in
      guard let self = self else { return }
      
      if case .disabled = dynamicAdjustState {
        dynamicAdjustState = .enabled()
      }
    }
  }
  
  public func informRateLimitHit() {
    syncQueue.async { [weak self] in
      guard let self = self, case .enabled(var rateLimitHits) = dynamicAdjustState else { return }
      
      let shouldAdjust: Bool = rateLimitHits % 10 == 0
      guard shouldAdjust else {
        dynamicAdjustState = .enabled(hits: rateLimitHits.successor)
        return
      }
      
      let newLimitDouble: Double = (Double(currentRateLimit) * 0.9).rounded(.down)
      currentRateLimit = max(1, Int(newLimitDouble))
      
      // Disable until next success, this ensures we don't keep decreasing limit during a long rate limit failure buffer.
      dynamicAdjustState = .disabled
    }
  }
  
  private func cleanupOldRequests(_ currentTime: Date) {
    requestTimestamps = requestTimestamps.filter { timestamp in
      return currentTime.timeIntervalSince(timestamp) <= interval
    }
  }
}
