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

  // MARK: - Shared Helpers

  private static func prepareURLRequest(_ networkRequest: NetworkRequest) throws -> URLRequest {
    var urlRequest = try networkRequest.urlRequest()
    urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    return urlRequest
  }

  private static func shouldRetryForRateLimit(
    _ httpResponse: HTTPURLResponse,
    _ networkRequest: NetworkRequest,
    numberOfRetries: Int
  ) -> Bool {
    return httpResponse.isRateLimitExceeded && networkRequest.retryOnRateLimitExceedFailure && numberOfRetries < 10
  }

  private static func shouldRetryForTimeout(
    _ error: Error,
    _ networkRequest: NetworkRequest,
    numberOfRetries: Int
  ) -> Bool {
    if let nsError = error as? NSError, networkRequest.retryOnTimeoutFailure, nsError.code == -1001, numberOfRetries < 3 {
      return true
    }
    return false
  }

  private static func shouldRetryGeneric(
    _ networkRequest: NetworkRequest,
    numberOfRetries: Int
  ) -> Bool {
    return networkRequest.retryLimit > numberOfRetries
  }

  private static func streamToMemory(
    _ bytesStream: URLSession.AsyncBytes,
    expectedContentLength: Int64,
    progress: ((Double) -> Void)?
  ) async throws -> Data {
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

    return downloadedData
  }

  private static func streamToFile(
    _ bytesStream: URLSession.AsyncBytes,
    outputURL: URL,
    expectedContentLength: Int64,
    progress: ((Double) -> Void)?
  ) async throws -> Void {
    guard let outputStream = OutputStream(url: outputURL, append: false) else {
      throw NetworkRequestError.requestFailed(message: "Failed to create output stream")
    }
    outputStream.open()
    defer { outputStream.close() }

    var totalBytesReceived: Int64 = 0
    var buffer = Data()
    let bufferSize = 65536

    for try await byte in bytesStream {
      buffer.append(byte)
      totalBytesReceived += 1

      if buffer.count >= bufferSize {
        let written = buffer.withUnsafeBytes { ptr in
          outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: buffer.count)
        }
        if written < 0 {
          throw NetworkRequestError.requestFailed(message: "Failed to write to output file")
        }
        buffer.removeAll(keepingCapacity: true)

        if let progress, expectedContentLength > 0 {
          progress(Double(totalBytesReceived) / Double(expectedContentLength))
        }
      }
    }

    // Write remaining buffer
    if !buffer.isEmpty {
      let written = buffer.withUnsafeBytes { ptr in
        outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: buffer.count)
      }
      if written < 0 {
        throw NetworkRequestError.requestFailed(message: "Failed to write final buffer to output file")
      }
    }
  }

  // MARK: - Core Request Implementation

  private static func _performRequest(
    _ networkRequest: NetworkRequest,
    skipCache: Bool,
    numberOfRetries: Int? = nil,
    progress: ((Double) -> Void)? = nil
  ) async -> NetworkResponse<Data> {
    var urlRequest: URLRequest
    do {
      urlRequest = try prepareURLRequest(networkRequest)
    } catch {
      return .init(request: networkRequest, urlResponse: nil, result: .failure(error))
    }

    // Cache check
#if DEBUG
    if NetworkRequestsCacher.shared.isOn, let cachedValue = try? NetworkRequestsCacher.shared.data(for: urlRequest) {
      return NetworkResponse(request: networkRequest, urlResponse: nil, result: .success(cachedValue))
    }
#endif

    let cacheKey: String? = try? networkRequest.constructedURL().normalizedCacheKey(commaSeparatedQueryKeys: networkRequest.cacheCommaSeparatedQueryKeys)
    if !skipCache, let cacheKey, !cacheKey.contains("localhost"), let cachedValue = try? Self.storage.nonExpiredObjectById(cacheKey) {
      return .init(request: networkRequest, urlResponse: nil, result: .success(cachedValue))
    }

    #if DEBUG
    NetworkLogger.requests.log("Requesting: \(urlRequest.url!.absoluteString)")
    #endif

    let numberOfRetries = numberOfRetries ?? networkRequest.retryLimit
    do {
      let (bytesStream, response) = try await URLSession.shared.bytes(for: urlRequest)

      guard let httpResponse = response as? HTTPURLResponse else {
        return .init(request: networkRequest, urlResponse: nil, result: .failure(NetworkRequestError.noDataReceived))
      }

      // Handle rate limit
      if shouldRetryForRateLimit(httpResponse, networkRequest, numberOfRetries: numberOfRetries) {
        NetworkLogger.requests.log("Rate Limit Exceeded")
        networkRequest.rateLimiterType.informRateLimitHit()
        return await _performRequest(networkRequest, skipCache: skipCache, numberOfRetries: numberOfRetries + 1, progress: progress)
      }

      let downloadedData = try await streamToMemory(
        bytesStream,
        expectedContentLength: httpResponse.expectedContentLength,
        progress: progress
      )

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
      if shouldRetryForTimeout(error, networkRequest, numberOfRetries: numberOfRetries) {
        NetworkLogger.requests.log("Timeout, retrying")
        networkRequest.rateLimiterType.informRateLimitHit()
        return await _performRequest(networkRequest, skipCache: skipCache, numberOfRetries: numberOfRetries + 1, progress: progress)
      }

      if shouldRetryGeneric(networkRequest, numberOfRetries: numberOfRetries) {
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

  // MARK: - File Download API

  /// Downloads a network request directly to a file URL instead of loading into memory.
  /// This is ideal for large files (EPG XML, video files, etc.) to avoid memory spikes.
  /// - Parameters:
  ///   - networkRequest: The network request to download
  ///   - outputURL: The file URL where the downloaded data should be written
  ///   - numberOfRetries: Internal retry counter (do not pass manually)
  ///   - progress: Optional progress callback (0.0 to 1.0)
  /// - Returns: NetworkResponse with the output file URL and HTTPURLResponse
  public static func downloadToFile(
    _ networkRequest: NetworkRequest,
    outputURL: URL,
    numberOfRetries: Int? = nil,
    progress: ((Double) -> Void)? = nil
  ) async -> NetworkResponse<URL> {
    var urlRequest: URLRequest
    do {
      urlRequest = try prepareURLRequest(networkRequest)
    } catch {
      return .init(request: networkRequest, urlResponse: nil, result: .failure(error))
    }

    #if DEBUG
    NetworkLogger.requests.log("Downloading to file: \(urlRequest.url!.absoluteString)")
    #endif

    let numberOfRetries = numberOfRetries ?? networkRequest.retryLimit
    do {
      let (bytesStream, response) = try await URLSession.shared.bytes(for: urlRequest)

      guard let httpResponse = response as? HTTPURLResponse else {
        return .init(request: networkRequest, urlResponse: nil, result: .failure(NetworkRequestError.noDataReceived))
      }

      // Handle rate limit
      if shouldRetryForRateLimit(httpResponse, networkRequest, numberOfRetries: numberOfRetries) {
        NetworkLogger.requests.log("Rate Limit Exceeded")
        networkRequest.rateLimiterType.informRateLimitHit()
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        return await downloadToFile(networkRequest, outputURL: outputURL, numberOfRetries: numberOfRetries + 1, progress: progress)
      }

      try await streamToFile(
        bytesStream,
        outputURL: outputURL,
        expectedContentLength: httpResponse.expectedContentLength,
        progress: progress
      )

      networkRequest.rateLimiterType.informSuccessfulCompletion()

      return .init(request: networkRequest, urlResponse: httpResponse, result: .success(outputURL))
    } catch {
      if shouldRetryForTimeout(error, networkRequest, numberOfRetries: numberOfRetries) {
        NetworkLogger.requests.log("Timeout, retrying download")
        networkRequest.rateLimiterType.informRateLimitHit()
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        return await downloadToFile(networkRequest, outputURL: outputURL, numberOfRetries: numberOfRetries + 1, progress: progress)
      }

      if shouldRetryGeneric(networkRequest, numberOfRetries: numberOfRetries) {
        NetworkLogger.requests.log("Retrying download (\(numberOfRetries + 1)): \(urlRequest.url?.absoluteString ?? "")")
        return await downloadToFile(networkRequest, outputURL: outputURL, numberOfRetries: numberOfRetries + 1, progress: progress)
      }

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
