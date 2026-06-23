import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
public struct RoArmM1JointTargetObservationEncoder: Sendable, Equatable {
    public enum EncodingError: Error, Sendable, Equatable, CustomStringConvertible {
        case invalidValueCount(field: String, expected: Int, actual: Int)
        case invalidRange(index: Int, lower: Double, upper: Double)
        case nonFiniteValue(field: String, index: Int, value: Double)

        public var description: String {
            switch self {
            case .invalidValueCount(let field, let expected, let actual):
                return "invalid-value-count field=\(field) expected=\(expected) actual=\(actual)"
            case .invalidRange(let index, let lower, let upper):
                return "invalid-range index=\(index) lower=\(lower) upper=\(upper)"
            case .nonFiniteValue(let field, let index, let value):
                return "non-finite-value field=\(field) index=\(index) value=\(value)"
            }
        }
    }

    public static let channelCount = RoArmM1ArmGripperSemantics.observationChannelNames.count

    public init() {}

    public static func metadata() -> TrainingObservationMetadata {
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
                    channels: RoArmM1ArmGripperSemantics.observationChannelNames,
                    timestampSource: "WorldStepLog.time",
                    provenance: TrainingObservationProvenanceMetadata(
                        producer: "ArticulatedRigidBodySimulator",
                        transport: "in-process",
                        notes: "Camera-free RoArm M1 arm and gripper target tracking observation."
                    )
                )
            ]
        )
    }

    public static func observationState(
        positions: [Double],
        velocities: [Double],
        targets: [Double],
        ranges: [ClosedRange<Double>]
    ) throws -> [Double] {
        let count = RoArmM1ArmGripperSemantics.driveIDs.count
        try validate(values: positions, field: "positions", expectedCount: count)
        try validate(values: velocities, field: "velocities", expectedCount: count)
        try validate(values: targets, field: "targets", expectedCount: count)
        guard ranges.count == count else {
            throw EncodingError.invalidValueCount(field: "ranges", expected: count, actual: ranges.count)
        }
        for (index, range) in ranges.enumerated() {
            guard range.lowerBound.isFinite, range.upperBound.isFinite, range.lowerBound < range.upperBound else {
                throw EncodingError.invalidRange(index: index, lower: range.lowerBound, upper: range.upperBound)
            }
        }

        let errors = zip(targets, positions).map { $0 - $1 }
        let lowerMargins = positions.enumerated().map { index, position in
            position - ranges[index].lowerBound
        }
        let upperMargins = positions.enumerated().map { index, position in
            ranges[index].upperBound - position
        }
        return positions + velocities + errors + lowerMargins + upperMargins
    }

    public static func samples(
        positions: [Double],
        velocities: [Double],
        targets: [Double],
        ranges: [ClosedRange<Double>],
        timestamp: Double
    ) throws -> [TrainingSensorSample] {
        try samples(
            observationState: observationState(
                positions: positions,
                velocities: velocities,
                targets: targets,
                ranges: ranges
            ),
            timestamp: timestamp
        )
    }

    public static func samples(
        observationState: [Double],
        timestamp: Double
    ) throws -> [TrainingSensorSample] {
        try validate(values: observationState, field: "observationState", expectedCount: channelCount)
        guard timestamp.isFinite else {
            throw EncodingError.nonFiniteValue(field: "timestamp", index: 0, value: timestamp)
        }
        return observationState.enumerated().map { index, value in
            TrainingSensorSample(channelIndex: UInt32(index), value: value, timestamp: timestamp)
        }
    }

    private static func validate(values: [Double], field: String, expectedCount: Int) throws {
        guard values.count == expectedCount else {
            throw EncodingError.invalidValueCount(field: field, expected: expectedCount, actual: values.count)
        }
        for (index, value) in values.enumerated() {
            guard value.isFinite else {
                throw EncodingError.nonFiniteValue(field: field, index: index, value: value)
            }
        }
    }
}
