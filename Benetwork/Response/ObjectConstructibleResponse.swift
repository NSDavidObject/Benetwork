//
//  ObjectConstructibleResponse.swift
//  Matterly
//
//  Created by David Elsonbaty on 9/24/17.
//  Copyright © 2017 Matterly. All rights reserved.
//

import Foundation

// MARK: Object Construction Error

enum ObjectConstructionError: Error {
    case unexpectedType
}

// MARK: Object Construction Response

protocol ObjectConstructibleResponse: ConstructibleResponse where ReturnType == ObjectType {}

// MARK: ObjectsArrayConstructibleResponse

protocol ObjectsArrayConstructibleResponse: ConstructibleResponse where ReturnType == [ObjectType] {}

extension ObjectsArrayConstructibleResponse {
    
    static func constructResponse(json: Any) throws -> [ObjectType] {
        guard let jsonArray = json as? [JSONDictionary] else { throw ObjectConstructionError.unexpectedType }
        return ObjectType.models(for: jsonArray)
    }
}

