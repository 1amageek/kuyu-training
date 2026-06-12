/// Result of reading `iterations.jsonl`.
///
/// A torn final line (bytes after the last newline, typically left by an
/// interrupted writer) is reported explicitly as `truncatedTailBytes` — never
/// silently dropped. Corruption in any non-final line throws instead.
public struct TrainingRunJournalReadResult: Sendable, Equatable {
    public let records: [TrainingRunIterationRecord]
    /// Number of bytes after the last record-terminating newline.
    /// Zero for a cleanly terminated journal.
    public let truncatedTailBytes: Int

    public init(records: [TrainingRunIterationRecord], truncatedTailBytes: Int) {
        self.records = records
        self.truncatedTailBytes = truncatedTailBytes
    }
}
