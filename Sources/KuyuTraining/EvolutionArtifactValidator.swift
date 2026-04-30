import Foundation

public struct EvolutionRunArtifactBundle: Sendable, Equatable {
    public let artifactDirectory: URL
    public let contract: EvolutionRunArtifactContract
    public let manifest: EvolutionRunManifest
    public let generations: [PopulationGenerationRecord]
    public let candidates: [GenomeCandidate]
    public let fitness: [FitnessSummary]
    public let eliteArchive: EvolutionEliteArchive
    public let acceptedCheckpoint: EvolutionAcceptedCheckpointDecision
    public let qualityDiversityArchive: EvolutionQualityDiversityArchive
    public let lineage: [EvolutionLineageRecord]

    public init(
        artifactDirectory: URL,
        contract: EvolutionRunArtifactContract,
        manifest: EvolutionRunManifest,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        acceptedCheckpoint: EvolutionAcceptedCheckpointDecision,
        qualityDiversityArchive: EvolutionQualityDiversityArchive,
        lineage: [EvolutionLineageRecord]
    ) {
        self.artifactDirectory = artifactDirectory
        self.contract = contract
        self.manifest = manifest
        self.generations = generations
        self.candidates = candidates
        self.fitness = fitness
        self.eliteArchive = eliteArchive
        self.acceptedCheckpoint = acceptedCheckpoint
        self.qualityDiversityArchive = qualityDiversityArchive
        self.lineage = lineage
    }
}

private func zipOptional<A, B>(_ lhs: A?, _ rhs: B?) -> (A, B)? {
    guard let lhs, let rhs else { return nil }
    return (lhs, rhs)
}

public struct EvolutionRunArtifactValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case missingFile(String)
        case unsupportedSchemaVersion(Int)
        case unsupportedContractVersion(Int)
        case invalidLine(file: String, line: Int)
        case emptyRunID
        case runIDMismatch(file: String, expected: String, actual: String)
        case nonTerminalManifestState(EvolutionRunTerminalState)
        case duplicateCandidateID(String)
        case duplicateFitnessSummary(String)
        case missingCandidateFitness(String)
        case nonFiniteFitness(candidateID: String)
        case duplicateLineage(String)
        case lineageMismatch(candidateID: String)
        case duplicateIncumbentCandidate(String)
        case invalidIncumbentCandidate(String)
        case eliteCandidateMissing(String)
        case missingCompletedEliteArchive
        case bestCandidateMissing(String)
        case bestCandidateNotElite(String)
        case acceptedCheckpointMismatch(String)
        case acceptedCheckpointCandidateMissing(String)
        case qualityDiversityCandidateMissing(String)
        case nonFiniteQualityDiversityCell(String)
    }

    public init() {}

    public func loadAndValidate(from artifactDirectory: URL) throws -> EvolutionRunArtifactBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        let contract = try decode(
            EvolutionRunArtifactContract.self,
            fileName: EvolutionRunArtifactContract.fileName,
            directory: artifactDirectory,
            decoder: decoder
        )
        try validate(contract: contract, directory: artifactDirectory)
        let manifest = try decode(
            EvolutionRunManifest.self,
            fileName: "evolution-manifest.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let generations = try loadJSONLines(
            PopulationGenerationRecord.self,
            fileName: "generations.jsonl",
            directory: artifactDirectory,
            decoder: decoder
        )
        let candidates = try loadJSONLines(
            GenomeCandidate.self,
            fileName: "candidates.jsonl",
            directory: artifactDirectory,
            decoder: decoder
        )
        let fitness = try loadJSONLines(
            FitnessSummary.self,
            fileName: "fitness.jsonl",
            directory: artifactDirectory,
            decoder: decoder
        )
        let eliteArchive = try decode(
            EvolutionEliteArchive.self,
            fileName: "elite-archive.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let acceptedCheckpoint = try decode(
            EvolutionAcceptedCheckpointDecision.self,
            fileName: EvolutionAcceptedCheckpointDecision.fileName,
            directory: artifactDirectory,
            decoder: decoder
        )
        let qualityDiversityArchive = try decode(
            EvolutionQualityDiversityArchive.self,
            fileName: EvolutionQualityDiversityArchive.fileName,
            directory: artifactDirectory,
            decoder: decoder
        )
        let lineage = try decode(
            [EvolutionLineageRecord].self,
            fileName: "lineage.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        try validate(
            manifest: manifest,
            generations: generations,
            candidates: candidates,
            fitness: fitness,
            eliteArchive: eliteArchive,
            acceptedCheckpoint: acceptedCheckpoint,
            qualityDiversityArchive: qualityDiversityArchive,
            lineage: lineage
        )
        return EvolutionRunArtifactBundle(
            artifactDirectory: artifactDirectory,
            contract: contract,
            manifest: manifest,
            generations: generations,
            candidates: candidates,
            fitness: fitness,
            eliteArchive: eliteArchive,
            acceptedCheckpoint: acceptedCheckpoint,
            qualityDiversityArchive: qualityDiversityArchive,
            lineage: lineage
        )
    }

    private func validate(contract: EvolutionRunArtifactContract, directory: URL) throws {
        guard contract.schemaVersion == EvolutionRunArtifactContract.currentSchemaVersion else {
            throw ValidationError.unsupportedSchemaVersion(contract.schemaVersion)
        }
        guard contract.contractVersion == EvolutionRunArtifactContract.currentContractVersion else {
            throw ValidationError.unsupportedContractVersion(contract.contractVersion)
        }
        for fileName in contract.requiredFiles + [EvolutionRunArtifactContract.fileName] {
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) else {
                throw ValidationError.missingFile(fileName)
            }
        }
    }

    private func validate(
        manifest: EvolutionRunManifest,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        acceptedCheckpoint: EvolutionAcceptedCheckpointDecision,
        qualityDiversityArchive: EvolutionQualityDiversityArchive,
        lineage: [EvolutionLineageRecord]
    ) throws {
        guard !manifest.runID.isEmpty else {
            throw ValidationError.emptyRunID
        }
        guard manifest.terminalState != .running else {
            throw ValidationError.nonTerminalManifestState(manifest.terminalState)
        }
        try validateRunIDs(
            expected: manifest.runID,
            generations: generations,
            candidates: candidates,
            fitness: fitness,
            eliteArchive: eliteArchive,
            acceptedCheckpoint: acceptedCheckpoint,
            qualityDiversityArchive: qualityDiversityArchive,
            lineage: lineage
        )
        var candidateIDs = Set<String>()
        var incumbentCandidateID: String?
        for candidate in candidates {
            guard candidateIDs.insert(candidate.candidateID).inserted else {
                throw ValidationError.duplicateCandidateID(candidate.candidateID)
            }
            if candidate.isIncumbent == true {
                guard incumbentCandidateID == nil else {
                    throw ValidationError.duplicateIncumbentCandidate(candidate.candidateID)
                }
                guard candidate.generationIndex == 0,
                      candidate.parentCandidateIDs.isEmpty,
                      candidate.mutationRate == 0,
                      candidate.mutationNoiseScale == 0 else {
                    throw ValidationError.invalidIncumbentCandidate(candidate.candidateID)
                }
                incumbentCandidateID = candidate.candidateID
            }
        }
        var fitnessByCandidateID: [String: FitnessSummary] = [:]
        for summary in fitness {
            guard fitnessByCandidateID[summary.candidateID] == nil else {
                throw ValidationError.duplicateFitnessSummary(summary.candidateID)
            }
            fitnessByCandidateID[summary.candidateID] = summary
        }
        for candidate in candidates {
            guard let summary = fitnessByCandidateID[candidate.candidateID] else {
                throw ValidationError.missingCandidateFitness(candidate.candidateID)
            }
            guard summary.scalarFitness.isFinite,
                  summary.rewardAverage.isFinite,
                  summary.taskPassRate.isFinite,
                  summary.safetyViolationRate.isFinite,
                  summary.holdTimeRatio?.isFinite ?? true,
                  summary.energyPenalty?.isFinite ?? true,
                  summary.noveltyScore?.isFinite ?? true,
                  summary.teacherDelta?.isFinite ?? true,
                  summary.workerThroughput?.isFinite ?? true else {
                throw ValidationError.nonFiniteFitness(candidateID: candidate.candidateID)
            }
        }
        var lineageByCandidateID: [String: EvolutionLineageRecord] = [:]
        for record in lineage {
            guard lineageByCandidateID[record.candidateID] == nil else {
                throw ValidationError.duplicateLineage(record.candidateID)
            }
            lineageByCandidateID[record.candidateID] = record
        }
        for candidate in candidates {
            guard let record = lineageByCandidateID[candidate.candidateID],
                  record.genomeID == candidate.genomeID,
                  record.parentCandidateIDs == candidate.parentCandidateIDs else {
                throw ValidationError.lineageMismatch(candidateID: candidate.candidateID)
            }
        }
        for candidateID in eliteArchive.eliteCandidateIDs {
            guard candidateIDs.contains(candidateID) else {
                throw ValidationError.eliteCandidateMissing(candidateID)
            }
        }
        if manifest.terminalState == .completed {
            guard !eliteArchive.eliteCandidateIDs.isEmpty,
                  eliteArchive.bestCandidateID != nil,
                  eliteArchive.bestFitness != nil else {
                throw ValidationError.missingCompletedEliteArchive
            }
        }
        if let bestCandidateID = eliteArchive.bestCandidateID {
            guard candidateIDs.contains(bestCandidateID) else {
                throw ValidationError.bestCandidateMissing(bestCandidateID)
            }
            guard eliteArchive.eliteCandidateIDs.contains(bestCandidateID) else {
                throw ValidationError.bestCandidateNotElite(bestCandidateID)
            }
        }
        try validateAcceptedCheckpoint(
            acceptedCheckpoint,
            manifest: manifest,
            candidates: candidates,
            fitness: fitness,
            eliteArchive: eliteArchive
        )
        for cell in qualityDiversityArchive.cells {
            guard candidateIDs.contains(cell.candidateID) else {
                throw ValidationError.qualityDiversityCandidateMissing(cell.candidateID)
            }
            guard cell.fitness.isFinite,
                  cell.behaviorDescriptor.values.allSatisfy(\.isFinite) else {
                throw ValidationError.nonFiniteQualityDiversityCell(cell.cellID)
            }
        }
    }

    private func validateRunIDs(
        expected: String,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        acceptedCheckpoint: EvolutionAcceptedCheckpointDecision,
        qualityDiversityArchive: EvolutionQualityDiversityArchive,
        lineage: [EvolutionLineageRecord]
    ) throws {
        if eliteArchive.runID != expected {
            throw ValidationError.runIDMismatch(file: "elite-archive.json", expected: expected, actual: eliteArchive.runID)
        }
        if qualityDiversityArchive.runID != expected {
            throw ValidationError.runIDMismatch(file: EvolutionQualityDiversityArchive.fileName, expected: expected, actual: qualityDiversityArchive.runID)
        }
        if acceptedCheckpoint.runID != expected {
            throw ValidationError.runIDMismatch(
                file: EvolutionAcceptedCheckpointDecision.fileName,
                expected: expected,
                actual: acceptedCheckpoint.runID
            )
        }
        for record in generations where record.runID != expected {
            throw ValidationError.runIDMismatch(file: "generations.jsonl", expected: expected, actual: record.runID)
        }
        for candidate in candidates where candidate.runID != expected {
            throw ValidationError.runIDMismatch(file: "candidates.jsonl", expected: expected, actual: candidate.runID)
        }
        for summary in fitness where summary.runID != expected {
            throw ValidationError.runIDMismatch(file: "fitness.jsonl", expected: expected, actual: summary.runID)
        }
        for record in lineage where record.runID != expected {
            throw ValidationError.runIDMismatch(file: "lineage.json", expected: expected, actual: record.runID)
        }
    }

    private func validateAcceptedCheckpoint(
        _ decision: EvolutionAcceptedCheckpointDecision,
        manifest: EvolutionRunManifest,
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive
    ) throws {
        guard decision.terminalState == manifest.terminalState else {
            throw ValidationError.acceptedCheckpointMismatch("terminal-state")
        }
        guard decision.accepted == (manifest.terminalState == .completed && eliteArchive.bestCandidateID != nil) else {
            throw ValidationError.acceptedCheckpointMismatch("accepted")
        }
        if decision.accepted {
            guard let candidateID = decision.candidateID else {
                throw ValidationError.acceptedCheckpointMismatch("candidate-id")
            }
            guard let candidate = candidates.first(where: { $0.candidateID == candidateID }) else {
                throw ValidationError.acceptedCheckpointCandidateMissing(candidateID)
            }
            guard eliteArchive.bestCandidateID == candidateID,
                  decision.checkpointID == candidate.checkpointID,
                  decision.checkpointURL == candidate.checkpointURL,
                  decision.scalarFitness == eliteArchive.bestFitness else {
                throw ValidationError.acceptedCheckpointMismatch(candidateID)
            }
        } else {
            guard decision.candidateID == nil,
                  decision.checkpointID == nil,
                  decision.checkpointURL == nil,
                  decision.scalarFitness == nil else {
                throw ValidationError.acceptedCheckpointMismatch("rejected-candidate")
            }
        }

        let expectedIncumbentFitness = decision.incumbentCandidateID.flatMap { candidateID in
            fitness.first { $0.candidateID == candidateID }?.scalarFitness
        }
        guard decision.incumbentFitness == expectedIncumbentFitness else {
            throw ValidationError.acceptedCheckpointMismatch("incumbent-fitness")
        }
        let expectedDelta = zipOptional(decision.scalarFitness, decision.incumbentFitness).map { best, incumbent in
            best - incumbent
        }
        guard decision.bestVsIncumbentDelta == expectedDelta else {
            throw ValidationError.acceptedCheckpointMismatch("best-vs-incumbent")
        }
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        fileName: String,
        directory: URL,
        decoder: JSONDecoder
    ) throws -> T {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError.missingFile(fileName)
        }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func loadJSONLines<T: Decodable>(
        _ type: T.Type,
        fileName: String,
        directory: URL,
        decoder: JSONDecoder
    ) throws -> [T] {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError.missingFile(fileName)
        }
        let raw = try String(contentsOf: url, encoding: .utf8)
        var records: [T] = []
        for (index, line) in raw.split(separator: "\n").enumerated() {
            guard let data = String(line).data(using: .utf8) else {
                throw ValidationError.invalidLine(file: fileName, line: index + 1)
            }
            do {
                records.append(try decoder.decode(type, from: data))
            } catch {
                throw ValidationError.invalidLine(file: fileName, line: index + 1)
            }
        }
        return records
    }
}
