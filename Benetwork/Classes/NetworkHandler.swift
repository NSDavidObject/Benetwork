import CommonUtilities
import Cache

public enum NetworkRequestError: Error {
  case noDataReceived
  case requestFailedGenerically
  case requestFailed(message: String)
}

public final class NetworkHandler {
  private static let storage: DiskStorage<String, Data> = ObjectStorage<Data>().diskOnlyStorage(
    sizeInMegabytes: 100,
    expiry: 1.daysToSeconds
  )!

  public static let allCaches: [CacheDumpable] = [
    storage,
  ]

  public static func request(_ networkRequest: NetworkRequest, skipCache: Bool) async -> NetworkResponse<Data> {
    await withCheckedContinuation({ continuation in
      request(networkRequest, skipCache: skipCache, completion: { response in
        continuation.resume(returning: response)
      })
    })
  }

  public static func requestAndThrowOnFailure(_ networkRequest: NetworkRequest, skipCache: Bool = false) async throws -> Data {
    let response = await request(networkRequest, skipCache: skipCache)
    switch response.result {
    case .failure(let error):
      throw error
    case .success(let data):
      return data
    }
  }

  public static func request(_ networkRequest: NetworkRequest, skipCache: Bool, completion: @escaping (NetworkResponse<Data>) -> Void, numberOfRetries: Int = 0) {

    var urlRequest: URLRequest
    do {
      urlRequest = try networkRequest.urlRequest()
    } catch {
      completion(.init(request: networkRequest, urlResponse: nil, result: .failure(error)))
      return
    }

    urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

#if DEBUG
    if NetworkRequestsCacher.shared.isOn, let cachedValue = try? NetworkRequestsCacher.shared.data(for: networkRequest.urlRequest()) {
      completion(NetworkResponse(request: networkRequest, urlResponse: nil, result: .success(cachedValue)))
      return
    }
#endif

    let cacheKey: String? = try? networkRequest.constructedURL().normalizedCacheKey(commaSeparatedQueryKeys: networkRequest.cacheCommaSeparatedQueryKeys)
    if !skipCache, let cacheKey {
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
    }

    networkRequest.rateLimiterType.execute({
      NetworkLogger.requests.log("Requesting: \(urlRequest.url?.absoluteString ?? "")")
      URLSession.shared.dataTask(with: urlRequest, completionHandler: { data, urlResponse, error in
        if let urlResponse = urlResponse, urlResponse.isRateLimitExceeded, networkRequest.retryOnRateLimitExceedFailure, numberOfRetries < 10 {
          NetworkLogger.requests.log("Rate Limit Exceeded")
          networkRequest.rateLimiterType.informRateLimitHit()
          request(networkRequest, skipCache: skipCache, completion: completion, numberOfRetries: numberOfRetries.successor)
          return
        }

        if let nsError = error as? NSError, networkRequest.retryOnTimeoutFailure, nsError.code == -1001, numberOfRetries < 3 {
          NetworkLogger.requests.log("Rate Limit Exceeded")
          networkRequest.rateLimiterType.informRateLimitHit()
          request(networkRequest, skipCache: skipCache, completion: completion, numberOfRetries: numberOfRetries.successor)
          return
        }

        if let error, networkRequest.retryLimit > numberOfRetries {
          NetworkLogger.requests.log("Retrying request (\(numberOfRetries.successor)): \(urlRequest.url?.absoluteString ?? "")")
          request(networkRequest, skipCache: skipCache, completion: completion, numberOfRetries: numberOfRetries.successor)
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

          if let cacheKey, case .duration(let duration) = networkRequest.cacheType, let urlResponse, urlResponse.isSuccessful {
            try? Self.storage.setObject(data, forKey: cacheKey, expiry: .seconds(duration))
          }
        default:
          result = .failure(NetworkRequestError.noDataReceived)
        }
      }).resume()
    }, onQueue: .global(qos: .userInitiated))
  }

  public static func request(
    _ networkRequest: NetworkRequest,
    progress: @escaping (Double) -> Void
  ) async -> NetworkResponse<Data> {
    do {
      var urlRequest = try networkRequest.urlRequest()
      urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

      let (bytesStream, response) = try await URLSession.shared.bytes(for: urlRequest)

      guard let httpResponse = response as? HTTPURLResponse else {
        return .init(request: networkRequest, urlResponse: nil, result: .failure(NetworkRequestError.noDataReceived))
      }

      let expectedContentLength = httpResponse.expectedContentLength
      var downloadedData = Data()
      var totalBytesReceived: Int64 = 0
      var buffer = Data()
      let bufferSize = 65536 // 64KB chunks

      for try await byte in bytesStream {
        buffer.append(byte)
        totalBytesReceived += 1

        if buffer.count >= bufferSize {
          downloadedData.append(buffer)
          buffer.removeAll(keepingCapacity: true)

          if expectedContentLength > 0 {
            let progressValue = Double(totalBytesReceived) / Double(expectedContentLength)
            progress(progressValue)
          }
        }
      }

      if !buffer.isEmpty {
        downloadedData.append(buffer)
      }

      return .init(request: networkRequest, urlResponse: httpResponse, result: .success(downloadedData))
    } catch {
      return .init(request: networkRequest, urlResponse: nil, result: .failure(error))
    }
  }
}

extension URL {
  func normalizedCacheKey(commaSeparatedQueryKeys: Set<String>?) -> String {
    guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
          var items = components.queryItems else {
      return self.absoluteString
    }

    // Sort query parameters by name
    items.sort { $0.name < $1.name }

    // Normalize append_to_response specifically
    if let commaSeparatedQueryKeys, !commaSeparatedQueryKeys.isEmpty {
      for (idx, item) in items.enumerated() {
        guard commaSeparatedQueryKeys.contains(item.name), let value = item.value else { continue }
        let sortedList = value
          .split(separator: ",")
          .map(String.init)
          .sorted()
          .joined(separator: ",")

        items[idx] = URLQueryItem(name: item.name, value: sortedList)
      }
    }

    components.queryItems = items
    return components.string ?? absoluteString
  }
}
