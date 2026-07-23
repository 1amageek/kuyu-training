public struct LearningProjectTemporalExecutionContract: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable, Equatable, CaseIterable {
        /// Every decision evaluates one complete history window from a zero recurrent state.
        case fixedWindowZeroRecurrentState = "fixed-window-zero-recurrent-state"
    }

    public enum PaddingRule: String, Codable, Sendable, Equatable, CaseIterable {
        case zero
    }

    public enum PreviousActionRule: String, Codable, Sendable, Equatable, CaseIterable {
        /// The first observation uses zero; later observations use the prior policy action.
        case zeroBeforeFirstDecision = "zero-before-first-decision"
    }

    public let mode: Mode
    public let paddingRule: PaddingRule
    public let previousActionRule: PreviousActionRule

    public init(
        mode: Mode,
        paddingRule: PaddingRule,
        previousActionRule: PreviousActionRule
    ) {
        self.mode = mode
        self.paddingRule = paddingRule
        self.previousActionRule = previousActionRule
    }

    public static let fixedWindowZeroState = Self(
        mode: .fixedWindowZeroRecurrentState,
        paddingRule: .zero,
        previousActionRule: .zeroBeforeFirstDecision
    )
}
