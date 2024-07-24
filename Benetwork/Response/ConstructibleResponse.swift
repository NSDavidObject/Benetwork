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
  
  public func requestAndConstruct(withPostConstructionMiddlewares middlewares: [NetworkResponseMiddleware.Type] = [], completion: @escaping (NetworkResponse<ReturnType>) -> Void) {
    JSONRequest(completion: { jsonResponse in
      let constructedResult = jsonResponse.result.flatMap({ self.construct($0)  })
      let constructedResultResponse = jsonResponse.response(withResult: constructedResult)
      let interceptedConstructedResultResponse = middlewares.intercepting(constructedResultResponse)
      completion(interceptedConstructedResultResponse)
    })
  }
  
  public func requestAndConstructOnBackgroundQueue(withPostConstructionMiddlewares middlewares: [NetworkResponseMiddleware.Type] = [], callbackQueue: DispatchQueue = .main, completion: @escaping (NetworkResponse<ReturnType>) -> Void) {
    DispatchQueue.global().async {
      requestAndConstruct(withPostConstructionMiddlewares: middlewares, callbackQueue: callbackQueue, completion: completion)
    }
  }
  
  private func requestAndConstruct(withPostConstructionMiddlewares middlewares: [NetworkResponseMiddleware.Type] = [], callbackQueue: DispatchQueue?, completion: @escaping (NetworkResponse<ReturnType>) -> Void) {
    requestAndConstruct(withPostConstructionMiddlewares: middlewares, completion: { result in
      if let callbackQueue = callbackQueue {
        callbackQueue.async {
          completion(result)
        }
      } else {
        completion(result)
      }
    })
  }
  
  public func requestAndConstruct(withPostConstructionMiddlewares middlewares: [NetworkResponseMiddleware.Type] = []) async throws -> NetworkResponse<ReturnType> {
    try await withCheckedThrowingContinuation { continuation in
      requestAndConstruct(withPostConstructionMiddlewares: middlewares, callbackQueue: nil) { response in
        continuation.resume(returning: response)
      }
    }
  }
  
  public func requestAndConstructSuccessOrThrow(withPostConstructionMiddlewares middlewares: [NetworkResponseMiddleware.Type] = []) async throws -> ReturnType {
    let result = try await requestAndConstruct()
    switch result.result {
    case .success(let value): return value
    case .failure(let error): throw error
    }
  }
}
