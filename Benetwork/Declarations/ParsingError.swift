//
//  ParsingError.swift
//  Matterly
//
//  Created by David Elsonbaty on 8/29/17.
//  Copyright © 2017 Matterly. All rights reserved.
//

import Foundation

public enum ParsingError: Error {
    case unexpectedType
    case unexpectedValue
    case valueNotFound
}
