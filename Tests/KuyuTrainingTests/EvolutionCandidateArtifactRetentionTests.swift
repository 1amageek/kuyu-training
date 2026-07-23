import Foundation
import Testing

@testable import KuyuEvolution

@Suite("Evolution candidate artifact retention")
struct EvolutionCandidateArtifactRetentionTests {
    @Test func compactRetentionKeepsNextPopulationAndCurrentBest() throws {
        try withRetentionTemporaryDirectory { root in
            let current = try candidates(count: 3, generation: 0, root: root)
            let next = try candidates(count: 2, generation: 1, root: root)
            let request = EvolutionCandidateArtifactRetentionRequest(
                runID: "run",
                generationIndex: 0,
                artifactDirectory: root,
                candidates: current,
                nextPopulation: EvolutionPopulation(
                    runID: "run",
                    generationIndex: 1,
                    candidates: next
                ),
                bestCandidateID: current[1].candidateID
            )

            try EvolutionCompactCandidateArtifactRetainer().retain(request)

            #expect(!exists(current[0]))
            #expect(exists(current[1]))
            #expect(!exists(current[2]))
            #expect(next.allSatisfy(exists))
            let records = try EvolutionCandidateArtifactRetentionStore().records(in: root)
            #expect(records.count == 1)
            #expect(records[0].deletions.count == 2)
            #expect(records[0].deletions.reduce(0) {
                $0 + $1.checkpointReference.byteCount
            } == 256)
        }
    }

    @Test func compactRetentionKeepsQualityDiversityArchiveCandidates() throws {
        try withRetentionTemporaryDirectory { root in
            let current = try candidates(count: 3, generation: 0, root: root)
            let next = try candidates(count: 2, generation: 1, root: root)
            let request = EvolutionCandidateArtifactRetentionRequest(
                runID: "run",
                generationIndex: 0,
                artifactDirectory: root,
                candidates: current,
                nextPopulation: EvolutionPopulation(
                    runID: "run",
                    generationIndex: 1,
                    candidates: next
                ),
                bestCandidateID: current[0].candidateID,
                protectedCandidateIDs: [current[2].candidateID]
            )

            try EvolutionCompactCandidateArtifactRetainer().retain(request)

            #expect(exists(current[0]))
            #expect(!exists(current[1]))
            #expect(exists(current[2]))
            #expect(next.allSatisfy(exists))
        }
    }

    @Test func compactRetentionReleasesSupersededBest() throws {
        try withRetentionTemporaryDirectory { root in
            let generation0 = try candidates(count: 2, generation: 0, root: root)
            let generation1 = try candidates(count: 2, generation: 1, root: root)
            let generation2 = try candidates(count: 2, generation: 2, root: root)
            let retainer = EvolutionCompactCandidateArtifactRetainer()
            try retainer.retain(EvolutionCandidateArtifactRetentionRequest(
                runID: "run",
                generationIndex: 0,
                artifactDirectory: root,
                candidates: generation0,
                nextPopulation: EvolutionPopulation(
                    runID: "run",
                    generationIndex: 1,
                    candidates: generation1
                ),
                bestCandidateID: generation0[1].candidateID
            ))

            try retainer.retain(EvolutionCandidateArtifactRetentionRequest(
                runID: "run",
                generationIndex: 1,
                artifactDirectory: root,
                candidates: generation0 + generation1,
                nextPopulation: EvolutionPopulation(
                    runID: "run",
                    generationIndex: 2,
                    candidates: generation2
                ),
                bestCandidateID: generation1[1].candidateID
            ))

            #expect(!exists(generation0[1]))
            #expect(!exists(generation1[0]))
            #expect(exists(generation1[1]))
            #expect(generation2.allSatisfy(exists))
        }
    }

    @Test func compactRetentionRecoversMissingLedgerForCommittedResumeGeneration() throws {
        try withRetentionTemporaryDirectory { root in
            let current = try candidates(count: 3, generation: 0, root: root)
            let next = try candidates(count: 2, generation: 1, root: root)
            let request = EvolutionCandidateArtifactRetentionRequest(
                runID: "run",
                generationIndex: 0,
                artifactDirectory: root,
                candidates: current,
                nextPopulation: EvolutionPopulation(
                    runID: "run",
                    generationIndex: 1,
                    candidates: next
                ),
                bestCandidateID: current[1].candidateID
            )

            try EvolutionCompactCandidateArtifactRetainer().recover(request)

            let records = try EvolutionCandidateArtifactRetentionStore().records(in: root)
            #expect(records.map(\.generationIndex) == [0])
            #expect(!exists(current[0]))
            #expect(exists(current[1]))
            #expect(!exists(current[2]))
            #expect(next.allSatisfy(exists))
        }
    }

    @Test func compactRetentionRejectsExternalCheckpoint() throws {
        try withRetentionTemporaryDirectory { root in
            try withRetentionTemporaryDirectory { outside in
                let external = try candidate(
                    id: "external",
                    generation: 0,
                    checkpointURL: outside.appendingPathComponent("checkpoint", isDirectory: true)
                )
                try writeCheckpoint(external)

                #expect(throws: EvolutionCandidateArtifactRetentionStore.StoreError.self) {
                    try EvolutionCompactCandidateArtifactRetainer().retain(
                        EvolutionCandidateArtifactRetentionRequest(
                            runID: "run",
                            generationIndex: 0,
                            artifactDirectory: root,
                            candidates: [external],
                            nextPopulation: EvolutionPopulation(
                                runID: "run",
                                generationIndex: 1,
                                candidates: []
                            ),
                            bestCandidateID: nil
                        )
                    )
                }
                #expect(exists(external))
            }
        }
    }

    @Test func reconciliationCompletesRecordedDeletion() throws {
        try withRetentionTemporaryDirectory { root in
            let candidate = try candidates(count: 1, generation: 0, root: root)[0]
            let store = EvolutionCandidateArtifactRetentionStore()
            let checkpointURL = try #require(candidate.checkpointURL)
            let path = try store.relativeCheckpointPath(
                checkpointURL,
                artifactDirectory: root
            )
            let record = EvolutionCandidateArtifactRetentionRecord(
                runID: "run",
                generationIndex: 0,
                protectedCheckpointPaths: [],
                deletions: [EvolutionCandidateArtifactRetentionRecord.Deletion(
                    candidateID: candidate.candidateID,
                    generationIndex: candidate.generationIndex,
                    relativePath: path,
                    checkpointReference: try EvolutionCheckpointIntegrity().reference(
                        checkpointID: try #require(candidate.checkpointID),
                        checkpointURL: checkpointURL,
                        artifactRoot: root
                    ),
                    reason: "test-reconciliation"
                )]
            )
            try store.write(record, in: root)

            try EvolutionCompactCandidateArtifactRetainer().reconcile(
                in: root,
                expectedRunID: "run"
            )

            #expect(!exists(candidate))
        }
    }

    @Test func reconciliationRejectsChangedCheckpoint() throws {
        try withRetentionTemporaryDirectory { root in
            let candidate = try candidates(count: 1, generation: 0, root: root)[0]
            let store = EvolutionCandidateArtifactRetentionStore()
            let checkpointURL = try #require(candidate.checkpointURL)
            let relativePath = try store.relativeCheckpointPath(
                checkpointURL,
                artifactDirectory: root
            )
            let record = EvolutionCandidateArtifactRetentionRecord(
                runID: "run",
                generationIndex: 0,
                protectedCheckpointPaths: [],
                deletions: [EvolutionCandidateArtifactRetentionRecord.Deletion(
                    candidateID: candidate.candidateID,
                    generationIndex: candidate.generationIndex,
                    relativePath: relativePath,
                    checkpointReference: try EvolutionCheckpointIntegrity().reference(
                        checkpointID: try #require(candidate.checkpointID),
                        checkpointURL: checkpointURL,
                        artifactRoot: root
                    ),
                    reason: "test-reconciliation"
                )]
            )
            try store.write(record, in: root)
            try Data("replacement".utf8).write(
                to: checkpointURL.appendingPathComponent("weights.bin", isDirectory: false),
                options: [.atomic]
            )

            #expect(throws: EvolutionCandidateArtifactRetentionStore.StoreError.self) {
                try EvolutionCompactCandidateArtifactRetainer().reconcile(
                    in: root,
                    expectedRunID: "run"
                )
            }
            #expect(exists(candidate))
        }
    }

    @Test func reconciliationRejectsDifferentRunID() throws {
        try withRetentionTemporaryDirectory { root in
            let candidate = try candidates(count: 1, generation: 0, root: root)[0]
            let store = EvolutionCandidateArtifactRetentionStore()
            let checkpointURL = try #require(candidate.checkpointURL)
            let record = EvolutionCandidateArtifactRetentionRecord(
                runID: "other-run",
                generationIndex: 0,
                protectedCheckpointPaths: [],
                deletions: [EvolutionCandidateArtifactRetentionRecord.Deletion(
                    candidateID: candidate.candidateID,
                    generationIndex: candidate.generationIndex,
                    relativePath: try store.relativeCheckpointPath(
                        checkpointURL,
                        artifactDirectory: root
                    ),
                    checkpointReference: try EvolutionCheckpointIntegrity().reference(
                        checkpointID: try #require(candidate.checkpointID),
                        checkpointURL: checkpointURL,
                        artifactRoot: root
                    ),
                    reason: "test-reconciliation"
                )]
            )
            try store.write(record, in: root)

            #expect(throws: EvolutionCandidateArtifactRetentionStore.StoreError.runIDMismatch(
                path: "generation-0",
                expected: "run",
                actual: "other-run"
            )) {
                try EvolutionCompactCandidateArtifactRetainer().reconcile(
                    in: root,
                    expectedRunID: "run"
                )
            }
            #expect(exists(candidate))
        }
    }

    @Test func compactRetentionRejectsSymlinkedLedgerDirectory() throws {
        try withRetentionTemporaryDirectory { root in
            try withRetentionTemporaryDirectory { outside in
                let candidate = try candidates(count: 1, generation: 0, root: root)[0]
                let retentionRoot = root.appendingPathComponent("retention", isDirectory: true)
                try FileManager.default.createSymbolicLink(
                    at: retentionRoot,
                    withDestinationURL: outside
                )

                #expect(throws: EvolutionCandidateArtifactRetentionStore.StoreError.self) {
                    try EvolutionCompactCandidateArtifactRetainer().retain(
                        EvolutionCandidateArtifactRetentionRequest(
                            runID: "run",
                            generationIndex: 0,
                            artifactDirectory: root,
                            candidates: [candidate],
                            nextPopulation: EvolutionPopulation(
                                runID: "run",
                                generationIndex: 1,
                                candidates: []
                            ),
                            bestCandidateID: nil
                        )
                    )
                }
                #expect(exists(candidate))
            }
        }
    }

    private func candidates(count: Int, generation: Int, root: URL) throws -> [GenomeCandidate] {
        try (0..<count).map { index in
            let checkpointURL = root
                .appendingPathComponent("candidates", isDirectory: true)
                .appendingPathComponent("run", isDirectory: true)
                .appendingPathComponent("generation-\(generation)", isDirectory: true)
                .appendingPathComponent("candidate-\(index)", isDirectory: true)
            let result = try candidate(
                id: "g\(generation)-c\(index)",
                generation: generation,
                checkpointURL: checkpointURL
            )
            try writeCheckpoint(result)
            return result
        }
    }

    private func candidate(
        id: String,
        generation: Int,
        checkpointURL: URL
    ) throws -> GenomeCandidate {
        GenomeCandidate(
            runID: "run",
            generationIndex: generation,
            candidateID: id,
            genomeID: "genome-\(id)",
            checkpointID: id,
            checkpointURL: checkpointURL
        )
    }

    private func writeCheckpoint(_ candidate: GenomeCandidate) throws {
        let url = try #require(candidate.checkpointURL)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 128).write(
            to: url.appendingPathComponent("weights.bin", isDirectory: false)
        )
    }

    private func exists(_ candidate: GenomeCandidate) -> Bool {
        candidate.checkpointURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }
}

private func withRetentionTemporaryDirectory<T>(
    _ body: (URL) throws -> T
) throws -> T {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("evolution-retention-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    do {
        let result = try body(root)
        try FileManager.default.removeItem(at: root)
        return result
    } catch let bodyError {
        do {
            try FileManager.default.removeItem(at: root)
        } catch let cleanupError {
            Issue.record("Temporary retention directory cleanup failed: \(cleanupError)")
        }
        throw bodyError
    }
}
