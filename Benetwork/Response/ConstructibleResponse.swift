import CommonUtilities

// MARK: Constructible Response

public protocol ConstructibleResponse {
  associatedtype ObjectType: JSONConstructible
  associatedtype ReturnType
  
  static func constructResponse(json: Any) throws -> ReturnType
}

extension ConstructibleResponse {
  
  public func construct(_ json: JSON) -> Result<ReturnType> {
    do {
      return try .success(Self.constructResponse(json: json.value))
    } catch let error {
      return .failure(error)
    }
  }
  
  public static func constructResponse(json: Any) throws -> ObjectType {
    guard let jsonDictionary = json as? JSONDictionary else { throw ObjectConstructionError.unexpectedType }
    return try ObjectType.init(json: jsonDictionary)
  }
}

extension ConstructibleResponse where Self: NetworkRequest {
  
  public func requestAndConstruct(withPostConstructionMiddlewares middlewares: [NetworkResponseMiddleware.Type] = [], skipCache: Bool = false, completion: @escaping (NetworkResponse<ReturnType>) -> Void) {
    JSONRequest(skipCache: skipCache, completion: { jsonResponse in
      let constructedResult = jsonResponse.result.flatMap({ self.construct($0)  })
      let constructedResultResponse = jsonResponse.response(withResult: constructedResult)
      let interceptedConstructedResultResponse = middlewares.intercepting(constructedResultResponse)
      completion(interceptedConstructedResultResponse)
    })
  }
  
  public func requestAndConstructOnBackgroundQueue(withPostConstructionMiddlewares middlewares: [NetworkResponseMiddleware.Type] = [], skipCache: Bool = false, callbackQueue: DispatchQueue = .main, completion: @escaping (NetworkResponse<ReturnType>) -> Void) {
    DispatchQueue.global().async {
      requestAndConstruct(withPostConstructionMiddlewares: middlewares, callbackQueue: callbackQueue, skipCache: skipCache, completion: completion)
    }
  }
  
  private func requestAndConstruct(withPostConstructionMiddlewares middlewares: [NetworkResponseMiddleware.Type] = [], callbackQueue: DispatchQueue?, skipCache: Bool, completion: @escaping (NetworkResponse<ReturnType>) -> Void) {
    requestAndConstruct(withPostConstructionMiddlewares: middlewares, skipCache: skipCache, completion: { result in
      if let callbackQueue = callbackQueue {
        callbackQueue.async {
          completion(result)
        }
      } else {
        completion(result)
      }
    })
  }
  
  public func requestAndConstruct(withPostConstructionMiddlewares middlewares: [NetworkResponseMiddleware.Type] = [], skipCache: Bool = false) async throws -> NetworkResponse<ReturnType> {
    try await withCheckedThrowingContinuation { continuation in
      requestAndConstruct(withPostConstructionMiddlewares: middlewares, callbackQueue: nil, skipCache: skipCache) { response in
        continuation.resume(returning: response)
      }
    }
  }
  
  public func requestAndConstructSuccessOrThrow(
    withPostConstructionMiddlewares middlewares: [NetworkResponseMiddleware.Type] = [],
    skipCache: Bool = false,
    progress: ((Double) -> Void)? = nil
  ) async throws -> ReturnType {
    // Step 1: Get raw data response
    let urlDataResponse = try await NetworkHandler.request(self, skipCache: skipCache, progress: progress)
    let request = urlDataResponse.request
    let urlResponse = urlDataResponse.urlResponse

    // Step 2: Serialize to JSON and immediately release Data
    let jsonResult: Result<JSON>
    switch urlDataResponse.result {
    case .success(let data):
      jsonResult = JSONSerializer.serialize(data: data)
      // data is released after this scope
    case .failure(let error):
      jsonResult = .failure(error)
    }

    // Step 3: Construct object and immediately release JSON
    let constructedResult: Result<ReturnType>
    switch jsonResult {
    case .success(let json):
      constructedResult = self.construct(json)
      // json is released after this scope
    case .failure(let error):
      constructedResult = .failure(error)
    }

    // Step 4: Apply middlewares and return
    let constructedResultResponse = NetworkResponse(request: request, urlResponse: urlResponse, result: constructedResult)
    let interceptedConstructedResultResponse = middlewares.intercepting(constructedResultResponse)

    switch interceptedConstructedResultResponse.result {
    case .success(let value): return value
    case .failure(let error): throw error
    }
  }
}
