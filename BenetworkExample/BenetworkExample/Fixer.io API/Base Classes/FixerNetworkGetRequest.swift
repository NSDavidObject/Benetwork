//
//  FixerNetworkGetRequest.swift
//  BenetworkExample
//
//  Created by David Elsonbaty on 10/10/17.
//  Copyright © 2017 Matterly. All rights reserved.
//

import Benetwork

protocol FixerNetworkGetRequest: FixerNetworkRequest {}
extension FixerNetworkGetRequest {
    
    var method: NetworkMethod {
        return .get
    }
}
