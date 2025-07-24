import CommonUtilities

enum NetworkLogger: Logger {
  case requests
  case rateLimiting

  var name: String {
    switch self {
    case .requests:
      return "NetworkRequests"
    case .rateLimiting:
      return "RateLimiting"
    }
  }

  public func log(_ text: String, file: String = #file, function: String = #function, line: UInt = #line) {
    print("\(name): \(text)")
  }
}
