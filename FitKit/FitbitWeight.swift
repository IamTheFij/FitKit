//
//  FitbitWeight.swift
//  FitKit
//
//  Created by Ian Fijolek on 1/14/18.
//  Copyright © 2018 iamthefij. All rights reserved.
//

import Foundation
import HealthKit

/// FitSample is a generic protocol that represents a datum from the Fitbit API
protocol FitSample {
    /// The integer ID from Fitbit for the given sample
    var logId: Int { get }
    /// The Fitbit source device
    var source: String { get }
    /// The date that this sample was taken
    var date: Date { get }

    /// Creates a HealthKit Sample from the Fitbit object
    ///
    /// - Returns: New HKSample instance that can be added to HealthKit
    func makeSample() -> HKSample

    /// Generates a metadata dictionary to be stored in HealthKit
    ///
    /// - Returns: Map of custom metadata keys to their values
    func metadata() -> [String: Any]

    /// Returns the HKSampleType for the FitSample for querying or creating of
    /// new instances.
    ///
    /// - Returns: <#return value description#>
    func getSampleType() -> HKSampleType

    /// Returns a predicate that can be used to retrieve this instance from
    /// HealthKit, if it has been added.
    ///
    /// - Returns: A new NSPredicate that can filter results of an HKSampleQuery
    func getPredicate() -> NSPredicate
}

// MARK: - Extension FitSample to return a metdata dictionary
extension FitSample {
    /// Returns default set of metadata for a FitSample
    ///
    /// - Returns: dictionary including the Fitbit source and Id
    func metadata() -> [String: Any] {
        return [
            "Fitbit Source": self.source,
            "Fitbit Id": self.logId
        ]
    }

    /// Returns predicate filtering results based on the "Fitbit Id" metadata
    ///
    /// - Returns: A new NSPredicate that should return an equivalent sample
    ///            from HealthKit
    func getPredicate() -> NSPredicate {
        return HKQuery.predicateForObjects(
            withMetadataKey: "Fitbit Id",
            operatorType: .equalTo,
            value: self.logId
        )
    }
}

/// FitbitWeight is a concrete subclass of FitSample. It represents a weigh
/// measurement retrieved from the Fitbit
class FitbitWeight: FitSample {
    var weight: Double
    var bmi: Double
    var logId: Int
    var source: String
    var date: Date

    /// Convenience initializer to create a FitbitWeight based on a response
    /// from the api
    ///
    /// - Parameter result: [String: Any?] dictionary response from the API
    convenience init(withResult result: [String: Any?]) {
        // TODO: Probably unsafe, but Swift...
        NSLog("Trying to initialize \(result)")
        let dateStringFormatter = DateFormatter()
        dateStringFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = result["date"] as! String
        let timeString = result["time"] as! String
        let weighDate = dateStringFormatter.date(from: "\(dateString) \(timeString)")!
        self.init(
            withWeight: result["weight"] as! Double,
            withBMI: result["bmi"] as! Double,
            withDate: weighDate,
            withLogId: result["logId"] as! Int,
            withSource: result["source"] as! String
        )
    }

    /// Initializes a FitbitWeight with specified properties
    ///
    /// - Parameters:
    ///   - weight: Double weight value in kg
    ///   - bmi: Double bmi value (Might go away)
    ///   - date: Date that the measurement was taken
    ///   - logId: Int ID from Fitbit
    ///   - source: String source name from Fitbit
    init(withWeight weight: Double, withBMI bmi: Double, withDate date: Date, withLogId logId: Int, withSource source: String) {
        self.weight = weight
        self.bmi = bmi
        self.date = date
        self.logId = logId
        self.source = source
    }

    func getSampleType() -> HKSampleType {
        // Forcing as we should be handling permissions
        return HKObjectType.quantityType(forIdentifier: .bodyMass)!
    }

    func makeSample() -> HKSample {
        let weight = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: self.weight)
        return HKQuantitySample(
            // Forcing downcast since each concrete class implementation should provide compatible types
            type: self.getSampleType() as! HKQuantityType,
            quantity: weight,
            start: self.date,
            end: self.date,
            metadata: self.metadata()
        )
    }
}
