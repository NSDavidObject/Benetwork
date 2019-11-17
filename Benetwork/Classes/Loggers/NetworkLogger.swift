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
}
