import Foundation

extension NetworkRequest {
  
  public static func jsonHeaders() -> [String: String] {
    var headers: [String: String] = [:]
    headers["Accept"] = "application/json"
    headers["Content-Type"] = "application/json"
    return headers
  }
}
