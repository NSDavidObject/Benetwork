import CommonUtilities

// MARK: - Network Method

public enum NetworkMethod: String {
    case get = "GET"
    case put = "PUT"
    case post = "POST"
    case delete = "DELETE"
}

// MARK: - Network Request

public protocol NetworkRequest {
    var urlBase: String { get }
    var urlPath: String { get }
    var method: NetworkMethod { get }
    var headers: [String: String] { get }
    var urlParameters: [String: CustomStringConvertible] { get }
    var bodyParameters: [String: AnyObject] { get }
    var responseMiddlewares: [NetworkResponseMiddleware.Type] { get }
    var rateLimiterType: RateLimitType { get }
}

// Setup default values
extension NetworkRequest {
    
    public var urlParameters: [String: CustomStringConvertible] {
        return [:]
    }
    
    public var bodyParameters: [String: AnyObject] {
        return [:]
    }
    
    public var responseMiddlewares: [NetworkResponseMiddleware.Type] {
        return []
    }

    public var rateLimiterType: RateLimitType {
        return .none
    }
}

// Helpers
extension NetworkRequest {
    
    public var urlRequest: URLRequest {
        let mutableRequest = NSMutableURLRequest(url: constructedURL)
        mutableRequest.httpMethod = method.rawValue
        mutableRequest.allHTTPHeaderFields = headers
        
        if bodyParameters.keys.count > 0, let serializedData = try? JSONSerialization.data(withJSONObject: bodyParameters, options: []) {
            mutableRequest.httpBody = serializedData
        }

        guard let request = mutableRequest.copy() as? URLRequest else { fatalError() }
        return request
    }
    
    public var constructedURL: URL {
        return URL.urlWithURLBase(urlBase, path: urlPath, urlParams: urlParameters)
    }
}

// Execution
extension NetworkRequest {
    
    public func rawRequest(completion: @escaping (NetworkResponse<Data>) -> Void) {
        NetworkHandler.request(self, completion: { completion($0) })
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
