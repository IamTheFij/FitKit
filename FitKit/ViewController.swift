//
//  ViewController.swift
//  FitKit
//
//  Created by Ian Fijolek on 1/6/18.
//  Copyright © 2018 iamthefij. All rights reserved.
//

import Alamofire
import HealthKit
import UIKit

class ViewController: UIViewController {
    
    @IBOutlet var loggedIn: UILabel!
    @IBOutlet var outputText: UITextView!
    let client = FitbitClient()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        updateAuthorizedLabel()
    }

    override func viewDidAppear(_ animated: Bool) {
        authorize()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    fileprivate func updateAuthorizedLabel() {
        if self.client.isAuthorized() {
            self.loggedIn.text = "Logged In"
        } else {
            self.loggedIn.text = "Not Logged In"
        }
    }

    fileprivate func authorize() {
        HealthKitHelper.authorizeHealthKit() {
            result, error in
            // TODO: Do something with the result and error
            if !self.client.isAuthorized() {
                self.client.authorize(viewController: self, success: self.authorized, failure: self.unauthroized)
            }
        }
    }

    fileprivate func authorized() {
        NSLog("We have Fitbit auth!!!")
        updateAuthorizedLabel()
        self.displayWeight()
    }
    
    fileprivate func unauthroized() {
        NSLog("No auth. Booo!!!")
    }

    func displayWeight() {
        let today = Date()
        let lastMonth = Calendar.current.date(byAdding: .day, value: -31, to: today)!
        self.client.getWeight(start: lastMonth, end: today) {
            response in FitbitClient.weightResponseHandler(response: response) {
                fbWeights, error in

                if let error = error {
                    NSLog("Unable to get weights: \(error)")
                    return
                }

                if let fbWeights = fbWeights {
                    for fbWeight in fbWeights {
                        NSLog("Got Weight: \(fbWeight.logId): \(fbWeight.date) \(fbWeight.weight)")
                        HealthKitHelper.maybeSaveSample(fbWeight, callback: {_,_ in})
                    }
                }
            }
        }
    }
}
