import Foundation
import HealthKit

struct HealthDataImportResult: Equatable {
    var form: ScreeningForm
    var importedFieldNames: [String]
    var missingFieldNames: [String]
    var notes: [String]
}

protocol HealthDataProvider {
    func requestAuthorization() async throws
    func latestScreeningForm(current: ScreeningForm) async throws -> HealthDataImportResult
}

struct ManualOnlyHealthDataProvider: HealthDataProvider {
    func requestAuthorization() async throws {}

    func latestScreeningForm(current: ScreeningForm) async throws -> HealthDataImportResult {
        HealthDataImportResult(form: current, importedFieldNames: [], missingFieldNames: [], notes: [])
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
            return "No Health data could be read. If permissions were turned off, re-enable RLS Screen in Health permissions, then try again."
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
        var notes: [String] = []

        if let sleep = try await latestSleepSummary() {
            form.sleepDurationMinutes = sleep.sleepDurationMinutes
            imported.append("Sleep duration")
            notes.append("Sleep ending \(Self.shortDateTimeFormatter.string(from: sleep.endDate))")
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

        return HealthDataImportResult(form: form, importedFieldNames: imported, missingFieldNames: missing, notes: notes)
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
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: nil)
                        return
                    }
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
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func latestSleepSummary() async throws -> SleepSummary? {
        let end = Date()
        let start = end.addingTimeInterval(-14 * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }

                let sleepSamples = (samples as? [HKCategorySample]) ?? []
                guard let session = Self.latestMajorSleepSession(from: sleepSamples) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: session)
            }
            healthStore.execute(query)
        }
    }

    private struct SleepSummary {
        let startDate: Date
        let endDate: Date
        let sleepDurationMinutes: Double
        let sleepEfficiency: Double?
    }

    private static var shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func isNoDataError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == HKError.errorDomain
            && nsError.localizedDescription.localizedCaseInsensitiveContains("no data")
            && nsError.localizedDescription.localizedCaseInsensitiveContains("predicate")
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

    private static func isSleepSessionValue(_ value: Int) -> Bool {
        value == HKCategoryValueSleepAnalysis.inBed.rawValue || isAsleepValue(value)
    }

    private static func latestMajorSleepSession(from samples: [HKCategorySample]) -> SleepSummary? {
        let sorted = samples
            .filter { isSleepSessionValue($0.value) }
            .sorted { $0.startDate < $1.startDate }

        var sessions: [[HKCategorySample]] = []
        var current: [HKCategorySample] = []
        var currentEnd: Date?
        let maximumSessionGap: TimeInterval = 3 * 3_600

        for sample in sorted {
            guard let end = currentEnd else {
                current = [sample]
                currentEnd = sample.endDate
                continue
            }

            if sample.startDate.timeIntervalSince(end) <= maximumSessionGap {
                current.append(sample)
                currentEnd = max(end, sample.endDate)
            } else {
                sessions.append(current)
                current = [sample]
                currentEnd = sample.endDate
            }
        }

        if !current.isEmpty {
            sessions.append(current)
        }

        return sessions
            .compactMap(makeSleepSummary)
            .sorted { $0.endDate > $1.endDate }
            .first
    }

    private static func makeSleepSummary(from samples: [HKCategorySample]) -> SleepSummary? {
        let asleepIntervals = samples.compactMap { sample -> DateInterval? in
            guard isAsleepValue(sample.value) else {
                return nil
            }
            return DateInterval(start: sample.startDate, end: sample.endDate)
        }
        let inBedIntervals = samples.compactMap { sample -> DateInterval? in
            guard sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue else {
                return nil
            }
            return DateInterval(start: sample.startDate, end: sample.endDate)
        }

        let asleepSeconds = unionDuration(of: asleepIntervals)
        guard asleepSeconds >= 60 * 60 else {
            return nil
        }

        let sessionStart = samples.map(\.startDate).min() ?? Date()
        let sessionEnd = samples.map(\.endDate).max() ?? sessionStart
        let inBedSeconds = unionDuration(of: inBedIntervals)
        let sessionSeconds = max(sessionEnd.timeIntervalSince(sessionStart), 1)
        let denominator = inBedSeconds > 0 ? inBedSeconds : sessionSeconds
        let efficiency = min(100.0, max(0.0, asleepSeconds / denominator * 100.0))

        return SleepSummary(
            startDate: sessionStart,
            endDate: sessionEnd,
            sleepDurationMinutes: asleepSeconds / 60.0,
            sleepEfficiency: efficiency
        )
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
