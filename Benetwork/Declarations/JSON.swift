import CommonUtilities

public enum JSON {
    case array(JSONArray)
    case dictionary(JSONDictionary)
    
    public var value: Any {
        switch self {
        case .array(let array): return array
        case .dictionary(let dictionary): return dictionary
        }
    }
}
