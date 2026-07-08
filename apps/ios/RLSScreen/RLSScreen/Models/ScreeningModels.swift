import Foundation
import RLSInference

struct ScreeningForm: Codable, Equatable {
    var sleepSessionEndDate: Date?
    var sleepDurationMinutes: Double?
    var sleepEfficiency: Double?
    var wasoMinutes: Double?
    var sleepLatencyMinutes: Double?
    var remLatencyMinutes: Double?
    var awakeStageMinutes: Double?
    var averageSpO2: Double?
    var minimumSpO2: Double?
    var lightSleepMinutes: Double?
    var lightSleepPercent: Double?
    var deepSleepMinutes: Double?
    var deepSleepPercent: Double?
    var remSleepMinutes: Double?
    var remSleepPercent: Double?
    var restingHeartRate: Double?
    var meanHeartRate: Double?
    var age: Double?
    var sex: String?
    var heightCm: Double?
    var weightKg: Double?
    var familyHistoryRLS: Bool?
    var diabetes: Bool?
    var psychiatricMedication: Bool?
    var nonLegSymptoms: Bool?

    var featureInput: RLSFeatureInput {
        RLSFeatureInput(
            sleepDurationMinutes: sleepDurationMinutes,
            sleepEfficiency: sleepEfficiency,
            wasoMinutes: wasoMinutes,
            sleepLatencyMinutes: sleepLatencyMinutes,
            remLatencyMinutes: remLatencyMinutes,
            awakeStageMinutes: awakeStageMinutes,
            averageSpO2: averageSpO2,
            minimumSpO2: minimumSpO2,
            lightSleepMinutes: lightSleepMinutes,
            lightSleepPercent: lightSleepPercent,
            deepSleepMinutes: deepSleepMinutes,
            deepSleepPercent: deepSleepPercent,
            remSleepMinutes: remSleepMinutes,
            remSleepPercent: remSleepPercent,
            restingHeartRate: restingHeartRate,
            meanHeartRate: meanHeartRate,
            age: age,
            sex: sex,
            heightCm: heightCm,
            weightKg: weightKg,
            familyHistoryRLS: familyHistoryRLS,
            diabetes: diabetes,
            psychiatricMedication: psychiatricMedication,
            nonLegSymptoms: nonLegSymptoms
        )
    }

    var isQuestionnaireComplete: Bool {
        familyHistoryRLS != nil
            && diabetes != nil
            && psychiatricMedication != nil
            && nonLegSymptoms != nil
    }

    func withQuestionnaire(from source: ScreeningForm) -> ScreeningForm {
        var copy = self
        copy.familyHistoryRLS = source.familyHistoryRLS
        copy.diabetes = source.diabetes
        copy.psychiatricMedication = source.psychiatricMedication
        copy.nonLegSymptoms = source.nonLegSymptoms
        return copy
    }
}

struct ScreeningRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let tier: String
    let riskScore: Double
    let riskLevel: String
    let xgboostProbability: Double
    let tabmProbability: Double
    let modelKey: String?
    let scenario: String
    let availableFeatureCount: Int?
    let totalFeatureCount: Int?
    let input: ScreeningForm

    init(prediction: RLSPrediction, input: ScreeningForm, createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.tier = prediction.tier.rawValue
        self.riskScore = prediction.riskScore
        self.riskLevel = RiskLevel(score: prediction.riskScore).rawValue
        self.xgboostProbability = prediction.xgboostProbability
        self.tabmProbability = prediction.tabmProbability ?? prediction.xgboostProbability
        self.modelKey = prediction.modelKey
        self.scenario = prediction.scenario
        self.availableFeatureCount = prediction.availableFeatureCount
        self.totalFeatureCount = prediction.totalFeatureCount
        self.input = input
    }
}

struct SleepAnalysisSample: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let createdAt: Date
    let sleepDurationMinutes: Double?
    let sleepEfficiency: Double?
    let deepSleepPercent: Double?
    let remSleepPercent: Double?
    let restingHeartRate: Double?
    let riskScore: Double
    let riskLevel: String

    init(record: ScreeningRecord) {
        self.id = record.id
        self.date = record.input.sleepSessionEndDate ?? record.createdAt
        self.createdAt = record.createdAt
        self.sleepDurationMinutes = record.input.sleepDurationMinutes
        self.sleepEfficiency = record.input.sleepEfficiency
        self.deepSleepPercent = record.input.deepSleepPercent
        self.remSleepPercent = record.input.remSleepPercent
        self.restingHeartRate = record.input.restingHeartRate
        self.riskScore = record.riskScore
        self.riskLevel = record.riskLevel
    }

    var sleepDurationHours: Double? {
        sleepDurationMinutes.map { $0 / 60.0 }
    }

    var bedTime: Date? {
        guard let sleepDurationMinutes else {
            return nil
        }
        return date.addingTimeInterval(-sleepDurationMinutes * 60)
    }

    var bedMinuteOfDay: Int? {
        guard let bedTime else {
            return nil
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: bedTime)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }
        return hour * 60 + minute
    }
}

struct SleepTrendInsight: Identifiable, Equatable {
    enum Severity: String {
        case stable
        case watch
        case attention
    }

    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let severity: Severity
}

struct SleepTrendAnalysis: Equatable {
    let samples: [SleepAnalysisSample]
    let recentSamples: [SleepAnalysisSample]
    let previousSamples: [SleepAnalysisSample]

    init(records: [ScreeningRecord]) {
        self.samples = Self.makeDailySamples(from: records)
        self.recentSamples = Array(samples.suffix(7))
        self.previousSamples = Array(samples.dropLast(7).suffix(7))
    }

    var hasSleepData: Bool {
        samples.contains { $0.sleepDurationMinutes != nil || $0.sleepEfficiency != nil }
    }

    var averageSleepDurationMinutes: Double? {
        average(recentSamples.compactMap(\.sleepDurationMinutes))
    }

    var previousAverageSleepDurationMinutes: Double? {
        average(previousSamples.compactMap(\.sleepDurationMinutes))
    }

    var sleepDurationChangeMinutes: Double? {
        guard let averageSleepDurationMinutes, let previousAverageSleepDurationMinutes else {
            return nil
        }
        return averageSleepDurationMinutes - previousAverageSleepDurationMinutes
    }

    var averageSleepEfficiency: Double? {
        average(recentSamples.compactMap(\.sleepEfficiency))
    }

    var averageDeepSleepPercent: Double? {
        average(recentSamples.compactMap(\.deepSleepPercent))
    }

    var averageREMSleepPercent: Double? {
        average(recentSamples.compactMap(\.remSleepPercent))
    }

    var averageRestingHeartRate: Double? {
        average(recentSamples.compactMap(\.restingHeartRate))
    }

    var averageRiskScore: Double? {
        average(recentSamples.map(\.riskScore))
    }

    var shortSleepNightCount: Int {
        recentSamples.compactMap(\.sleepDurationMinutes).filter { $0 < 390 }.count
    }

    var lowEfficiencyNightCount: Int {
        recentSamples.compactMap(\.sleepEfficiency).filter { $0 < 80 }.count
    }

    var highRiskNightCount: Int {
        recentSamples.filter { RiskLevel(score: $0.riskScore) == .high }.count
    }

    var bedTimeRangeMinutes: Int? {
        let bedTimes = recentSamples.compactMap(\.bedMinuteOfDay)
        guard bedTimes.count >= 2, let minBedTime = bedTimes.min(), let maxBedTime = bedTimes.max() else {
            return nil
        }
        let directRange = maxBedTime - minBedTime
        return min(directRange, 1440 - directRange)
    }

    var insights: [SleepTrendInsight] {
        var insights: [SleepTrendInsight] = []

        if !hasSleepData {
            return [
                SleepTrendInsight(
                    id: "missing-sleep-data",
                    title: "No sleep trend yet",
                    detail: "Import Health sleep data or run screenings after sleep sessions to build a trend.",
                    systemImage: "bed.double",
                    severity: .watch
                )
            ]
        }

        if let averageSleepDurationMinutes, averageSleepDurationMinutes < 390 {
            insights.append(
                SleepTrendInsight(
                    id: "short-sleep",
                    title: "Short recent sleep",
                    detail: "Recent recorded nights average below 6.5 hours. Track whether symptoms or daytime fatigue increase on these nights.",
                    systemImage: "moon.zzz",
                    severity: .attention
                )
            )
        } else if shortSleepNightCount >= 2 {
            insights.append(
                SleepTrendInsight(
                    id: "short-sleep-nights",
                    title: "Some short nights",
                    detail: "\(shortSleepNightCount) of the latest \(recentSamples.count) recorded nights were under 6.5 hours.",
                    systemImage: "moon",
                    severity: .watch
                )
            )
        }

        if let sleepDurationChangeMinutes, sleepDurationChangeMinutes <= -30 {
            insights.append(
                SleepTrendInsight(
                    id: "sleep-down",
                    title: "Sleep duration is down",
                    detail: "The latest records average \(Self.formatSignedMinutes(sleepDurationChangeMinutes)) versus the prior set.",
                    systemImage: "chart.line.downtrend.xyaxis",
                    severity: .watch
                )
            )
        }

        if let averageSleepEfficiency, averageSleepEfficiency < 80 {
            insights.append(
                SleepTrendInsight(
                    id: "low-efficiency",
                    title: "Lower sleep efficiency",
                    detail: "Recent sleep efficiency averages below 80%, which can reflect fragmented sleep or long awake periods.",
                    systemImage: "timer",
                    severity: .attention
                )
            )
        } else if lowEfficiencyNightCount >= 2 {
            insights.append(
                SleepTrendInsight(
                    id: "low-efficiency-nights",
                    title: "Efficiency dips",
                    detail: "\(lowEfficiencyNightCount) recent nights were below 80% sleep efficiency.",
                    systemImage: "timer",
                    severity: .watch
                )
            )
        }

        if let bedTimeRangeMinutes, bedTimeRangeMinutes >= 90 {
            insights.append(
                SleepTrendInsight(
                    id: "irregular-bedtime",
                    title: "Variable bedtime",
                    detail: "Estimated bedtimes vary by about \(Self.formatDuration(minutes: Double(bedTimeRangeMinutes))).",
                    systemImage: "calendar.badge.clock",
                    severity: .watch
                )
            )
        }

        if highRiskNightCount >= 2 {
            insights.append(
                SleepTrendInsight(
                    id: "elevated-risk",
                    title: "Repeated elevated screening",
                    detail: "\(highRiskNightCount) recent screenings were in the high band. This is not a diagnosis; consider discussing persistent symptoms with a clinician.",
                    systemImage: "exclamationmark.triangle",
                    severity: .attention
                )
            )
        }

        if insights.isEmpty {
            insights.append(
                SleepTrendInsight(
                    id: "stable",
                    title: "Recent sleep looks stable",
                    detail: "No repeated short-sleep, low-efficiency, or elevated screening pattern is visible in the saved records.",
                    systemImage: "checkmark.seal",
                    severity: .stable
                )
            )
        }

        return insights
    }

    static func formatDuration(minutes: Double) -> String {
        let roundedMinutes = Int(minutes.rounded())
        let hours = roundedMinutes / 60
        let minutes = roundedMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func formatSignedMinutes(_ minutes: Double) -> String {
        let sign = minutes >= 0 ? "+" : "-"
        return "\(sign)\(formatDuration(minutes: abs(minutes)))"
    }

    private static func makeDailySamples(from records: [ScreeningRecord]) -> [SleepAnalysisSample] {
        var latestByDay: [Date: SleepAnalysisSample] = [:]

        for sample in records.map(SleepAnalysisSample.init(record:)) {
            let day = Calendar.current.startOfDay(for: sample.date)
            if let existing = latestByDay[day], existing.createdAt >= sample.createdAt {
                continue
            }
            latestByDay[day] = sample
        }

        return latestByDay.values.sorted { $0.date < $1.date }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct BaselineNightScore: Codable, Identifiable, Equatable {
    let id: UUID
    let sleepSessionEndDate: Date
    let riskScore: Double
    let riskLevel: String
    let xgboostProbability: Double
    let tabmProbability: Double
    let availableFeatureCount: Int?
    let totalFeatureCount: Int?

    init(prediction: RLSPrediction, sleepSessionEndDate: Date) {
        self.id = UUID()
        self.sleepSessionEndDate = sleepSessionEndDate
        self.riskScore = prediction.riskScore
        self.riskLevel = RiskLevel(score: prediction.riskScore).rawValue
        self.xgboostProbability = prediction.xgboostProbability
        self.tabmProbability = prediction.tabmProbability ?? .nan
        self.availableFeatureCount = prediction.availableFeatureCount
        self.totalFeatureCount = prediction.totalFeatureCount
    }
}

struct BaselineScreeningResult: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let windowDays: Int
    let requestedNightLimit: Int
    let modelKey: String
    let scenario: String
    let nightScores: [BaselineNightScore]

    init(windowDays: Int, requestedNightLimit: Int, predictions: [(RLSPrediction, ScreeningForm)]) {
        self.id = UUID()
        self.createdAt = Date()
        self.windowDays = windowDays
        self.requestedNightLimit = requestedNightLimit
        self.modelKey = predictions.first?.0.modelKey ?? "sleep_heart_basic_q"
        self.scenario = predictions.first?.0.scenario ?? "sleep_heart_basic_q"
        self.nightScores = predictions.compactMap { prediction, form in
            guard let sleepSessionEndDate = form.sleepSessionEndDate else {
                return nil
            }
            return BaselineNightScore(prediction: prediction, sleepSessionEndDate: sleepSessionEndDate)
        }
        .sorted { $0.sleepSessionEndDate > $1.sleepSessionEndDate }
    }

    var validNightCount: Int {
        nightScores.count
    }

    var typicalScore: Double? {
        percentile(0.5)
    }

    var meanScore: Double? {
        guard !nightScores.isEmpty else {
            return nil
        }
        return nightScores.map(\.riskScore).reduce(0, +) / Double(nightScores.count)
    }

    var p75Score: Double? {
        percentile(0.75)
    }

    var riskLevel: RiskLevel? {
        typicalScore.map(RiskLevel.init(score:))
    }

    var highRiskNightCount: Int {
        nightScores.filter { RiskLevel(score: $0.riskScore) == .high }.count
    }

    var dataQuality: BaselineDataQuality {
        if validNightCount >= 42 {
            return .good
        }
        if validNightCount >= 21 {
            return .fair
        }
        return .limited
    }

    var dateRangeLabel: String? {
        guard
            let oldest = nightScores.map(\.sleepSessionEndDate).min(),
            let newest = nightScores.map(\.sleepSessionEndDate).max()
        else {
            return nil
        }
        return "\(Self.shortDateFormatter.string(from: oldest)) - \(Self.shortDateFormatter.string(from: newest))"
    }

    private func percentile(_ percentile: Double) -> Double? {
        let values = nightScores.map(\.riskScore).sorted()
        guard !values.isEmpty else {
            return nil
        }
        guard values.count > 1 else {
            return values[0]
        }

        let position = percentile * Double(values.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        if lowerIndex == upperIndex {
            return values[lowerIndex]
        }

        let weight = position - Double(lowerIndex)
        return values[lowerIndex] * (1 - weight) + values[upperIndex] * weight
    }

    private static var shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

enum BaselineDataQuality: String, Codable {
    case good
    case fair
    case limited

    var title: String {
        switch self {
        case .good:
            return "Good"
        case .fair:
            return "Fair"
        case .limited:
            return "Limited"
        }
    }
}

enum RiskLevel: String {
    case low
    case moderate
    case high

    init(score: Double) {
        if score >= 0.55 {
            self = .high
        } else if score >= 0.32 {
            self = .moderate
        } else {
            self = .low
        }
    }

    var title: String {
        switch self {
        case .low:
            return "Low"
        case .moderate:
            return "Moderate"
        case .high:
            return "High"
        }
    }
}
