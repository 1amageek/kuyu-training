import Foundation
import KuyuCore
import KuyuPhysics

public extension TrainingDatasetWriter {
    func write(
        episode: RolloutEpisode,
        timeStep: Double,
        determinismTier: String,
        to directory: URL,
        purpose: TrainingDatasetPurpose = .reinforcementRollout,
        observation: TrainingObservationMetadata? = nil,
        provenance: TrainingProvenanceManifest? = nil
    ) throws -> URL {
        try rejectDirectActuatorActions(in: episode)
        let dataset = makeDataset(
            episode: episode,
            timeStep: timeStep,
            determinismTier: determinismTier,
            purpose: purpose,
            observation: observation,
            provenance: provenance
        )
        let contract: TrainingDatasetContract
        switch purpose {
        case .behaviorCloning:
            contract = TrainingDatasetContract(
                requiresTerminalFacts: false,
                requiresBehaviorCloningSamples: true
            )
        case .reinforcementRollout, .worldModel:
            contract = TrainingDatasetContract(
                requiresTerminalFacts: false,
                requiresCausalTransitions: true
            )
        }
        try TrainingDatasetContractValidator().validate(dataset, against: contract)
        return try write(
            dataset: dataset,
            to: directory
        )
    }

    private func rejectDirectActuatorActions(in episode: RolloutEpisode) throws {
        if let transitions = episode.transitions {
            for (index, transition) in transitions.enumerated() {
                if case .actuatorValues = transition.action {
                    throw TrainingDatasetContractValidator.ValidationError.missingPolicyAction(
                        recordIndex: index
                    )
                }
            }
            return
        }

        for (index, step) in episode.steps.enumerated() {
            guard step.log.driveIntents.isEmpty, !step.log.actuatorValues.isEmpty else { continue }
            throw TrainingDatasetContractValidator.ValidationError.missingPolicyAction(
                recordIndex: index
            )
        }
    }

    func makeDataset(
        episode: RolloutEpisode,
        timeStep: Double,
        determinismTier: String,
        purpose: TrainingDatasetPurpose = .reinforcementRollout,
        observation: TrainingObservationMetadata? = nil,
        provenance: TrainingProvenanceManifest? = nil
    ) -> TrainingDataset {
        let records: [TrainingDatasetRecord]
        if purpose == .behaviorCloning {
            records = buildBehaviorCloningRecords(from: episode)
        } else {
            records = buildTransitionRecords(from: episode)
        }
        let resolvedPhysicsTimeStep = episode.physicsTimeStep ?? timeStep
        let resolvedControlPeriodSteps = episode.controlPeriodSteps ?? 1
        let resolvedTimeStep = resolvedPhysicsTimeStep * Double(resolvedControlPeriodSteps)
        let metadata = TrainingDatasetMetadata(
            scenarioId: episode.scenarioId,
            seed: episode.seed,
            timeStep: resolvedTimeStep,
            determinismTier: determinismTier,
            configHash: episode.configHash,
            channelCount: maxChannelCount(records),
            driveCount: maxDriveCount(records),
            recordCount: records.count,
            purpose: purpose,
            physicsTimeStep: resolvedPhysicsTimeStep,
            controlPeriodSteps: resolvedControlPeriodSteps,
            failureReason: episode.failureReason,
            failureTime: episode.failureTime,
            episodeId: episode.episodeId,
            policyId: episode.policyId,
            rewardSum: episode.rewardSum,
            done: episode.done,
            truncated: episode.truncated,
            terminalReason: episode.terminalReason,
            rewardDescriptor: episode.rewardDescriptor,
            taskReference: episode.taskReference,
            observation: observation,
            provenance: provenance
        )

        return TrainingDataset(metadata: metadata, records: records)
    }

    private func buildTransitionRecords(from episode: RolloutEpisode) -> [TrainingDatasetRecord] {
        guard let transitions = episode.transitions,
              transitions.count == episode.steps.count else {
            return episode.steps.map { legacyTransitionRecord(step: $0, episode: episode) }
        }
        return transitions.map { transition in
            let step = transition.outcome
            let event = step.log
            var sensors = transition.actionObservation.sensorSamples.map { sample in
                TrainingSensorSample(
                    channelIndex: sample.channelIndex,
                    value: sample.value,
                    timestamp: sample.timestamp
                )
            }
            // Achieved per-motor actuator outputs at channels 16-19 so
            // motor-feedback (20ch) tensor materialization can read them;
            // additive and ignored by 16ch consumers.
            let telemetry = transition.actionObservation.actuatorTelemetry.channels
                .sorted { $0.id < $1.id }
            for (offset, channel) in telemetry.prefix(4).enumerated() {
                sensors.append(TrainingSensorSample(
                    channelIndex: UInt32(16 + offset),
                    value: channel.value,
                    timestamp: transition.actionObservation.time.time
                ))
            }
            let reflex = reflexCorrections(from: transition.action)
            return TrainingDatasetRecord(
                time: event.time.time,
                policyDecisionID: transition.decisionID,
                actionObservationTime: actionObservationTime(for: transition),
                actionObservationState: stateVector(from: transition.actionObservation.plantState),
                sensors: sensors,
                driveIntents: driveIntents(from: transition.action),
                reflexCorrections: reflex,
                physicsState: predictedStateVector(
                    from: transition.actionObservation.plantState,
                    dt: transition.duration
                ),
                actualState: stateVector(from: step.observation.plantState),
                actionValues: transition.policyAction.values,
                policyActionEncoding: transition.policyAction.encoding,
                behaviorMean: transition.behaviorStatistics?.mean,
                behaviorLogProbability: transition.behaviorStatistics?.logProbability,
                actuatorCommandValues: actuatorCommandValues(from: event),
                continueValue: (step.done || step.truncated) ? 0.0 : 1.0,
                reward: step.reward,
                done: step.done,
                truncated: step.truncated,
                episodeId: episode.episodeId,
                policyId: episode.policyId
            )
        }
    }

    private func buildBehaviorCloningRecords(from episode: RolloutEpisode) -> [TrainingDatasetRecord] {
        episode.steps.map { step in
            let event = step.log
            let sensors = event.sensorSamples.map { sample in
                TrainingSensorSample(
                    channelIndex: sample.channelIndex,
                    value: sample.value,
                    timestamp: sample.timestamp
                )
            }
            let reflex = event.reflexCorrections.map { correction in
                TrainingReflexCorrection(
                    driveIndex: correction.driveIndex.rawValue,
                    clamp: correction.clampMultiplier,
                    damping: correction.damping,
                    delta: correction.delta
                )
            }
            return TrainingDatasetRecord(
                time: event.time.time,
                actionObservationTime: actionObservationTime(for: event),
                actionObservationState: stateVector(from: step.observation.plantState),
                sensors: sensors,
                driveIntents: driveIntents(from: event),
                reflexCorrections: reflex,
                actualState: stateVector(from: step.observation.plantState),
                actionValues: policyActionValues(from: event),
                policyActionEncoding: "environment",
                actuatorCommandValues: actuatorCommandValues(from: event),
                continueValue: (step.done || step.truncated) ? 0.0 : 1.0,
                reward: step.reward,
                done: step.done,
                truncated: step.truncated,
                episodeId: episode.episodeId,
                policyId: episode.policyId
            )
        }
    }

    private func legacyTransitionRecord(
        step: EnvironmentStep,
        episode: RolloutEpisode
    ) -> TrainingDatasetRecord {
        let event = step.log
        return TrainingDatasetRecord(
            time: event.time.time,
            sensors: event.sensorSamples.map {
                TrainingSensorSample(
                    channelIndex: $0.channelIndex,
                    value: $0.value,
                    timestamp: $0.timestamp
                )
            },
            driveIntents: driveIntents(from: event),
            reflexCorrections: event.reflexCorrections.map {
                TrainingReflexCorrection(
                    driveIndex: $0.driveIndex.rawValue,
                    clamp: $0.clampMultiplier,
                    damping: $0.damping,
                    delta: $0.delta
                )
            },
            actualState: stateVector(from: step.observation.plantState),
            actionValues: policyActionValues(from: event),
            policyActionEncoding: "environment",
            actuatorCommandValues: actuatorCommandValues(from: event),
            continueValue: (step.done || step.truncated) ? 0.0 : 1.0,
            reward: step.reward,
            done: step.done,
            truncated: step.truncated,
            episodeId: episode.episodeId,
            policyId: episode.policyId
        )
    }

    private func maxChannelCount(_ records: [TrainingDatasetRecord]) -> Int {
        let maxIndex = records.flatMap { $0.sensors }.map { Int($0.channelIndex) }.max() ?? -1
        return maxIndex + 1
    }

    private func actionObservationTime(for transition: RolloutTransition) -> Double {
        transition.actionObservation.time.time
    }

    private func actionObservationTime(for event: WorldStepLog) -> Double {
        event.time.time
    }

    private func maxDriveCount(_ records: [TrainingDatasetRecord]) -> Int {
        let maxIndex = records.flatMap { $0.driveIntents }.map { Int($0.driveIndex) }.max() ?? -1
        return maxIndex + 1
    }

    private func driveIntents(from action: EnvironmentAction) -> [TrainingDriveIntent] {
        switch action {
        case .driveIntents(let drives, _):
            return drives.map { intent in
                TrainingDriveIntent(
                    driveIndex: intent.index.rawValue,
                    value: intent.activation,
                    parameters: intent.parameters
                )
            }
        case .actuatorValues:
            return []
        }
    }

    private func driveIntents(from event: WorldStepLog) -> [TrainingDriveIntent] {
        event.driveIntents.map {
            TrainingDriveIntent(
                driveIndex: $0.index.rawValue,
                value: $0.activation,
                parameters: $0.parameters
            )
        }
    }

    private func reflexCorrections(from action: EnvironmentAction) -> [TrainingReflexCorrection] {
        guard case .driveIntents(_, let corrections) = action else { return [] }
        return corrections.map {
            TrainingReflexCorrection(
                driveIndex: $0.driveIndex.rawValue,
                clamp: $0.clampMultiplier,
                damping: $0.damping,
                delta: $0.delta
            )
        }
    }

    private func stateVector(from snapshot: PlantStateSnapshot) -> [Double] {
        let root = snapshot.root
        return [
            root.position.x,
            root.position.y,
            root.position.z,
            root.velocity.x,
            root.velocity.y,
            root.velocity.z,
            root.orientation.w,
            root.orientation.x,
            root.orientation.y,
            root.orientation.z,
            root.angularVelocity.x,
            root.angularVelocity.y,
            root.angularVelocity.z,
        ]
    }

    private func predictedStateVector(from snapshot: PlantStateSnapshot, dt: Double) -> [Double] {
        let root = snapshot.root
        return [
            root.position.x + root.velocity.x * dt,
            root.position.y + root.velocity.y * dt,
            root.position.z + root.velocity.z * dt,
            root.velocity.x,
            root.velocity.y,
            root.velocity.z,
            root.orientation.w,
            root.orientation.x,
            root.orientation.y,
            root.orientation.z,
            root.angularVelocity.x,
            root.angularVelocity.y,
            root.angularVelocity.z,
        ]
    }

    private func policyActionValues(from event: WorldStepLog) -> [Double] {
        if !event.driveIntents.isEmpty {
            return event.driveIntents.sorted { $0.index.rawValue < $1.index.rawValue }.map(\.activation)
        }
        return event.actuatorValues.sorted { $0.index.rawValue < $1.index.rawValue }.map(\.value)
    }

    private func actuatorCommandValues(from event: WorldStepLog) -> [Double]? {
        guard !event.actuatorValues.isEmpty else { return nil }
        return event.actuatorValues.sorted { $0.index.rawValue < $1.index.rawValue }.map(\.value)
    }
}
