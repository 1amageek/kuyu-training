import CryptoKit
import Foundation
import KuyuTraining
import Testing

@Test func kuyuDatasetV7RoundTripPreservesValidatedOnPolicyRecords() throws {
    try withKuyuDatasetTemporaryDirectory { root in
        let destination = root.appendingPathComponent("artifact", isDirectory: true)
        let descriptor = makeKuyuDatasetDescriptor()
        let records = makeOnPolicyRecords()

        let manifest = try KuyuDatasetWriter().write(
            descriptor: descriptor,
            records: records,
            to: destination
        )
        var observed: [KuyuDatasetRecord] = []
        let summary = try KuyuDatasetReader().read(destination) { observed.append($0) }
        var inspected: [KuyuDatasetRecord] = []
        let inspection = try KuyuDatasetReader().inspect(destination) { inspected.append($0) }

        #expect(manifest.schemaVersion == 7)
        #expect(manifest.recordCount == 2)
        #expect(summary.observedRecordCount == 2)
        #expect(summary.observedRecordsDigest == manifest.recordsDigest)
        let manifestData = try Data(
            contentsOf: destination.appendingPathComponent("manifest.json")
        )
        #expect(
            summary.observedManifestDigest
                == SHA256.hash(data: manifestData)
                .map { String(format: "%02x", $0) }
                .joined()
        )
        #expect(observed == records)
        #expect(inspection == summary)
        #expect(inspected == records)
        #expect(try stagingDirectories(in: root).isEmpty)
    }
}

@Test func kuyuDatasetV7ReaderRejectsDigestCorruption() throws {
    try withKuyuDatasetTemporaryDirectory { root in
        let destination = root.appendingPathComponent("artifact", isDirectory: true)
        let manifest = try KuyuDatasetWriter().write(
            descriptor: makeKuyuDatasetDescriptor(),
            records: makeOnPolicyRecords(),
            to: destination
        )
        let recordsURL = destination.appendingPathComponent("records.jsonl")
        var data = try Data(contentsOf: recordsURL)
        data.insert(0x20, at: data.index(before: data.endIndex))
        try data.write(to: recordsURL)

        do {
            try KuyuDatasetReader().validate(destination)
            Issue.record("Expected modified record bytes to fail digest validation.")
        } catch KuyuDatasetArtifactError.recordsDigestMismatch(let expected, let actual) {
            #expect(expected == manifest.recordsDigest)
            #expect(actual != expected)
        }
    }
}

@Test func kuyuDatasetV7ReaderRejectsUnknownFixedHistoryPaddingRule() throws {
    try withKuyuDatasetTemporaryDirectory { root in
        let destination = root.appendingPathComponent("artifact", isDirectory: true)
        _ = try KuyuDatasetWriter().write(
            descriptor: makeKuyuDatasetDescriptor(),
            records: makeOnPolicyRecords(),
            to: destination
        )
        let manifestURL = destination.appendingPathComponent("manifest.json")
        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        let modifiedText = manifestText.replacingOccurrences(
            of: "\"paddingRule\" : \"zero\"",
            with: "\"paddingRule\" : \"repeat-segment-initial-observation\""
        )
        #expect(modifiedText != manifestText)
        try Data(modifiedText.utf8).write(to: manifestURL)

        do {
            try KuyuDatasetReader().validate(destination)
            Issue.record("Expected an unknown fixed-history padding rule to fail decoding.")
        } catch KuyuDatasetArtifactError.manifestDecodeFailed(let path, _) {
            #expect(path == manifestURL)
        }
    }
}

@Test func kuyuDatasetV7WriterDoesNotPublishRecordKindMismatch() throws {
    try withKuyuDatasetTemporaryDirectory { root in
        let destination = root.appendingPathComponent("artifact", isDirectory: true)
        let onPolicy = makeOnPolicyRecords()[0]
        guard case .onPolicyTransition(let sample) = onPolicy else {
            Issue.record("Expected on-policy fixture.")
            return
        }

        do {
            try KuyuDatasetWriter().write(
                descriptor: makeKuyuDatasetDescriptor(),
                records: [KuyuDatasetRecord.offPolicyTransition(
                    KuyuOffPolicyTransition(transition: sample.transition)
                )],
                to: destination
            )
            Issue.record("Expected record-kind mismatch to fail publication.")
        } catch KuyuDatasetValidator.ValidationError.recordKindMismatch(
            let index,
            let expected,
            let actual
        ) {
            #expect(index == 0)
            #expect(expected == .onPolicyTransition)
            #expect(actual == .offPolicyTransition)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try stagingDirectories(in: root).isEmpty)
    }
}

@Test func kuyuDatasetV7WriterRejectsContinuingFinalBoundary() throws {
    try withKuyuDatasetTemporaryDirectory { root in
        let destination = root.appendingPathComponent("artifact", isDirectory: true)
        let record = makeOnPolicyRecord(
            index: 0,
            source: [0, 0],
            outcome: [0.1, 0.1],
            startTime: 0,
            boundary: .continues
        )

        do {
            try KuyuDatasetWriter().write(
                descriptor: makeKuyuDatasetDescriptor(),
                records: [record],
                to: destination
            )
            Issue.record("Expected a continuing final boundary to fail publication.")
        } catch KuyuDatasetValidator.ValidationError.finalBoundaryContinues {
            #expect(true)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try stagingDirectories(in: root).isEmpty)
    }
}

@Test func kuyuDatasetV7WriterRejectsFalsePhysicsTickCount() throws {
    try withKuyuDatasetTemporaryDirectory { root in
        let destination = root.appendingPathComponent("artifact", isDirectory: true)
        let transition = makeControlTransition(
            index: 0,
            source: [0, 0],
            outcome: [0.1, 0.1],
            startTime: 0,
            boundary: .segmentEnd(KuyuTrajectoryBoundary.SegmentEnd(bootstrapAllowed: false)),
            physicsTickCount: 1
        )
        let record = KuyuDatasetRecord.onPolicyTransition(KuyuOnPolicyTransition(
            transition: transition,
            behavior: makeBehavior(action: transition.policyAction.values)
        ))

        do {
            try KuyuDatasetWriter().write(
                descriptor: makeKuyuDatasetDescriptor(),
                records: [record],
                to: destination
            )
            Issue.record("Expected a false physics tick count to fail publication.")
        } catch KuyuDatasetValidator.ValidationError.invalidInterval(let index, let reason) {
            #expect(index == 0)
            #expect(reason == "physics tick duration mismatch")
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

@Test func kuyuDatasetV7RecurrentContextRequiresInitialAndContinuousStateDigests() throws {
    try withKuyuDatasetTemporaryDirectory { root in
        let recurrent = KuyuPolicyContextContract.recurrent(.init(
            stateSpaceDigest: KuyuDatasetTestDigest.a,
            resetRule: "segment-initial-state",
            initialState: [0, 0],
            initialStateDigest: KuyuDatasetTestDigest.b,
            burnInCount: 0,
            lossStartTransitionIndex: 0
        ))
        let descriptor = makeKuyuDatasetDescriptor(policyContext: recurrent)
        let firstTransition = makeControlTransition(
            index: 0,
            source: [0, 0],
            outcome: [0.1, 0.1],
            startTime: 0,
            boundary: .continues
        )
        let invalidInitial = KuyuDatasetRecord.onPolicyTransition(KuyuOnPolicyTransition(
            transition: firstTransition,
            behavior: makeBehavior(
                action: firstTransition.policyAction.values,
                inputRecurrentStateDigest: KuyuDatasetTestDigest.c,
                outputRecurrentStateDigest: KuyuDatasetTestDigest.d
            )
        ))

        do {
            try KuyuDatasetWriter().write(
                descriptor: descriptor,
                records: [invalidInitial],
                to: root.appendingPathComponent("invalid-initial", isDirectory: true)
            )
            Issue.record("Expected the initial recurrent state mismatch to fail.")
        } catch KuyuDatasetValidator.ValidationError.invalidBehaviorEvidence(let index, let reason) {
            #expect(index == 0)
            #expect(reason == "initial recurrent state digest mismatch")
        }

        let first = KuyuDatasetRecord.onPolicyTransition(KuyuOnPolicyTransition(
            transition: firstTransition,
            behavior: makeBehavior(
                action: firstTransition.policyAction.values,
                inputRecurrentStateDigest: KuyuDatasetTestDigest.b,
                outputRecurrentStateDigest: KuyuDatasetTestDigest.c
            )
        ))
        let secondTransition = makeControlTransition(
            index: 1,
            source: [0.1, 0.1],
            outcome: [0.2, 0.2],
            startTime: 0.02,
            boundary: .segmentEnd(KuyuTrajectoryBoundary.SegmentEnd(bootstrapAllowed: false))
        )
        let second = KuyuDatasetRecord.onPolicyTransition(KuyuOnPolicyTransition(
            transition: secondTransition,
            behavior: makeBehavior(
                action: secondTransition.policyAction.values,
                inputRecurrentStateDigest: KuyuDatasetTestDigest.d,
                outputRecurrentStateDigest: KuyuDatasetTestDigest.e
            )
        ))

        do {
            try KuyuDatasetWriter().write(
                descriptor: descriptor,
                records: [first, second],
                to: root.appendingPathComponent("invalid-chain", isDirectory: true)
            )
            Issue.record("Expected the recurrent state chain mismatch to fail.")
        } catch KuyuDatasetValidator.ValidationError.transitionDiscontinuity(let index, let field) {
            #expect(index == 1)
            #expect(field == "recurrentStateDigest")
        }
        #expect(try stagingDirectories(in: root).isEmpty)
    }
}

@Test func kuyuDatasetV7WorldEventsRequireAnInIntervalTick() throws {
    try withKuyuDatasetTemporaryDirectory { root in
        let destination = root.appendingPathComponent("artifact", isDirectory: true)
        let record = KuyuDatasetRecord.worldTransition(KuyuWorldTransition(
            coordinate: makeCoordinate(index: 0),
            sourceState: .init(values: [0, 0]),
            actuatorCommand: .init(values: [0.4]),
            events: [.init(id: "gust", physicsTickOffset: 2, values: [1])],
            outcomeState: .init(values: [0.1, 0.1]),
            interval: .init(startTime: 0, endTime: 0.02, actualDuration: 0.02, physicsTickCount: 2),
            boundary: .segmentEnd(.init(bootstrapAllowed: false))
        ))

        do {
            try KuyuDatasetWriter().write(
                descriptor: makeKuyuDatasetDescriptor(recordKind: .worldTransition),
                records: [record],
                to: destination
            )
            Issue.record("Expected an out-of-interval world event to fail.")
        } catch KuyuDatasetValidator.ValidationError.invalidRecord(let index, let reason) {
            #expect(index == 0)
            #expect(reason == "event tick is outside the interval")
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

@Test func kuyuDatasetV7PolicyActionOutsideDeclaredBoundsIsRejected() throws {
    try withKuyuDatasetTemporaryDirectory { root in
        let destination = root.appendingPathComponent("artifact", isDirectory: true)
        let valid = makeOnPolicyRecords()
        guard case .onPolicyTransition(let source) = valid[0] else {
            Issue.record("Expected an on-policy fixture.")
            return
        }
        let invalidTransition = KuyuControlTransition(
            coordinate: source.transition.coordinate,
            sourceObservation: source.transition.sourceObservation,
            sourceStateFacts: source.transition.sourceStateFacts,
            policyAction: .init(values: [2]),
            realizedControl: source.transition.realizedControl,
            actuatorCommand: source.transition.actuatorCommand,
            outcomeObservation: source.transition.outcomeObservation,
            outcomeStateFacts: source.transition.outcomeStateFacts,
            reward: source.transition.reward,
            safetyCost: source.transition.safetyCost,
            interval: source.transition.interval,
            boundary: source.transition.boundary
        )
        let invalid = KuyuDatasetRecord.onPolicyTransition(.init(
            transition: invalidTransition,
            behavior: makeBehavior(action: [2])
        ))

        do {
            try KuyuDatasetWriter().write(
                descriptor: makeKuyuDatasetDescriptor(),
                records: [invalid, valid[1]],
                to: destination
            )
            Issue.record("Expected an out-of-bounds policy action to fail.")
        } catch KuyuDatasetValidator.ValidationError.invalidRecord(let index, let reason) {
            #expect(index == 0)
            #expect(reason == "policyAction is outside channel bounds at index 0")
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

@Test func kuyuDatasetV7LegacyReinforcementRejectsUnprovenObservationRelations() throws {
    try withKuyuDatasetTemporaryDirectory { root in
        let destination = root.appendingPathComponent("artifact", isDirectory: true)
        let source = try makeLegacySource(
            makeLegacyReinforcementDataset(),
            root: root,
            name: "source"
        )
        let result = try KuyuDatasetLegacyMigrator().migrate(
            source,
            descriptor: makeKuyuDatasetDescriptor(),
            to: destination
        )

        guard case .rejected(let report) = result else {
            Issue.record("Expected legacy rollout with unproven observation relations to be rejected.")
            return
        }
        #expect(report.unavailableFacts.contains("explicitPolicyObservationRelation"))
        #expect(report.unavailableFacts.contains("explicitOutcomeObservationRelation"))
        #expect(report.unavailableFacts.contains("explicitBootstrapPermission"))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

@Test func kuyuDatasetV7LegacyMigrationRejectsMissingCostAndBoundaryFacts() throws {
    try withKuyuDatasetTemporaryDirectory { root in
        let source = makeLegacyReinforcementDataset()
        let missingCost = TrainingDataset(
            metadata: source.metadata,
            records: [source.records[0].replacingCost(with: nil), source.records[1]]
        )
        let costDestination = root.appendingPathComponent("missing-cost", isDirectory: true)
        let missingCostSource = try makeLegacySource(missingCost, root: root, name: "missing-cost-source")
        let costResult = try KuyuDatasetLegacyMigrator().migrate(
            missingCostSource,
            descriptor: makeKuyuDatasetDescriptor(),
            to: costDestination
        )
        guard case .rejected(let costReport) = costResult else {
            Issue.record("Expected missing safety cost to reject migration.")
            return
        }
        #expect(costReport.unavailableFacts.contains("safetyCost"))
        #expect(!FileManager.default.fileExists(atPath: costDestination.path))

        let nonterminalRecords = source.records.enumerated().map { index, record in
            makeLegacyRecord(
                index: index,
                source: record.actionObservationState ?? [],
                outcome: record.actualState ?? [],
                done: false,
                truncated: false
            )
        }
        let nonterminal = TrainingDataset(
            metadata: makeLegacyMetadata(records: nonterminalRecords, done: false, truncated: false),
            records: nonterminalRecords
        )
        let boundaryDestination = root.appendingPathComponent("missing-boundary", isDirectory: true)
        let nonterminalSource = try makeLegacySource(nonterminal, root: root, name: "nonterminal-source")
        let boundaryResult = try KuyuDatasetLegacyMigrator().migrate(
            nonterminalSource,
            descriptor: makeKuyuDatasetDescriptor(),
            to: boundaryDestination
        )
        guard case .rejected(let boundaryReport) = boundaryResult else {
            Issue.record("Expected an implicit segment end to reject migration.")
            return
        }
        #expect(boundaryReport.unavailableFacts.contains("explicitFinalBoundary"))
        #expect(!FileManager.default.fileExists(atPath: boundaryDestination.path))
    }
}

private enum KuyuDatasetTestDigest {
    static let a = String(repeating: "a", count: 64)
    static let b = String(repeating: "b", count: 64)
    static let c = String(repeating: "c", count: 64)
    static let d = String(repeating: "d", count: 64)
    static let e = String(repeating: "e", count: 64)
    static let f = String(repeating: "f", count: 64)
}

private func makeKuyuDatasetDescriptor(
    recordKind: KuyuDatasetRecord.Kind = .onPolicyTransition,
    policyContext: KuyuPolicyContextContract? = .fixedHistory(.init(
        historyLength: 2,
        featureOrderDigest: KuyuDatasetTestDigest.a,
        paddingRule: .zero,
        previousActionRule: .zeroBeforeFirstDecision
    ))
) -> KuyuDatasetDescriptor {
    let usesPolicy = recordKind == .onPolicyTransition
    return KuyuDatasetDescriptor(
        identity: .init(
            datasetID: "dataset-a",
            scenarioID: "scenario-a",
            scenarioRevision: "1",
            suiteID: "suite-a",
            suiteVersion: "1",
            seed: 7,
            episodeID: "episode-a",
            segmentID: "segment-a",
            segmentIndex: 0
        ),
        producer: .init(id: "test-producer", version: "1"),
        recordKind: recordKind,
        execution: .init(
            dynamicsProgramSchemaVersion: 1,
            dynamicsProgramDigest: KuyuDatasetTestDigest.a,
            fidelityID: "reference",
            constraintProjectionID: "projection-a",
            mixerID: "mixer-a",
            rotorSpinConventionID: "spin-a",
            backendID: "scalar",
            backendVersion: "1",
            numericType: "float64",
            deviceClass: "cpu",
            determinismTier: "strict"
        ),
        spaces: .init(
            observation: makeSpace(id: "observation", digest: KuyuDatasetTestDigest.b, count: 2),
            criticState: makeSpace(id: "critic-state", digest: KuyuDatasetTestDigest.c, count: 2),
            policyAction: makeSpace(
                id: "policy-action",
                digest: KuyuDatasetTestDigest.d,
                count: 1,
                transform: .affineTanh,
                bounds: -1...1
            ),
            realizedControl: makeSpace(id: "realized-control", digest: KuyuDatasetTestDigest.e, count: 1),
            actuatorCommand: makeSpace(id: "actuator-command", digest: KuyuDatasetTestDigest.f, count: 1),
            worldState: recordKind == .worldTransition
                ? makeSpace(id: "world-state", digest: KuyuDatasetTestDigest.a, count: 2)
                : nil
        ),
        timing: .init(physicsTimeStep: 0.01, controlPeriodTicks: 2),
        semantics: .init(
            rewardDescriptorDigest: KuyuDatasetTestDigest.a,
            safetyCostDescriptorDigest: KuyuDatasetTestDigest.b,
            failureDescriptorDigest: KuyuDatasetTestDigest.c,
            taskQualityDescriptorDigest: KuyuDatasetTestDigest.d
        ),
        policy: usesPolicy ? .init(
            policyID: "policy-a",
            checkpointDigest: KuyuDatasetTestDigest.e,
            distributionContractDigest: KuyuDatasetTestDigest.f
        ) : nil,
        policyContext: usesPolicy ? policyContext : nil,
        provenance: .init(
            codeDigest: KuyuDatasetTestDigest.a,
            configurationDigest: KuyuDatasetTestDigest.b,
            embodimentDigest: KuyuDatasetTestDigest.c
        )
    )
}

private func makeSpace(
    id: String,
    digest: String,
    count: Int,
    transform: KuyuDatasetDescriptor.ChannelTransform = .identity,
    bounds: ClosedRange<Double>? = nil
) -> KuyuDatasetDescriptor.Space {
    KuyuDatasetDescriptor.Space(
        id: id,
        version: "1",
        digest: digest,
        channels: (0..<count).map { index in
            KuyuDatasetDescriptor.Channel(
                index: index,
                id: "\(id).\(index)",
                unit: "normalized",
                lowerBound: bounds?.lowerBound,
                upperBound: bounds?.upperBound,
                transform: transform
            )
        }
    )
}

private func makeOnPolicyRecords() -> [KuyuDatasetRecord] {
    [
        makeOnPolicyRecord(
            index: 0,
            source: [0, 0],
            outcome: [0.1, 0.1],
            startTime: 0,
            boundary: .continues
        ),
        makeOnPolicyRecord(
            index: 1,
            source: [0.1, 0.1],
            outcome: [0.2, 0.2],
            startTime: 0.02,
            boundary: .segmentEnd(.init(bootstrapAllowed: false))
        ),
    ]
}

private func makeOnPolicyRecord(
    index: Int,
    source: [Double],
    outcome: [Double],
    startTime: Double,
    boundary: KuyuTrajectoryBoundary
) -> KuyuDatasetRecord {
    let transition = makeControlTransition(
        index: index,
        source: source,
        outcome: outcome,
        startTime: startTime,
        boundary: boundary
    )
    return .onPolicyTransition(KuyuOnPolicyTransition(
        transition: transition,
        behavior: makeBehavior(action: transition.policyAction.values)
    ))
}

private func makeControlTransition(
    index: Int,
    source: [Double],
    outcome: [Double],
    startTime: Double,
    boundary: KuyuTrajectoryBoundary,
    physicsTickCount: UInt64 = 2
) -> KuyuControlTransition {
    let action = [tanh(0.2)]
    return KuyuControlTransition(
        coordinate: makeCoordinate(index: index),
        sourceObservation: .init(time: startTime, values: source),
        sourceStateFacts: .init(values: source),
        policyAction: .init(values: action),
        realizedControl: .init(
            driveIntents: [.init(driveIndex: 0, activation: 0.4)],
            reflexCorrections: []
        ),
        actuatorCommand: .init(values: [0.4]),
        outcomeObservation: .init(time: startTime + 0.02, values: outcome),
        outcomeStateFacts: .init(values: outcome),
        reward: 1,
        safetyCost: 0.1,
        interval: .init(
            startTime: startTime,
            endTime: startTime + 0.02,
            actualDuration: 0.02,
            physicsTickCount: physicsTickCount
        ),
        boundary: boundary
    )
}

private func makeBehavior(
    action: [Double],
    inputRecurrentStateDigest: String? = nil,
    outputRecurrentStateDigest: String? = nil
) -> KuyuBehaviorPolicyEvidence {
    KuyuBehaviorPolicyEvidence(
        policyID: "policy-a",
        checkpointDigest: KuyuDatasetTestDigest.e,
        distributionKinds: [.affineTanhGaussian],
        distributionVersion: 1,
        distributionContractDigest: KuyuDatasetTestDigest.f,
        baseMean: [0],
        transformedMean: [0],
        baseLogStandardDeviation: [-0.5],
        preTransformSample: [0.2],
        transformedAction: action,
        logProbability: -0.3,
        rewardValue: 0.8,
        costValue: 0.2,
        inputRecurrentStateDigest: inputRecurrentStateDigest,
        outputRecurrentStateDigest: outputRecurrentStateDigest
    )
}

private func makeCoordinate(index: Int) -> KuyuTrajectoryCoordinate {
    .init(
        episodeID: "episode-a",
        segmentID: "segment-a",
        segmentIndex: 0,
        transitionIndex: index,
        decisionID: "decision-\(index)"
    )
}

private func makeLegacyReinforcementDataset() -> TrainingDataset {
    let records = [
        makeLegacyRecord(
            index: 0,
            source: [0, 0],
            outcome: [0.1, 0.1],
            done: false,
            truncated: false
        ),
        makeLegacyRecord(
            index: 1,
            source: [0.1, 0.1],
            outcome: [0.2, 0.2],
            done: false,
            truncated: true
        ),
    ]
    return TrainingDataset(
        metadata: makeLegacyMetadata(records: records, done: false, truncated: true),
        records: records
    )
}

private func makeLegacyMetadata(
    records: [TrainingDatasetRecord],
    done: Bool,
    truncated: Bool
) -> TrainingDatasetMetadata {
    TrainingDatasetMetadata(
        scenarioId: "scenario-a",
        seed: 7,
        timeStep: 0.01,
        determinismTier: "strict",
        configHash: KuyuDatasetTestDigest.b,
        channelCount: 2,
        driveCount: 1,
        recordCount: records.count,
        schemaVersion: 6,
        purpose: .reinforcementRollout,
        physicsTimeStep: 0.01,
        controlPeriodSteps: 2,
        episodeId: "episode-a",
        policyId: "legacy-policy",
        rewardSum: Double(records.count),
        done: done,
        truncated: truncated,
        terminalReason: truncated ? "time-limit" : nil
    )
}

private func makeLegacyRecord(
    index: Int,
    source: [Double],
    outcome: [Double],
    done: Bool,
    truncated: Bool
) -> TrainingDatasetRecord {
    let startTime = Double(index) * 0.02
    return TrainingDatasetRecord(
        time: startTime + 0.02,
        policyDecisionID: "decision-\(index)",
        actionObservationTime: startTime,
        actionObservationState: source,
        sensors: [],
        driveIntents: [.init(driveIndex: 0, value: 0.4)],
        reflexCorrections: [],
        actualState: outcome,
        actionValues: [tanh(0.2)],
        actuatorCommandValues: [0.4],
        continueValue: done || truncated ? 0 : 1,
        reward: 1,
        cost: 0.1,
        done: done,
        truncated: truncated,
        episodeId: "episode-a",
        policyId: "legacy-policy"
    )
}

private func stagingDirectories(in root: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix(".kuyu-dataset.staging.") }
}

private func makeLegacySource(
    _ dataset: TrainingDataset,
    root: URL,
    name: String
) throws -> KuyuLegacyDatasetSource {
    let directory = root.appendingPathComponent(name, isDirectory: true)
    try TrainingDatasetWriter().write(dataset: dataset, to: directory)
    return try KuyuLegacyDatasetSource.load(from: directory)
}

private func withKuyuDatasetTemporaryDirectory<T>(
    _ operation: (URL) throws -> T
) throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-dataset-v7-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    do {
        let result = try operation(directory)
        try FileManager.default.removeItem(at: directory)
        return result
    } catch {
        let operationError = error
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw KuyuDatasetTestCleanupError(
                operation: String(describing: operationError),
                cleanup: String(describing: error)
            )
        }
        throw operationError
    }
}

private struct KuyuDatasetTestCleanupError: Error {
    let operation: String
    let cleanup: String
}
