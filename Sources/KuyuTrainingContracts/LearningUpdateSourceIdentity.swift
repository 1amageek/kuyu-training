public struct LearningUpdateSourceIdentity:
  Sendable, Codable, Equatable
{
  public let datasetID: String
  public let recordsDigest: String
  public let policyID: String
  public let checkpointDigest: String
  public let actorInputContractDigest: String
  public let criticInputContractDigest: String

  public init(
    datasetID: String,
    recordsDigest: String,
    policyID: String,
    checkpointDigest: String,
    actorInputContractDigest: String,
    criticInputContractDigest: String
  ) {
    self.datasetID = datasetID
    self.recordsDigest = recordsDigest
    self.policyID = policyID
    self.checkpointDigest = checkpointDigest
    self.actorInputContractDigest = actorInputContractDigest
    self.criticInputContractDigest = criticInputContractDigest
  }
}
