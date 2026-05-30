import Foundation

/// Durable, crash-safe store for per-generation resume checkpoints under an
/// evolution artifact directory (`<dir>/resume/generation-<n>.json`).
///
/// Writes are atomic (`Data.write(options: .atomic)` = temp + rename), so a
/// committed `generation-<n>.json` is never torn: it is either absent or a
/// complete, decodable checkpoint. A present-but-undecodable file is therefore
/// genuine corruption and is reported as an explicit error (never silently
/// skipped or rolled back).
public struct EvolutionResumeCheckpointStore: Sendable {
    public enum StoreError: Error, Sendable, Equatable, CustomStringConvertible {
        case corruptCheckpoint(path: String, reason: String)
        case unsupportedSchemaVersion(path: String, version: Int)
        case configHashMismatch(path: String, expected: String, actual: String)
        case generationIndexMismatch(path: String, expected: Int, actual: Int)
        case missingGenerationCheckpoint(generation: Int)
        case writeFailed(path: String, reason: String)

        public var description: String {
            switch self {
            case .corruptCheckpoint(let path, let reason):
                return "corrupt-resume-checkpoint: \(path) (\(reason))"
            case .unsupportedSchemaVersion(let path, let version):
                return "unsupported-resume-schema-version: \(path) version=\(version)"
            case .configHashMismatch(let path, let expected, let actual):
                return "resume-config-hash-mismatch: \(path) expected=\(expected) actual=\(actual)"
            case .generationIndexMismatch(let path, let expected, let actual):
                return "resume-generation-index-mismatch: \(path) expected=\(expected) actual=\(actual)"
            case .missingGenerationCheckpoint(let generation):
                return "missing-resume-checkpoint: generation-\(generation)"
            case .writeFailed(let path, let reason):
                return "resume-checkpoint-write-failed: \(path) (\(reason))"
            }
        }
    }

    private static let directoryName = "resume"
    private static let filePrefix = "generation-"
    private static let fileSuffix = ".json"

    public init() {}

    private var fileManager: FileManager { .default }

    // MARK: - Paths

    public func resumeDirectory(in artifactDirectory: URL) -> URL {
        artifactDirectory.appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    private func checkpointURL(generation: Int, in artifactDirectory: URL) -> URL {
        resumeDirectory(in: artifactDirectory)
            .appendingPathComponent("\(Self.filePrefix)\(generation)\(Self.fileSuffix)", isDirectory: false)
    }

    private func generationIndex(fromFileName name: String) -> Int? {
        guard name.hasPrefix(Self.filePrefix), name.hasSuffix(Self.fileSuffix) else {
            return nil
        }
        let start = name.index(name.startIndex, offsetBy: Self.filePrefix.count)
        let end = name.index(name.endIndex, offsetBy: -Self.fileSuffix.count)
        let digits = name[start..<end]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let index = Int(digits) else {
            return nil
        }
        return index
    }

    // MARK: - Write

    /// Atomically writes `checkpoint` as `resume/generation-<N>.json`.
    public func write(_ checkpoint: EvolutionGenerationCheckpoint, to artifactDirectory: URL) throws {
        let directory = resumeDirectory(in: artifactDirectory)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw StoreError.writeFailed(path: directory.path, reason: String(describing: error))
        }
        let url = checkpointURL(generation: checkpoint.lastCommittedGeneration, in: artifactDirectory)
        let data: Data
        do {
            data = try Self.makeEncoder().encode(checkpoint)
        } catch {
            throw StoreError.writeFailed(path: url.path, reason: "encode: \(String(describing: error))")
        }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw StoreError.writeFailed(path: url.path, reason: String(describing: error))
        }
    }

    // MARK: - Read / resolve

    /// Sorted ascending list of committed generation indices found on disk.
    /// Throws (fail-closed) if any present checkpoint file is corrupt or carries a
    /// config-hash / schema mismatch.
    public func committedGenerations(
        in artifactDirectory: URL,
        expectedConfigHash: String? = nil
    ) throws -> [Int] {
        let directory = resumeDirectory(in: artifactDirectory)
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw StoreError.corruptCheckpoint(path: directory.path, reason: String(describing: error))
        }
        var indices: [Int] = []
        for entry in entries {
            guard let index = generationIndex(fromFileName: entry.lastPathComponent) else {
                continue
            }
            let checkpoint = try decode(at: entry)
            guard checkpoint.lastCommittedGeneration == index else {
                throw StoreError.generationIndexMismatch(
                    path: entry.path,
                    expected: index,
                    actual: checkpoint.lastCommittedGeneration
                )
            }
            if let expectedConfigHash, checkpoint.configHash != expectedConfigHash {
                throw StoreError.configHashMismatch(
                    path: entry.path,
                    expected: expectedConfigHash,
                    actual: checkpoint.configHash
                )
            }
            indices.append(index)
        }
        return indices.sorted()
    }

    /// Highest committed generation index, or nil if no resumable checkpoint exists.
    public func highestCommittedGeneration(
        in artifactDirectory: URL,
        expectedConfigHash: String? = nil
    ) throws -> Int? {
        try committedGenerations(in: artifactDirectory, expectedConfigHash: expectedConfigHash).last
    }

    public func loadCheckpoint(generation: Int, in artifactDirectory: URL) throws -> EvolutionGenerationCheckpoint {
        let url = checkpointURL(generation: generation, in: artifactDirectory)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StoreError.missingGenerationCheckpoint(generation: generation)
        }
        return try decode(at: url)
    }

    /// Assembles the in-memory resume state by accumulating generations
    /// `0...upToGeneration`. The contiguous prefix must be fully present;
    /// a gap is fail-closed.
    public func loadResumeState(
        in artifactDirectory: URL,
        upToGeneration: Int,
        expectedConfigHash: String? = nil
    ) throws -> EvolutionResumeState {
        var generations: [PopulationGenerationRecord] = []
        var candidates: [GenomeCandidate] = []
        var fitness: [FitnessSummary] = []
        var traces: [EvolutionCandidateEvaluationTrace] = []
        var latest: EvolutionGenerationCheckpoint?

        for generation in 0...max(0, upToGeneration) {
            let checkpoint = try loadCheckpoint(generation: generation, in: artifactDirectory)
            if let expectedConfigHash, checkpoint.configHash != expectedConfigHash {
                throw StoreError.configHashMismatch(
                    path: checkpointURL(generation: generation, in: artifactDirectory).path,
                    expected: expectedConfigHash,
                    actual: checkpoint.configHash
                )
            }
            generations.append(checkpoint.generationRecord)
            candidates.append(contentsOf: checkpoint.generationCandidates)
            fitness.append(contentsOf: checkpoint.generationFitness)
            traces.append(contentsOf: checkpoint.generationTraces)
            latest = checkpoint
        }
        guard let latest else {
            throw StoreError.missingGenerationCheckpoint(generation: upToGeneration)
        }
        return EvolutionResumeState(
            runID: latest.runID,
            startGenerationIndex: latest.lastCommittedGeneration + 1,
            currentPopulation: latest.nextPopulation,
            generations: generations,
            candidates: candidates,
            fitness: fitness,
            evaluationTraces: traces,
            mutationRate: latest.mutationRate,
            mutationNoiseScale: latest.mutationNoiseScale,
            earlyStopping: latest.earlyStopping,
            incumbentCandidateID: latest.incumbentCandidateID,
            incumbentFitness: latest.incumbentFitness,
            bestAcceptedFitness: latest.bestAcceptedFitness
        )
    }

    // MARK: - Codec

    private func decode(at url: URL) throws -> EvolutionGenerationCheckpoint {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StoreError.corruptCheckpoint(path: url.path, reason: "read: \(String(describing: error))")
        }
        let checkpoint: EvolutionGenerationCheckpoint
        do {
            checkpoint = try Self.makeDecoder().decode(EvolutionGenerationCheckpoint.self, from: data)
        } catch {
            throw StoreError.corruptCheckpoint(path: url.path, reason: "decode: \(String(describing: error))")
        }
        guard checkpoint.schemaVersion == EvolutionGenerationCheckpoint.currentSchemaVersion else {
            throw StoreError.unsupportedSchemaVersion(path: url.path, version: checkpoint.schemaVersion)
        }
        return checkpoint
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return decoder
    }
}
