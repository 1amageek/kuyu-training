import Foundation

public struct VectorizedTaskQualitySummary: Sendable, Codable, Equatable {
    public let profileID: String?
    public let task: String
    public let scenarioSuiteID: String
    public let scenarioID: String
    public let seed: UInt64
    public let passed: Bool
    public let failureReasons: [String]
    public let evaluatorID: String
    public let metrics: [String: Double]

    public init(
        profileID: String? = nil,
        task: String,
        scenarioSuiteID: String,
        scenarioID: String,
        seed: UInt64,
        passed: Bool,
        failureReasons: [String],
        evaluatorID: String,
        metrics: [String: Double] = [:]
    ) throws {
        guard !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VectorizedTaskQualitySummaryError.emptyTask
        }
        guard !scenarioSuiteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VectorizedTaskQualitySummaryError.emptyScenarioSuiteID
        }
        guard !scenarioID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VectorizedTaskQualitySummaryError.emptyScenarioID
        }
        guard !evaluatorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VectorizedTaskQualitySummaryError.emptyEvaluatorID
        }
        for (id, value) in metrics {
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VectorizedTaskQualitySummaryError.emptyMetricID
            }
            guard value.isFinite else {
                throw VectorizedTaskQualitySummaryError.nonFiniteMetric(id)
            }
        }
        self.profileID = profileID
        self.task = task
        self.scenarioSuiteID = scenarioSuiteID
        self.scenarioID = scenarioID
        self.seed = seed
        self.passed = passed
        self.failureReasons = failureReasons
        self.evaluatorID = evaluatorID
        self.metrics = metrics
    }
}

public enum VectorizedTaskQualitySummaryError: Error, Sendable, Equatable {
    case emptyTask
    case emptyScenarioSuiteID
    case emptyScenarioID
    case emptyEvaluatorID
    case emptyMetricID
    case nonFiniteMetric(String)
}
