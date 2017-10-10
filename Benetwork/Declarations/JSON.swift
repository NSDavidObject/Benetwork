//
//  JSON.swift
//  Benetwork
//
//  Created by David Elsonbaty on 10/9/17.
//

import Foundation

public enum JSON {
    case array(JSONArray)
    case dictionary(JSONDictionary)
    
    var value: Any {
        switch self {
        case .array(let array): return array
        case .dictionary(let dictionary): return dictionary
        }
    }
}
