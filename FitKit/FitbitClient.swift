//
//  Client.swift
//  FitKit
//
//  Created by Ian Fijolek on 1/6/18.
//  Copyright © 2018 iamthefij. All rights reserved.
//

import Foundation
import Alamofire
import OAuthSwift
import SwiftKeychainWrapper
import OAuthSwiftAlamofire

class FitbitClient {
    private enum FitKitRequestError: Error {
        case unableToParseResults
        case invalidAuthorization
    }

    private var oauthClient: OAuth2Swift
    private var consumerKey = "invalid-key"  // Set in Fitkit/Secrets.plist
    private var consumerSecret = "invalid-secret"  // Set in Fitkit/Secrets.plist
    private let callbackUrl = "fitkit://oauth-callback/fitbit"
    private let authorizeUrl = "https://www.fitbit.com/oauth2/authorize"
    private let accessTokenUrl = "https://api.fitbit.com/oauth2/token"
    private var keychainWrapper: KeychainWrapper
    private let keychainCredKey = "credential"
    
    init() {
        // Init inner client
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
            let secrets = NSDictionary(contentsOfFile: path),
            let fitbitCreds = secrets["Fitbit Credentials"] as? NSDictionary,
            let consumerKey = fitbitCreds["Consumer Key"] as? String,
            let consumerSecret = fitbitCreds["Consumer Secret"] as? String
        {
            self.consumerKey = consumerKey
            self.consumerSecret = consumerSecret
        }
        self.oauthClient = OAuth2Swift(
            consumerKey: self.consumerKey,
            consumerSecret: self.consumerSecret,
            authorizeUrl: self.authorizeUrl,
            accessTokenUrl: self.accessTokenUrl,
            responseType: "token"
        )
        
        // Set OAuth client to handle default sessions
        let sessionManager = SessionManager.default
        sessionManager.adapter = self.oauthClient.requestAdapter
        sessionManager.retrier = self.oauthClient.requestAdapter

        // Use standard KeychainWrapper
        self.keychainWrapper = KeychainWrapper.standard

        // Attempt to load tokens
        self.maybeLoadStoredCredential()
    }
    
    /// Attempts to load and use stored credentials
    func maybeLoadStoredCredential() {
        if let credential = self.readCredential() {
            NSLog("Using credential from Keychain")
            self.oauthClient.client.credential.oauthToken = credential.oauthToken
            self.oauthClient.client.credential.oauthTokenExpiresAt = credential.oauthTokenExpiresAt
        }
    }

    /// Attempts to read OAuthSwiftCredential from the keychain
    ///
    /// - Returns: If a valid credential is found, it will be returned
    func readCredential() -> OAuthSwiftCredential? {
        if let credential = self.keychainWrapper.object(forKey: keychainCredKey) as? OAuthSwiftCredential {
            NSLog("Found credential in keychain")
            return credential
        }
        NSLog("No credential found in keychain")
        return nil
    }

    /// Persists an OAuthSwiftCredential into the keychain
    ///
    /// - Parameter credential: credential to be persisted
    /// - Returns: TRUE if persisted successfully
    private func storeCredential(_ credential: OAuthSwiftCredential) -> Bool {
        return self.keychainWrapper.set(credential, forKey: keychainCredKey)
    }

    /// Clears credential token and expiration
    func clearCredential() {
        self.oauthClient.client.credential.oauthToken = ""
        self.oauthClient.client.credential.oauthTokenExpiresAt = nil
        self.keychainWrapper.removeObject(forKey: keychainCredKey)
    }

    /// Check if the current client is already authorized
    ///
    /// - Returns: True if the current client can make requests
    func isAuthorized() -> Bool {
        if self.oauthClient.client.credential.oauthToken != "" {
            if self.oauthClient.client.credential.isTokenExpired() {
                NSLog("Credentials are expired")
                return false
            }
            return true
        }
        
        // TODO: This should probably return true sometimes
        return false
    }
    
    /// Displays authorization screen for user in a Safari web view
    ///
    /// - Parameters:
    ///   - viewController: the source controller to create the new Safari view
    ///   - success: Callback to be executed on success
    ///   - failure: Callback to be executed on failure
    func authorize(viewController: UIViewController, callback: @escaping (String?, Error?) -> Void) {
        // Set webview handler
        self.oauthClient.authorizeURLHandler = SafariURLHandler(
            viewController: viewController,
            oauthSwift: self.oauthClient
        )

        // Authorize
        let _ = self.oauthClient.authorize(
            withCallbackURL: URL(string: self.callbackUrl)!,
            scope: "weight activity",
            state:"FITKIT", // TODO: make CSRF token
            success: {
                credential, response, parameters in
                // Verify state is consistent
                guard parameters["state"] as? String == "FITKIT",
                    let scope = parameters["scope"] as? String
                    else {
                        NSLog("Invalid authorization response")
                        callback(nil, FitKitRequestError.invalidAuthorization)
                        return
                }
                NSLog("Authorized scope: \(scope)")
                NSLog("Succesfully authenticated with credentials \(credential.oauthToken)")
                let _ = self.storeCredential(credential)
                callback(scope, nil)
            },
            failure: {
                error in
                NSLog("Error authorizing \(error.localizedDescription)")
                callback(nil, error)
            }
        )
    }
    
    /// Request all weight data from Fitbit API for the current user beteween
    /// two dates. Maximum allowed distance between the two dates is 31 days.
    ///
    /// - Parameters:
    ///   - start: initial date to search from
    ///   - end: last date to include in search
    ///   - handler: function to handle the response
    func getWeight(start: Date, end: Date, handler: @escaping (DataResponse<Any>) -> Void) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let urlString = "https://api.fitbit.com/1/user/-/body/log/weight/date/\(dateFormatter.string(from: start))/\(dateFormatter.string(from: end)).json"

        NSLog("Maing request to \(urlString)")


        Alamofire.request(urlString)
            .validate()
            .validate(contentType: ["application/json"])
            .responseJSON(completionHandler: handler)
    }

    /// Handler that parses responses from Fitbit Weight API and provides
    /// instances of FitbitWeight to a new callback.
    ///
    /// - Parameters:
    ///   - response: Original DataResponse<Any> from the Fitbit request
    ///   - callback: Callback that will accept a list of FitbitWeight instances
    ///     and an Error if, if present.
    class func weightResponseHandler(response: DataResponse<Any>, callback: @escaping ([FitbitWeight]?, Error?) -> Void) {
        NSLog("Handling weight response \(response.debugDescription)")

        guard response.result.isSuccess else {
            NSLog("Error while fetching weight: \(response.result.error!)")
            callback(nil, response.result.error)
            return
        }

        NSLog("Got weight! \(response.result.value!)")

        guard let results = response.result.value as? [String: Any] else {
            NSLog("Return result not in form [String: Any]")
            callback(nil, FitKitRequestError.unableToParseResults)
            return
        }

        guard let weights = results["weight"] as? [[String: Any]] else {
            NSLog("Return result does not contain a list of weights")
            callback(nil, FitKitRequestError.unableToParseResults)
            return
        }

        var fbWeights = [FitbitWeight]()
        for weight in weights {
            fbWeights.append(FitbitWeight(withResult: weight))
        }

        callback(fbWeights, nil)
    }
}
