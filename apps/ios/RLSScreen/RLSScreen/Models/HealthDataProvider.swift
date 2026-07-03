import Foundation
import HealthKit

struct HealthDataImportResult: Equatable {
    var form: ScreeningForm
    var importedFieldNames: [String]
    var missingFieldNames: [String]
}

protocol HealthDataProvider {
    func requestAuthorization() async throws
    func latestScreeningForm(current: ScreeningForm) async throws -> HealthDataImportResult
}

struct ManualOnlyHealthDataProvider: HealthDataProvider {
    func requestAuthorization() async throws {}

    func latestScreeningForm(current: ScreeningForm) async throws -> HealthDataImportResult {
        HealthDataImportResult(form: current, importedFieldNames: [], missingFieldNames: [])
    }
}

enum HealthDataProviderError: LocalizedError {
    case unavailable
    case missingReadableData

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Health data is not available on this device."
        case .missingReadableData:
            return "No readable Health data was found. You can keep using manual inputs."
        }
    }
}

final class HealthKitDataProvider: HealthDataProvider {
    private let healthStore = HKHealthStore()
    private let calendar = Calendar.current

    private var sleepType: HKCategoryType {
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            sleepType,
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)!,
        ]

        [
            HKQuantityTypeIdentifier.heartRate,
            .restingHeartRate,
            .height,
            .bodyMass,
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }
            .forEach { types.insert($0) }

        return types
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataProviderError.unavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthDataProviderError.unavailable)
                }
            }
        }
    }

    func latestScreeningForm(current: ScreeningForm) async throws -> HealthDataImportResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataProviderError.unavailable
        }

        var form = current
        var imported: [String] = []
        var missing: [String] = []

        if let sleep = try await latestSleepSummary() {
            form.sleepDurationMinutes = sleep.sleepDurationMinutes
            imported.append("Sleep duration")
            if let efficiency = sleep.sleepEfficiency {
                form.sleepEfficiency = efficiency
                imported.append("Sleep efficiency")
            } else {
                missing.append("Sleep efficiency")
            }
        } else {
            missing.append("Sleep")
        }

        if let restingHeartRate = try await latestQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute()), lookbackDays: 30) {
            form.restingHeartRate = restingHeartRate
            imported.append("Resting heart rate")
        } else {
            missing.append("Resting heart rate")
        }

        if let meanHeartRate = try await averageQuantity(.heartRate, unit: .count().unitDivided(by: .minute()), lookbackHours: 24) {
            form.meanHeartRate = meanHeartRate
            imported.append("Mean heart rate")
        } else {
            missing.append("Mean heart rate")
        }

        if let age = try? ageInYears() {
            form.age = age
            imported.append("Age")
        } else {
            missing.append("Age")
        }

        if let sex = try? biologicalSex() {
            form.sex = sex
            imported.append("Sex")
        } else {
            missing.append("Sex")
        }

        if let heightCm = try await latestQuantity(.height, unit: .meterUnit(with: .centi), lookbackDays: 3650) {
            form.heightCm = heightCm
            imported.append("Height")
        } else {
            missing.append("Height")
        }

        if let weightKg = try await latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo), lookbackDays: 3650) {
            form.weightKg = weightKg
            imported.append("Weight")
        } else {
            missing.append("Weight")
        }

        guard !imported.isEmpty else {
            throw HealthDataProviderError.missingReadableData
        }

        return HealthDataImportResult(form: form, importedFieldNames: imported, missingFieldNames: missing)
    }

    private func ageInYears() throws -> Double? {
        let components = try healthStore.dateOfBirthComponents()
        guard let birthday = calendar.date(from: components) else {
            return nil
        }
        return Double(calendar.dateComponents([.year], from: birthday, to: Date()).year ?? 0)
    }

    private func biologicalSex() throws -> String? {
        switch try healthStore.biologicalSex().biologicalSex {
        case .female:
            return "female"
        case .male:
            return "male"
        default:
            return nil
        }
    }

    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, lookbackDays: Int) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let end = Date()
        let start = calendar.date(byAdding: .day, value: -lookbackDays, to: end) ?? end.addingTimeInterval(-Double(lookbackDays) * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func averageQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, lookbackHours: Int) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let end = Date()
        let start = end.addingTimeInterval(-Double(lookbackHours) * 3_600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func latestSleepSummary() async throws -> (sleepDurationMinutes: Double, sleepEfficiency: Double?)? {
        let end = Date()
        let start = end.addingTimeInterval(-36 * 3_600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let sleepSamples = (samples as? [HKCategorySample]) ?? []
                let asleepIntervals = sleepSamples.compactMap { sample -> DateInterval? in
                    guard Self.isAsleepValue(sample.value) else {
                        return nil
                    }
                    return DateInterval(start: sample.startDate, end: sample.endDate)
                }
                let inBedIntervals = sleepSamples.compactMap { sample -> DateInterval? in
                    guard sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue else {
                        return nil
                    }
                    return DateInterval(start: sample.startDate, end: sample.endDate)
                }

                let asleepSeconds = Self.unionDuration(of: asleepIntervals)
                guard asleepSeconds > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let inBedSeconds = Self.unionDuration(of: inBedIntervals)
                let efficiency = inBedSeconds > 0 ? min(100.0, max(0.0, asleepSeconds / inBedSeconds * 100.0)) : nil
                continuation.resume(returning: (asleepSeconds / 60.0, efficiency))
            }
            healthStore.execute(query)
        }
    }

    private static func isAsleepValue(_ value: Int) -> Bool {
        let asleepValues = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        return asleepValues.contains(value)
    }

    private static func unionDuration(of intervals: [DateInterval]) -> TimeInterval {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []

        for interval in sorted {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }

            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }

        return merged.reduce(0) { $0 + $1.duration }
    }
}
