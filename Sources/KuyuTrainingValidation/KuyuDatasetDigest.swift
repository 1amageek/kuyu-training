import CryptoKit
import Foundation

enum KuyuDatasetDigest {
    static let zero = String(repeating: "0", count: 64)

    static func hex(_ digest: SHA256.Digest) -> String {
        let alphabet = Array("0123456789abcdef".utf8)
        var output: [UInt8] = []
        output.reserveCapacity(SHA256.Digest.byteCount * 2)
        for byte in digest {
            output.append(alphabet[Int(byte >> 4)])
            output.append(alphabet[Int(byte & 0x0F)])
        }
        return String(decoding: output, as: UTF8.self)
    }
}
