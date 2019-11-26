import Foundation

extension URLResponse {

  public var statusCode: Int? {
    return (self as? HTTPURLResponse)?.statusCode
  }

  public var isRateLimitExceeded: Bool {
    return statusCode == 429
  }
}
