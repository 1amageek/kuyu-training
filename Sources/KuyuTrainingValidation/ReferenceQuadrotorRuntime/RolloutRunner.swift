import KuyuCore
import KuyuPhysics

public struct RolloutRunner: Sendable {
    public enum RolloutError: Error, Equatable {
        case emptyEpisode(scenarioId: String, seed: UInt64)
        case cancelled(scenarioId: String, seed: UInt64)
        case exceededMaxSteps(scenarioId: String, seed: UInt64, maxSteps: Int)
        case exceededMaxWallTime(scenarioId: String, seed: UInt64, maxWallTimeSeconds: Double)
        case invalidMaxSteps(Int)
        case invalidMaxWallTime(Double)
        case transitionCountMismatch(expected: Int, actual: Int)
        case transitionDurationMismatch(expected: Double, actual: Double)
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
    public var loadedRobot: LoadedKuyuRobot?
    public var robotManifestID: String?
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
        loadedRobot: LoadedKuyuRobot? = nil,
        robotManifestID: String? = nil,
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
        self.loadedRobot = loadedRobot
        self.robotManifestID = robotManifestID ?? loadedRobot?.manifest.robotID
        self.motorNerveRateLimitPerSecond = motorNerveRateLimitPerSecond
        self.motorNerveSmoothingTimeConstant = motorNerveSmoothingTimeConstant
        self.limits = limits
    }
}
