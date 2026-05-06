import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public protocol ReferenceQuadrotorPolicyFactory: Sendable {
    var policyID: String { get }
    func makePolicy(
        definition: ReferenceQuadrotorScenarioDefinition,
        workerIndex: Int
    ) throws -> any ReferenceQuadrotorEnvironmentPolicy
}

public struct KuyAtt1BaselinePolicyFactory: ReferenceQuadrotorPolicyFactory {
    public let policyID: String
    public let parameters: ReferenceQuadrotorParameters
    public let gains: ImuRateDampingCutGains
    public let mode: KuyAtt1BaselineMode

    public init(
        parameters: ReferenceQuadrotorParameters = .baseline,
        gains: ImuRateDampingCutGains,
        mode: KuyAtt1BaselineMode
    ) {
        self.parameters = parameters
        self.gains = gains
        self.mode = mode
        switch mode {
        case .teacher:
            self.policyID = "teacherBaseline"
        case .sensor:
            self.policyID = "sensorBaseline"
        }
    }

    public func makePolicy(
        definition: ReferenceQuadrotorScenarioDefinition,
        workerIndex: Int
    ) throws -> any ReferenceQuadrotorEnvironmentPolicy {
        switch definition.kind {
        case .liftHover, .singleLiftHover:
            return try KuyLiftBaselineEnvironmentPolicy(
                definition: definition,
                parameters: parameters,
                mode: mode,
                hoverThrustScale: gains.hoverThrustScale
            )
        case .hoverStart, .impulseTorqueShock, .sustainedWindTorque, .sensorDriftStress, .actuatorDegradation:
            return try KuyAtt1BaselineEnvironmentPolicy(
                definition: definition,
                parameters: parameters,
                gains: gains,
                mode: mode
            )
        }
    }
}

public struct RolloutEpisode: Sendable, Codable, Equatable {
    public let episodeId: String
    public let scenarioId: String
    public let seed: UInt64
    public let workerIndex: Int
    public let policyId: String
    public let configHash: String
    public let descriptorId: String?
    public let rewardDescriptor: RewardDescriptor?
    public let rewardSum: Double
    public let done: Bool
    public let truncated: Bool
    public let terminalReason: String?
    public let failureReason: String?
    public let failureTime: Double?
    public let stepCount: Int
    public let workerCount: Int?
    public let maxSteps: Int?
    public let durationSeconds: Double
    public let cancelled: Bool
    public let steps: [EnvironmentStep]

    public init(
        episodeId: String,
        scenarioId: String,
        seed: UInt64,
        workerIndex: Int,
        policyId: String,
        configHash: String,
        descriptorId: String?,
        rewardDescriptor: RewardDescriptor? = nil,
        rewardSum: Double,
        done: Bool,
        truncated: Bool,
        terminalReason: String?,
        failureReason: String?,
        failureTime: Double?,
        stepCount: Int,
        workerCount: Int? = nil,
        maxSteps: Int? = nil,
        durationSeconds: Double,
        cancelled: Bool = false,
        steps: [EnvironmentStep]
    ) {
        self.episodeId = episodeId
        self.scenarioId = scenarioId
        self.seed = seed
        self.workerIndex = workerIndex
        self.policyId = policyId
        self.configHash = configHash
        self.descriptorId = descriptorId
        self.rewardDescriptor = rewardDescriptor
        self.rewardSum = rewardSum
        self.done = done
        self.truncated = truncated
        self.terminalReason = terminalReason
        self.failureReason = failureReason
        self.failureTime = failureTime
        self.stepCount = stepCount
        self.workerCount = workerCount
        self.maxSteps = maxSteps
        self.durationSeconds = durationSeconds
        self.cancelled = cancelled
        self.steps = steps
    }
}

public struct RolloutSummary: Sendable, Codable, Equatable {
    public let episodeCount: Int
    public let rewardDescriptor: RewardDescriptor?
    public let rewardSum: Double
    public let doneCount: Int
    public let truncatedCount: Int
    public let failureCount: Int
    public let cancelledCount: Int

    public init(episodes: [RolloutEpisode]) {
        self.episodeCount = episodes.count
        self.rewardDescriptor = episodes.first?.rewardDescriptor
        self.rewardSum = episodes.reduce(0.0) { $0 + $1.rewardSum }
        self.doneCount = episodes.filter(\.done).count
        self.truncatedCount = episodes.filter(\.truncated).count
        self.failureCount = episodes.filter { $0.failureReason != nil }.count
        self.cancelledCount = episodes.filter(\.cancelled).count
    }
}

public struct RolloutRunner: Sendable {
    public enum RolloutError: Error, Equatable {
        case emptyEpisode(scenarioId: String, seed: UInt64)
        case cancelled(scenarioId: String, seed: UInt64)
        case exceededMaxSteps(scenarioId: String, seed: UInt64, maxSteps: Int)
        case exceededMaxWallTime(scenarioId: String, seed: UInt64, maxWallTimeSeconds: Double)
        case invalidMaxSteps(Int)
        case invalidMaxWallTime(Double)
    }

    public struct Limits: Sendable, Codable, Equatable {
        public let maxStepsPerEpisode: Int?
        public let maxWallTimeSeconds: Double?

        public init(maxStepsPerEpisode: Int? = nil, maxWallTimeSeconds: Double? = nil) {
            self.maxStepsPerEpisode = maxStepsPerEpisode
            self.maxWallTimeSeconds = maxWallTimeSeconds
        }

        public static func validated(maxStepsPerEpisode: Int? = nil, maxWallTimeSeconds: Double? = nil) throws -> Limits {
            if let maxStepsPerEpisode, maxStepsPerEpisode <= 0 {
                throw RolloutError.invalidMaxSteps(maxStepsPerEpisode)
            }
            if let maxWallTimeSeconds, !(maxWallTimeSeconds.isFinite && maxWallTimeSeconds > 0) {
                throw RolloutError.invalidMaxWallTime(maxWallTimeSeconds)
            }
            return Limits(maxStepsPerEpisode: maxStepsPerEpisode, maxWallTimeSeconds: maxWallTimeSeconds)
        }
    }

    public var parameters: ReferenceQuadrotorParameters
    public var mixer: ReferenceQuadrotorMixer
    public var schedule: SimulationSchedule
    public var determinism: DeterminismConfig
    public var noise: IMU6NoiseConfig
    public var worldEnvironment: WorldEnvironment
    public var hoverThrustScale: Double
    public var loadedDescriptor: LoadedRobotDescriptor?
    public var descriptorId: String?
    public var motorNerveRateLimitPerSecond: Double
    public var motorNerveSmoothingTimeConstant: Double?
    public var limits: Limits

    public init(
        parameters: ReferenceQuadrotorParameters = .baseline,
        mixer: ReferenceQuadrotorMixer? = nil,
        schedule: SimulationSchedule,
        determinism: DeterminismConfig,
        noise: IMU6NoiseConfig = .zero,
        worldEnvironment: WorldEnvironment = .standard,
        hoverThrustScale: Double = 1.0,
        loadedDescriptor: LoadedRobotDescriptor? = nil,
        descriptorId: String? = nil,
        motorNerveRateLimitPerSecond: Double = 2.0,
        motorNerveSmoothingTimeConstant: Double? = 0.08,
        limits: Limits = Limits()
    ) {
        self.parameters = parameters
        self.mixer = mixer ?? ReferenceQuadrotorMixer(armLength: parameters.armLength, yawCoefficient: parameters.yawCoefficient)
        self.schedule = schedule
        self.determinism = determinism
        self.noise = noise
        self.worldEnvironment = worldEnvironment
        self.hoverThrustScale = hoverThrustScale
        self.loadedDescriptor = loadedDescriptor
        self.descriptorId = descriptorId ?? loadedDescriptor?.descriptor.robot.robotID
        self.motorNerveRateLimitPerSecond = motorNerveRateLimitPerSecond
        self.motorNerveSmoothingTimeConstant = motorNerveSmoothingTimeConstant
        self.limits = limits
    }

    public func run(
        definitions: [ReferenceQuadrotorScenarioDefinition],
        policyFactory: any ReferenceQuadrotorPolicyFactory,
        workerIndex: Int = 0
    ) async throws -> [RolloutEpisode] {
        var episodes: [RolloutEpisode] = []
        episodes.reserveCapacity(definitions.count)
        for definition in definitions {
            let episode = try await runEpisode(
                definition: definition,
                policyFactory: policyFactory,
                workerIndex: workerIndex
            )
            episodes.append(episode)
        }
        return episodes
    }

    public func runEpisode(
        definition: ReferenceQuadrotorScenarioDefinition,
        policyFactory: any ReferenceQuadrotorPolicyFactory,
        workerIndex: Int = 0
    ) async throws -> RolloutEpisode {
        var environment: ReferenceQuadrotorRLEnvironment
        if let loadedDescriptor {
            environment = try ReferenceQuadrotorRLEnvironment(
                loadedDescriptor: loadedDescriptor,
                schedule: schedule,
                determinism: determinism,
                noise: noise,
                worldEnvironment: worldEnvironment,
                hoverThrustScale: hoverThrustScale,
                motorNerveRateLimitPerSecond: motorNerveRateLimitPerSecond,
                motorNerveSmoothingTimeConstant: motorNerveSmoothingTimeConstant
            )
        } else {
            environment = ReferenceQuadrotorRLEnvironment(
                parameters: parameters,
                mixer: mixer,
                schedule: schedule,
                determinism: determinism,
                noise: noise,
                worldEnvironment: worldEnvironment,
                hoverThrustScale: hoverThrustScale,
                descriptorId: descriptorId,
                motorNerveRateLimitPerSecond: motorNerveRateLimitPerSecond,
                motorNerveSmoothingTimeConstant: motorNerveSmoothingTimeConstant
            )
        }
        var observation = try environment.reset(seed: definition.config.seed, scenario: definition)
        var policy = try policyFactory.makePolicy(definition: definition, workerIndex: workerIndex)
        var steps: [EnvironmentStep] = []
        let plannedStepCount = Int((definition.config.duration / definition.config.timeStep.delta).rounded(.down))
        steps.reserveCapacity(min(plannedStepCount, limits.maxStepsPerEpisode ?? plannedStepCount))
        let start = ContinuousClock.now

        while true {
            if Task.isCancelled {
                throw RolloutError.cancelled(
                    scenarioId: definition.config.id.rawValue,
                    seed: definition.config.seed.rawValue
                )
            }
            if let maxWallTimeSeconds = limits.maxWallTimeSeconds {
                let elapsed = start.duration(to: ContinuousClock.now)
                let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                if elapsedSeconds > maxWallTimeSeconds {
                    throw RolloutError.exceededMaxWallTime(
                        scenarioId: definition.config.id.rawValue,
                        seed: definition.config.seed.rawValue,
                        maxWallTimeSeconds: maxWallTimeSeconds
                    )
                }
            }
            if let maxSteps = limits.maxStepsPerEpisode, steps.count >= maxSteps {
                throw RolloutError.exceededMaxSteps(
                    scenarioId: definition.config.id.rawValue,
                    seed: definition.config.seed.rawValue,
                    maxSteps: maxSteps
                )
            }
            let action = try await policy.action(for: observation)
            let step = try environment.step(action: action)
            steps.append(step)
            observation = step.observation
            if step.done || step.truncated {
                break
            }
        }

        guard let final = steps.last else {
            throw RolloutError.emptyEpisode(
                scenarioId: definition.config.id.rawValue,
                seed: definition.config.seed.rawValue
            )
        }
        let info = final.info
        let episodeId = Self.makeEpisodeId(
            scenarioId: info.scenarioId.rawValue,
            seed: info.seed.rawValue,
            workerIndex: workerIndex
        )
        return RolloutEpisode(
            episodeId: episodeId,
            scenarioId: info.scenarioId.rawValue,
            seed: info.seed.rawValue,
            workerIndex: workerIndex,
            policyId: policyFactory.policyID,
            configHash: info.configHash,
            descriptorId: descriptorId,
            rewardDescriptor: info.rewardDescriptor,
            rewardSum: info.rewardSum,
            done: final.done,
            truncated: final.truncated,
            terminalReason: info.terminalReason,
            failureReason: info.failureReason?.rawValue,
            failureTime: info.failureTime,
            stepCount: info.stepCount,
            workerCount: nil,
            maxSteps: limits.maxStepsPerEpisode,
            durationSeconds: final.log.time.time,
            cancelled: false,
            steps: steps
        )
    }

    public static func makeEpisodeId(scenarioId: String, seed: UInt64, workerIndex: Int) -> String {
        "\(scenarioId)#seed=\(seed)#worker=\(workerIndex)"
    }
}

public struct ParallelRolloutCollector: Sendable {
    public enum CollectorError: Error, Equatable {
        case invalidWorkerCount(Int)
    }

    public let runner: RolloutRunner
    public let workerCount: Int

    public init(runner: RolloutRunner, workerCount: Int = Self.defaultWorkerCount()) throws {
        guard workerCount > 0 else { throw CollectorError.invalidWorkerCount(workerCount) }
        self.runner = runner
        self.workerCount = workerCount
    }

    public static func defaultWorkerCount(activeProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount) -> Int {
        min(4, max(1, activeProcessorCount - 1))
    }

    public func collect(
        definitions: [ReferenceQuadrotorScenarioDefinition],
        policyFactory: any ReferenceQuadrotorPolicyFactory
    ) async throws -> [RolloutEpisode] {
        let shardCount = min(workerCount, max(definitions.count, 1))
        return try await withThrowingTaskGroup(of: [RolloutEpisode].self) { group in
            for workerIndex in 0..<shardCount {
                let workerDefinitions = definitions.enumerated().compactMap { index, definition in
                    index % shardCount == workerIndex ? definition : nil
                }
                guard !workerDefinitions.isEmpty else { continue }
                let runner = runner
                group.addTask {
                    let episodes = try await runner.run(
                        definitions: workerDefinitions,
                        policyFactory: policyFactory,
                        workerIndex: workerIndex
                    )
                    return episodes.map { episode in
                        RolloutEpisode(
                            episodeId: episode.episodeId,
                            scenarioId: episode.scenarioId,
                            seed: episode.seed,
                            workerIndex: episode.workerIndex,
                            policyId: episode.policyId,
                            configHash: episode.configHash,
                            descriptorId: episode.descriptorId,
                            rewardDescriptor: episode.rewardDescriptor,
                            rewardSum: episode.rewardSum,
                            done: episode.done,
                            truncated: episode.truncated,
                            terminalReason: episode.terminalReason,
                            failureReason: episode.failureReason,
                            failureTime: episode.failureTime,
                            stepCount: episode.stepCount,
                            workerCount: workerCount,
                            maxSteps: episode.maxSteps,
                            durationSeconds: episode.durationSeconds,
                            cancelled: episode.cancelled,
                            steps: episode.steps
                        )
                    }
                }
            }

            var episodes: [RolloutEpisode] = []
            episodes.reserveCapacity(definitions.count)
            for try await workerEpisodes in group {
                episodes.append(contentsOf: workerEpisodes)
            }
            return episodes.sorted { lhs, rhs in
                if lhs.scenarioId != rhs.scenarioId { return lhs.scenarioId < rhs.scenarioId }
                if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
                return lhs.workerIndex < rhs.workerIndex
            }
        }
    }
}
