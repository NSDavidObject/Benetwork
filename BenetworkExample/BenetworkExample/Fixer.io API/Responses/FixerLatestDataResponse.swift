//
//  FixerLatestDataResponse.swift
//  BenetworkExample
//
//  Created by David Elsonbaty on 10/10/17.
//  Copyright © 2017 Benetwork. All rights reserved.
//

import Benetwork

struct FixerLatestDataResponse: JSONConstructible {
    
    let baseCurrency: Currency
    let currencyConversions: [CurrencyConversion]
    init(json: JSONDictionary) throws {
        let baseCurrencyAbbreviation: String = try json.value("base").required()
        let baseCurrency = Currency(abbreviation: baseCurrencyAbbreviation)
        let rates: [String: Double] = try json.value("rates").required()
        let currencyConversions: [CurrencyConversion] = rates.map { rateData -> CurrencyConversion in
            let conversionCurrencyAbbreviation = rateData.key
            let conversionCurrency = Currency(abbreviation: conversionCurrencyAbbreviation)
            let conversionRate = rateData.value
            return CurrencyConversion(baseCurrency: baseCurrency, conversionCurrency: conversionCurrency, conversionRate: conversionRate)
        }
        self.baseCurrency = baseCurrency
        self.currencyConversions = currencyConversions
    }
}
