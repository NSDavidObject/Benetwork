import CommonUtilities

public enum NetworkResponseStatusCode: Int {
  case ok = 200
  case unauthorized = 401
  case upgradeRequired = 426
  case internalServerError = 500
}

public struct NetworkResponse<T> {
    
    public let request: NetworkRequest
    public let urlResponse: URLResponse?
    public let result: Result<T>
    
    public func response<N>(withResult newResult: Result<N>) -> NetworkResponse<N> {
        return NetworkResponse<N>(request: request, urlResponse: urlResponse, result: newResult)
    }
}

extension NetworkResponse {

  public var statusCode: Int? {
    return urlResponse?.statusCode
  }
  
  public var isSuccessful: Bool {
    guard let statusCode = statusCode else { return false }
    return (200..<300).contains(statusCode)
  }
}
