import CommonUtilities

public final class SingleFutureLimiter {

  private var timer: Timer?

  public let waitTime: TimeInterval
  public init(waitTime: TimeInterval) {
    self.waitTime = waitTime
  }

  public func execute(_ block: @escaping () -> Void) {
    timer = Timer.scheduledTimer(withTimeInterval: waitTime, repeats: false, block: { [weak self] timer in
      guard let strongSelf = self, strongSelf.timer == timer else { return }
      block()
      strongSelf.timer = nil
    })
  }
}
