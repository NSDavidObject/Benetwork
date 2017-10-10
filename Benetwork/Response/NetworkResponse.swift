//
//  NetworkResponse.swift
//  Matterly
//
//  Created by David Elsonbaty on 10/7/17.
//  Copyright © 2017 Matterly. All rights reserved.
//

import Foundation

public struct NetworkResponse<T> {
    
    public let request: NetworkRequest
    public let urlResponse: URLResponse?
    public let result: Result<T>
    
    public func response<N>(withResult newResult: Result<N>) -> NetworkResponse<N> {
        return NetworkResponse<N>(request: request, urlResponse: urlResponse, result: newResult)
    }
}
