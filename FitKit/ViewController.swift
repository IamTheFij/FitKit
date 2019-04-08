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
    @IBOutlet var logInButton: UIBarButtonItem!
    let client = FitbitClient()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        updateAuthorizedLabel()
    }

    override func viewDidAppear(_ animated: Bool) {
        ensureAuthorized(callback: self.updateView)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    fileprivate func updateAuthorizedLabel() {
        DispatchQueue.main.async {
            if self.client.isAuthorized() {
                self.loggedIn.text = "Logged In"
                self.logInButton.title = "Log Out"
            } else {
                self.loggedIn.text = "Not Logged In"
                self.logInButton.title = "Log In"
            }
        }
    }

    @IBAction func logOut(_ sender: Any) {
        NSLog("Log out!!!")
        self.client.clearCredential()
        self.updateAuthorizedLabel()
    }
    @IBAction func syncNow(_ sender: Any) {
        NSLog("Sync button tapped")
        self.syncWeights()
    }
    /// Ensure that the client is authorized and then continue
    fileprivate func ensureAuthorized(callback: @escaping (Bool) -> Void) {
        // If already authroized, we can short circuit
        if self.client.isAuthorized() {
            callback(true)
            return
        }
        // Authorize the client
        self.client.authorize(viewController: self) {
            scope, error in
            if error != nil {
                NSLog("Error encountered when attempting authorization: \(error.debugDescription)")
            }
            guard let scope = scope else {
                NSLog("Did not retreive any authorized scope")
                callback(false)
                return
            }
            NSLog("Authorized for scope: \(scope). Requesting HealthKit access")
            HealthKitHelper.authorizeHealthKit() {
                result, error in
                // TODO: Enforce that access was provided or display an error
                NSLog("Error authing HealthKit: \(error.debugDescription)")
                callback(result)
            }
        }
    }

    fileprivate func updateView(authSuccess: Bool) {
        self.updateAuthorizedLabel()
        if authSuccess {
            self.syncWeights()
        } else {
            self.outputText.text = "Error connecting to Fitbit or authorizing"
        }
    }

    /// Synchronizes weights from Fitbit to HealthKit
    func syncWeights() {
        let today = Date()
        let lastMonth = Calendar.current.date(byAdding: .day, value: -31, to: today)!
        self.client.getWeight(start: lastMonth, end: today) {
            response in FitbitClient.weightResponseHandler(response: response) {
                fbWeights, error in
                if let error = error {
                    NSLog("Unable to get weights: \(error.localizedDescription)")
                    if let error = error as? AFError {
                        if let suggestion = error.recoverySuggestion {
                            NSLog("Suggestion to resolve: \(suggestion)")
                        }
                        if error.responseCode == 401 {
                            NSLog("Unauthorized. Clearing credentials")
                            self.client.clearCredential()
                        }
                    }
                    self.outputText.text = "Error getting weights"

                    return
                }

                if let fbWeights = fbWeights {
                    for fbWeight in fbWeights {
                        NSLog("Got Weight with ID: \(fbWeight.logId)")
                        HealthKitHelper.maybeSaveSample(fbWeight, callback: {_,_ in})
                    }
                    self.outputText.text = "Health data is synced"
                }
            }
        }
    }
}
