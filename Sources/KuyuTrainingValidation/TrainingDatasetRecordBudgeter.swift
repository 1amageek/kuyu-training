import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
public struct TrainingDatasetRecordBudgeter: Sendable {
    public enum Selection: Sendable, Equatable {
        case prefix
        case suffix
    }

    public init() {}

    public func limit(
        _ datasets: [TrainingDataset],
        maxTotalRecordCount: Int,
        selection: Selection
    ) -> [TrainingDataset] {
        guard maxTotalRecordCount > 0 else { return [] }
        let totalRecordCount = datasets.reduce(0) { $0 + $1.records.count }
        guard totalRecordCount > maxTotalRecordCount else { return datasets }

        switch selection {
        case .prefix:
            return prefixLimit(datasets, maxTotalRecordCount: maxTotalRecordCount)
        case .suffix:
            return suffixLimit(datasets, maxTotalRecordCount: maxTotalRecordCount)
        }
    }

    public func suffix(
        _ dataset: TrainingDataset,
        startingAtRecordIndex startIndex: Int
    ) -> TrainingDataset? {
        let boundedStartIndex = min(max(0, startIndex), dataset.records.count)
        guard boundedStartIndex < dataset.records.count else { return nil }
        let records = Array(dataset.records[boundedStartIndex...])
        return clippedDataset(dataset, records: records)
    }

    private func prefixLimit(
        _ datasets: [TrainingDataset],
        maxTotalRecordCount: Int
    ) -> [TrainingDataset] {
        var remaining = maxTotalRecordCount
        var limited: [TrainingDataset] = []
        limited.reserveCapacity(datasets.count)

        for dataset in datasets {
            guard remaining > 0 else { break }
            if dataset.records.count <= remaining {
                limited.append(dataset)
                remaining -= dataset.records.count
            } else {
                let records = Array(dataset.records.prefix(remaining))
                limited.append(clippedDataset(dataset, records: records))
                remaining = 0
            }
        }

        return limited
    }

    private func suffixLimit(
        _ datasets: [TrainingDataset],
        maxTotalRecordCount: Int
    ) -> [TrainingDataset] {
        var remaining = maxTotalRecordCount
        var limitedReversed: [TrainingDataset] = []
        limitedReversed.reserveCapacity(datasets.count)

        for dataset in datasets.reversed() {
            guard remaining > 0 else { break }
            if dataset.records.count <= remaining {
                limitedReversed.append(dataset)
                remaining -= dataset.records.count
            } else {
                let records = Array(dataset.records.suffix(remaining))
                limitedReversed.append(clippedDataset(dataset, records: records))
                remaining = 0
            }
        }

        return Array(limitedReversed.reversed())
    }

    private func clippedDataset(
        _ dataset: TrainingDataset,
        records: [TrainingDatasetRecord]
    ) -> TrainingDataset {
        let metadata = dataset.metadata
        let finalRecord = records.last
        let terminal = (finalRecord?.done ?? false) || (finalRecord?.truncated ?? false)
        let rewardSum = metadata.rewardSum.map { _ in
            records.reduce(0.0) { partial, record in
                partial + (record.reward ?? 0.0)
            }
        }
        let clippedMetadata = TrainingDatasetMetadata(
            scenarioId: metadata.scenarioId,
            seed: metadata.seed,
            timeStep: metadata.timeStep,
            determinismTier: metadata.determinismTier,
            configHash: metadata.configHash,
            channelCount: Self.maxChannelCount(records),
            driveCount: Self.maxDriveCount(records),
            recordCount: records.count,
            schemaVersion: metadata.schemaVersion,
            failureReason: terminal ? metadata.failureReason : nil,
            failureTime: terminal ? metadata.failureTime : nil,
            episodeId: metadata.episodeId,
            policyId: metadata.policyId,
            rewardSum: rewardSum,
            done: finalRecord?.done ?? false,
            truncated: finalRecord?.truncated ?? false,
            terminalReason: terminal ? metadata.terminalReason : nil,
            rewardDescriptor: metadata.rewardDescriptor,
            taskReference: metadata.taskReference,
            observation: metadata.observation,
            provenance: metadata.provenance
        )
        return TrainingDataset(metadata: clippedMetadata, records: records)
    }

    private static func maxChannelCount(_ records: [TrainingDatasetRecord]) -> Int {
        let maxIndex = records.flatMap(\.sensors).map { Int($0.channelIndex) }.max() ?? -1
        return maxIndex + 1
    }

    private static func maxDriveCount(_ records: [TrainingDatasetRecord]) -> Int {
        let maxIndex = records.flatMap(\.driveIntents).map { Int($0.driveIndex) }.max() ?? -1
        return maxIndex + 1
    }
}
