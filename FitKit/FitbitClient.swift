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
    }

    private var oauthClient: OAuth2Swift
    private let consumerKey = "22CPJ4"
    private let consumerSecret = "eb05e27f6aa224bcc1cf273119565b28"
    private let callbackUrl = "fitkit://oauth-callback/fitbit"
    private let authorizeUrl = "https://www.fitbit.com/oauth2/authorize"
    private let accessTokenUrl = "https://api.fitbit.com/oauth2/token"
    private var keychainWrapper: KeychainWrapper
    
    init() {
        // Init inner client
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
        self.loadStoredTokens()
    }
    
    func loadStoredTokens() {
        if let credential = self.readCredential() {
            NSLog("Using credential from Keychain")
            self.oauthClient.client.credential.oauthToken = credential.oauthToken
            self.oauthClient.client.credential.oauthTokenExpiresAt = credential.oauthTokenExpiresAt
        }
    }

    func readCredential() -> OAuthSwiftCredential? {
        if let credential = self.keychainWrapper.object(forKey: "credential") as? OAuthSwiftCredential {
            NSLog("Found credential in keychain")
            return credential
        }
        NSLog("No credential found in keychain")
        return nil
    }

    private func storeCredential(_ credential: OAuthSwiftCredential) -> Bool {
        return self.keychainWrapper.set(credential, forKey: "credential")
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
    func authorize(viewController: UIViewController, success: @escaping () -> Void, failure: @escaping () -> Void) {
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
                        failure()
                        return
                }
                NSLog("Authorized scope: \(scope)")
                NSLog("Succesfully authenticated with credentials \(credential.oauthToken)")
                let _ = self.storeCredential(credential)
                success()
            },
            failure: {
                error in
                // TODO: Maybe return the error
                NSLog(error.localizedDescription)
                failure()
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
