import CommonUtilities

public enum NetworkRequestError: Error {
  case noDataReceived
  case requestFailedGenerically
  case requestFailed(message: String)
}

public final class NetworkHandler {

  public static func request(_ networkRequest: NetworkRequest, completion: @escaping (NetworkResponse<Data>) -> Void) {

    #if DEBUG
    if NetworkRequestsCacher.shared.isOn, let cachedValue = NetworkRequestsCacher.shared.data(for: networkRequest.urlRequest) {
      DispatchQueue.global().async {
        completion(NetworkResponse(request: networkRequest, urlResponse: nil, result: .success(cachedValue)))
      }
      return
    }
    #endif

    networkRequest.rateLimiterType.execute({
      NetworkLogger.requests.log("Requesting: \(networkRequest.constructedURL)")
      URLSession.shared.dataTask(with: networkRequest.urlRequest, completionHandler: { data, urlResponse, error in
        if let urlResponse = urlResponse, urlResponse.isRateLimitExceeded, networkRequest.retryOnRateLimitExceedFailure {
          NetworkLogger.requests.log("Rate Limit Exceeded")
          request(networkRequest, completion: completion)
          return
        }
        
        if let nsError = error as? NSError, networkRequest.retryOnTimeoutFailure, nsError.code == -1001 {
          NetworkLogger.requests.log("Rate Limit Exceeded")
          request(networkRequest, completion: completion)
          return
        }

        var result: Result<Data>
        defer { completion(NetworkResponse(request: networkRequest, urlResponse: urlResponse, result: result)) }

        switch (data, error) {
        case (_, .some(let error)):
          result = .failure(error)
        case (.some(let data), _):
          result = .success(data)

          #if DEBUG
          Task(priority: .low) {
            NetworkRequestsCacher.shared.cache(urlRequest: networkRequest.urlRequest, data: data)
          }
          #endif
        default:
          result = .failure(NetworkRequestError.noDataReceived)
        }
      }).resume()
    }, onQueue: .global())
  }
}
