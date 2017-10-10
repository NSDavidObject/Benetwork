//
//  Dictionary+Additions.swift
//  Matterly
//
//  Created by David Elsonbaty on 8/29/17.
//  Copyright © 2017 Matterly. All rights reserved.
//

import Foundation

extension Dictionary {

    public func value<ExpectedType>(_ key: Key) -> ExpectedType? {
        return self[key] as? ExpectedType
    }
    
    public func enumValue<EnumType: RawRepresentable>(_ key: Key) -> EnumType? {
        guard let value = self[key] as? EnumType.RawValue else { return nil }
        return EnumType(rawValue: value)
    }
    
    public func enumArray<EnumType: RawRepresentable>(_ key: Key) -> [EnumType]? {
        guard let value = self[key] as? [EnumType.RawValue?] else { return nil }
        return value.flatMap { $0 }.flatMap { EnumType(rawValue: $0) }
    }

    public func boolean(_ key: Key) -> Bool? {
        guard let integer = integer(key) else { return nil }
        return Bool(integer != 0)
    }

    public func integer(_ key: Key) -> Int? {
        guard let value = self[key] else { return nil }
        if let intValue = value as? Int {
            return intValue
        } else if let stringValue = value as? String {
            guard let intValue = Int(stringValue) else { return nil }
            return intValue
        }
        return nil
    }

    public static func +(lhs: [Key: Value], rhs: [Key: Value]) -> [Key: Value] {
        var result = lhs
        for (key, value) in rhs {
            result[key] = value
        }
        return result
    }
}
