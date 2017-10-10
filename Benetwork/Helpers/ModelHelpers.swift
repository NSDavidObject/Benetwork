//
//  ModelHelpers.swift
//  Matterly
//
//  Created by David Elsonbaty on 9/24/17.
//  Copyright © 2017 Matterly. All rights reserved.
//

import Foundation

// MARK: - Identification

public protocol Identifiable {
    associatedtype Identifier
}

// MARK: - Construction

public protocol JSONConstructible {
    init(json: JSONDictionary) throws
}

extension JSONConstructible {
    
    public static func models(for array: [JSONDictionary]) -> [Self] {
        return array.flatMap({ try? Self.init(json: $0) })
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
