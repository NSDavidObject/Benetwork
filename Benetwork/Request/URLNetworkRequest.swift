import Foundation

open class URLNetworkRequest: NetworkRequest {
  open var urlBase: String = ""
  open var urlPath: String = ""
  open var method: NetworkMethod = .get
  open var headers: [String : String] = [:]
  
  public let url: URL
  public init(url: URL) {
    self.url = url
  }
  
  public func urlRequest() throws -> URLRequest {
    return .init(url: url)
  }
}
