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
  
  public func execute(_ block: @escaping () -> Void) async {
    switch self {
    case .none:
      execute(block, onQueue: .global())
    case .timed(let timedLimiter):
      timedLimiter.execute(block, onQueue: .global())
    case .singleFutureLimiter(let singleFutureLimiter):
      singleFutureLimiter.execute(block)
    case .perFrequency(let frequencyRateLimiter):
      await frequencyRateLimiter.execute(block)
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


import Foundation

public class TokenBucket {
  public let capacity: Int
  public private(set) var tokensPerInterval: Int
  public private(set) var replenishingInterval: TimeInterval
  
  private var tokenCount: Int
  private var lastReplenished: Date
  private let lock = NSLock()
  
  public init(capacity: Int, tokensPerInterval: Int, interval: TimeInterval, initialTokenCount: Int = 0) {
    self.capacity = capacity
    self.tokensPerInterval = tokensPerInterval
    self.replenishingInterval = interval
    self.tokenCount = min(capacity, initialTokenCount)
    self.lastReplenished = Date()
  }
  
  public func consume(_ count: Int) async {
    guard count <= capacity else {
      fatalError("Cannot consume more tokens than the capacity.")
    }
    
    while true {
      if tokenCount >= count {
        tokenCount -= count
        return
      }
      await replenish()
      if tokenCount >= count {
        tokenCount -= count
        return
      }
      try? await Task.sleep(nanoseconds: .random(in: 10_000_000...50_000_000)) // Sleep for 50 milliseconds
    }
  }
  
  private func replenish() async {
    lock.lock()
    defer { lock.unlock() }
    
    let elapsedTime = -lastReplenished.timeIntervalSinceNow
    if elapsedTime > replenishingInterval {
      let elapsedIntervals = Int(elapsedTime / replenishingInterval)
      tokenCount = min(tokenCount + (elapsedIntervals * tokensPerInterval), capacity)
      lastReplenished = Date()
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
  
  private let requestsPerInterval: Int
  private lazy var currentRateLimit: Int = requestsPerInterval
  
  // Rate limit adaptation
  private var dynamicAdjustState: RateLimitAdjustmentState = .enabled()
  private let interval: TimeInterval // Interval in seconds
  
  private lazy var tokenBucket: TokenBucket = createBucket()
  
  private let taskPriority: TaskPriority
  public init(requestsPerFrequency: Int, frequency: Frequency, taskPriority: TaskPriority = .background) {
    self.requestsPerInterval = requestsPerFrequency
    self.interval = frequency.intervalInSeconds
    self.taskPriority = taskPriority
  }
  
  public func execute(_ block: @escaping () -> Void) async {
    await tokenBucket.consume(1)
    block()
  }
  
  public func execute(_ block: @escaping () -> Void, completion: (() -> Void)? = nil, onQueue queue: DispatchQueue) {
    Task(priority: taskPriority) {
      await tokenBucket.consume(1)
      queue.async {
        block()
        completion?()
      }
    }
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
    
    tokenBucket = {
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
    tokenBucket = createBucket()
  }
}
