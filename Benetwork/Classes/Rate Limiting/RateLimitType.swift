import CommonUtilities

public enum RateLimitType {
  // no rate limiting required
  case none
  // seconds delay between requests
  case timed(TimedLimiter)
  // only fire once after wait time, timer resets on each execution
  case singleFutureLimiter(SingleFutureLimiter)
}

extension RateLimitType {
  
  public func reset() {
    switch self {
    case .none: break
    case .timed(let timer):
      timer.reset()
    case .singleFutureLimiter(let limiter):
      limiter.cancel()
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
    }
  }
}
