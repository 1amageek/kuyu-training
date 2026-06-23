import Foundation
import KuyuCore
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public struct CheckpointEvaluationDiagnostics: Sendable, Codable, Equatable {
    public let scenarioComparisons: [CheckpointEvaluationScenarioDiagnostics]
    public let worstFinalAltitudeDelta: Double?
    public let worstFinalVerticalVelocityDelta: Double?
    public let worstMotorOutputMAE: Double?
    public let earliestAltitudeDivergenceTime: Double?

    public init(scenarioComparisons: [CheckpointEvaluationScenarioDiagnostics]) {
        self.scenarioComparisons = scenarioComparisons.sorted()
        self.worstFinalAltitudeDelta = Self.maxMagnitude(scenarioComparisons.map(\.finalAltitudeDelta))
        self.worstFinalVerticalVelocityDelta = Self.maxMagnitude(
            scenarioComparisons.map(\.finalVerticalVelocityDelta)
        )
        self.worstMotorOutputMAE = scenarioComparisons.compactMap(\.motorOutputMAE).max()
        self.earliestAltitudeDivergenceTime = scenarioComparisons.compactMap(\.altitudeDivergenceTime).min()
    }

    public init(
        teacher: KuyAtt1RunOutput,
        policy: KuyAtt1RunOutput,
        altitudeDivergenceThreshold: Double = 0.25,
        earlyWindowDuration: Double = 0.25
    ) {
        let teacherLogs = Self.logsByKey(teacher.logs)
        let policyLogs = Self.logsByKey(policy.logs)
        let keys = Set(teacherLogs.keys).union(policyLogs.keys).sorted()
        self.init(
            scenarioComparisons: keys.map { key in
                CheckpointEvaluationScenarioDiagnostics(
                    key: key,
                    teacherLog: teacherLogs[key],
                    policyLog: policyLogs[key],
                    altitudeDivergenceThreshold: altitudeDivergenceThreshold,
                    earlyWindowDuration: earlyWindowDuration
                )
            }
        )
    }

    private static func logsByKey(_ entries: [ScenarioLogEntry]) -> [CheckpointEvaluationScenarioKey: SimulationLog] {
        var logs: [CheckpointEvaluationScenarioKey: SimulationLog] = [:]
        for entry in entries {
            let key = CheckpointEvaluationScenarioKey(
                scenarioID: entry.key.scenarioId.rawValue,
                seed: entry.key.seed.rawValue
            )
            logs[key] = entry.log
        }
        return logs
    }

    private static func maxMagnitude(_ values: [Double?]) -> Double? {
        let finiteValues = values.compactMap { $0 }
        guard !finiteValues.isEmpty else { return nil }
        return finiteValues.max { abs($0) < abs($1) }
    }
}

public struct CheckpointEvaluationScenarioDiagnostics: Sendable, Codable, Equatable, Comparable {
    public let scenarioID: String
    public let seed: UInt64
    public let teacherFailureReason: String?
    public let policyFailureReason: String?
    public let teacherFailureTime: Double?
    public let policyFailureTime: Double?
    public let initialAltitudeDelta: Double?
    public let finalAltitudeDelta: Double?
    public let minAltitudeDelta: Double?
    public let maxAltitudeDelta: Double?
    public let finalVerticalVelocityDelta: Double?
    public let altitudeDivergenceTime: Double?
    public let driveActivationMAE: Double?
    public let motorOutputMAE: Double?
    public let policyInitialDriveActivation: Double?
    public let teacherInitialDriveActivation: Double?
    public let policyInitialMotorOutput: Double?
    public let teacherInitialMotorOutput: Double?
    public let policyEarlyDriveActivationAverage: Double?
    public let teacherEarlyDriveActivationAverage: Double?
    public let policyEarlyMotorOutputAverage: Double?
    public let teacherEarlyMotorOutputAverage: Double?
    public let policyAverageMotorOutput: Double?
    public let teacherAverageMotorOutput: Double?
    public let policyAverageDriveActivation: Double?
    public let teacherAverageDriveActivation: Double?

    public init(
        key: CheckpointEvaluationScenarioKey,
        teacherLog: SimulationLog?,
        policyLog: SimulationLog?,
        altitudeDivergenceThreshold: Double,
        earlyWindowDuration: Double = 0.25
    ) {
        self.scenarioID = key.scenarioID
        self.seed = key.seed
        self.teacherFailureReason = teacherLog?.failureReason?.rawValue
        self.policyFailureReason = policyLog?.failureReason?.rawValue
        self.teacherFailureTime = teacherLog?.failureTime
        self.policyFailureTime = policyLog?.failureTime

        let teacherEvents = teacherLog?.events ?? []
        let policyEvents = policyLog?.events ?? []
        let pairedEvents = Array(zip(teacherEvents, policyEvents))
        let altitudeDeltas = pairedEvents.map { pair in
            pair.1.plantState.root.position.z - pair.0.plantState.root.position.z
        }
        let verticalVelocityDeltas = pairedEvents.map { pair in
            pair.1.plantState.root.velocity.z - pair.0.plantState.root.velocity.z
        }
        self.initialAltitudeDelta = altitudeDeltas.first
        self.finalAltitudeDelta = altitudeDeltas.last
        self.minAltitudeDelta = altitudeDeltas.min()
        self.maxAltitudeDelta = altitudeDeltas.max()
        self.finalVerticalVelocityDelta = verticalVelocityDeltas.last
        self.altitudeDivergenceTime = pairedEvents.first { pair in
            abs(pair.1.plantState.root.position.z - pair.0.plantState.root.position.z) >= altitudeDivergenceThreshold
        }?.1.time.time
        self.driveActivationMAE = Self.meanAbsoluteError(
            policyEvents.flatMap { $0.driveIntents.map(\.activation) },
            teacherEvents.flatMap { $0.driveIntents.map(\.activation) }
        )
        self.motorOutputMAE = Self.meanAbsoluteError(
            policyEvents.flatMap { $0.motorNerveTrace?.uOut ?? [] },
            teacherEvents.flatMap { $0.motorNerveTrace?.uOut ?? [] }
        )
        self.policyInitialDriveActivation = Self.firstDriveActivation(policyEvents)
        self.teacherInitialDriveActivation = Self.firstDriveActivation(teacherEvents)
        self.policyInitialMotorOutput = Self.firstMotorOutput(policyEvents)
        self.teacherInitialMotorOutput = Self.firstMotorOutput(teacherEvents)
        self.policyEarlyDriveActivationAverage = Self.averageDriveActivation(
            policyEvents,
            through: earlyWindowDuration
        )
        self.teacherEarlyDriveActivationAverage = Self.averageDriveActivation(
            teacherEvents,
            through: earlyWindowDuration
        )
        self.policyEarlyMotorOutputAverage = Self.averageMotorOutput(
            policyEvents,
            through: earlyWindowDuration
        )
        self.teacherEarlyMotorOutputAverage = Self.averageMotorOutput(
            teacherEvents,
            through: earlyWindowDuration
        )
        self.policyAverageMotorOutput = Self.average(policyEvents.flatMap { $0.motorNerveTrace?.uOut ?? [] })
        self.teacherAverageMotorOutput = Self.average(teacherEvents.flatMap { $0.motorNerveTrace?.uOut ?? [] })
        self.policyAverageDriveActivation = Self.average(policyEvents.flatMap { $0.driveIntents.map(\.activation) })
        self.teacherAverageDriveActivation = Self.average(teacherEvents.flatMap { $0.driveIntents.map(\.activation) })
    }

    public static func < (
        lhs: CheckpointEvaluationScenarioDiagnostics,
        rhs: CheckpointEvaluationScenarioDiagnostics
    ) -> Bool {
        if lhs.scenarioID != rhs.scenarioID {
            return lhs.scenarioID < rhs.scenarioID
        }
        return lhs.seed < rhs.seed
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func meanAbsoluteError(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return nil }
        return zip(lhs, rhs).reduce(0.0) { partial, pair in
            partial + abs(pair.0 - pair.1)
        } / Double(lhs.count)
    }

    private static func firstDriveActivation(_ events: [WorldStepLog]) -> Double? {
        events.lazy
            .flatMap { $0.driveIntents.map(\.activation) }
            .first
    }

    private static func firstMotorOutput(_ events: [WorldStepLog]) -> Double? {
        events.lazy
            .flatMap { $0.motorNerveTrace?.uOut ?? [] }
            .first
    }

    private static func averageDriveActivation(
        _ events: [WorldStepLog],
        through duration: Double
    ) -> Double? {
        average(events.filter { $0.time.time <= duration }.flatMap { $0.driveIntents.map(\.activation) })
    }

    private static func averageMotorOutput(
        _ events: [WorldStepLog],
        through duration: Double
    ) -> Double? {
        average(events.filter { $0.time.time <= duration }.flatMap { $0.motorNerveTrace?.uOut ?? [] })
    }
}
