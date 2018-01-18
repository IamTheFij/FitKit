//
//  HealthKitHelper.swift
//  FitKit
//
//  Created by Ian Fijolek on 1/14/18.
//  Copyright © 2018 iamthefij. All rights reserved.
//

import Foundation
import HealthKit

/// Helper class with class functions to simplify interraction with HealthKit
class HealthKitHelper {
    private enum HealthKitSetupError: Error {
        case hkUnavailable
        case dataTypeUnavailable
    }
    private enum FitKitSaveError: Error {
        case sampleAlreadyExists
    }

    /// Attempts to authorize the application with HealthKit
    /// If HealthKit is unavailable or access is not provided to the requested
    /// types, an error will be passed into the callback.
    ///
    /// - Parameter callback: Callback function for handling missing or unprovided
    ///     access.
    class func authorizeHealthKit(_ callback: @escaping (Bool, Error?) -> Void) {
        // Verify Health data is available
        guard HKHealthStore.isHealthDataAvailable() else {
            callback(false, HealthKitSetupError.hkUnavailable)
            return
        }

        // This is not very well abstracted yet
        guard let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            callback(false, HealthKitSetupError.dataTypeUnavailable)
            return
        }

        // Request access to the specified metrics
        HKHealthStore().requestAuthorization(
            toShare: [bodyMass],
            read: [bodyMass],
            completion: callback
        )
    }

    /// Simplifies querying for HealthKit samples given types and predicates.
    /// This is executed async and will dispatch the callback on the main thread
    ///
    /// - Parameters:
    ///   - sampleType: The HKSampleType that you wish to query
    ///   - predicate: An NSPredicate to use in the query
    ///   - limit: Return a limited number of samples
    ///   - callback: Callback to be executed on the main thread
    class func querySamplesWithPredicate(
        for sampleType: HKSampleType,
        withPredicate predicate: NSPredicate,
        limit: Int,
        callback: @escaping ([HKQuantitySample]?, Error?) -> Void)
    {
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        let sampleQuery = HKSampleQuery(
            sampleType: sampleType,
            predicate: predicate,
            limit: limit,
            sortDescriptors: [sortDescriptor]
        ) {
            (query, samples, error) in

            DispatchQueue.main.async {
                guard let samples = samples as? [HKQuantitySample] else {
                    callback(nil, error)
                    return
                }
                callback(samples, error)
                return
            }
        }

        HKHealthStore().execute(sampleQuery)
    }

    /// Provides easy query for the most recent sample of a given type
    ///
    /// - Parameters:
    ///   - sampleType: The HKSampleType that you wish to query
    ///   - callback: Callback to be executed on the main thread
    class func queryMostRecentSample(for sampleType: HKSampleType, callback: @escaping (HKQuantitySample?, Error?) -> Void) {
        let mostRecentPredicate = HKQuery.predicateForSamples(
            withStart: Date.distantPast,
            end: Date(),
            options: .strictStartDate
        )
        self.querySamplesWithPredicate(for: sampleType, withPredicate: mostRecentPredicate, limit: 1) {
            samples, error in
            guard let sample = samples?.first else {
                callback(nil, error)
                return
            }
            callback(sample, nil)
            return
        }
    }

    /// Simple query for a HealthKit sample of a given type and Fitbit Id
    ///
    /// - Parameters:
    ///   - sampleType: The HKSampleType that you wish to query
    ///   - logId: The Fitbit logId to be queried for (FitSample.logId)
    ///   - callback: Callback to be executed on the main thread
    class func getSampleWithFitbitId(for sampleType: HKSampleType, withId logId: Int, callback: @escaping (HKQuantitySample?, Error?) -> Void) {
        let logIdEquals = HKQuery.predicateForObjects(withMetadataKey: "Fitbit Id", operatorType: .equalTo, value: logId)
        self.querySamplesWithPredicate(for: sampleType, withPredicate: logIdEquals, limit: 1) {
            samples, error in
            guard let sample = samples?.first else {
                callback(nil, error)
                return
            }
            callback(sample, nil)
            return
        }
    }

    /// Simple query for a HealthKit for a given FitSample
    ///
    /// - Parameters:
    ///   - fitSample: The FitSample that you wish to query for in HealthKit
    ///   - callback: Callback to be executed on the main thread
    class func querySample(for fitSample: FitSample, callback: @escaping (HKQuantitySample?, Error?) -> Void) {
        self.querySamplesWithPredicate(
            for: fitSample.getSampleType(),
            withPredicate: fitSample.getPredicate(),
            limit: 1
        ) {
            samples, error in
            guard let sample = samples?.first else {
                callback(nil, error)
                return
            }
            callback(sample, nil)
            return
        }
    }

    /// Save a FitSample to HealthKit
    ///
    /// - Parameters:
    ///   - sample: FitSample instance to save
    ///   - callback: Callback function that will accept the completion from
    ///     HealthKit
    class func saveFitSample(_ sample: FitSample, callback: @escaping (Bool, Error?) -> Void) {
        HKHealthStore().save(sample.makeSample(), withCompletion: callback)
    }

    /// Idempotent save of a FitSample to HealthKit. Before saving, executes an
    /// async query for the sample in HealthKit. If found, it will not save.
    ///
    /// - Parameters:
    ///   - sample: FitSample instance to save
    ///   - callback: Callback funciton that accepts parameters indicating a
    ///     success or failure and any error that is returned. In the case of an
    ///     existing sample, it will be designated a success, but there it will
    ///     also return a FitKitSaveError.sampleAlreadyExists error.
    class func maybeSaveSample(_ sample: FitSample, callback: @escaping (Bool, Error?) -> Void) {
        self.querySample(for: sample) {
            (existingSample, error) in
            if let error = error {
                NSLog("Error querying for sample")
                callback(false, error)
                return
            }
            if existingSample == nil {
                // Save only if no existing sample was found
                self.saveFitSample(sample) {
                    (success, error) in
                    if let error = error {
                        NSLog("Error Saving Sample: \(error.localizedDescription)")
                        callback(false, error)
                        return
                    } else {
                        NSLog("Successfully saved Sample")
                        callback(true, nil)
                        return
                    }
                }
            } else {
                NSLog("Sample already found in HealthKit. Will not save")
                callback(true, FitKitSaveError.sampleAlreadyExists)
                return
            }
        }
    }
}
