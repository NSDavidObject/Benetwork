//
//  NetworkRequest+Additions.swift
//  Benetwork
//
//  Created by David Elsonbaty on 10/10/17.
//

import Foundation

extension NetworkRequest {
    
    public static func jsonHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        headers["Accept"] = "application/json"
        headers["Content-Type"] = "application/json"
        return headers
    }
}
