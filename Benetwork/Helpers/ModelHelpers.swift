import CommonUtilities

// MARK: - Construction

public protocol JSONConstructible {
    init(json: JSONDictionary) throws
}

extension JSONConstructible {
    
    public static func models(for array: [JSONDictionary]) -> [Self] {
        return array.compactMap({ try? Self.init(json: $0) })
    }
}

public protocol EnumJSONConstrucible: JSONConstructible {
    static func value(fromJSON json: JSONDictionary) throws -> Self
}

extension EnumJSONConstrucible {
    
    public init(json: JSONDictionary) throws {
        self = try Self.value(fromJSON: json)
    }
}

// MARK: - Disassembly

public protocol JSONDisassembler {
    func disassembledJSON() -> JSONDictionary
}

extension Collection where Element: JSONDisassembler {

    public func disassembledJSON() -> [JSONDictionary] {
        return map({ $0.disassembledJSON() })
    }
}
