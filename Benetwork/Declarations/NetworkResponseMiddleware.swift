import Foundation

public protocol NetworkResponseMiddleware {
    static func interceptingResponse<T>(_ response: NetworkResponse<T>) -> NetworkResponse<T>
}

extension Collection where Element == NetworkResponseMiddleware.Type {
    
    public func intercepting<T>(_ response: NetworkResponse<T>) -> NetworkResponse<T> {
        var interceptedResponse = response
        for middleware in self {
            interceptedResponse = middleware.interceptingResponse(interceptedResponse)
        }
        return interceptedResponse
    }
}
