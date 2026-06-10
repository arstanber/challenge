import Foundation
import HealthKit

/// Reads Apple Health / Apple Fitness data (steps, energy, exercise minutes, distance).
/// Read-only. Requires the HealthKit capability + `NSHealthShareUsageDescription`.
final class HealthKitConnector {
    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.distanceWalkingRunning)
        ]
    }

    /// Presents the system Health permission sheet.
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw ConnectorError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Sum of the metric from midnight until now.
    func todayValue(_ metric: ConnectorMetric) async throws -> Double {
        let type: HKQuantityType
        let unit: HKUnit
        switch metric {
        case .steps:           type = HKQuantityType(.stepCount);              unit = .count()
        case .activeEnergy:    type = HKQuantityType(.activeEnergyBurned);     unit = .kilocalorie()
        case .exerciseMinutes: type = HKQuantityType(.appleExerciseTime);      unit = .minute()
        case .distance:        type = HKQuantityType(.distanceWalkingRunning); unit = .meter()
        }

        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
