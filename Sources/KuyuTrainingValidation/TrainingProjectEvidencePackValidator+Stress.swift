import Foundation
import KuyuScenarios

extension TrainingProjectEvidencePackValidator {
    func validateStressSuites(
        _ stressSuites: [TrainingProjectEvidencePack.StressSuiteEvidence]
    ) throws {
        var suiteIDs: Set<String> = []
        var paths: Set<String> = []
        for suite in stressSuites {
            let suiteID = suite.suiteID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !suiteID.isEmpty else { throw ValidationError.emptyStressSuiteID }
            guard suiteIDs.insert(suiteID).inserted else {
                throw ValidationError.duplicateStressSuiteID(suiteID)
            }
            guard suite.recordCount > 0 else {
                throw ValidationError.invalidStressSuiteRecordCount(
                    suiteID: suiteID,
                    recordCount: suite.recordCount
                )
            }
            guard !suite.coverageTargets.isEmpty else {
                throw ValidationError.emptyStressCoverageTargets(suiteID)
            }
            for target in suite.coverageTargets {
                guard target.actualCount >= target.minimumCount else {
                    throw ValidationError.stressCoverageTargetNotMet(
                        suiteID: suiteID,
                        dimension: target.dimension,
                        minimumCount: target.minimumCount,
                        actualCount: target.actualCount
                    )
                }
            }
            try validateStressReplayEvidence(suite)
            let path = suite.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { throw ValidationError.emptyStressSuitePath }
            guard !path.hasPrefix("/") else {
                throw ValidationError.absoluteStressSuitePath(path)
            }
            let components = path.split(separator: "/").map(String.init)
            guard !components.contains("..") else {
                throw ValidationError.escapingStressSuitePath(path)
            }
            guard paths.insert(path).inserted else {
                throw ValidationError.duplicateStressSuitePath(path)
            }
        }
    }

    func validateStressReplayEvidence(
        _ suite: TrainingProjectEvidencePack.StressSuiteEvidence
    ) throws {
        switch suite.replayStatus {
        case .performed:
            guard suite.replayCheckCount > 0 else {
                throw ValidationError.invalidStressReplayEvidence(suite.suiteID)
            }
        case .notPerformed:
            guard suite.replayCheckCount == 0 else {
                throw ValidationError.invalidStressReplayEvidence(suite.suiteID)
            }
        }
    }

    func missingReferenceM2StressDimensions(
        in pack: TrainingProjectEvidencePack
    ) -> [StressSuiteManifest.StressDimension] {
        let bestCoverage = pack.stressSuites
            .filter { $0.profile == .referenceQuadrotor }
            .map(\.fulfilledCoverageDimensions)
            .max { lhs, rhs in lhs.count < rhs.count } ?? []
        return StressSuiteManifest.requiredReferenceQuadrotorM2Dimensions.filter {
            !bestCoverage.contains($0)
        }
    }

    func referenceQuadrotorStressSuiteIDs(
        in pack: TrainingProjectEvidencePack
    ) -> [String] {
        pack.stressSuites
            .filter { $0.profile == .referenceQuadrotor }
            .map(\.suiteID)
            .sorted()
    }
}
