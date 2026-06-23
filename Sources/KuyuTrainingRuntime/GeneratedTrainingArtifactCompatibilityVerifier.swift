import Foundation
import KuyuTrainingValidation

public struct CheckpointEvaluationArtifactCompatibilityRequest: Sendable, Equatable {
    public let artifactDirectory: URL
    public let expectedProfile: TaskEvaluationProfile
    public let expectedCheckpointPath: String
    public let requiresPolicyPass: Bool

    public init(
        artifactDirectory: URL,
        expectedProfile: TaskEvaluationProfile,
        expectedCheckpointPath: String,
        requiresPolicyPass: Bool
    ) {
        self.artifactDirectory = artifactDirectory
        self.expectedProfile = expectedProfile
        self.expectedCheckpointPath = expectedCheckpointPath
        self.requiresPolicyPass = requiresPolicyPass
    }
}

public struct GeneratedTrainingArtifactCompatibilityRequest: Sendable, Equatable {
    public let runArtifactDirectory: URL?
    public let probeArtifactDirectory: URL?
    public let checkpointEvaluation: CheckpointEvaluationArtifactCompatibilityRequest?

    public init(
        runArtifactDirectory: URL? = nil,
        probeArtifactDirectory: URL? = nil,
        checkpointEvaluation: CheckpointEvaluationArtifactCompatibilityRequest? = nil
    ) {
        self.runArtifactDirectory = runArtifactDirectory
        self.probeArtifactDirectory = probeArtifactDirectory
        self.checkpointEvaluation = checkpointEvaluation
    }
}

public struct GeneratedTrainingArtifactCompatibilityReport: Sendable, Equatable {
    public let runArtifacts: TrainingRunArtifactBundle?
    public let probeArtifacts: TrainingProbeArtifactBundle?
    public let checkpointEvaluationArtifact: CheckpointEvaluationArtifact?

    public init(
        runArtifacts: TrainingRunArtifactBundle? = nil,
        probeArtifacts: TrainingProbeArtifactBundle? = nil,
        checkpointEvaluationArtifact: CheckpointEvaluationArtifact? = nil
    ) {
        self.runArtifacts = runArtifacts
        self.probeArtifacts = probeArtifacts
        self.checkpointEvaluationArtifact = checkpointEvaluationArtifact
    }
}

public struct GeneratedTrainingArtifactCompatibilityVerifier: Sendable {
    public enum VerificationError: Error, Sendable, Equatable {
        case missingCheckpointEvaluationArtifact(String)
    }

    private let runValidator: TrainingRunArtifactValidator
    private let probeValidator: TrainingProbeArtifactValidator

    public init(
        runValidator: TrainingRunArtifactValidator = TrainingRunArtifactValidator(),
        probeValidator: TrainingProbeArtifactValidator = TrainingProbeArtifactValidator()
    ) {
        self.runValidator = runValidator
        self.probeValidator = probeValidator
    }

    public func verify(
        _ request: GeneratedTrainingArtifactCompatibilityRequest
    ) throws -> GeneratedTrainingArtifactCompatibilityReport {
        let runArtifacts = try request.runArtifactDirectory.map(loadRunArtifacts)
        let probeArtifacts = try request.probeArtifactDirectory.map(loadProbeArtifacts)
        let checkpointEvaluationArtifact = try request.checkpointEvaluation.map(loadCheckpointEvaluationArtifact)
        return GeneratedTrainingArtifactCompatibilityReport(
            runArtifacts: runArtifacts,
            probeArtifacts: probeArtifacts,
            checkpointEvaluationArtifact: checkpointEvaluationArtifact
        )
    }

    public func loadRunArtifacts(from artifactDirectory: URL) throws -> TrainingRunArtifactBundle {
        try runValidator.loadAndValidate(from: artifactDirectory)
    }

    public func loadProbeArtifacts(from artifactDirectory: URL) throws -> TrainingProbeArtifactBundle {
        try probeValidator.loadAndValidate(from: artifactDirectory)
    }

    public func loadCheckpointEvaluationArtifact(
        _ request: CheckpointEvaluationArtifactCompatibilityRequest
    ) throws -> CheckpointEvaluationArtifact {
        let url = request.artifactDirectory.appendingPathComponent(CheckpointEvaluationArtifact.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VerificationError.missingCheckpointEvaluationArtifact(CheckpointEvaluationArtifact.fileName)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let artifact = try decoder.decode(CheckpointEvaluationArtifact.self, from: Data(contentsOf: url))
        try CheckpointEvaluationArtifactValidator.validate(
            artifact,
            expectedProfile: request.expectedProfile,
            expectedCheckpointPath: request.expectedCheckpointPath,
            requiresPolicyPass: request.requiresPolicyPass
        )
        return artifact
    }
}
