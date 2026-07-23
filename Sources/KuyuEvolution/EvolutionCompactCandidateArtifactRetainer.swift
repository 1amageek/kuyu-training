import Foundation

public struct EvolutionCompactCandidateArtifactRetainer: EvolutionCandidateArtifactRetaining {
    public enum RetentionError: Error, Sendable, Equatable {
        case candidateCheckpointMissing(String)
        case bestCandidateMissing(String)
        case incumbentCandidateMissing(String)
    }

    private let store: EvolutionCandidateArtifactRetentionStore

    public init(store: EvolutionCandidateArtifactRetentionStore = EvolutionCandidateArtifactRetentionStore()) {
        self.store = store
    }

    public func reconcile(in artifactDirectory: URL, expectedRunID: String) throws {
        try store.reconcile(in: artifactDirectory, expectedRunID: expectedRunID)
    }

    public func recover(_ request: EvolutionCandidateArtifactRetentionRequest) throws {
        let records = try store.records(in: request.artifactDirectory)
        if records.last?.generationIndex == request.generationIndex {
            try validate(request)
            return
        }
        guard records.count == request.generationIndex else {
            throw EvolutionCandidateArtifactRetentionStore.StoreError.invalidRecord(
                "resume-generation-\(request.generationIndex)-ledger-count-\(records.count)"
            )
        }
        try retain(request)
    }

    public func validate(_ request: EvolutionCandidateArtifactRetentionRequest) throws {
        for candidate in request.nextPopulation.candidates {
            _ = try checkpointReference(candidate, artifactDirectory: request.artifactDirectory)
        }
        if let bestCandidateID = request.bestCandidateID {
            guard let best = request.candidates.first(where: {
                $0.candidateID == bestCandidateID
            }) else {
                throw RetentionError.bestCandidateMissing(bestCandidateID)
            }
            _ = try checkpointReference(best, artifactDirectory: request.artifactDirectory)
        }
        if let incumbentCandidateID = request.incumbentCandidateID {
            guard let incumbent = request.candidates.first(where: {
                $0.candidateID == incumbentCandidateID
            }) else {
                throw RetentionError.incumbentCandidateMissing(incumbentCandidateID)
            }
            _ = try checkpointReference(incumbent, artifactDirectory: request.artifactDirectory)
        }
        for candidateID in request.protectedCandidateIDs {
            guard let candidate = request.candidates.first(where: {
                $0.candidateID == candidateID
            }) else {
                throw RetentionError.candidateCheckpointMissing(candidateID)
            }
            _ = try checkpointReference(candidate, artifactDirectory: request.artifactDirectory)
        }
    }

    public func retain(_ request: EvolutionCandidateArtifactRetentionRequest) throws {
        try validate(request)
        var protectedURLs = request.nextPopulation.candidates.compactMap(\.checkpointURL)
        if let bestCandidateID = request.bestCandidateID,
           let bestCheckpointURL = request.candidates.first(where: {
               $0.candidateID == bestCandidateID
           })?.checkpointURL {
            protectedURLs.append(bestCheckpointURL)
        }
        if let incumbentCandidateID = request.incumbentCandidateID,
           let incumbentCheckpointURL = request.candidates.first(where: {
               $0.candidateID == incumbentCandidateID
           })?.checkpointURL {
            protectedURLs.append(incumbentCheckpointURL)
        }
        let protectedCandidateIDSet = Set(request.protectedCandidateIDs)
        protectedURLs.append(contentsOf: request.candidates.compactMap { candidate in
            protectedCandidateIDSet.contains(candidate.candidateID)
                ? candidate.checkpointURL
                : nil
        })
        let protectedPaths = try Set(protectedURLs.map {
            try store.relativeCheckpointPath($0, artifactDirectory: request.artifactDirectory)
        })

        var seen = Set<String>()
        var deletions: [EvolutionCandidateArtifactRetentionRecord.Deletion] = []
        for candidate in request.candidates {
            guard let checkpointURL = candidate.checkpointURL else { continue }
            let path = try store.relativeCheckpointPath(
                checkpointURL,
                artifactDirectory: request.artifactDirectory
            )
            guard seen.insert(path).inserted,
                  !protectedPaths.contains(path),
                  FileManager.default.fileExists(atPath: checkpointURL.path) else {
                continue
            }
            let reference = try checkpointReference(
                candidate,
                artifactDirectory: request.artifactDirectory
            )
            deletions.append(EvolutionCandidateArtifactRetentionRecord.Deletion(
                candidateID: candidate.candidateID,
                generationIndex: candidate.generationIndex,
                relativePath: path,
                checkpointReference: reference,
                reason: "not-required-for-latest-resume-or-acceptance"
            ))
        }
        let record = EvolutionCandidateArtifactRetentionRecord(
            runID: request.runID,
            generationIndex: request.generationIndex,
            protectedCheckpointPaths: protectedPaths.sorted(),
            deletions: deletions.sorted { $0.relativePath < $1.relativePath }
        )
        try store.write(record, in: request.artifactDirectory)
        try store.deleteScheduledArtifacts(record, in: request.artifactDirectory)
    }

    private func checkpointReference(
        _ candidate: GenomeCandidate,
        artifactDirectory: URL
    ) throws -> EvolutionCheckpointReference {
        guard let checkpointID = candidate.checkpointID,
              let checkpointURL = candidate.checkpointURL else {
            throw RetentionError.candidateCheckpointMissing(candidate.candidateID)
        }
        return try EvolutionCheckpointIntegrity().reference(
            checkpointID: checkpointID,
            checkpointURL: checkpointURL,
            artifactRoot: artifactDirectory
        )
    }
}
