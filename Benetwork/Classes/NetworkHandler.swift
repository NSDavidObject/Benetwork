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

  public static func requestAndThrowOnFailure(_ networkRequest: NetworkRequest, skipCache: Bool = false) async throws -> Data {
    let response = await request(networkRequest, skipCache: skipCache)
    switch response.result {
    case .failure(let error):
      throw error
    case .success(let data):
      return data
    }
  }

  private static func requestInternal(
    _ networkRequest: NetworkRequest,
    skipCache: Bool,
    numberOfRetries: Int? = nil,
    progress: ((Double) -> Void)? = nil
  ) async -> NetworkResponse<Data> {
    return await withCheckedContinuation { continuation in
      networkRequest.rateLimiterType.execute({
        Task {
          let response = await _performRequest(networkRequest, skipCache: skipCache, numberOfRetries: numberOfRetries, progress: progress)
          continuation.resume(returning: response)
        }
      }, onQueue: .global(qos: .userInitiated))
    }
  }

  private static func _performRequest(
    _ networkRequest: NetworkRequest,
    skipCache: Bool,
    numberOfRetries: Int? = nil,
    progress: ((Double) -> Void)? = nil
  ) async -> NetworkResponse<Data> {
    var urlRequest: URLRequest
    do {
      urlRequest = try networkRequest.urlRequest()
    } catch {
      return .init(request: networkRequest, urlResponse: nil, result: .failure(error))
    }

    urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

    // Cache check
#if DEBUG
    if NetworkRequestsCacher.shared.isOn, let cachedValue = try? NetworkRequestsCacher.shared.data(for: urlRequest) {
      return NetworkResponse(request: networkRequest, urlResponse: nil, result: .success(cachedValue))
    }
#endif

    let cacheKey: String? = try? networkRequest.constructedURL().normalizedCacheKey(commaSeparatedQueryKeys: networkRequest.cacheCommaSeparatedQueryKeys)
    if !skipCache, let cacheKey {
      if let cachedValue = try? Self.storage.nonExpiredObjectById(cacheKey), !cacheKey.contains("localhost") {
        return .init(request: networkRequest, urlResponse: nil, result: .success(cachedValue))
      }
    }

    let numberOfRetries = numberOfRetries ?? networkRequest.retryLimit
    do {
      let (bytesStream, response) = try await URLSession.shared.bytes(for: urlRequest)

      guard let httpResponse = response as? HTTPURLResponse else {
        return .init(request: networkRequest, urlResponse: nil, result: .failure(NetworkRequestError.noDataReceived))
      }

      // Handle rate limit
      if httpResponse.isRateLimitExceeded, networkRequest.retryOnRateLimitExceedFailure, numberOfRetries < 10 {
        NetworkLogger.requests.log("Rate Limit Exceeded")
        networkRequest.rateLimiterType.informRateLimitHit()
        return await _performRequest(networkRequest, skipCache: skipCache, numberOfRetries: numberOfRetries + 1, progress: progress)
      }

      let expectedContentLength = httpResponse.expectedContentLength
      var downloadedData = Data()
      var totalBytesReceived: Int64 = 0
      var buffer = Data()
      let bufferSize = 65536

      for try await byte in bytesStream {
        buffer.append(byte)
        totalBytesReceived += 1

        if buffer.count >= bufferSize {
          downloadedData.append(buffer)
          buffer.removeAll(keepingCapacity: true)

          if let progress, expectedContentLength > 0 {
            progress(Double(totalBytesReceived) / Double(expectedContentLength))
          }
        }
      }

      if !buffer.isEmpty {
        downloadedData.append(buffer)
      }

      networkRequest.rateLimiterType.informSuccessfulCompletion()

      // Cache successful response
#if DEBUG
      if NetworkRequestsCacher.shared.isOn {
        Task(priority: .low) {
          NetworkRequestsCacher.shared.cache(urlRequest: urlRequest, data: downloadedData)
        }
      }
#endif

      if let cacheKey, case .duration(let duration) = networkRequest.cacheType, httpResponse.isSuccessful {
        try? Self.storage.setObject(downloadedData, forKey: cacheKey, expiry: .seconds(duration))
      }

      return .init(request: networkRequest, urlResponse: httpResponse, result: .success(downloadedData))
    } catch {
      if let nsError = error as? NSError, networkRequest.retryOnTimeoutFailure, nsError.code == -1001, numberOfRetries < 3 {
        NetworkLogger.requests.log("Timeout, retrying")
        networkRequest.rateLimiterType.informRateLimitHit()
        return await _performRequest(networkRequest, skipCache: skipCache, numberOfRetries: numberOfRetries + 1, progress: progress)
      }

      if networkRequest.retryLimit > numberOfRetries {
        NetworkLogger.requests.log("Retrying request (\(numberOfRetries + 1)): \(urlRequest.url?.absoluteString ?? "")")
        return await _performRequest(networkRequest, skipCache: skipCache, numberOfRetries: numberOfRetries + 1, progress: progress)
      }

      return .init(request: networkRequest, urlResponse: nil, result: .failure(error))
    }
  }

  // Async public API
  public static func request(
    _ networkRequest: NetworkRequest,
    skipCache: Bool = false,
    progress: ((Double) -> Void)? = nil
  ) async -> NetworkResponse<Data> {
    await requestInternal(networkRequest, skipCache: skipCache, numberOfRetries: nil, progress: progress)
  }

  // Completion-based wrapper
  public static func request(
    _ networkRequest: NetworkRequest,
    skipCache: Bool = false,
    progress: ((Double) -> Void)? = nil,
    completion: @escaping (NetworkResponse<Data>) -> Void,
  ) {
    Task {
      let response = await request(networkRequest, skipCache: skipCache, progress: progress)
      completion(response)
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
