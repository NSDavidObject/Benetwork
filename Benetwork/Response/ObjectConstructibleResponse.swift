import CommonUtilities

// MARK: Object Construction Error

public enum ObjectConstructionError: Error {
    case unexpectedType
}

// MARK: Object Construction Response

public protocol ObjectConstructibleResponse: ConstructibleResponse where ReturnType == ObjectType {}

// MARK: ObjectsArrayConstructibleResponse

public protocol ObjectsArrayConstructibleResponse: ConstructibleResponse where ReturnType == [ObjectType] {}

extension ObjectsArrayConstructibleResponse {
    
    public static func constructResponse(json: Any) throws -> [ObjectType] {
        guard let jsonArray = json as? [JSONDictionary] else { throw ObjectConstructionError.unexpectedType }
        return ObjectType.models(for: jsonArray)
    }
}

