//
//  JSONSerializer.swift
//  Matterly
//
//  Created by David Elsonbaty on 9/24/17.
//  Copyright © 2017 Matterly. All rights reserved.
//

import Foundation

public final class JSONSerializer {
    
    public enum JSONSerializationError: Error {
        case invalidType
    }
    
    public static func serialize(data: Data) -> Result<JSON> {
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            if let array = jsonObject as? JSONArray {
                return .success(.array(array))
            } else if let dictionary = jsonObject as? JSONDictionary {
                return .success(.dictionary(dictionary))
            } else {
                return .failure(JSONSerializationError.invalidType)
            }
        } catch let error {
            return .failure(error)
        }
    }
    
    public static func serializeDictionaryData(data: Data) -> Result<JSONDictionary> {
        return serialize(data: data).flatMap { castJSONToType(json: $0) }
    }
    
    public static func serializeArrayData(data: Data) -> Result<JSONArray> {
        return serialize(data: data).flatMap { castJSONToType(json: $0) }
    }
    
    private static func castJSONToType<T>(json: JSON) -> Result<T> {
        guard let castedValue = json.value as? T else { return .failure(JSONSerializationError.invalidType) }
        return .success(castedValue)
    }
}
