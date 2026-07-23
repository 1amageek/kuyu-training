import Foundation
import KuyuTrainingContracts

public struct KuyuDatasetValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case unsupportedSchemaVersion(found: Int, expected: Int)
        case invalidManifestField(String)
        case invalidDigest(field: String, value: String)
        case invalidSpace(field: String, reason: String)
        case invalidPolicyContext(String)
        case emptyDataset
        case recordCountMismatch(expected: UInt64, actual: UInt64)
        case recordKindMismatch(index: UInt64, expected: KuyuDatasetRecord.Kind, actual: KuyuDatasetRecord.Kind)
        case coordinateMismatch(index: UInt64, field: String, expected: String, actual: String)
        case transitionIndexMismatch(expected: Int, actual: Int)
        case recordAfterClosedBoundary(index: UInt64, previous: KuyuTrajectoryBoundary.Kind)
        case finalBoundaryContinues
        case vectorDimensionMismatch(index: UInt64, field: String, expected: Int, actual: Int)
        case nonFiniteValue(index: UInt64, field: String)
        case invalidInterval(index: UInt64, reason: String)
        case transitionDiscontinuity(index: UInt64, field: String)
        case invalidBehaviorEvidence(index: UInt64, reason: String)
        case invalidRecord(index: UInt64, reason: String)
    }

    public init() {}

    public func validationSession(for manifest: KuyuDatasetManifest) throws -> KuyuDatasetValidationSession {
        try validate(manifest: manifest)
        return KuyuDatasetValidationSession(manifest: manifest, validator: self)
    }

    public func validate(manifest: KuyuDatasetManifest) throws {
        guard manifest.schemaVersion == KuyuDatasetManifest.currentSchemaVersion else {
            throw ValidationError.unsupportedSchemaVersion(
                found: manifest.schemaVersion,
                expected: KuyuDatasetManifest.currentSchemaVersion
            )
        }
        try validateDescriptor(manifest.descriptor)
        try validateDigest(manifest.recordsDigest, field: "recordsDigest")
    }

    func validateDescriptor(_ descriptor: KuyuDatasetDescriptor) throws {
        let identity = descriptor.identity
        try requireText(identity.datasetID, field: "identity.datasetID")
        try requireText(identity.scenarioID, field: "identity.scenarioID")
        try requireText(identity.scenarioRevision, field: "identity.scenarioRevision")
        try requireText(identity.suiteID, field: "identity.suiteID")
        try requireText(identity.suiteVersion, field: "identity.suiteVersion")
        try requireText(identity.episodeID, field: "identity.episodeID")
        try requireText(identity.segmentID, field: "identity.segmentID")
        guard identity.segmentIndex >= 0 else {
            throw ValidationError.invalidManifestField("identity.segmentIndex")
        }

        try requireText(descriptor.producer.id, field: "producer.id")
        try requireText(descriptor.producer.version, field: "producer.version")
        try validateExecution(descriptor.execution)
        try validateSpaces(descriptor.spaces)
        try validateTiming(descriptor.timing)
        try validateSemantics(descriptor.semantics)
        try validateProvenance(descriptor.provenance)
        try validateMigrationConsistency(descriptor)

        if descriptor.recordKind == .onPolicyTransition {
            guard let policy = descriptor.policy else {
                throw ValidationError.invalidManifestField("policy")
            }
            guard let policyContext = descriptor.policyContext else {
                throw ValidationError.invalidManifestField("policyContext")
            }
            try validatePolicy(policy)
            try validatePolicyContext(policyContext)
        } else {
            if let policy = descriptor.policy {
                try validatePolicy(policy)
            }
            if let policyContext = descriptor.policyContext {
                try validatePolicyContext(policyContext)
            }
        }
    }

    private func validateExecution(_ execution: KuyuDatasetDescriptor.Execution) throws {
        guard execution.dynamicsProgramSchemaVersion > 0 else {
            throw ValidationError.invalidManifestField("execution.dynamicsProgramSchemaVersion")
        }
        try validateDigest(execution.dynamicsProgramDigest, field: "execution.dynamicsProgramDigest")
        try requireText(execution.fidelityID, field: "execution.fidelityID")
        try requireText(execution.constraintProjectionID, field: "execution.constraintProjectionID")
        try requireText(execution.mixerID, field: "execution.mixerID")
        try requireText(execution.rotorSpinConventionID, field: "execution.rotorSpinConventionID")
        try requireText(execution.backendID, field: "execution.backendID")
        try requireText(execution.backendVersion, field: "execution.backendVersion")
        try requireText(execution.numericType, field: "execution.numericType")
        try requireText(execution.deviceClass, field: "execution.deviceClass")
        try requireText(execution.determinismTier, field: "execution.determinismTier")
    }

    private func validateSpaces(_ spaces: KuyuDatasetDescriptor.Spaces) throws {
        try validateSpace(spaces.observation, field: "spaces.observation", requiresChannels: true)
        if let criticState = spaces.criticState {
            try validateSpace(criticState, field: "spaces.criticState", requiresChannels: true)
        }
        try validateSpace(spaces.policyAction, field: "spaces.policyAction", requiresChannels: true)
        try validateSpace(spaces.realizedControl, field: "spaces.realizedControl", requiresChannels: false)
        try validateSpace(spaces.actuatorCommand, field: "spaces.actuatorCommand", requiresChannels: true)
        if let worldState = spaces.worldState {
            try validateSpace(worldState, field: "spaces.worldState", requiresChannels: true)
        }
    }

    private func validateSpace(
        _ space: KuyuDatasetDescriptor.Space,
        field: String,
        requiresChannels: Bool
    ) throws {
        try requireText(space.id, field: "\(field).id")
        try requireText(space.version, field: "\(field).version")
        try validateDigest(space.digest, field: "\(field).digest")
        if requiresChannels, space.channels.isEmpty {
            throw ValidationError.invalidSpace(field: field, reason: "empty channels")
        }

        var ids = Set<String>()
        for (expectedIndex, channel) in space.channels.enumerated() {
            guard channel.index == expectedIndex else {
                throw ValidationError.invalidSpace(field: field, reason: "non-contiguous channel indices")
            }
            guard !channel.id.isEmpty, ids.insert(channel.id).inserted else {
                throw ValidationError.invalidSpace(field: field, reason: "empty or duplicate channel id")
            }
            guard !channel.unit.isEmpty else {
                throw ValidationError.invalidSpace(field: field, reason: "empty channel unit")
            }
            if let lower = channel.lowerBound, !lower.isFinite {
                throw ValidationError.invalidSpace(field: field, reason: "non-finite lower bound")
            }
            if let upper = channel.upperBound, !upper.isFinite {
                throw ValidationError.invalidSpace(field: field, reason: "non-finite upper bound")
            }
            guard (channel.lowerBound == nil) == (channel.upperBound == nil) else {
                throw ValidationError.invalidSpace(field: field, reason: "incomplete bounds")
            }
            if let lower = channel.lowerBound, let upper = channel.upperBound, lower >= upper {
                throw ValidationError.invalidSpace(field: field, reason: "unordered bounds")
            }
            if channel.transform == .affineTanh || channel.transform == .affineSigmoid {
                guard channel.lowerBound != nil, channel.upperBound != nil else {
                    throw ValidationError.invalidSpace(field: field, reason: "bounded transform without bounds")
                }
            }
        }
    }

    private func validateTiming(_ timing: KuyuDatasetDescriptor.Timing) throws {
        guard timing.physicsTimeStep.isFinite, timing.physicsTimeStep > 0 else {
            throw ValidationError.invalidManifestField("timing.physicsTimeStep")
        }
        guard timing.controlPeriodTicks > 0 else {
            throw ValidationError.invalidManifestField("timing.controlPeriodTicks")
        }
    }

    private func validateSemantics(_ semantics: KuyuDatasetDescriptor.Semantics) throws {
        try validateDigest(semantics.rewardDescriptorDigest, field: "semantics.rewardDescriptorDigest")
        try validateDigest(semantics.safetyCostDescriptorDigest, field: "semantics.safetyCostDescriptorDigest")
        try validateDigest(semantics.failureDescriptorDigest, field: "semantics.failureDescriptorDigest")
        try validateDigest(semantics.taskQualityDescriptorDigest, field: "semantics.taskQualityDescriptorDigest")
    }

    private func validatePolicy(_ policy: KuyuDatasetDescriptor.Policy) throws {
        try requireText(policy.policyID, field: "policy.policyID")
        try validateDigest(policy.checkpointDigest, field: "policy.checkpointDigest")
        try validateDigest(policy.distributionContractDigest, field: "policy.distributionContractDigest")
    }

    private func validatePolicyContext(_ context: KuyuPolicyContextContract) throws {
        switch context {
        case .fixedHistory(let fixed):
            guard fixed.historyLength > 0 else {
                throw ValidationError.invalidPolicyContext("non-positive history length")
            }
            try validateDigest(fixed.featureOrderDigest, field: "policyContext.featureOrderDigest")
        case .recurrent(let recurrent):
            try validateDigest(recurrent.stateSpaceDigest, field: "policyContext.stateSpaceDigest")
            try validateDigest(recurrent.initialStateDigest, field: "policyContext.initialStateDigest")
            guard !recurrent.resetRule.isEmpty else {
                throw ValidationError.invalidPolicyContext("empty reset rule")
            }
            guard !recurrent.initialState.isEmpty, recurrent.initialState.allSatisfy(\.isFinite) else {
                throw ValidationError.invalidPolicyContext("invalid initial recurrent state")
            }
            guard recurrent.burnInCount >= 0,
                  recurrent.lossStartTransitionIndex >= recurrent.burnInCount else {
                throw ValidationError.invalidPolicyContext("invalid burn-in or loss start")
            }
        }
    }

    private func validateProvenance(_ provenance: KuyuDatasetDescriptor.Provenance) throws {
        try validateDigest(provenance.codeDigest, field: "provenance.codeDigest")
        try validateDigest(provenance.configurationDigest, field: "provenance.configurationDigest")
        try validateDigest(provenance.embodimentDigest, field: "provenance.embodimentDigest")
        if let sourceDatasetDigest = provenance.sourceDatasetDigest {
            try validateDigest(sourceDatasetDigest, field: "provenance.sourceDatasetDigest")
        }
        if let importerID = provenance.importerID {
            try requireText(importerID, field: "provenance.importerID")
        }
        if let migration = provenance.migration {
            guard (3...6).contains(migration.sourceSchemaVersion),
                  provenance.sourceDatasetDigest != nil,
                  provenance.importerID != nil else {
                throw ValidationError.invalidManifestField("provenance.migration")
            }
            if migration.classification == .migrated, !migration.unavailableFacts.isEmpty {
                throw ValidationError.invalidManifestField("provenance.migration.unavailableFacts")
            }
        }
    }

    private func validateMigrationConsistency(_ descriptor: KuyuDatasetDescriptor) throws {
        guard let migration = descriptor.provenance.migration else { return }
        switch migration.classification {
        case .migrated:
            guard migration.unavailableFacts.isEmpty else {
                throw ValidationError.invalidManifestField("provenance.migration.unavailableFacts")
            }
        case .downgradedToOffPolicy:
            guard descriptor.recordKind == .offPolicyTransition,
                  descriptor.policy == nil,
                  descriptor.policyContext == nil,
                  !migration.unavailableFacts.isEmpty else {
                throw ValidationError.invalidManifestField("provenance.migration.downgrade")
            }
        }
    }

    func validateDigest(_ value: String, field: String) throws {
        let valid = value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
        guard valid else {
            throw ValidationError.invalidDigest(field: field, value: value)
        }
    }

    private func requireText(_ value: String, field: String) throws {
        guard !value.isEmpty else {
            throw ValidationError.invalidManifestField(field)
        }
    }
}
