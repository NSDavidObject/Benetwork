import CommonUtilities
import SwiftUI

// MARK: - Network Method

public enum NetworkMethod: String {
  case get = "GET"
  case put = "PUT"
  case post = "POST"
  case delete = "DELETE"
}

public enum NetworkRequestBody {
  case none
  case rawData(Data)
  case paramters([String: Any])
}

public enum NetworkRequestCache {
  case none
  case duration(TimeInterval)
}

// MARK: - Network Request

public protocol NetworkRequest {
  var urlBase: String { get }
  var urlPath: String { get }
  var method: NetworkMethod { get }
  var headers: [String: String] { get }
  var urlParameters: [String: CustomStringConvertible] { get }
  var body: NetworkRequestBody { get }
  var responseMiddlewares: [NetworkResponseMiddleware.Type] { get }
  var rateLimiterType: RateLimitType { get }
  var retryLimit: Int { get }
  var retryOnRateLimitExceedFailure: Bool { get }
  var retryOnTimeoutFailure: Bool { get }
  var cacheType: NetworkRequestCache { get }

  func urlRequest() throws -> URLRequest
}

// Setup default values
extension NetworkRequest {

  public var retryLimit: Int {
    return 0
  }

  public var cacheType: NetworkRequestCache {
    return .none
  }
  
  public var urlParameters: [String: CustomStringConvertible] {
    return [:]
  }
  
  public var body: NetworkRequestBody {
    return .none
  }
  
  public var responseMiddlewares: [NetworkResponseMiddleware.Type] {
    return []
  }
  
  public var rateLimiterType: RateLimitType {
    return .none
  }
  
  public var retryOnRateLimitExceedFailure: Bool {
    return true
  }
  
  public var retryOnTimeoutFailure: Bool {
    return false
  }
}

// Helpers
extension NetworkRequest {
  
  public func urlRequest() throws -> URLRequest {
    let mutableRequest = NSMutableURLRequest(url: try constructedURL())
    mutableRequest.httpMethod = method.rawValue
    mutableRequest.allHTTPHeaderFields = headers
    mutableRequest.cachePolicy = .reloadIgnoringLocalCacheData
    
    switch body {
    case .none: break
    case .rawData(let data):
      mutableRequest.httpBody = data
    case .paramters(let parameters):
      if parameters.keys.count > 0, let serializedData = try? JSONSerialization.data(withJSONObject: parameters, options: []) {
        mutableRequest.httpBody = serializedData
      }
    }
    
    guard let request = mutableRequest.copy() as? URLRequest else { fatalError() }
    return request
  }
  
  public func constructedURL() throws -> URL {
    return try URL.urlWithURLBase(urlBase, path: urlPath, urlParams: urlParameters)
  }
}

// Execution
extension NetworkRequest {

  public func requestAndThrowOnFailure() async throws {
    let response = await NetworkHandler.request(self)
    guard response.isSuccessful else { throw "Something went wrong!".localized }
    switch response.result {
      case .failure(let error):
        throw error
      case .success:
        return
    }
  }


  public func rawRequest(completion: @escaping (NetworkResponse<Data>) -> Void) {
    NetworkHandler.request(self, completion: { completion($0) })
  }
  
  public func rawRequestOnBackgroundQueue(callbackQueue: DispatchQueue = .main, completion: @escaping (NetworkResponse<Data>) -> Void) {
    DispatchQueue.global().async {
      self.rawRequest { result in
        callbackQueue.async {
          completion(result)
        }
      }
    }
  }
  
  public func JSONRequest(completion: @escaping (NetworkResponse<JSON>) -> Void) {
    rawRequest(completion: { urlDataResponse in
      let result = urlDataResponse.result
      let jsonResult = result.flatMap({ JSONSerializer.serialize(data: $0) })
      let jsonResponse = urlDataResponse.response(withResult: jsonResult)
      let interceptedJSONResponse = self.responseMiddlewares.intercepting(jsonResponse)
      completion(interceptedJSONResponse)
    })
  }
}
