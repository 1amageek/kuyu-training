import KuyuCore
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public struct JointTargetActionCodec: Sendable, Equatable {
    public enum CodecError: Error, Sendable, Equatable, CustomStringConvertible {
        case invalidRangeCount(expected: Int, actual: Int)
        case invalidRange(index: Int, lower: Double, upper: Double)
        case unsupportedActionContract(String)
        case nonFiniteValue(index: Int, value: Double)
        case outOfPhysicalRange(index: Int, value: Double, lower: Double, upper: Double)
        case outOfNormalizedRange(index: Int, value: Double, lower: Double, upper: Double)

        public var description: String {
            switch self {
            case .invalidRangeCount(let expected, let actual):
                return "invalid-range-count expected=\(expected) actual=\(actual)"
            case .invalidRange(let index, let lower, let upper):
                return "invalid-range index=\(index) lower=\(lower) upper=\(upper)"
            case .unsupportedActionContract(let reason):
                return "unsupported-action-contract reason=\(reason)"
            case .nonFiniteValue(let index, let value):
                return "non-finite-value index=\(index) value=\(value)"
            case .outOfPhysicalRange(let index, let value, let lower, let upper):
                return "out-of-physical-range index=\(index) value=\(value) lower=\(lower) upper=\(upper)"
            case .outOfNormalizedRange(let index, let value, let lower, let upper):
                return "out-of-normalized-range index=\(index) value=\(value) lower=\(lower) upper=\(upper)"
            }
        }
    }

    public enum DecodingMode: Sendable, Equatable {
        case strict
        case clamped
    }

    public let physicalRanges: [ClosedRange<Double>]
    public let normalizedRanges: [ClosedRange<Double>]

    public init(
        physicalRanges: [ClosedRange<Double>],
        normalizedRanges: [ClosedRange<Double>]
    ) throws {
        guard physicalRanges.count == normalizedRanges.count else {
            throw CodecError.invalidRangeCount(expected: physicalRanges.count, actual: normalizedRanges.count)
        }
        try Self.validate(ranges: physicalRanges)
        try Self.validate(ranges: normalizedRanges)
        self.physicalRanges = physicalRanges
        self.normalizedRanges = normalizedRanges
    }

    public init(
        physicalRanges: [ClosedRange<Double>],
        actionContract: LearningProjectActionContract
    ) throws {
        guard actionContract.kind == .continuous else {
            throw CodecError.unsupportedActionContract("kind.\(actionContract.kind.rawValue)")
        }
        if let driveCount = actionContract.driveCount, driveCount != physicalRanges.count {
            throw CodecError.invalidRangeCount(expected: physicalRanges.count, actual: driveCount)
        }
        guard actionContract.channels.count == physicalRanges.count else {
            throw CodecError.invalidRangeCount(
                expected: physicalRanges.count,
                actual: actionContract.channels.count
            )
        }
        let channels = actionContract.channels.sorted { $0.index < $1.index }
        guard channels.map(\.index) == Array(0..<physicalRanges.count) else {
            throw CodecError.unsupportedActionContract("non-contiguous-channel-indices")
        }
        let normalizedRanges = channels.map { $0.normalizedLowerBound...$0.normalizedUpperBound }
        try self.init(physicalRanges: physicalRanges, normalizedRanges: normalizedRanges)
    }

    public func normalizedActions(fromPhysicalTargets targets: [Double]) throws -> [Double] {
        guard targets.count == physicalRanges.count else {
            throw CodecError.invalidRangeCount(expected: physicalRanges.count, actual: targets.count)
        }
        return try targets.enumerated().map { index, value in
            try ensureFinite(value, index: index)
            let source = physicalRanges[index]
            try ensureContainsPhysical(value, range: source, index: index)
            return map(value: clamped(value, to: source), from: source, to: normalizedRanges[index])
        }
    }

    public func physicalTargets(
        fromNormalizedActions actions: [Double],
        decodingMode: DecodingMode = .strict
    ) throws -> [Double] {
        guard actions.count == normalizedRanges.count else {
            throw CodecError.invalidRangeCount(expected: normalizedRanges.count, actual: actions.count)
        }
        return try actions.enumerated().map { index, value in
            try ensureFinite(value, index: index)
            let source = normalizedRanges[index]
            let normalized: Double
            switch decodingMode {
            case .strict:
                try ensureContainsNormalized(value, range: source, index: index)
                normalized = value
            case .clamped:
                normalized = clamped(value, to: source)
            }
            return map(value: normalized, from: source, to: physicalRanges[index])
        }
    }

    public func trainingDriveIntents(fromPhysicalTargets targets: [Double]) throws -> [TrainingDriveIntent] {
        let actions = try normalizedActions(fromPhysicalTargets: targets)
        return actions.enumerated().map { index, value in
            TrainingDriveIntent(driveIndex: UInt32(index), value: value)
        }
    }

    public func driveIntents(
        fromNormalizedActions actions: [Double],
        decodingMode: DecodingMode = .strict
    ) throws -> [DriveIntent] {
        let targets = try physicalTargets(fromNormalizedActions: actions, decodingMode: decodingMode)
        return try targets.enumerated().map { index, value in
            try DriveIntent(index: DriveIndex(UInt32(index)), activation: value)
        }
    }

    private static func validate(ranges: [ClosedRange<Double>]) throws {
        for (index, range) in ranges.enumerated() {
            guard range.lowerBound.isFinite, range.upperBound.isFinite, range.lowerBound < range.upperBound else {
                throw CodecError.invalidRange(index: index, lower: range.lowerBound, upper: range.upperBound)
            }
        }
    }

    private func ensureFinite(_ value: Double, index: Int) throws {
        guard value.isFinite else {
            throw CodecError.nonFiniteValue(index: index, value: value)
        }
    }

    private func ensureContainsPhysical(_ value: Double, range: ClosedRange<Double>, index: Int) throws {
        guard range.contains(value) else {
            throw CodecError.outOfPhysicalRange(
                index: index,
                value: value,
                lower: range.lowerBound,
                upper: range.upperBound
            )
        }
    }

    private func ensureContainsNormalized(_ value: Double, range: ClosedRange<Double>, index: Int) throws {
        guard range.contains(value) else {
            throw CodecError.outOfNormalizedRange(
                index: index,
                value: value,
                lower: range.lowerBound,
                upper: range.upperBound
            )
        }
    }

    private func map(
        value: Double,
        from source: ClosedRange<Double>,
        to target: ClosedRange<Double>
    ) -> Double {
        let fraction = (value - source.lowerBound) / (source.upperBound - source.lowerBound)
        return target.lowerBound + fraction * (target.upperBound - target.lowerBound)
    }

    private func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
