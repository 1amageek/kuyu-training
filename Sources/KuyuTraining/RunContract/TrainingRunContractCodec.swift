import Foundation

/// Shared JSON codec configuration for training run contract files.
///
/// Document files (`manifest.json`, `heartbeat.json`, `outcome.json`,
/// control files) are pretty-printed with sorted keys. Journal records are
/// compact single-line JSON with sorted keys. Both use ISO-8601 dates and
/// string-encoded non-finite floats, matching existing KuyuTraining artifact
/// conventions.
enum TrainingRunContractCodec {
    static func makeDocumentEncoder() -> JSONEncoder {
        let encoder = makeJournalEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeJournalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return decoder
    }
}
