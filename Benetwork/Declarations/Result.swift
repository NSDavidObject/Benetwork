//
//  Result.swift
//  Benetwork
//
//  Created by David Elsonbaty on 9/24/17.
//  Copyright © 2017 Benetwork. All rights reserved.
//

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
