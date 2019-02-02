import Foundation

public enum Result<A> {
    case success(A)
    case failure(Error)
    
    public var value: A? {
        switch self {
        case .success(let value): return value
        default: return nil
        }
    }
    
    public func map<B>(_ mapper: (A) -> B) -> Result<B> {
        switch self {
        case .success(let value): return .success(mapper(value))
        case .failure(let error): return .failure(error)
        }
    }
    
    public func flatMap<B>(_ mapper: ((A) -> Result<B>)) -> Result<B> {
        switch self {
        case .success(let value): return mapper(value)
        case .failure(let error): return .failure(error)
        }
    }
}

enum ResultError: Error {
    case message(String)
}

extension Result: Codable where A: Codable {

    private var rawValue: String {
        switch self {
        case .success: return CodingKeys.success.rawValue
        case .failure: return CodingKeys.failure.rawValue
        }
    }

    enum CodingKeys: String, CodingKey {
        case success
        case failure
        case rawValue
    }

    enum CodingError: Error {
        case unrecognizedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .rawValue)
        switch rawValue {
        case CodingKeys.success.rawValue:
            let success = try container.decode(A.self, forKey: .success)
            self = .success(success)
        case CodingKeys.failure.rawValue:
            let errorString = try container.decode(String.self, forKey: .failure)
            self = .failure(ResultError.message(errorString))
        default:
            throw CodingError.unrecognizedValue
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
        switch self {
        case .success(let object):
            try container.encode(object, forKey: .success)
        case .failure(let error):
            try container.encode(error.localizedDescription, forKey: .failure)
        }
    }
}
