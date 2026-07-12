import Foundation

/// Runtime-owned read model for operator-facing learning progress.
///
/// This projection preserves the distinction between observed iteration
/// metrics and optional candidate-lineage decisions. Consumers must not infer
/// accepted generations when the journal contains no decision records.
public struct LearningProgressSnapshot: Sendable, Equatable {
    public struct Attempt: Identifiable, Sendable, Equatable {
        public let id: Int
        public let generation: Int
        public let recordedAt: Date
        public let accepted: Bool
        public let supportHorizon: Int?
        public let frontierHorizon: Int?
        public let fullHorizon: Int?
        public let mode: String?
        public let failureRate: Double?
        public let maximumAngularRate: Double?
        public let maximumTilt: Double?
        public let minimumAltitude: Double?
        public let rewardPerStep: Double?
        public let trainingLoss: Double?
        public let episodeCount: Int?
        public let failureCount: Int?
        public let rejectionReasons: [String]
        public let evaluationPassed: Bool?
        public let evaluationScore: Double?
        public let checkpointPath: String?
        public let iterationDuration: Double?
        public let safetyCost: Double?
        public let safetyCostLimit: Double?
        public let failureObservationCount: Int
    }

    public struct Generation: Identifiable, Sendable, Equatable {
        public let id: Int
        public let acceptedAtAttempt: Int?
        public let firstAttempt: Int
        public let lastAttempt: Int
        public let attemptCount: Int
        public let rejectedAttemptCount: Int
        public let checkpointPath: String?
        public let latestAttempt: Attempt
        public let bestSupportHorizon: Int?
        public let latestEvaluationAttempt: Int?
        public let latestEvaluationPassed: Bool?
        public let latestEvaluationScore: Double?
        public let failureObservationCount: Int

        public var displayName: String {
            id == 0 ? "Baseline" : "Rev \(id)"
        }
    }

    public struct FailureObservation: Identifiable, Sendable, Equatable {
        public let id: String
        public let attempt: Int
        public let generation: Int
        public let scenario: String
        public let seed: UInt64
        public let terminalStep: Int
        public let reason: String
    }

    public struct FailureGroup: Identifiable, Sendable, Equatable {
        public let id: String
        public let scenario: String
        public let reason: String
        public let observationCount: Int
        public let seeds: [UInt64]
        public let firstAttempt: Int
        public let lastAttempt: Int
        public let latestGeneration: Int
        public let latestTerminalStep: Int
        public let observations: [FailureObservation]
    }

    public let attempts: [Attempt]
    public let generations: [Generation]
    public let failureGroups: [FailureGroup]
    public let failureObservations: [FailureObservation]
    public let acceptedGenerationCount: Int
    public let decisionRecordedCount: Int
    public let currentGeneration: Int
    public let attemptsSinceLastAccepted: Int?
    public let currentSupportHorizon: Int?
    public let initialSupportHorizon: Int?
    public let fullHorizon: Int?
    public let supportCompletionRatio: Double?
    public let latestEvaluationAttempt: Int?
    public let latestEvaluationPassed: Bool?
    public let latestEvaluationScore: Double?

    public init(records: [TrainingRunIterationRecord]) {
        let ordered = records.sorted { $0.iteration < $1.iteration }
        var retainedGeneration = 0
        var attempts: [Attempt] = []
        var observations: [FailureObservation] = []
        attempts.reserveCapacity(ordered.count)

        for record in ordered {
            let accepted = record.decision?.accepted == true
            if accepted {
                retainedGeneration += 1
            }
            let attemptNumber = record.iteration + 1
            let health = record.decision?.horizonHealth ?? [:]
            let attempt = Attempt(
                id: attemptNumber,
                generation: retainedGeneration,
                recordedAt: record.recordedAt,
                accepted: accepted,
                supportHorizon: record.horizon?.supportHorizon,
                frontierHorizon: record.horizon?.frontierHorizon,
                fullHorizon: record.horizon?.fullHorizon,
                mode: record.horizon?.mode,
                failureRate: Self.failureRate(health: health),
                maximumAngularRate: Self.finite(health["maxOmega"]),
                maximumTilt: Self.finite(health["maxTilt"]),
                minimumAltitude: Self.finite(health["minAltitude"]),
                rewardPerStep: Self.rewardPerStep(health: health),
                trainingLoss: Self.metric(["trainingLoss", "loss"], in: record.evaluation?.metrics),
                episodeCount: Self.integerMetric("episodeCount", health: health),
                failureCount: Self.integerMetric("failureCount", health: health),
                rejectionReasons: record.decision?.rejectionReasons ?? [],
                evaluationPassed: Self.metric(["policyPassed", "suitePassed"], in: record.evaluation?.metrics)
                    .map { $0 >= 0.5 },
                evaluationScore: Self.metric(["policyScore", "score"], in: record.evaluation?.metrics),
                checkpointPath: record.checkpoint?.path,
                iterationDuration: Self.finite(record.phaseTimings["iterationSeconds"]),
                safetyCost: Self.finite(record.constraint?.observedCost),
                safetyCostLimit: Self.finite(record.constraint?.costLimit),
                failureObservationCount: record.failureEpisodes.count
            )
            attempts.append(attempt)

            for (index, failure) in record.failureEpisodes.enumerated() {
                observations.append(FailureObservation(
                    id: "\(attemptNumber)-\(index)-\(failure.scenario)-\(failure.seed)-\(failure.reason)",
                    attempt: attemptNumber,
                    generation: retainedGeneration,
                    scenario: failure.scenario,
                    seed: failure.seed,
                    terminalStep: failure.terminalStep,
                    reason: failure.reason
                ))
            }
        }

        self.attempts = attempts
        self.generations = Self.makeGenerations(attempts: attempts)
        self.failureObservations = observations
        self.failureGroups = Self.makeFailureGroups(observations: observations)
        self.acceptedGenerationCount = retainedGeneration
        self.decisionRecordedCount = ordered.reduce(into: 0) { count, record in
            if record.decision != nil {
                count += 1
            }
        }
        self.currentGeneration = attempts.last?.generation ?? 0
        if let latestAttempt = attempts.last?.id,
           let acceptedAttempt = attempts.last(where: \.accepted)?.id {
            self.attemptsSinceLastAccepted = latestAttempt - acceptedAttempt
        } else {
            self.attemptsSinceLastAccepted = nil
        }
        self.currentSupportHorizon = attempts.reversed().compactMap(\.supportHorizon).first
        self.initialSupportHorizon = attempts.compactMap(\.supportHorizon).first
        self.fullHorizon = attempts.reversed().compactMap(\.fullHorizon).first
        if let currentSupportHorizon, let fullHorizon, fullHorizon > 0 {
            self.supportCompletionRatio = Double(currentSupportHorizon) / Double(fullHorizon)
        } else {
            self.supportCompletionRatio = nil
        }
        let latestEvaluation = attempts.reversed().first {
            $0.evaluationPassed != nil || $0.evaluationScore != nil
        }
        self.latestEvaluationAttempt = latestEvaluation?.id
        self.latestEvaluationPassed = latestEvaluation?.evaluationPassed
        self.latestEvaluationScore = latestEvaluation?.evaluationScore
    }

    public var hasGenerationLineage: Bool {
        decisionRecordedCount > 0
    }

    public func failureGroups(forRevision revision: Int?) -> [FailureGroup] {
        guard let revision else { return failureGroups }
        return Self.makeFailureGroups(
            observations: failureObservations.filter { $0.generation == revision }
        )
    }

    public func failureObservations(forRevision revision: Int?) -> [FailureObservation] {
        guard let revision else { return failureObservations }
        return failureObservations.filter { $0.generation == revision }
    }

    private static func makeGenerations(attempts: [Attempt]) -> [Generation] {
        let grouped = Dictionary(grouping: attempts, by: \.generation)
        return grouped.keys.sorted().compactMap { generationID in
            guard let generationAttempts = grouped[generationID],
                  let first = generationAttempts.first,
                  let latest = generationAttempts.last else {
                return nil
            }
            let acceptedAttempt = generationAttempts.first(where: \.accepted)
            let evaluationAttempt = generationAttempts.reversed().first {
                $0.evaluationPassed != nil || $0.evaluationScore != nil
            }
            return Generation(
                id: generationID,
                acceptedAtAttempt: acceptedAttempt?.id,
                firstAttempt: first.id,
                lastAttempt: latest.id,
                attemptCount: generationAttempts.count,
                rejectedAttemptCount: generationAttempts.filter { !$0.accepted }.count,
                checkpointPath: acceptedAttempt?.checkpointPath,
                latestAttempt: latest,
                bestSupportHorizon: generationAttempts.compactMap(\.supportHorizon).max(),
                latestEvaluationAttempt: evaluationAttempt?.id,
                latestEvaluationPassed: evaluationAttempt?.evaluationPassed,
                latestEvaluationScore: evaluationAttempt?.evaluationScore,
                failureObservationCount: generationAttempts.reduce(0) {
                    $0 + $1.failureObservationCount
                }
            )
        }
    }

    private static func makeFailureGroups(
        observations: [FailureObservation]
    ) -> [FailureGroup] {
        struct GroupKey: Hashable {
            let scenario: String
            let reason: String
        }

        let grouped = Dictionary(grouping: observations) {
            GroupKey(scenario: $0.scenario, reason: $0.reason)
        }
        return grouped.map { key, group in
            let ordered = group.sorted {
                if $0.attempt != $1.attempt { return $0.attempt < $1.attempt }
                if $0.seed != $1.seed { return $0.seed < $1.seed }
                return $0.terminalStep < $1.terminalStep
            }
            return FailureGroup(
                id: "\(key.scenario)|\(key.reason)",
                scenario: key.scenario,
                reason: key.reason,
                observationCount: ordered.count,
                seeds: Array(Set(ordered.map(\.seed))).sorted(),
                firstAttempt: ordered.first?.attempt ?? 0,
                lastAttempt: ordered.last?.attempt ?? 0,
                latestGeneration: ordered.last?.generation ?? 0,
                latestTerminalStep: ordered.last?.terminalStep ?? 0,
                observations: ordered
            )
        }
        .sorted {
            if $0.observationCount != $1.observationCount {
                return $0.observationCount > $1.observationCount
            }
            if $0.scenario != $1.scenario { return $0.scenario < $1.scenario }
            return $0.reason < $1.reason
        }
    }

    private static func rewardPerStep(health: [String: Double]) -> Double? {
        guard let reward = finite(health["rewardAverage"]),
              let terminalStepAverage = finite(health["terminalStepAverage"]),
              terminalStepAverage > 0 else {
            return nil
        }
        return reward / terminalStepAverage
    }

    private static func failureRate(health: [String: Double]) -> Double? {
        if let value = finite(health["failureRate"]) {
            return value
        }
        guard let failureCount = finite(health["failureCount"]),
              let episodeCount = finite(health["episodeCount"]),
              episodeCount > 0 else {
            return nil
        }
        return failureCount / episodeCount
    }

    private static func metric(_ keys: [String], in metrics: [String: Double]?) -> Double? {
        guard let metrics else { return nil }
        for key in keys {
            if let value = finite(metrics[key]) {
                return value
            }
        }
        return nil
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func integerMetric(_ key: String, health: [String: Double]) -> Int? {
        guard let value = finite(health[key]) else { return nil }
        return Int(value.rounded())
    }
}
