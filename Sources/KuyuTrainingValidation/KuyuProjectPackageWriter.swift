import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public struct KuyuProjectPackageWriter: Sendable {
    private let encoder: JSONEncoder

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func write(_ package: KuyuProjectPackage, allowOverwrite: Bool = false) throws {
        try Self.validatePackageExtension(package.rootURL)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: package.rootURL.path) {
            guard allowOverwrite else {
                throw KuyuProjectPackageError.packageAlreadyExists(path: package.rootURL.path)
            }
        }

        try fileManager.createDirectory(at: package.rootURL, withIntermediateDirectories: true)
        try createDirectories(at: package.rootURL)
        try writeJSON(package.manifest, to: package.rootURL.appendingPathComponent("project.json"))
        try writeJSON(
            package.selectedTemplate,
            to: package.rootURL
                .appendingPathComponent("templates", isDirectory: true)
                .appendingPathComponent("selected-template.json")
        )
        try writeJSON(
            package.defaultExperiment,
            to: package.rootURL
                .appendingPathComponent("experiments", isDirectory: true)
                .appendingPathComponent("default", isDirectory: true)
                .appendingPathComponent("experiment.json")
        )
        try writeJSON(
            package.robotManifestReference,
            to: package.rootURL
                .appendingPathComponent("robot-manifests", isDirectory: true)
                .appendingPathComponent("default", isDirectory: true)
                .appendingPathComponent("robot-manifest-ref.json")
        )
        try writeJSON(
            package.environmentReference,
            to: package.rootURL
                .appendingPathComponent("environments", isDirectory: true)
                .appendingPathComponent("default", isDirectory: true)
                .appendingPathComponent("environment.json")
        )
        try writeJSON(
            package.sourceBundleReference,
            to: package.rootURL
                .appendingPathComponent("model-bundles", isDirectory: true)
                .appendingPathComponent("source.bundle-ref.json")
        )
    }

    public static func validatePackageExtension(_ url: URL) throws {
        guard url.pathExtension == "kuyu" else {
            throw KuyuProjectPackageError.invalidPackageExtension(path: url.path)
        }
    }

    private func createDirectories(at rootURL: URL) throws {
        let directories = [
            "templates",
            "experiments/default",
            "robot-manifests/default",
            "environments/default",
            "model-bundles",
            "runs",
            "artifacts",
            "logs"
        ]
        for directory in directories {
            try FileManager.default.createDirectory(
                at: rootURL.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}
