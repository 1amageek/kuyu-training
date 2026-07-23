import Foundation

public extension TrainingRunDriver {
    /// Polls `control/command.json` and applies the pending command, if any.
    /// `pause` blocks here (heartbeating) until a `resume` or `stop` arrives.
    ///
    /// Runs on the caller's actor (`nonisolated(nonsending)`) so the
    /// non-`Sendable` driver never crosses an isolation boundary.
    nonisolated(nonsending) func applyPendingControl(iteration: Int) async throws -> ControlDirective {
        while true {
            guard let command = try writer.pendingControlCommand() else {
                return .continueRun
            }
            switch command.action {
            case .stop:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration
                    )
                )
                return .stopRun
            case .pause:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration
                    )
                )
                try writer.writeOutcome(
                    TrainingRunOutcome(status: .paused, updatedAt: Date())
                )
                print("TRAINING-RUN paused at iteration \(iteration) (awaiting resume)")
                try await waitWhilePaused(iteration: iteration)
                try writer.writeOutcome(
                    TrainingRunOutcome(status: .running, updatedAt: Date())
                )
                print("TRAINING-RUN resumed at iteration \(iteration)")
                continue
            case .resume:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration,
                        rejected: true,
                        reason: "run is not paused"
                    )
                )
                continue
            case .checkpoint:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration,
                        rejected: true,
                        reason: "checkpoint-on-demand is not supported by this harness"
                    )
                )
                continue
            case nil:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration,
                        rejected: true,
                        reason: "unknown command: \(command.command)"
                    )
                )
                continue
            }
        }
    }

    nonisolated(nonsending) private func waitWhilePaused(iteration: Int) async throws {
        while true {
            try await Task.sleep(for: .seconds(2))
            try writeHeartbeat(iteration: iteration, phase: "paused")
            guard let command = try writer.pendingControlCommand() else {
                continue
            }
            switch command.action {
            case .resume:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration
                    )
                )
                return
            case .stop:
                // Leave the stop pending; the outer loop consumes it and
                // returns .stopRun so the harness exits cleanly.
                return
            default:
                try writer.acknowledgeControlCommand(
                    TrainingRunControlAcknowledgment(
                        sequence: command.sequence,
                        command: command.command,
                        appliedAt: Date(),
                        iteration: iteration,
                        rejected: true,
                        reason: "command not applicable while paused: \(command.command)"
                    )
                )
                continue
            }
        }
    }
}
