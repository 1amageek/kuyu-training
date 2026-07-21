import Foundation
import KuyuTrainingContracts

public struct EvolutionRunConfigValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case insufficientPopulation(populationSize: Int, generationCount: Int)
        case invalidAntitheticPopulationSize(Int)
        case invalidMutationRate(Double)
        case invalidMutationNoiseScale(Double)
        case invalidAdaptiveMutationRateRange(minimum: Double, maximum: Double)
        case unsupportedBoundedRefinementFidelity(TrainingEvaluationFidelity)
    }

    public init() {}

    public func validate(_ config: EvolutionRunConfig) throws {
        // INCOMPLETE: bounded (screening-fidelity) refinement evidence is not yet
        // consumable by this runtime. EvolutionGatePolicy.candidatePasses requires
        // full-scenario fidelity, so a bounded-refinement run evaluates the entire
        // population, terminates search-gate-rejected at generation 0, and writes an
        // artifact bundle that EvolutionRunArtifactValidator rejects at terminal
        // states. Reject the configuration before any evaluation is spent. Bounded
        // refinement may only be re-enabled together with multi-fidelity evidence
        // typing (bounded search-only evidence + full-scenario promotion evidence).
        if let refinementPolicy = config.searchRefinementPolicy,
           !refinementPolicy.evaluationFidelity.isFullScenario {
            throw ValidationError.unsupportedBoundedRefinementFidelity(
                refinementPolicy.evaluationFidelity
            )
        }
        if config.generationCount > 1, config.populationSize < 2 {
            throw ValidationError.insufficientPopulation(
                populationSize: config.populationSize,
                generationCount: config.generationCount
            )
        }
        if config.antitheticSampling {
            let variationCount = config.populationSize - 1
            guard variationCount >= 2, variationCount.isMultiple(of: 2) else {
                throw ValidationError.invalidAntitheticPopulationSize(config.populationSize)
            }
        }
        guard config.mutationRate.isFinite,
              config.mutationRate >= 0,
              config.mutationRate <= 1 else {
            throw ValidationError.invalidMutationRate(config.mutationRate)
        }
        guard config.mutationNoiseScale.isFinite, config.mutationNoiseScale >= 0 else {
            throw ValidationError.invalidMutationNoiseScale(config.mutationNoiseScale)
        }
        let adaptive = config.adaptiveMutation
        guard adaptive.minimumMutationRate.isFinite,
              adaptive.maximumMutationRate.isFinite,
              adaptive.minimumMutationRate >= 0,
              adaptive.minimumMutationRate <= adaptive.maximumMutationRate,
              adaptive.maximumMutationRate <= 1 else {
            throw ValidationError.invalidAdaptiveMutationRateRange(
                minimum: adaptive.minimumMutationRate,
                maximum: adaptive.maximumMutationRate
            )
        }
    }
}
