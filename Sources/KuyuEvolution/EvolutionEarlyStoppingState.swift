import Foundation
import KuyuTrainingContracts

struct EvolutionEarlyStoppingState {
    private let config: EvolutionEarlyStoppingConfig
    private var bestFitness: Double?
    private var bestTaskPassRate: Double?
    private var bestHoldTimeRatio: Double?
    private var stagnantGenerationCount = 0

    init(config: EvolutionEarlyStoppingConfig) {
        self.config = config
    }

    init(config: EvolutionEarlyStoppingConfig, snapshot: EvolutionEarlyStoppingSnapshot) {
        self.config = config
        self.bestFitness = snapshot.bestFitness
        self.bestTaskPassRate = snapshot.bestTaskPassRate
        self.bestHoldTimeRatio = snapshot.bestHoldTimeRatio
        self.stagnantGenerationCount = snapshot.stagnantGenerationCount
    }

    var snapshot: EvolutionEarlyStoppingSnapshot {
        EvolutionEarlyStoppingSnapshot(
            bestFitness: bestFitness,
            bestTaskPassRate: bestTaskPassRate,
            bestHoldTimeRatio: bestHoldTimeRatio,
            stagnantGenerationCount: stagnantGenerationCount
        )
    }

    mutating func record(fitness: [FitnessSummary]) -> String? {
        guard config.enabled, !fitness.isEmpty else {
            return nil
        }
        let eligibleFitness = fitness.filter(\.failureReasons.isEmpty)
        guard !eligibleFitness.isEmpty else {
            return nil
        }
        let generationBestFitness = eligibleFitness.compactMap { summary in
            summary.scalarFitness.isFinite ? summary.scalarFitness : nil
        }.max()
        let generationBestTaskPassRate = eligibleFitness.compactMap { summary in
            summary.taskPassRate.isFinite ? summary.taskPassRate : nil
        }.max()
        let generationBestHoldTimeRatio = eligibleFitness.compactMap { summary in
            summary.holdTimeRatio?.isFinite == true ? summary.holdTimeRatio : nil
        }.max()

        let improved = improved(
            current: generationBestFitness,
            best: bestFitness,
            minimumDelta: config.minimumFitnessImprovement
        ) || improved(
            current: generationBestTaskPassRate,
            best: bestTaskPassRate,
            minimumDelta: config.minimumTaskPassRateImprovement
        ) || improved(
            current: generationBestHoldTimeRatio,
            best: bestHoldTimeRatio,
            minimumDelta: config.minimumHoldTimeRatioImprovement
        )

        updateBest(&bestFitness, with: generationBestFitness)
        updateBest(&bestTaskPassRate, with: generationBestTaskPassRate)
        updateBest(&bestHoldTimeRatio, with: generationBestHoldTimeRatio)

        if improved {
            stagnantGenerationCount = 0
            return nil
        }
        stagnantGenerationCount += 1
        guard stagnantGenerationCount >= config.patienceGenerations else {
            return nil
        }
        return [
            "early-stopped:plateau",
            "stagnantGenerations=\(stagnantGenerationCount)",
            "patience=\(config.patienceGenerations)",
            bestFitness.map { "bestFitness=\($0)" },
            bestTaskPassRate.map { "bestTaskPassRate=\($0)" },
            bestHoldTimeRatio.map { "bestHoldTimeRatio=\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: ":")
    }

    private func improved(current: Double?, best: Double?, minimumDelta: Double) -> Bool {
        guard let current else {
            return false
        }
        guard let best else {
            return true
        }
        return current > best + minimumDelta
    }

    private func updateBest(_ best: inout Double?, with current: Double?) {
        guard let current else {
            return
        }
        guard let existing = best else {
            best = current
            return
        }
        if current > existing {
            best = current
        }
    }
}
