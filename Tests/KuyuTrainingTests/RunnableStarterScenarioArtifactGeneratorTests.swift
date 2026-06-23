import Foundation
import KuyuTraining
import Testing

@Test(.timeLimit(.minutes(2))) func runnableStarterScenarioArtifactGeneratorWritesReplayValidatedArtifacts() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-runnable-starter-artifacts-\(UUID().uuidString)", isDirectory: true)
    defer {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Failed to remove temporary directory: \(error)")
        }
    }

    let report = try await RunnableStarterScenarioArtifactGenerator().generate(
        to: directory,
        generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    #expect(report.artifacts.map(\.templateID) == [
        "aerial-drone-autonomy-starter-v1",
        "aerial-single-prop-lift-recovery-v1",
    ])
    #expect(report.artifacts.allSatisfy { $0.scenarioCount > 0 })
    #expect(report.artifacts.allSatisfy { $0.replayCheckCount == $0.scenarioCount })

    let reportURL = directory.appendingPathComponent(RunnableStarterScenarioArtifactReport.fileName)
    #expect(FileManager.default.fileExists(atPath: reportURL.path))

    for record in report.artifacts {
        let bundle = try TrainingRunArtifactValidator().loadAndValidate(from: record.artifactDirectory)
        #expect(bundle.scenarioRuns.count == record.suiteIDs.count)
        #expect(bundle.scenarioRuns.allSatisfy { $0.summary.replay.notPerformedReason == nil })
        #expect(bundle.scenarioRuns.allSatisfy { $0.summary.replay.checks.allSatisfy(\.passed) })
        #expect(bundle.scenarioRuns.reduce(0) { $0 + $1.summary.evaluations.count } == record.scenarioCount)
        #expect(bundle.scenarioRuns.reduce(0) { $0 + $1.summary.replay.checks.count } == record.replayCheckCount)
    }
}
