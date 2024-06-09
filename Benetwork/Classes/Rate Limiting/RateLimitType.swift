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





public class TokenBucket: NSObject {
  public let capacity: Int
  public private(set) var tokensPerInterval: Int
  public private(set) var replenishingInterval: TimeInterval
  
  private var _tokenCount: Int
  public var tokenCount: Int {
    replenish()
    return _tokenCount
  }
  private var lastReplenished: Date
  
  public init(capacity: Int, tokensPerInterval: Int, interval: TimeInterval, initialTokenCount: Int = 0) {
    guard interval > 0.0 else {
      fatalError("interval must be a positive number")
    }
    self.capacity = capacity
    self.tokensPerInterval = tokensPerInterval
    self.replenishingInterval = interval
    self._tokenCount = min(capacity, initialTokenCount)
    self.lastReplenished = Date()
  }
  
  public func consume(_ count: Int) {
    guard count <= capacity else {
      fatalError("Cannot consume \(count) amount of tokens on a bucket with capacity \(capacity)")
    }
    
    let _ = tryConsume(count, until: .now.addingTimeInterval(0.1))
  }
  
  public func tryConsume(_ count: Int, until limitDate: Date) -> Bool {
    guard count <= capacity else {
      fatalError("Cannot consume \(count) amount of tokens on a bucket with capacity \(capacity)")
    }
    
    return wait(until: limitDate, for: count)
  }
  
  private let condition = NSCondition()
  private func replenish() {
    condition.lock()
    let ellapsedTime = abs(lastReplenished.timeIntervalSinceNow)
    if ellapsedTime > replenishingInterval {
      let ellapsedIntervals = Int((floor(ellapsedTime / Double(replenishingInterval))))
      _tokenCount = min(_tokenCount + (ellapsedIntervals * tokensPerInterval), capacity)
      lastReplenished = Date()
      condition.signal()
    }
    condition.unlock()
  }
  
  private func wait(until limitDate: Date, for tokens: Int) -> Bool {
    replenish()
    
    condition.lock()
    defer {
      condition.unlock()
    }
    while _tokenCount < tokens {
      if limitDate < Date() {
        return false
      }
      DispatchQueue.global().async {
        self.replenish()
      }
      condition.wait(until: Date().addingTimeInterval(0.2))
    }
    _tokenCount -= tokens
    return true
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
  
  private let requestsPerInterval: Int
  private lazy var currentRateLimit: Int = requestsPerInterval
  
  // Rate limit adaptation
  private var dynamicAdjustState: RateLimitAdjustmentState = .enabled()
  private let interval: TimeInterval // Interval in seconds
  
  private lazy var tokenBucket: Atomic<TokenBucket> = .init(createBucket())
  
  public init(requestsPerFrequency: Int, frequency: Frequency) {
    self.requestsPerInterval = requestsPerFrequency
    self.interval = frequency.intervalInSeconds
  }
  
  public func execute(_ block: @escaping () -> Void, completion: Completion? = nil, onQueue queue: DispatchQueue) {
    tokenBucket.value.consume(1)
    queue.async(execute: {
      block()
      completion?()
    })
  }
  
  public func informSuccessfulCompletion() {
    if case .disabled = dynamicAdjustState {
      dynamicAdjustState = .enabled()
    }
  }
  
  public func informRateLimitHit() {
    guard currentRateLimit != 1 else { return }
    guard case .enabled(var rateLimitHits) = dynamicAdjustState else { return }
    
    let shouldAdjust: Bool = rateLimitHits % 10 == 0
    guard shouldAdjust else {
      dynamicAdjustState = .enabled(hits: rateLimitHits.successor)
      return
    }
    
    let newLimitDouble: Double = (Double(currentRateLimit) * 0.9).rounded(.down)
    currentRateLimit = max(1, Int(newLimitDouble))
    
    // Disable until next success, this ensures we don't keep decreasing limit during a long rate limit failure buffer.
    dynamicAdjustState = .disabled
    
    tokenBucket.value = {
      // Sleep for 15 seconds
      usleep(useconds_t(interval * 1_000_000)) // Convert 15secs to microseconds
      return createBucket()
    }()
  }
  
  func createBucket() -> TokenBucket {
    let capacity = currentRateLimit
    let tokensPerInterval = max(currentRateLimit / Int(interval), 1)
    let interval = 1
    return TokenBucket(capacity: capacity, tokensPerInterval: tokensPerInterval, interval: TimeInterval(interval))
  }
  
  func reset() {
    // Reset
    currentRateLimit = requestsPerInterval
    tokenBucket.value = createBucket()
  }
}
