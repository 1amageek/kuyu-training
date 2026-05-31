import Foundation
import KuyuCore
import KuyuPhysics

public struct RoArmM1JointTargetTrainingDatasetBuilderConfig: Sendable, Equatable {
    public let goal: RoArmM1JointTargetTrainingGoal
    public let policyID: String
    public let episodeID: String
    public let jointRanges: [ClosedRange<Double>]
    public let includeHindsightRelabels: Bool

    public init(
        goal: RoArmM1JointTargetTrainingGoal = .canonical,
        policyID: String = "roarm-m1-joint-target-teacher-v1",
        episodeID: String = "roarm-m1-joint-target-smoke",
        jointRanges: [ClosedRange<Double>] = RoArmM1ServoCommandEncoder.manufacturerJointLimits,
        includeHindsightRelabels: Bool = true
    ) {
        self.goal = goal
        self.policyID = policyID
        self.episodeID = episodeID
        self.jointRanges = jointRanges
        self.includeHindsightRelabels = includeHindsightRelabels
    }
}

public struct RoArmM1JointTargetTrainingResult: Sendable, Equatable {
    public let dataset: TrainingDataset
    public let report: RoArmM1JointTargetTrainingReport

    public init(dataset: TrainingDataset, report: RoArmM1JointTargetTrainingReport) {
        self.dataset = dataset
        self.report = report
    }
}

public struct RoArmM1JointTargetTrainingDatasetBuilder: Sendable {
    public enum BuildError: Error, Sendable, Equatable, CustomStringConvertible {
        case emptyLog
        case invalidJointRangeCount(expected: Int, actual: Int)
        case missingScalar(String)
        case nonFiniteScalar(String)

        public var description: String {
            switch self {
            case .emptyLog:
                return "empty-log"
            case .invalidJointRangeCount(let expected, let actual):
                return "invalid-joint-range-count expected=\(expected) actual=\(actual)"
            case .missingScalar(let id):
                return "missing-scalar id=\(id)"
            case .nonFiniteScalar(let id):
                return "non-finite-scalar id=\(id)"
            }
        }
    }

    public let config: RoArmM1JointTargetTrainingDatasetBuilderConfig

    public init(config: RoArmM1JointTargetTrainingDatasetBuilderConfig = RoArmM1JointTargetTrainingDatasetBuilderConfig()) {
        self.config = config
    }

    public func build(from log: SimulationLog) throws -> RoArmM1JointTargetTrainingResult {
        guard !log.events.isEmpty else {
            throw BuildError.emptyLog
        }
        let jointCount = RoArmM1ServoCommandEncoder.jointCount
        guard config.jointRanges.count == jointCount else {
            throw BuildError.invalidJointRangeCount(expected: jointCount, actual: config.jointRanges.count)
        }

        var records: [TrainingDatasetRecord] = []
        records.reserveCapacity(log.events.count * (config.includeHindsightRelabels ? 2 : 1))
        var aggregate = MetricsAccumulator(jointCount: jointCount)

        for (eventIndex, event) in log.events.enumerated() {
            let isLastSourceRecord = eventIndex == log.events.count - 1
            let jointState = try extractJointState(from: event)
            let reward = reward(for: jointState)
            aggregate.append(jointState: jointState, reward: reward, ranges: config.jointRanges)
            records.append(
                makeRecord(
                    event: event,
                    jointState: jointState,
                    reward: reward,
                    isHindsight: false,
                    done: isLastSourceRecord
                )
            )

            if config.includeHindsightRelabels {
                let hindsightState = jointState.asAchievedGoal()
                records.append(
                    makeRecord(
                        event: event,
                        jointState: hindsightState,
                        reward: 1.0,
                        isHindsight: true,
                        done: isLastSourceRecord
                    )
                )
            }
        }

        let report = makeReport(
            log: log,
            aggregate: aggregate,
            recordCount: records.count,
            sourceRecordCount: log.events.count,
            hindsightRecordCount: records.count - log.events.count
        )
        let metadata = TrainingDatasetMetadata(
            scenarioId: log.scenarioId.rawValue,
            seed: log.seed.rawValue,
            timeStep: log.timeStep.delta,
            determinismTier: log.determinism.tier.rawValue,
            configHash: "\(log.configHash)-\(config.goal.goalID)",
            channelCount: RoArmM1JointTargetObservation.channelCount,
            driveCount: RoArmM1ServoCommandEncoder.jointCount,
            recordCount: records.count,
            failureReason: log.failureReason?.rawValue,
            failureTime: log.failureTime,
            episodeId: config.episodeID,
            policyId: config.policyID,
            rewardSum: report.rewardSum,
            done: report.passed,
            truncated: false,
            terminalReason: report.passed ? "goal-achieved" : "goal-not-achieved",
            rewardDescriptor: RewardDescriptor(
                id: "roarm-m1-joint-target-dense-reward",
                version: "v1",
                configHash: config.goal.goalID
            ),
            observation: RoArmM1JointTargetObservation.metadata(),
            provenance: nil
        )
        return RoArmM1JointTargetTrainingResult(
            dataset: TrainingDataset(metadata: metadata, records: records),
            report: report
        )
    }

    @discardableResult
    public func write(result: RoArmM1JointTargetTrainingResult, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let datasetDirectory = directory.appendingPathComponent("dataset", isDirectory: true)
        try TrainingDatasetWriter().write(dataset: result.dataset, to: datasetDirectory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let reportURL = directory.appendingPathComponent("roarm-m1-joint-target-training-report.json")
        try encoder.encode(result.report).write(to: reportURL, options: [.atomic])
        return directory
    }

    private func extractJointState(from event: WorldStepLog) throws -> RoArmM1JointTargetState {
        var positions: [Double] = []
        var velocities: [Double] = []
        var targets: [Double] = []
        var torques: [Double] = []
        positions.reserveCapacity(RoArmM1ServoCommandEncoder.jointCount)
        velocities.reserveCapacity(RoArmM1ServoCommandEncoder.jointCount)
        targets.reserveCapacity(RoArmM1ServoCommandEncoder.jointCount)
        torques.reserveCapacity(RoArmM1ServoCommandEncoder.jointCount)

        for index in 1...RoArmM1ServoCommandEncoder.jointCount {
            let signalID = "joint_\(index)"
            positions.append(try scalar(signalID, from: event))
            velocities.append(try scalar("velocity_\(signalID)", from: event))
            targets.append(try scalar("target_\(signalID)", from: event))
            torques.append(try scalar("torque_\(signalID)", from: event))
        }

        return RoArmM1JointTargetState(
            positions: positions,
            velocities: velocities,
            targets: targets,
            torques: torques,
            ranges: config.jointRanges
        )
    }

    private func scalar(_ id: String, from event: WorldStepLog) throws -> Double {
        guard let value = event.plantState.scalars[id] else {
            throw BuildError.missingScalar(id)
        }
        guard value.isFinite else {
            throw BuildError.nonFiniteScalar(id)
        }
        return value
    }

    private func reward(for state: RoArmM1JointTargetState) -> Double {
        let normalizedError = state.errors.enumerated().map { index, error in
            abs(error) / max(config.jointRanges[index].upperBound - config.jointRanges[index].lowerBound, 1e-6)
        }.reduce(0, +) / Double(state.errors.count)
        let normalizedVelocity = state.velocities.map { abs($0) }.reduce(0, +) / Double(state.velocities.count)
        let limitPenalty = state.limitViolationCount > 0 ? 1.0 : 0.0
        return max(-1.0, 1.0 - normalizedError * 4.0 - normalizedVelocity * 0.02 - limitPenalty)
    }

    private func makeRecord(
        event: WorldStepLog,
        jointState: RoArmM1JointTargetState,
        reward: Double,
        isHindsight: Bool,
        done: Bool
    ) -> TrainingDatasetRecord {
        let targetActions = isHindsight ? jointState.positions : jointState.targets
        let sensors = RoArmM1JointTargetObservation.samples(
            state: jointState,
            timestamp: event.time.time
        )
        let drives = targetActions.enumerated().map { index, value in
            TrainingDriveIntent(driveIndex: UInt32(index), value: value, parameters: [])
        }
        return TrainingDatasetRecord(
            time: event.time.time,
            sensors: sensors,
            driveIntents: drives,
            reflexCorrections: [],
            physicsState: jointState.physicsState,
            actualState: jointState.observationState,
            actionValues: targetActions,
            continueValue: done ? 0.0 : 1.0,
            reward: reward,
            done: done,
            truncated: false,
            episodeId: config.episodeID,
            policyId: config.policyID
        )
    }

    private func makeReport(
        log: SimulationLog,
        aggregate: MetricsAccumulator,
        recordCount: Int,
        sourceRecordCount: Int,
        hindsightRecordCount: Int
    ) -> RoArmM1JointTargetTrainingReport {
        let perJoint = aggregate.perJointMetrics()
        let status: RoArmM1JointTargetTrainingStatus
        if aggregate.nonFiniteRecordCount == 0,
           aggregate.jointLimitViolationCount == 0,
           aggregate.meanAbsoluteError <= config.goal.targetMeanAbsoluteErrorRadians,
           aggregate.maximumAbsoluteError <= config.goal.targetMaximumAbsoluteErrorRadians,
           aggregate.movementMagnitude >= config.goal.minimumMovementRadians {
            status = .achieved
        } else {
            status = .notAchieved
        }

        return RoArmM1JointTargetTrainingReport(
            goal: config.goal,
            status: status,
            scenarioID: log.scenarioId.rawValue,
            seed: log.seed.rawValue,
            durationSeconds: Double(sourceRecordCount) * log.timeStep.delta,
            timeStepSeconds: log.timeStep.delta,
            recordCount: recordCount,
            sourceRecordCount: sourceRecordCount,
            hindsightRecordCount: hindsightRecordCount,
            rewardSum: aggregate.rewardSum + Double(hindsightRecordCount),
            meanAbsoluteErrorRadians: aggregate.meanAbsoluteError,
            maximumAbsoluteErrorRadians: aggregate.maximumAbsoluteError,
            maximumAbsoluteVelocityRadiansPerSecond: aggregate.maximumAbsoluteVelocity,
            movementMagnitudeRadians: aggregate.movementMagnitude,
            jointLimitViolationCount: aggregate.jointLimitViolationCount,
            nonFiniteRecordCount: aggregate.nonFiniteRecordCount,
            perJoint: perJoint,
            activeEfficiencyTechniqueIDs: [
                "roarm-m1-teacher-trajectory-bootstrap-v1",
                "roarm-m1-hindsight-goal-relabeling-v1",
                "roarm-m1-model-based-state-tuples-v1"
            ]
        )
    }
}

private struct RoArmM1JointTargetState: Sendable, Equatable {
    let positions: [Double]
    let velocities: [Double]
    let targets: [Double]
    let torques: [Double]
    let ranges: [ClosedRange<Double>]

    var errors: [Double] {
        zip(targets, positions).map { $0 - $1 }
    }

    var limitViolationCount: Int {
        positions.enumerated().filter { index, position in
            !ranges[index].contains(position)
        }.count
    }

    var observationState: [Double] {
        positions + velocities + errors + lowerMargins + upperMargins
    }

    var physicsState: [Double] {
        positions + velocities + targets + torques
    }

    var lowerMargins: [Double] {
        positions.enumerated().map { index, position in
            position - ranges[index].lowerBound
        }
    }

    var upperMargins: [Double] {
        positions.enumerated().map { index, position in
            ranges[index].upperBound - position
        }
    }

    func asAchievedGoal() -> RoArmM1JointTargetState {
        RoArmM1JointTargetState(
            positions: positions,
            velocities: velocities,
            targets: positions,
            torques: torques,
            ranges: ranges
        )
    }
}

private enum RoArmM1JointTargetObservation {
    static let channelCount = 25

    static func metadata() -> TrainingObservationMetadata {
        TrainingObservationMetadata(
            clock: TrainingObservationClockMetadata(
                timebase: "kuyu-world-time",
                maxSkewMs: 0,
                syncPolicy: "single-authoritative-simulation-step"
            ),
            modalities: [
                TrainingObservationModalityMetadata(
                    id: "roarm-m1-proprioception",
                    type: "joint-state",
                    channels: channelNames,
                    timestampSource: "WorldStepLog.time",
                    provenance: TrainingObservationProvenanceMetadata(
                        producer: "ArticulatedRigidBodySimulator",
                        transport: "in-process",
                        notes: "Camera-free RoArm M1 joint target tracking observation."
                    )
                )
            ]
        )
    }

    static func samples(
        state: RoArmM1JointTargetState,
        timestamp: Double
    ) -> [TrainingSensorSample] {
        state.observationState.enumerated().map { index, value in
            TrainingSensorSample(channelIndex: UInt32(index), value: value, timestamp: timestamp)
        }
    }

    private static var channelNames: [String] {
        let joints = (1...RoArmM1ServoCommandEncoder.jointCount).map { "joint\($0)" }
        return joints.map { "\($0)Position" }
            + joints.map { "\($0)Velocity" }
            + joints.map { "\($0)TargetError" }
            + joints.map { "\($0)LowerLimitMargin" }
            + joints.map { "\($0)UpperLimitMargin" }
    }
}

private struct MetricsAccumulator: Sendable, Equatable {
    private var errorSums: [Double]
    private var maximumErrors: [Double]
    private var maximumVelocities: [Double]
    private var limitViolations: [Int]
    private var totalError: Double = 0
    private var sampleCount: Int = 0

    var rewardSum: Double = 0
    var maximumAbsoluteError: Double = 0
    var maximumAbsoluteVelocity: Double = 0
    var movementMagnitude: Double = 0
    var jointLimitViolationCount: Int = 0
    var nonFiniteRecordCount: Int = 0

    init(jointCount: Int) {
        self.errorSums = Array(repeating: 0, count: jointCount)
        self.maximumErrors = Array(repeating: 0, count: jointCount)
        self.maximumVelocities = Array(repeating: 0, count: jointCount)
        self.limitViolations = Array(repeating: 0, count: jointCount)
    }

    var meanAbsoluteError: Double {
        guard sampleCount > 0 else { return 0 }
        return totalError / Double(sampleCount)
    }

    mutating func append(
        jointState: RoArmM1JointTargetState,
        reward: Double,
        ranges: [ClosedRange<Double>]
    ) {
        rewardSum += reward
        for index in jointState.positions.indices {
            let position = jointState.positions[index]
            let velocity = jointState.velocities[index]
            let error = abs(jointState.errors[index])
            if !position.isFinite || !velocity.isFinite || !error.isFinite {
                nonFiniteRecordCount += 1
                continue
            }
            errorSums[index] += error
            maximumErrors[index] = max(maximumErrors[index], error)
            maximumVelocities[index] = max(maximumVelocities[index], abs(velocity))
            maximumAbsoluteError = max(maximumAbsoluteError, error)
            maximumAbsoluteVelocity = max(maximumAbsoluteVelocity, abs(velocity))
            movementMagnitude = max(movementMagnitude, abs(position))
            totalError += error
            sampleCount += 1
            if !ranges[index].contains(position) {
                limitViolations[index] += 1
                jointLimitViolationCount += 1
            }
        }
    }

    func perJointMetrics() -> [RoArmM1JointTargetPerJointMetrics] {
        errorSums.indices.map { index in
            let denominator = max(sampleCount / max(errorSums.count, 1), 1)
            return RoArmM1JointTargetPerJointMetrics(
                jointID: "joint_\(index + 1)",
                meanAbsoluteErrorRadians: errorSums[index] / Double(denominator),
                maximumAbsoluteErrorRadians: maximumErrors[index],
                maximumAbsoluteVelocityRadiansPerSecond: maximumVelocities[index],
                jointLimitViolationCount: limitViolations[index]
            )
        }
    }
}
