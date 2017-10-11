//
//  Optionals+Additions.swift
//  Benetwork
//
//  Created by David Elsonbaty on 8/29/17.
//  Copyright © 2017 Benetwork. All rights reserved.
//

import Foundation

extension Optional {

    public func required() throws -> Wrapped {
        guard let value = self.flatMap({ $0 }) else { throw ParsingError.valueNotFound }
        return value
    }
}
