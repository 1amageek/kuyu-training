import Foundation

public struct EvolutionCandidateAcceptanceResultValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case emptyEvaluatorID
        case emptyScenarioSuites
        case duplicateScenarioSuite(String)
        case invalidEpisodesPerSuite(Int)
        case emptyDeterminismTier
        case invalidConfigurationDigest(String)
        case invalidRobotManifestIdentity
        case acceptanceRequiresFullScenario
        case acceptanceRequiresCandidateGate
        case nonFiniteFitness(String)
        case missingEvidence
        case duplicateEvidencePath(String)
    }

    public init() {}

    public func validate(
        _ result: EvolutionCandidateAcceptanceResult,
        acceptanceDirectory: URL
    ) throws {
        let contract = result.evaluationContract
        guard !contract.evaluatorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyEvaluatorID
        }
        guard !contract.scenarioSuiteIDs.isEmpty else {
            throw ValidationError.emptyScenarioSuites
        }
        var suiteIDs = Set<String>()
        for suiteID in contract.scenarioSuiteIDs {
            let normalized = suiteID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, suiteIDs.insert(normalized).inserted else {
                throw ValidationError.duplicateScenarioSuite(suiteID)
            }
        }
        guard contract.episodesPerSuite > 0 else {
            throw ValidationError.invalidEpisodesPerSuite(contract.episodesPerSuite)
        }
        guard !contract.determinismTier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyDeterminismTier
        }
        let digestCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        guard contract.configurationDigest.count == 64,
              contract.configurationDigest.unicodeScalars.allSatisfy(digestCharacters.contains) else {
            throw ValidationError.invalidConfigurationDigest(contract.configurationDigest)
        }
        guard (contract.robotManifestID == nil) == (contract.robotManifestHash == nil) else {
            throw ValidationError.invalidRobotManifestIdentity
        }
        try contract.evaluationFidelity.validate()
        guard contract.evaluationFidelity.isFullScenario else {
            throw ValidationError.acceptanceRequiresFullScenario
        }
        guard contract.workPhase == .candidateGate else {
            throw ValidationError.acceptanceRequiresCandidateGate
        }
        for summary in [result.fitness, result.incumbentFitness] where !isFinite(summary) {
            throw ValidationError.nonFiniteFitness(summary.candidateID)
        }
        guard !result.evidence.isEmpty else {
            throw ValidationError.missingEvidence
        }
        var paths = Set<String>()
        let integrity = EvolutionAcceptanceEvidenceIntegrity()
        for reference in result.evidence {
            guard paths.insert(reference.relativePath).inserted else {
                throw ValidationError.duplicateEvidencePath(reference.relativePath)
            }
            try integrity.validatedURL(for: reference, in: acceptanceDirectory)
        }
    }

    private func isFinite(_ summary: FitnessSummary) -> Bool {
        summary.scalarFitness.isFinite
            && summary.rewardAverage.isFinite
            && summary.taskPassRate.isFinite
            && summary.safetyViolationRate.isFinite
            && (summary.holdTimeRatio?.isFinite ?? true)
            && (summary.altitudeErrorRatio?.isFinite ?? true)
            && (summary.energyPenalty?.isFinite ?? true)
            && (summary.noveltyScore?.isFinite ?? true)
            && (summary.teacherDelta?.isFinite ?? true)
            && (summary.workerThroughput?.isFinite ?? true)
            && summary.behaviorDescriptor.values.allSatisfy(\.isFinite)
    }
}
