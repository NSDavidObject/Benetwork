//
//  FixerNetworkRequest.swift
//  BenetworkExample
//
//  Created by David Elsonbaty on 10/10/17.
//  Copyright © 2017 Benetwork. All rights reserved.
//

import Benetwork

protocol FixerNetworkRequest: Benetwork.NetworkRequest {}
extension FixerNetworkRequest {
    
    var urlBase: String {
        return FixerAPIConstants.baseURL
    }
    
    var headers: [String: String] {
        return Self.jsonHeaders()
    }
}
