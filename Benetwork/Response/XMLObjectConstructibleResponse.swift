import XMLCoder
import Benetwork

extension NetworkRequest {
  
  public func requestAndConstructXMLSuccessOrThrow<T>(skipCache: Bool) async throws -> T where T: Codable {
    let data = try await NetworkHandler.requestAndThrowOnFailure(self, skipCache: skipCache)
    let decoder = XMLDecoder()
    decoder.shouldProcessNamespaces = true
    return try decoder.decode(T.self, from: data)
  }
}

public protocol XMLConstructableResponse {
  associatedtype ObjectType: Codable
  associatedtype ReturnType
}

// MARK: Object Construction Response

public protocol XMLObjectConstructibleResponse: XMLConstructableResponse where ReturnType == ObjectType {}

// MARK: ObjectsArrayConstructibleResponse

public protocol XMLObjectsArrayConstructibleResponse: XMLConstructableResponse where ReturnType == [ObjectType] {}

public extension XMLObjectConstructibleResponse where Self: NetworkRequest {
  func requestAndConstructSuccessOrThrow(skipCache: Bool) async throws -> ReturnType {
    return try await requestAndConstructXMLSuccessOrThrow(skipCache: skipCache)
  }
}
