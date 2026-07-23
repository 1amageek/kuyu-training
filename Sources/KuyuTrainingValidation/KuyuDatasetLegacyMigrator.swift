import Foundation
import KuyuTrainingContracts

public struct KuyuDatasetLegacyMigrator: Sendable {
    public enum MigrationError: Error, Sendable, Equatable {
        case assessmentMismatch(recordIndex: Int, field: String)
    }

    private let writer: KuyuDatasetWriter
    private let validator: KuyuDatasetValidator

    public init(
        writer: KuyuDatasetWriter = KuyuDatasetWriter(),
        validator: KuyuDatasetValidator = KuyuDatasetValidator()
    ) {
        self.writer = writer
        self.validator = validator
    }

    public func migrate(
        _ source: KuyuLegacyDatasetSource,
        descriptor: KuyuDatasetDescriptor,
        to destination: URL
    ) throws -> KuyuDatasetLegacyMigrationResult {
        let dataset = source.dataset
        let sourceDatasetDigest = source.sourceDigest
        try validator.validateDigest(sourceDatasetDigest, field: "sourceDatasetDigest")
        let sourceID = "\(dataset.metadata.scenarioId)#\(dataset.metadata.seed)"
        guard (3...6).contains(dataset.metadata.schemaVersion) else {
            return .rejected(report: rejectedReport(
                dataset: dataset,
                sourceID: sourceID,
                sourceDigest: sourceDatasetDigest,
                targetDatasetID: descriptor.identity.datasetID,
                missing: ["supportedLegacySchemaVersion"]
            ))
        }
        guard !dataset.records.isEmpty else {
            return .rejected(report: rejectedReport(
                dataset: dataset,
                sourceID: sourceID,
                sourceDigest: sourceDatasetDigest,
                targetDatasetID: descriptor.identity.datasetID,
                missing: ["records"]
            ))
        }
        let identityMissing = identityMissingFacts(dataset, descriptor: descriptor)
        guard identityMissing.isEmpty else {
            return .rejected(report: rejectedReport(
                dataset: dataset,
                sourceID: sourceID,
                sourceDigest: sourceDatasetDigest,
                targetDatasetID: descriptor.identity.datasetID,
                missing: identityMissing
            ))
        }

        switch dataset.metadata.purpose {
        case .behaviorCloning:
            return try migrateDemonstrations(
                dataset,
                descriptor: descriptor,
                sourceID: sourceID,
                sourceDigest: sourceDatasetDigest,
                destination: destination
            )
        case .reinforcementRollout:
            return rejectUnverifiedReinforcement(
                dataset,
                descriptor: descriptor,
                sourceID: sourceID,
                sourceDigest: sourceDatasetDigest
            )
        case .worldModel:
            return .rejected(report: rejectedReport(
                dataset: dataset,
                sourceID: sourceID,
                sourceDigest: sourceDatasetDigest,
                targetDatasetID: descriptor.identity.datasetID,
                missing: ["explicitWorldStateRelation", "eventFacts"]
            ))
        case nil:
            return .rejected(report: rejectedReport(
                dataset: dataset,
                sourceID: sourceID,
                sourceDigest: sourceDatasetDigest,
                targetDatasetID: descriptor.identity.datasetID,
                missing: ["datasetPurpose"]
            ))
        }
    }

    private func migrateDemonstrations(
        _ dataset: TrainingDataset,
        descriptor: KuyuDatasetDescriptor,
        sourceID: String,
        sourceDigest: String,
        destination: URL
    ) throws -> KuyuDatasetLegacyMigrationResult {
        guard descriptor.recordKind == .demonstration else {
            return .rejected(report: rejectedReport(
                dataset: dataset,
                sourceID: sourceID,
                sourceDigest: sourceDigest,
                targetDatasetID: descriptor.identity.datasetID,
                missing: ["demonstrationTargetDescriptor"]
            ))
        }

        let missing = demonstrationMissingFacts(dataset, descriptor: descriptor)
        guard missing.isEmpty else {
            return .rejected(report: rejectedReport(
                dataset: dataset,
                sourceID: sourceID,
                sourceDigest: sourceDigest,
                targetDatasetID: descriptor.identity.datasetID,
                missing: missing
            ))
        }

        let migratedDescriptor = migratedDescriptor(
            descriptor,
            recordKind: .demonstration,
            sourceDigest: sourceDigest,
            sourceSchemaVersion: dataset.metadata.schemaVersion,
            classification: .migrated,
            unavailableFacts: []
        )
        guard let teacherID = dataset.metadata.policyId else {
            throw MigrationError.assessmentMismatch(recordIndex: 0, field: "teacherID")
        }
        let records: [KuyuDatasetRecord] = try dataset.records.enumerated().map { index, record in
            guard let decisionID = record.policyDecisionID,
                  let observationTime = record.actionObservationTime,
                  let teacherAction = record.actionValues else {
                throw MigrationError.assessmentMismatch(recordIndex: index, field: "demonstration facts")
            }
            let stateFacts: [Double]
            if descriptor.spaces.criticState == nil {
                stateFacts = []
            } else if let actionObservationState = record.actionObservationState {
                stateFacts = actionObservationState
            } else {
                throw MigrationError.assessmentMismatch(recordIndex: index, field: "sourceStateFacts")
            }
            return KuyuDatasetRecord.demonstration(KuyuDemonstrationSample(
                coordinate: coordinate(index: index, decisionID: decisionID, identity: descriptor.identity),
                observation: KuyuControlTransition.Observation(
                    time: observationTime,
                    values: record.sensors.sorted { $0.channelIndex < $1.channelIndex }.map(\.value)
                ),
                stateFacts: KuyuControlTransition.StateFacts(values: stateFacts),
                teacherAction: KuyuControlTransition.PolicyAction(values: teacherAction),
                teacherID: teacherID
            ))
        }
        let manifest = try writer.write(descriptor: migratedDescriptor, records: records, to: destination)
        let report = report(
            dataset: dataset,
            sourceID: sourceID,
            sourceDigest: sourceDigest,
            manifest: manifest,
            outcome: .migrated,
            unavailableFacts: []
        )
        return .migrated(report: report, manifest: manifest)
    }

    private func rejectUnverifiedReinforcement(
        _ dataset: TrainingDataset,
        descriptor: KuyuDatasetDescriptor,
        sourceID: String,
        sourceDigest: String
    ) -> KuyuDatasetLegacyMigrationResult {
        guard descriptor.recordKind == .onPolicyTransition || descriptor.recordKind == .offPolicyTransition else {
            return .rejected(report: rejectedReport(
                dataset: dataset,
                sourceID: sourceID,
                sourceDigest: sourceDigest,
                targetDatasetID: descriptor.identity.datasetID,
                missing: ["reinforcementTargetDescriptor"]
            ))
        }
        let missing = reinforcementMissingFacts(dataset, descriptor: descriptor)
        return .rejected(report: rejectedReport(
            dataset: dataset,
            sourceID: sourceID,
            sourceDigest: sourceDigest,
            targetDatasetID: descriptor.identity.datasetID,
            missing: missing + [
                "typedReinforcementImporter",
            ]
        ))
    }

    private func demonstrationMissingFacts(
        _ dataset: TrainingDataset,
        descriptor: KuyuDatasetDescriptor
    ) -> [String] {
        var missing = Set<String>()
        if dataset.metadata.policyId == nil { missing.insert("teacherID") }
        for record in dataset.records {
            if record.policyDecisionID == nil { missing.insert("policyDecisionID") }
            if record.actionObservationTime == nil { missing.insert("actionObservationTime") }
            if record.actionValues == nil { missing.insert("teacherAction") }
            if record.sensors.isEmpty { missing.insert("sourceObservation") }
            if record.episodeId != descriptor.identity.episodeID {
                missing.insert("episodeIdentity")
            }
            let sensorIndices = record.sensors.map(\.channelIndex).sorted()
            let expectedSensorIndices = (0..<descriptor.spaces.observation.channels.count).map(UInt32.init)
            if sensorIndices != expectedSensorIndices {
                missing.insert("exactObservationChannelLayout")
            }
            if let observationTime = record.actionObservationTime,
               record.sensors.contains(where: { abs($0.timestamp - observationTime) > 1e-9 }) {
                missing.insert("synchronizedObservationTime")
            }
            if descriptor.spaces.criticState != nil, record.actionObservationState == nil {
                missing.insert("sourceStateFacts")
            }
        }
        return missing.sorted()
    }

    private func reinforcementMissingFacts(
        _ dataset: TrainingDataset,
        descriptor: KuyuDatasetDescriptor
    ) -> [String] {
        var missing = Set([
            "verifiedLegacyArtifactDigest",
            "explicitPolicyObservationRelation",
            "explicitOutcomeObservationRelation",
            "explicitBootstrapPermission",
        ])
        guard let physicsTimeStep = dataset.metadata.physicsTimeStep,
              physicsTimeStep.isFinite,
              physicsTimeStep > 0 else {
            return ["physicsTimeStep"]
        }
        if dataset.metadata.controlPeriodSteps != descriptor.timing.controlPeriodTicks {
            missing.insert("matchingControlPeriodTicks")
        }
        if abs(physicsTimeStep - descriptor.timing.physicsTimeStep) > 1e-12 {
            missing.insert("matchingPhysicsTimeStep")
        }
        for (index, record) in dataset.records.enumerated() {
            if record.policyDecisionID == nil { missing.insert("policyDecisionID") }
            if record.actionObservationTime == nil { missing.insert("actionObservationTime") }
            if record.actionObservationState == nil { missing.insert("sourceObservation") }
            if record.actualState == nil { missing.insert("outcomeObservation") }
            if record.actionValues == nil { missing.insert("policyAction") }
            if record.actuatorCommandValues == nil || record.actuatorCommandValues?.isEmpty == true {
                missing.insert("actuatorCommand")
            }
            if record.reward == nil { missing.insert("reward") }
            if record.cost == nil { missing.insert("safetyCost") }
            if record.done == nil { missing.insert("done") }
            if record.truncated == nil { missing.insert("truncated") }
            if record.done == true, record.truncated == true {
                missing.insert("exclusiveBoundary")
            }
            let isFinal = index == dataset.records.index(before: dataset.records.endIndex)
            if isFinal, record.done != true, record.truncated != true {
                missing.insert("explicitFinalBoundary")
            }
            if !isFinal, record.done == true || record.truncated == true {
                missing.insert("boundaryBeforeFinalRecord")
            }
            if record.done == true,
               dataset.metadata.failureReason == nil,
               dataset.metadata.terminalReason == nil {
                missing.insert("terminalReason")
            }
            if record.truncated == true, dataset.metadata.terminalReason == nil {
                missing.insert("truncationReason")
            }
            if record.episodeId != descriptor.identity.episodeID { missing.insert("episodeIdentity") }
            if let start = record.actionObservationTime {
                let duration = record.time - start
                let ticks = duration / physicsTimeStep
                if !duration.isFinite || duration <= 0 || abs(ticks - ticks.rounded()) > 1e-9 {
                    missing.insert("integralPhysicsTickDuration")
                }
            }
        }
        return missing.sorted()
    }

    private func identityMissingFacts(
        _ dataset: TrainingDataset,
        descriptor: KuyuDatasetDescriptor
    ) -> [String] {
        var missing = Set<String>()
        if dataset.metadata.scenarioId != descriptor.identity.scenarioID {
            missing.insert("matchingScenarioIdentity")
        }
        if dataset.metadata.seed != descriptor.identity.seed {
            missing.insert("matchingSeed")
        }
        if dataset.metadata.recordCount != dataset.records.count {
            missing.insert("matchingRecordCount")
        }
        if dataset.metadata.episodeId != descriptor.identity.episodeID {
            missing.insert("matchingEpisodeIdentity")
        }
        if dataset.metadata.channelCount != descriptor.spaces.observation.channels.count {
            missing.insert("matchingObservationDimension")
        }
        if dataset.metadata.driveCount != descriptor.spaces.realizedControl.channels.count {
            missing.insert("matchingRealizedControlDimension")
        }
        if dataset.metadata.determinismTier != descriptor.execution.determinismTier {
            missing.insert("matchingDeterminismTier")
        }
        if dataset.metadata.configHash != descriptor.provenance.configurationDigest {
            missing.insert("matchingConfigurationDigest")
        }
        return missing.sorted()
    }

    private func coordinate(
        index: Int,
        decisionID: String,
        identity: KuyuDatasetDescriptor.Identity
    ) -> KuyuTrajectoryCoordinate {
        KuyuTrajectoryCoordinate(
            episodeID: identity.episodeID,
            segmentID: identity.segmentID,
            segmentIndex: identity.segmentIndex,
            transitionIndex: index,
            decisionID: decisionID
        )
    }

    private func migratedDescriptor(
        _ descriptor: KuyuDatasetDescriptor,
        recordKind: KuyuDatasetRecord.Kind,
        sourceDigest: String,
        sourceSchemaVersion: Int,
        classification: KuyuDatasetDescriptor.Provenance.Migration.Classification,
        unavailableFacts: [String]
    ) -> KuyuDatasetDescriptor {
        let provenance = KuyuDatasetDescriptor.Provenance(
            codeDigest: descriptor.provenance.codeDigest,
            configurationDigest: descriptor.provenance.configurationDigest,
            embodimentDigest: descriptor.provenance.embodimentDigest,
            sourceDatasetDigest: sourceDigest,
            importerID: "kuyu-training.legacy-migrator",
            migration: KuyuDatasetDescriptor.Provenance.Migration(
                sourceSchemaVersion: sourceSchemaVersion,
                classification: classification,
                unavailableFacts: unavailableFacts
            )
        )
        return KuyuDatasetDescriptor(
            identity: descriptor.identity,
            producer: descriptor.producer,
            recordKind: recordKind,
            execution: descriptor.execution,
            spaces: descriptor.spaces,
            timing: descriptor.timing,
            semantics: descriptor.semantics,
            policy: recordKind == .offPolicyTransition ? nil : descriptor.policy,
            policyContext: recordKind == .offPolicyTransition ? nil : descriptor.policyContext,
            provenance: provenance
        )
    }

    private func report(
        dataset: TrainingDataset,
        sourceID: String,
        sourceDigest: String,
        manifest: KuyuDatasetManifest,
        outcome: KuyuDatasetLegacyMigrationReport.Outcome,
        unavailableFacts: [String]
    ) -> KuyuDatasetLegacyMigrationReport {
        KuyuDatasetLegacyMigrationReport(
            sourceSchemaVersion: dataset.metadata.schemaVersion,
            sourceDatasetID: sourceID,
            sourceDatasetDigest: sourceDigest,
            targetDatasetID: manifest.descriptor.identity.datasetID,
            targetRecordKind: manifest.descriptor.recordKind,
            targetRecordsDigest: manifest.recordsDigest,
            outcome: outcome,
            unavailableFacts: unavailableFacts
        )
    }

    private func rejectedReport(
        dataset: TrainingDataset,
        sourceID: String,
        sourceDigest: String,
        targetDatasetID: String,
        missing: [String]
    ) -> KuyuDatasetLegacyMigrationReport {
        KuyuDatasetLegacyMigrationReport(
            sourceSchemaVersion: dataset.metadata.schemaVersion,
            sourceDatasetID: sourceID,
            sourceDatasetDigest: sourceDigest,
            targetDatasetID: targetDatasetID,
            targetRecordKind: nil,
            targetRecordsDigest: nil,
            outcome: .rejected,
            unavailableFacts: missing.sorted()
        )
    }
}
