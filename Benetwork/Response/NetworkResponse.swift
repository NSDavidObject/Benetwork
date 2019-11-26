import CommonUtilities

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
}
