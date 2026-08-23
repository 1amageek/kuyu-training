import Foundation

extension TrainingRunDriver {
    /// Resolves the backend-neutral task-local seed base from `KUYU_RANDOM_SEED`, defaulting to 0.
    /// An unparsable value is a typed error — never silently fall back.
    public static func resolveRandomSeedBase(environment: [String: String]) throws -> UInt64 {
        guard let raw = environment["KUYU_RANDOM_SEED"] else {
            return 0
        }
        guard let seed = UInt64(raw) else {
            throw DriverError.invalidSeedOverride(variable: "KUYU_RANDOM_SEED", value: raw)
        }
        return seed
    }

    static func generateRunID(task: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())
        let alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
        let suffix = String((0..<4).map { _ in alphabet.randomElement() ?? "0" })
        return "\(task)-\(stamp)-\(suffix)"
    }

    static func resolveCodeIdentity(repositoryDirectory: URL) throws -> TrainingRunManifest.CodeIdentity {
        let head = try runGitCommand(
            arguments: ["-C", repositoryDirectory.path, "rev-parse", "HEAD"]
        )
        let status = try runGitCommand(
            arguments: ["-C", repositoryDirectory.path, "status", "--porcelain"]
        )
        #if DEBUG
        let buildConfiguration = "debug"
        #else
        let buildConfiguration = "release"
        #endif
        return TrainingRunManifest.CodeIdentity(
            gitHead: head,
            gitDirty: !status.isEmpty,
            buildConfiguration: buildConfiguration
        )
    }

    static func relevantEnvironmentOverrides() -> [String: String] {
        ProcessInfo.processInfo.environment.filter { key, _ in
            key.hasPrefix("KUYU_") || key.hasPrefix("MANAS_")
        }
    }

    private static func runGitCommand(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw DriverError.gitCommandFailed(
                command: "git " + arguments.joined(separator: " "),
                reason: String(describing: error)
            )
        }
        guard waitForProcessExit(process, timeout: 5) else {
            process.terminate()
            _ = waitForProcessExit(process, timeout: 1)
            throw DriverError.gitCommandFailed(
                command: "git " + arguments.joined(separator: " "),
                reason: "command timed out"
            )
        }
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "unknown git error"
            throw DriverError.gitCommandFailed(
                command: "git " + arguments.joined(separator: " "),
                reason: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let output = String(data: outputData, encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func waitForProcessExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return !process.isRunning
    }
}
