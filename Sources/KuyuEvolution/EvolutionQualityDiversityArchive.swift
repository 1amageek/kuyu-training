import Foundation
import KuyuTrainingContracts

public struct EvolutionQualityDiversityCell: Sendable, Codable, Equatable {
    public let cellID: String
    public let candidateID: String
    public let generationIndex: Int
    public let fitness: Double
    public let behaviorDescriptor: [String: Double]

    public init(
        cellID: String,
        candidateID: String,
        generationIndex: Int,
        fitness: Double,
        behaviorDescriptor: [String: Double]
    ) {
        self.cellID = cellID
        self.candidateID = candidateID
        self.generationIndex = max(0, generationIndex)
        self.fitness = fitness
        self.behaviorDescriptor = behaviorDescriptor
    }
}

public struct EvolutionQualityDiversityArchive: Sendable, Codable, Equatable {
    public static let fileName = "quality-diversity-archive.json"

    public let runID: String
    public let descriptorKeys: [String]
    public let cells: [EvolutionQualityDiversityCell]

    public init(
        runID: String,
        descriptorKeys: [String],
        cells: [EvolutionQualityDiversityCell]
    ) {
        self.runID = runID
        self.descriptorKeys = descriptorKeys
        self.cells = cells.sorted { lhs, rhs in
            if lhs.cellID == rhs.cellID {
                return lhs.candidateID < rhs.candidateID
            }
            return lhs.cellID < rhs.cellID
        }
    }
}

public struct EvolutionQualityDiversityArchiveBuilder: Sendable {
    public let descriptorKeys: [String]
    public let bucketScale: Double

    public init(
        descriptorKeys: [String] = [
            "taskPassRate",
            "holdTimeRatio",
            "altitudeErrorRatio",
            "safetyViolationRate",
            "rewardAverage",
        ],
        bucketScale: Double = 10
    ) {
        self.descriptorKeys = descriptorKeys
        self.bucketScale = max(1, bucketScale)
    }

    public func build(
        runID: String,
        fitness: [FitnessSummary]
    ) -> EvolutionQualityDiversityArchive {
        var cells: [String: EvolutionQualityDiversityCell] = [:]
        for summary in fitness
        where summary.evaluationFidelity.isFullScenario
            && summary.scalarFitness.isFinite
            && summary.failureReasons.isEmpty {
            let descriptor = behaviorDescriptor(for: summary)
            let cellID = self.cellID(descriptor: descriptor)
            let cell = EvolutionQualityDiversityCell(
                cellID: cellID,
                candidateID: summary.candidateID,
                generationIndex: summary.generationIndex,
                fitness: summary.scalarFitness,
                behaviorDescriptor: descriptor
            )
            if let existing = cells[cellID] {
                if cell.fitness == existing.fitness {
                    if cell.candidateID < existing.candidateID {
                        cells[cellID] = cell
                    }
                } else if cell.fitness > existing.fitness {
                    cells[cellID] = cell
                }
            } else {
                cells[cellID] = cell
            }
        }
        return EvolutionQualityDiversityArchive(
            runID: runID,
            descriptorKeys: descriptorKeys,
            cells: Array(cells.values)
        )
    }

    private func behaviorDescriptor(for summary: FitnessSummary) -> [String: Double] {
        var descriptor = summary.behaviorDescriptor
        descriptor["taskPassRate"] = summary.taskPassRate
        descriptor["holdTimeRatio"] = summary.holdTimeRatio ?? 0
        descriptor["altitudeErrorRatio"] = summary.altitudeErrorRatio ?? 0
        descriptor["safetyViolationRate"] = summary.safetyViolationRate
        descriptor["rewardAverage"] = summary.rewardAverage
        return descriptor
    }

    private func cellID(descriptor: [String: Double]) -> String {
        descriptorKeys.map { key in
            let raw = descriptor[key] ?? 0
            let value = raw.isFinite ? raw : 0
            let bucket = Int((value * bucketScale).rounded(.down))
            return "\(key)=\(bucket)"
        }
        .joined(separator: "|")
    }
}
