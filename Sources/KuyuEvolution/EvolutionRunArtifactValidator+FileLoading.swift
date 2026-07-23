import Foundation

extension EvolutionRunArtifactValidator {
    func decode<T: Decodable>(
        _ type: T.Type,
        fileName: String,
        directory: URL,
        decoder: JSONDecoder
    ) throws -> T {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError.missingFile(fileName)
        }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    func loadJSONLines<T: Decodable>(
        _ type: T.Type,
        fileName: String,
        directory: URL,
        decoder: JSONDecoder
    ) throws -> [T] {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError.missingFile(fileName)
        }
        let raw = try String(contentsOf: url, encoding: .utf8)
        var records: [T] = []
        for (index, line) in raw.split(separator: "\n").enumerated() {
            guard let data = String(line).data(using: .utf8) else {
                throw ValidationError.invalidLine(file: fileName, line: index + 1)
            }
            do {
                records.append(try decoder.decode(type, from: data))
            } catch {
                throw ValidationError.invalidLine(file: fileName, line: index + 1)
            }
        }
        return records
    }
}
