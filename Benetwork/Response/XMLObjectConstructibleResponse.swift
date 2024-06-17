import XMLCoder
import Benetwork

extension NetworkRequest {
  
  public func requestAndConstructXMLSuccessOrThrow<T>() async throws -> T where T: Codable {
    let data = try await NetworkHandler.requestAndThrowOnFailure(self)
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
  func requestAndConstructSuccessOrThrow() async throws -> ReturnType {
    return try await requestAndConstructXMLSuccessOrThrow()
  }
}
