import Foundation

public enum NetworkRequestError: Error {
    case noDataReceived
    case requestFailedGenerically
    case requestFailed(message: String)
}

public final class NetworkHandler {
    
    public static func request(_ networkRequest: NetworkRequest, completion: @escaping (NetworkResponse<Data>) -> Void) {
        networkRequest.rateLimiterType.execute({
            URLSession.shared.dataTask(with: networkRequest.urlRequest, completionHandler: { data, urlResponse, error in
                var result: Result<Data>
                defer { completion(NetworkResponse(request: networkRequest, urlResponse: urlResponse, result: result)) }

                switch (data, error) {
                case (_, .some(let error)):
                    result = .failure(error)
                case (.some(let data), _):
                    result = .success(data)
                default:
                    result = .failure(NetworkRequestError.noDataReceived)
                }
            }).resume()
        }, onQueue: .global())
    }
}
