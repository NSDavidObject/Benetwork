//
//  ViewController.swift
//  BenetworkExample
//
//  Created by David Elsonbaty on 10/10/17.
//  Copyright © 2017 Benetwork. All rights reserved.
//

import UIKit
import Benetwork

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
     
        let baseCurrency = Currency(abbreviation: "USD")
        let request = FixerLatestDataRequest(baseCurrency: baseCurrency)
        request.requestAndConstructOnBackgroundQueue { response in
            print(response.result.value as Any)
        }
    }
}

