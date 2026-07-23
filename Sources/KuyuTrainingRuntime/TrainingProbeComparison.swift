import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct TrainingProbeComparison: Sendable, Codable, Equatable {
    public enum SelectedCheckpointRole: String, Sendable, Codable, Equatable {
        case candidate
        case source
        case none
    }

    public let probeID: String
    public let trainingRunID: String
    public let teacherScore: Double
    public let initialScore: Double
    public let trainedScore: Double?
    public let scoreDelta: Double?
    public let trainingAccepted: Bool
    public let checkpointDecision: CheckpointDecisionState
    public private(set) var acceptedCheckpointURL: URL?
    public let sourceCheckpointURL: URL?
    public private(set) var selectedCheckpointURL: URL?
    public private(set) var selectedCheckpointRole: SelectedCheckpointRole
    public let reloadSucceeded: Bool
    public let safetyViolationDelta: Double?
    public let safetyEvidenceAvailable: Bool
    public let safetyNonRegression: Bool
    public let passedImproved: Bool
    public let meetsMinimumDelta: Bool
    public let teacherPassed: Bool
    public let trainedPassed: Bool
    public let referenceSatisfied: Bool
    public let policySatisfied: Bool
    public let probeAccepted: Bool
    public let probeRejectionReasons: [String]
    public let initialTeacherDriveAverageMAE: Double?
    public let trainedTeacherDriveAverageMAE: Double?
    public let initialTeacherMotorAverageMAE: Double?
    public let trainedTeacherMotorAverageMAE: Double?
    public let initialTeacherFinalAltitudeDelta: Double?
    public let trainedTeacherFinalAltitudeDelta: Double?
    public let teacherDriveDivergenceNonRegression: Bool
    public let teacherMotorDivergenceNonRegression: Bool
    public let teacherAltitudeDivergenceNonRegression: Bool
    public let teacherDivergenceNonRegression: Bool

    public init(
        probeID: String,
        trainingRunID: String,
        teacher: TrainingProbeRunSummary,
        initial: TrainingProbeRunSummary,
        trained: TrainingProbeRunSummary?,
        training: TrainingRunResult,
        minScoreDelta: Double,
        requireTeacherPass: Bool,
        requireTrainedPass: Bool,
        sourceCheckpointURL: URL? = nil
    ) {
        let scoreDelta = trained.map { $0.score - initial.score }
        self.probeID = probeID
        self.trainingRunID = trainingRunID
        self.teacherScore = teacher.score
        self.initialScore = initial.score
        self.trainedScore = trained?.score
        self.scoreDelta = scoreDelta
        self.trainingAccepted = training.convergence.accepted
        self.checkpointDecision = training.checkpointDecision.state
        self.acceptedCheckpointURL = training.checkpointDecision.publishedCheckpointURL
        self.sourceCheckpointURL = sourceCheckpointURL
        self.reloadSucceeded = trained != nil
        self.safetyViolationDelta = trained.map { $0.safetyViolationSeconds - initial.safetyViolationSeconds }
        self.safetyEvidenceAvailable = self.safetyViolationDelta != nil
        self.safetyNonRegression = self.safetyViolationDelta.map { $0 <= 0 } ?? false
        self.passedImproved = (trained?.suitePassed == true) && !initial.suitePassed
        self.meetsMinimumDelta = (scoreDelta ?? -Double.greatestFiniteMagnitude) >= minScoreDelta
        self.teacherPassed = teacher.suitePassed
        self.trainedPassed = trained?.suitePassed == true
        self.referenceSatisfied = !requireTeacherPass || teacher.suitePassed
        self.policySatisfied = !requireTrainedPass || self.trainedPassed
        self.initialTeacherDriveAverageMAE = Self.meanAbsoluteError(
            initial.diagnostics.averageDriveActivationByIndex,
            teacher.diagnostics.averageDriveActivationByIndex
        )
        self.trainedTeacherDriveAverageMAE = Self.meanAbsoluteError(
            trained?.diagnostics.averageDriveActivationByIndex,
            teacher.diagnostics.averageDriveActivationByIndex
        )
        self.initialTeacherMotorAverageMAE = Self.meanAbsoluteError(
            initial.diagnostics.averageMotorFinalOutputByIndex,
            teacher.diagnostics.averageMotorFinalOutputByIndex
        )
        self.trainedTeacherMotorAverageMAE = Self.meanAbsoluteError(
            trained?.diagnostics.averageMotorFinalOutputByIndex,
            teacher.diagnostics.averageMotorFinalOutputByIndex
        )
        self.initialTeacherFinalAltitudeDelta = Self.delta(
            initial.diagnostics.finalAltitudeZ,
            teacher.diagnostics.finalAltitudeZ
        )
        self.trainedTeacherFinalAltitudeDelta = Self.delta(
            trained?.diagnostics.finalAltitudeZ,
            teacher.diagnostics.finalAltitudeZ
        )
        self.teacherDriveDivergenceNonRegression = Self.nonRegression(
            trained: self.trainedTeacherDriveAverageMAE,
            initial: self.initialTeacherDriveAverageMAE,
            tolerance: 0.01
        )
        self.teacherMotorDivergenceNonRegression = Self.nonRegression(
            trained: self.trainedTeacherMotorAverageMAE,
            initial: self.initialTeacherMotorAverageMAE,
            tolerance: 0.01
        )
        self.teacherAltitudeDivergenceNonRegression = Self.absoluteNonRegression(
            trained: self.trainedTeacherFinalAltitudeDelta,
            initial: self.initialTeacherFinalAltitudeDelta,
            tolerance: 0.25
        )
        self.teacherDivergenceNonRegression = self.teacherDriveDivergenceNonRegression
            && self.teacherMotorDivergenceNonRegression
            && self.teacherAltitudeDivergenceNonRegression

        var rejectionReasons: [String] = []
        if !self.trainingAccepted {
            rejectionReasons.append("training-not-accepted")
        }
        if !self.reloadSucceeded {
            rejectionReasons.append("reload-not-run")
        }
        if !self.meetsMinimumDelta {
            rejectionReasons.append("minimum-delta-not-met")
        }
        if !self.safetyEvidenceAvailable {
            rejectionReasons.append("safety-evidence-missing")
        } else if !self.safetyNonRegression {
            rejectionReasons.append("safety-regression")
        }
        if !self.referenceSatisfied {
            rejectionReasons.append("reference-not-satisfied")
        }
        if !self.policySatisfied {
            rejectionReasons.append("policy-not-satisfied")
        }
        if !self.teacherDivergenceNonRegression {
            rejectionReasons.append("teacher-divergence-regression")
        }
        self.probeRejectionReasons = rejectionReasons
        self.probeAccepted = rejectionReasons.isEmpty
        if self.probeAccepted {
            self.selectedCheckpointURL = training.checkpointDecision.publishedCheckpointURL
                ?? training.checkpointDecision.candidateCheckpointURL
            self.selectedCheckpointRole = self.selectedCheckpointURL == nil ? .none : .candidate
        } else if let sourceCheckpointURL {
            self.selectedCheckpointURL = sourceCheckpointURL
            self.selectedCheckpointRole = .source
        } else {
            self.selectedCheckpointURL = nil
            self.selectedCheckpointRole = .none
        }
    }

    public func selectingCheckpoint(from decision: CheckpointDecision) -> TrainingProbeComparison {
        var resolved = self
        if probeAccepted,
           decision.state == .accepted,
           let publishedCheckpointURL = decision.publishedCheckpointURL {
            resolved.acceptedCheckpointURL = publishedCheckpointURL
            resolved.selectedCheckpointURL = publishedCheckpointURL
            resolved.selectedCheckpointRole = .candidate
        } else if let sourceCheckpointURL {
            resolved.acceptedCheckpointURL = nil
            resolved.selectedCheckpointURL = sourceCheckpointURL
            resolved.selectedCheckpointRole = .source
        } else {
            resolved.acceptedCheckpointURL = nil
            resolved.selectedCheckpointURL = nil
            resolved.selectedCheckpointRole = .none
        }
        return resolved
    }

    private static func meanAbsoluteError(_ lhs: [Double]?, _ rhs: [Double]?) -> Double? {
        guard let lhs, let rhs, !lhs.isEmpty, lhs.count == rhs.count else {
            return nil
        }
        let total = zip(lhs, rhs).reduce(0.0) { partial, pair in
            partial + abs(pair.0 - pair.1)
        }
        return total / Double(lhs.count)
    }

    private static func delta(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else {
            return nil
        }
        return lhs - rhs
    }

    private static func nonRegression(trained: Double?, initial: Double?, tolerance: Double) -> Bool {
        guard let trained, let initial else {
            return true
        }
        return trained <= initial + tolerance
    }

    private static func absoluteNonRegression(trained: Double?, initial: Double?, tolerance: Double) -> Bool {
        guard let trained, let initial else {
            return true
        }
        return abs(trained) <= abs(initial) + tolerance
    }

}
