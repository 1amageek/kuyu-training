import Foundation
import KuyuTrainingValidation

public extension TrainingProbeArtifactValidator {
    func validatedAcceptance(in artifactDirectory: URL) throws -> TrainingProbeAcceptanceReceipt {
        let bundle = try validatedBundle(in: artifactDirectory)
        guard bundle.manifest.terminalState == .completed,
              bundle.manifest.failureReason == nil,
              bundle.comparison.probeAccepted else {
            throw ValidationError.inconsistentProbeComparison(
                "accepted receipt requires a completed probe without failure"
            )
        }
        guard bundle.probeCheckpointDecision.state == .accepted,
              let publishedCheckpointURL = bundle.probeCheckpointDecision.publishedCheckpointURL else {
            throw ValidationError.inconsistentProbeComparison(
                "accepted receipt requires an accepted published checkpoint"
            )
        }
        guard bundle.comparison.selectedCheckpointRole == .candidate,
              bundle.comparison.selectedCheckpointURL == publishedCheckpointURL,
              bundle.comparison.acceptedCheckpointURL == publishedCheckpointURL else {
            throw ValidationError.inconsistentProbeComparison(
                "accepted receipt requires the published checkpoint to be selected"
            )
        }
        guard let sourceCheckpointURL = bundle.manifest.sourceCheckpointURL else {
            throw ValidationError.inconsistentProbeComparison(
                "accepted receipt requires source checkpoint lineage"
            )
        }
        guard let candidateCheckpointURL = bundle.training.checkpointDecision.candidateCheckpointURL,
              bundle.probeCheckpointDecision.candidateCheckpointURL?.standardizedFileURL
                == candidateCheckpointURL.standardizedFileURL else {
            throw ValidationError.inconsistentProbeComparison(
                "accepted receipt requires consistent candidate checkpoint lineage"
            )
        }
        try validateCheckpointDirectory(
            sourceCheckpointURL,
            role: "source",
            artifactDirectory: artifactDirectory
        )
        try validateCheckpointDirectory(
            candidateCheckpointURL,
            role: "candidate",
            artifactDirectory: artifactDirectory
        )
        try validateCheckpointDirectory(
            publishedCheckpointURL,
            role: "published",
            artifactDirectory: artifactDirectory
        )

        let datasetDirectories = try trainingDatasetDirectories(in: bundle.training.artifactDirectory)
        guard !datasetDirectories.isEmpty else {
            throw ValidationError.inconsistentProbeComparison(
                "accepted receipt requires persisted training datasets"
            )
        }
        for datasetDirectory in datasetDirectories {
            do {
                _ = try TrainingDatasetContractValidator().validatedDataset(in: datasetDirectory)
            } catch {
                throw ValidationError.inconsistentProbeComparison(
                    "training dataset contract violation at \(datasetDirectory.path): \(error)"
                )
            }
        }
        let expectedDatasetCount: Int
        if try usesSharedDatasetLayout(in: bundle.training.artifactDirectory) {
            let scenarioKeys = Set(
                bundle.training.scenarioRuns.flatMap(\.scenarioKeys)
            )
            guard !scenarioKeys.isEmpty else {
                throw ValidationError.inconsistentProbeComparison(
                    "shared training dataset layout requires scenario key lineage"
                )
            }
            expectedDatasetCount = scenarioKeys.count
        } else {
            expectedDatasetCount = bundle.training.scenarioRuns.reduce(0) { partial, run in
                partial + run.logCount
            }
        }
        guard datasetDirectories.count == expectedDatasetCount else {
            throw ValidationError.inconsistentProbeComparison(
                "training dataset count does not match persisted scenario evidence (datasets: \(datasetDirectories.count), scenario logs: \(expectedDatasetCount))"
            )
        }
        guard let trainedScore = bundle.comparison.trainedScore,
              let scoreDelta = bundle.comparison.scoreDelta else {
            throw ValidationError.inconsistentProbeComparison(
                "accepted receipt requires trained score evidence"
            )
        }
        return TrainingProbeAcceptanceReceipt(
            artifactDirectory: artifactDirectory,
            probeID: bundle.manifest.probeID,
            trainingRunID: bundle.manifest.trainingRunID,
            sourceCheckpointURL: sourceCheckpointURL,
            publishedCheckpointURL: publishedCheckpointURL,
            datasetCount: datasetDirectories.count,
            scenarioRunCount: bundle.training.scenarioRuns.count,
            trainedScore: trainedScore,
            scoreDelta: scoreDelta
        )
    }

    private func validateCheckpointDirectory(
        _ checkpointURL: URL,
        role: String,
        artifactDirectory: URL
    ) throws {
        let standardizedCheckpointURL = checkpointURL.standardizedFileURL
        let standardizedArtifactURL = artifactDirectory.standardizedFileURL
        guard isContained(standardizedCheckpointURL, in: standardizedArtifactURL) else {
            throw ValidationError.inconsistentProbeComparison(
                "\(role) checkpoint is outside the probe artifact directory"
            )
        }
        try validateNoSymbolicLinks(
            from: standardizedArtifactURL,
            to: standardizedCheckpointURL,
            role: role
        )

        let resolvedCheckpointURL = standardizedCheckpointURL.resolvingSymlinksInPath()
        let resolvedArtifactURL = standardizedArtifactURL.resolvingSymlinksInPath()
        guard isContained(resolvedCheckpointURL, in: resolvedArtifactURL) else {
            throw ValidationError.inconsistentProbeComparison(
                "\(role) checkpoint is outside the probe artifact directory"
            )
        }
        let values: URLResourceValues
        do {
            values = try resolvedCheckpointURL.resourceValues(
                forKeys: [.isDirectoryKey]
            )
        } catch {
            throw ValidationError.inconsistentProbeComparison(
                "\(role) checkpoint cannot be inspected: \(error)"
            )
        }
        guard values.isDirectory == true else {
            throw ValidationError.inconsistentProbeComparison(
                "\(role) checkpoint is not a regular directory"
            )
        }
    }

    private func validateNoSymbolicLinks(
        from artifactDirectory: URL,
        to checkpointURL: URL,
        role: String
    ) throws {
        let artifactComponents = artifactDirectory.pathComponents
        let checkpointComponents = checkpointURL.pathComponents
        var current = artifactDirectory
        for component in checkpointComponents.dropFirst(artifactComponents.count) {
            current.appendPathComponent(component)
            let values: URLResourceValues
            do {
                values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
            } catch {
                throw ValidationError.inconsistentProbeComparison(
                    "\(role) checkpoint cannot be inspected: \(error)"
                )
            }
            if values.isSymbolicLink == true {
                throw ValidationError.inconsistentProbeComparison(
                    "\(role) checkpoint must not traverse symbolic links"
                )
            }
        }
    }

    private func isContained(_ child: URL, in parent: URL) -> Bool {
        let parentComponents = parent.pathComponents
        let childComponents = child.pathComponents
        guard childComponents.count >= parentComponents.count else {
            return false
        }
        return Array(childComponents.prefix(parentComponents.count)) == parentComponents
    }

    private func trainingDatasetDirectories(in trainingDirectory: URL) throws -> [URL] {
        let datasetsRoot = trainingDirectory.appendingPathComponent("datasets", isDirectory: true)
        let iterationDirectories = try childDirectories(in: datasetsRoot)
        var datasets: [URL] = []
        for iterationDirectory in iterationDirectories {
            datasets.append(contentsOf: try childDirectories(in: iterationDirectory).filter { directory in
                FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent("meta.json", isDirectory: false).path
                ) && FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent("records.jsonl", isDirectory: false).path
                )
            })
        }
        return datasets.sorted { $0.path < $1.path }
    }

    private func usesSharedDatasetLayout(in trainingDirectory: URL) throws -> Bool {
        let datasetsRoot = trainingDirectory.appendingPathComponent("datasets", isDirectory: true)
        return try childDirectories(in: datasetsRoot).contains { directory in
            directory.lastPathComponent == "shared"
        }
    }

    private func childDirectories(in directory: URL) throws -> [URL] {
        let values: URLResourceValues
        do {
            values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw ValidationError.inconsistentProbeComparison(
                "expected readable directory at \(directory.path): \(error)"
            )
        }
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ValidationError.inconsistentProbeComparison(
                "expected directory at \(directory.path)"
            )
        }
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ).filter { child in
                let childValues = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return childValues.isDirectory == true && childValues.isSymbolicLink != true
            }
        } catch {
            throw ValidationError.inconsistentProbeComparison(
                "failed to inspect directory at \(directory.path): \(error)"
            )
        }
    }
}
