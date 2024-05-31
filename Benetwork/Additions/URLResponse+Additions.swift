import Foundation

extension URLResponse {

  public var statusCode: Int? {
    guard let httpURLResponse = self as? HTTPURLResponse else { return nil }
    let statusCode: Int = httpURLResponse.statusCode
    return statusCode
  }

  public var isRateLimitExceeded: Bool {
    return statusCode == 429
  }
  
  public var isNotFound: Bool {
    return statusCode == 404
  }
}
