//
//  FixerLastestDataRequest.swift
//  BenetworkExample
//
//  Created by David Elsonbaty on 10/10/17.
//  Copyright © 2017 Benetwork. All rights reserved.
//

import Benetwork

struct FixerLatestDataRequest: FixerNetworkGetRequest, ObjectConstructibleResponse {
    typealias ObjectType = FixerLatestDataResponse

    var baseCurrency: Currency?
    var conversionCurrencies: [Currency]?
    
    var urlPath: String {
        return "latest"
    }
    
    var urlParameters: [String: CustomStringConvertible] {
        var urlParameters: [String: CustomStringConvertible] = [:]
        if let baseCurrency = baseCurrency {
            urlParameters["base"] = baseCurrency.abbreviation
        }
        if let conversionCurrencies = conversionCurrencies {
            urlParameters["symbols"] = conversionCurrenciesValue(for: conversionCurrencies)
        }
        return urlParameters
    }
    
    init(baseCurrency: Currency? = nil, conversionCurrencies: [Currency]? = nil) {
        self.baseCurrency = baseCurrency
        self.conversionCurrencies = conversionCurrencies
    }
}

extension FixerLatestDataRequest {
    
    func conversionCurrenciesValue(for currencies: [Currency]) -> String {
        var value: String = ""
        for currency in currencies {
            value += currency.abbreviation + ","
        }
        return value.trimmingCharacters(in: [","])
    }
}
