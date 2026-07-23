import Foundation
import KuyuTrainingRuntime
import Testing

@Suite(.serialized)
struct TrainingCheckpointReferenceResolverTests {
    @Test func resolverIsIndependentOfSymlinkedRootPath() throws {
        let root = try temporaryDirectory()
        defer { remove(root) }
        let checkpoint = root.appendingPathComponent("checkpoint", isDirectory: true)
        try FileManager.default.createDirectory(
            at: checkpoint,
            withIntermediateDirectories: true
        )
        try Data("weights".utf8).write(
            to: checkpoint.appendingPathComponent("core.safetensors"),
            options: .atomic
        )
        try Data("{}".utf8).write(
            to: checkpoint.appendingPathComponent("model.json"),
            options: .atomic
        )
        let linkedCheckpoint = root.appendingPathComponent(
            "checkpoint-link",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedCheckpoint,
            withDestinationURL: checkpoint
        )

        let resolved = try TrainingCheckpointReferenceResolver().reference(for: checkpoint)
        let linked = try TrainingCheckpointReferenceResolver().reference(for: linkedCheckpoint)

        #expect(resolved.sha256Digest == linked.sha256Digest)
        #expect(resolved.digestAlgorithm == .relativePathV2)
    }

    @Test func resolverDetectsCheckpointContentChanges() throws {
        let root = try temporaryDirectory()
        defer { remove(root) }
        let checkpoint = root.appendingPathComponent("checkpoint", isDirectory: true)
        try FileManager.default.createDirectory(
            at: checkpoint,
            withIntermediateDirectories: true
        )
        let weights = checkpoint.appendingPathComponent("core.safetensors")
        try Data("first".utf8).write(to: weights, options: .atomic)
        let resolver = TrainingCheckpointReferenceResolver()
        let first = try resolver.reference(for: checkpoint)

        try Data("second".utf8).write(to: weights, options: .atomic)
        let second = try resolver.reference(for: checkpoint)

        #expect(first.sha256Digest != second.sha256Digest)
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "training-checkpoint-reference-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func remove(_ root: URL) {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove checkpoint reference fixture: \(error)")
        }
    }
}
