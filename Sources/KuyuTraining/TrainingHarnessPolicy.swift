import Foundation

/// Outcome of evaluating a training probe against the harness acceptance gate.
public struct TrainingHarnessGateReport: Codable, Sendable, Equatable {
    public let requirement: String
    public let accepted: Bool
    public let reasons: [String]

    public init(requirement: String, accepted: Bool, reasons: [String]) {
        self.requirement = requirement
        self.accepted = accepted
        self.reasons = reasons
    }
}

/// Shared acceptance policy for the training-probe harness. Owning this in
/// `kuyu-training` (next to `TrainingProbeResult`) keeps checkpoint-acceptance logic in
/// the Kuyu API rather than in a CLI/UI adapter (kuyu/SPEC.md "API-First Application
/// Boundary"). Both KuyuCLI and KuyuUI consume this single source of truth.
public enum TrainingHarnessPolicy {
    /// Maximum allowed divergence between teacher and trained average drive activation.
    public static let driveActivationTolerance = 0.05
    /// Minimum altitude (m) required by the lift smoke check (min and final altitude).
    public static let altitudeSmokeThreshold = 0.25
    /// Failure reasons treated as hard (non-recoverable) safety failures.
    public static let hardSafetyFailureReasons: Set<String> = [
        "ground-violation", "sustained-fall", "sustained-violation",
    ]

    public static func report(
        result: TrainingProbeResult,
        requireTaskSolved: Bool
    ) -> TrainingHarnessGateReport {
        let reasons = requireTaskSolved
            ? taskSolvedRejectionReasons(result: result)
            : harnessRejectionReasons(result: result)
        return TrainingHarnessGateReport(
            requirement: requireTaskSolved ? "taskSolved" : "harnessSatisfied",
            accepted: reasons.isEmpty,
            reasons: reasons
        )
    }

    public static func taskSolved(result: TrainingProbeResult) -> Bool {
        taskSolvedRejectionReasons(result: result).isEmpty
    }

    public static func satisfied(result: TrainingProbeResult) -> Bool {
        harnessRejectionReasons(result: result).isEmpty
    }

    public static func taskSolvedRejectionReasons(result: TrainingProbeResult) -> [String] {
        var reasons: [String] = []
        if result.manifest.terminalState != .completed {
            reasons.append("terminal-not-completed:\(result.manifest.terminalState.rawValue)")
        }
        if result.probeCheckpointDecision.state != .accepted {
            reasons.append("probe-checkpoint-not-accepted:\(result.probeCheckpointDecision.state.rawValue)")
        }
        if !result.comparison.reloadSucceeded {
            reasons.append("reload-failed")
        }
        if !result.comparison.policySatisfied {
            reasons.append("policy-not-satisfied")
        }
        reasons.append(contentsOf: result.comparison.probeRejectionReasons.map { "probe:\($0)" })
        return Array(Set(reasons)).sorted()
    }

    public static func harnessRejectionReasons(result: TrainingProbeResult) -> [String] {
        var reasons: [String] = []
        if !result.training.convergence.accepted {
            reasons.append("convergence-rejected:\(result.training.convergence.reason)")
        }
        if result.comparison.checkpointDecision != .accepted && result.comparison.checkpointDecision != .staged {
            reasons.append("checkpoint-not-accepted:\(result.comparison.checkpointDecision.rawValue)")
        }
        if result.comparison.selectedCheckpointRole != .candidate {
            reasons.append("selected-checkpoint-not-candidate:\(result.comparison.selectedCheckpointRole.rawValue)")
        }
        if result.comparison.selectedCheckpointURL == nil {
            reasons.append("missing-selected-checkpoint")
        }
        if !result.comparison.reloadSucceeded {
            reasons.append("reload-failed")
        }
        if !result.comparison.referenceSatisfied {
            reasons.append("reference-not-satisfied")
        }
        if !result.comparison.meetsMinimumDelta {
            reasons.append("minimum-delta-not-met")
        }
        if !result.comparison.safetyNonRegression {
            reasons.append("safety-regression")
        }
        if !result.comparison.teacherDivergenceNonRegression {
            reasons.append("teacher-divergence-regression")
        }
        guard let trained = result.trained else {
            reasons.append("missing-trained-run")
            return Array(Set(reasons)).sorted()
        }
        reasons.append(contentsOf: hardSafetyFailures(trained.diagnostics.failureReasons).map { "hard-safety-failure:\($0)" })
        if !driveActivationCloseEnough(teacher: result.teacher, trained: trained) {
            reasons.append("drive-activation-diverged")
        }
        if !altitudeSmokeSatisfied(trained: trained) {
            reasons.append("altitude-smoke-failed")
        }
        if (result.comparison.scoreDelta ?? -Double.greatestFiniteMagnitude) < 0 {
            reasons.append("negative-score-delta")
        }
        return Array(Set(reasons)).sorted()
    }

    public static func hardSafetyFailures(_ reasons: [String]) -> [String] {
        reasons.filter { hardSafetyFailureReasons.contains($0) }.sorted()
    }

    private static func driveActivationCloseEnough(
        teacher: TrainingProbeRunSummary,
        trained: TrainingProbeRunSummary
    ) -> Bool {
        guard
            let teacherAverage = teacher.diagnostics.averageDriveActivation,
            let trainedAverage = trained.diagnostics.averageDriveActivation
        else {
            return false
        }
        return abs(teacherAverage - trainedAverage) <= driveActivationTolerance
    }

    private static func altitudeSmokeSatisfied(trained: TrainingProbeRunSummary) -> Bool {
        guard
            let minAltitude = trained.diagnostics.minAltitudeZ,
            let finalAltitude = trained.diagnostics.finalAltitudeZ
        else {
            return false
        }
        return minAltitude >= altitudeSmokeThreshold && finalAltitude >= altitudeSmokeThreshold
    }
}
