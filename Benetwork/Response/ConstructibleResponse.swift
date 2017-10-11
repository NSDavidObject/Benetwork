//
//  ConstructibleResponse.swift
//  Benetwork
//
//  Created by David Elsonbaty on 9/24/17.
//  Copyright © 2017 Benetwork. All rights reserved.
//

import Foundation

// MARK: Constructible Response

public protocol ConstructibleResponse {
    associatedtype ObjectType: JSONConstructible
    associatedtype ReturnType
    
    static func constructResponse(json: Any) throws -> ReturnType
}

extension ConstructibleResponse {
    
    public func construct(_ json: JSON) -> Result<ReturnType> {
        do {
            return try .success(Self.constructResponse(json: json.value))
        } catch let error {
            return .failure(error)
        }
    }

    public static func constructResponse(json: Any) throws -> ObjectType {
        guard let jsonDictionary = json as? JSONDictionary else { throw ObjectConstructionError.unexpectedType }
        return try ObjectType.init(json: jsonDictionary)
    }
}

extension ConstructibleResponse where Self: NetworkRequest {
    
    private func requestAndConstruct(withPostConstructionMiddlewares middlewares: [NetworkResponseMiddleware.Type], completion: @escaping (NetworkResponse<ReturnType>) -> Void) {
        JSONRequest(completion: { jsonResponse in
            let constructedResult = jsonResponse.result.flatMap({ self.construct($0)  })
            let constructedResultResponse = jsonResponse.response(withResult: constructedResult)
            let interceptedConstructedResultResponse = middlewares.intercepting(constructedResultResponse)
            completion(interceptedConstructedResultResponse)
        })
    }
    
    public func requestAndConstructOnBackgroundQueue(withPostConstructionMiddlewares middlewares: [NetworkResponseMiddleware.Type] = [], completion: @escaping (NetworkResponse<ReturnType>) -> Void) {
        DispatchQueue.global().async {
            self.requestAndConstruct(withPostConstructionMiddlewares: middlewares, completion: { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            })
        }
    }
}
