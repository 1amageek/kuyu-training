/// How the dedicated acceptance stage judges a search winner.
///
/// `incumbentRelative` is the standard capability-claim criterion: the
/// candidate must pass the absolute gate and strictly improve on the
/// incumbent without regressing any acceptance metric.
///
/// `absoluteThreshold` is the curriculum-rung criterion (ADR-style): the
/// candidate must pass the absolute gate (full task pass rate, zero safety
/// violations, and any configured metric floors) on the acceptance
/// scenarios; the incumbent is evaluated and recorded for transparency but
/// not compared. Intermediate severity rungs promote on this criterion so a
/// robustness stepping stone is not rejected for trailing the incumbent's
/// clean-scenario reward; the final full-severity rung must keep
/// `incumbentRelative`.
public enum TrainingPromotionCriterion: String, Sendable, Codable, Equatable, CaseIterable {
    case incumbentRelative
    case absoluteThreshold
}
