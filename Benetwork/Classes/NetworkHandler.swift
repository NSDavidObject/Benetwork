import CommonUtilities
import Cache

public enum NetworkRequestError: Error {
  case noDataReceived
  case requestFailedGenerically
  case requestFailed(message: String)
}

public final class NetworkHandler {
  private static let storage: DiskStorage<String, Data> = ObjectStorage<Data>().diskOnlyStorage!

  public static func request(_ networkRequest: NetworkRequest) async -> NetworkResponse<Data> {
    await withCheckedContinuation({ continuation in
      request(networkRequest, completion: { response in
        continuation.resume(returning: response)
      })
    })
  }
  
  public static func requestAndThrowOnFailure(_ networkRequest: NetworkRequest) async throws -> Data {
    let response = await request(networkRequest)
    switch response.result {
    case .failure(let error):
      throw error
    case .success(let data):
      return data
    }
  }

  public static func request(_ networkRequest: NetworkRequest, completion: @escaping (NetworkResponse<Data>) -> Void, numberOfRetries: Int = 0) {

    let urlRequest: URLRequest
    do {
      urlRequest = try networkRequest.urlRequest()
    } catch {
      completion(.init(request: networkRequest, urlResponse: nil, result: .failure(error)))
      return
    }
    
    #if DEBUG
    if NetworkRequestsCacher.shared.isOn, let cachedValue = try? NetworkRequestsCacher.shared.data(for: networkRequest.urlRequest()) {
      completion(NetworkResponse(request: networkRequest, urlResponse: nil, result: .success(cachedValue)))
      return
    }
    #endif
    
    let cacheKey: String = (try? networkRequest.constructedURL().absoluteString) ?? ""
    if let cachedValue = try? Self.storage.nonExpiredObjectById(cacheKey), !cacheKey.contains("localhost") {
      completion(
        .init(
          request: networkRequest,
          urlResponse: nil,
          result: .success(cachedValue)
        )
      )
      return
    }

    networkRequest.rateLimiterType.execute({
      NetworkLogger.requests.log("Requesting: \(urlRequest.url?.absoluteString ?? "")")
      URLSession.shared.dataTask(with: urlRequest, completionHandler: { data, urlResponse, error in
        if let urlResponse = urlResponse, urlResponse.isRateLimitExceeded, networkRequest.retryOnRateLimitExceedFailure, numberOfRetries < 10 {
          NetworkLogger.requests.log("Rate Limit Exceeded")
          networkRequest.rateLimiterType.informRateLimitHit()
          request(networkRequest, completion: completion, numberOfRetries: numberOfRetries.successor)
          return
        }
        
        if let nsError = error as? NSError, networkRequest.retryOnTimeoutFailure, nsError.code == -1001, numberOfRetries < 3 {
          NetworkLogger.requests.log("Rate Limit Exceeded")
          networkRequest.rateLimiterType.informRateLimitHit()
          request(networkRequest, completion: completion, numberOfRetries: numberOfRetries.successor)
          return
        }

        if let error, networkRequest.retryLimit > numberOfRetries {
          NetworkLogger.requests.log("Retrying request (\(numberOfRetries.successor)): \(urlRequest.url?.absoluteString ?? "")")
          request(networkRequest, completion: completion, numberOfRetries: numberOfRetries.successor)
          return
        }

        networkRequest.rateLimiterType.informSuccessfulCompletion()
        
        var result: Result<Data>
        defer { completion(NetworkResponse(request: networkRequest, urlResponse: urlResponse, result: result)) }

        switch (data, error) {
        case (_, .some(let error)):
          result = .failure(error)
        case (.some(let data), _):
          result = .success(data)

          #if DEBUG
          if NetworkRequestsCacher.shared.isOn {
            Task(priority: .low) {
              NetworkRequestsCacher.shared.cache(urlRequest: urlRequest, data: data)
            }
          }
          #endif
            
          if case .duration(let duration) = networkRequest.cacheType, let urlResponse, urlResponse.isSuccessful {
            try? Self.storage.setObject(data, forKey: cacheKey, expiry: .seconds(duration))
          }
        default:
          result = .failure(NetworkRequestError.noDataReceived)
        }
      }).resume()
    }, onQueue: .global(qos: .userInitiated))
  }
}
