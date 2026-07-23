import Foundation

public protocol ModelBundlePublicationValidating: Sendable {
    func validatePublicationBundle(at bundleURL: URL) throws
}
