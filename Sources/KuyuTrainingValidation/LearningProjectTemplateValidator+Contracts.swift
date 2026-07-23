import KuyuTrainingContracts

extension LearningProjectTemplateValidator {
    func validateObservation(_ observation: LearningProjectObservationContract) throws {
        do {
            try LearningProjectContractValidator().validateObservation(observation)
        } catch LearningProjectContractValidationError.invalidObservation(let reason) {
            switch reason {
            case "empty-schema-id":
                throw LearningProjectTemplateValidationError.emptyObservationSchemaID
            case "non-positive-channel-count":
                throw LearningProjectTemplateValidationError.invalidObservationChannelCount(
                    expected: 1,
                    actual: observation.channelCount
                )
            case "channel-count-mismatch":
                throw LearningProjectTemplateValidationError.observationChannelCountMismatch(
                    expected: observation.channelCount,
                    actual: observation.channels.count
                )
            case "channel-index-out-of-range":
                let invalidIndex = observation.channels.first { channel in
                    channel.index < 0 || channel.index >= observation.channelCount
                }?.index ?? -1
                throw LearningProjectTemplateValidationError.invalidObservationChannelCount(
                    expected: observation.channelCount,
                    actual: invalidIndex
                )
            case "duplicate-channel-index":
                var seen: Set<Int> = []
                let duplicate = observation.channels.first { channel in
                    if seen.contains(channel.index) {
                        return true
                    }
                    seen.insert(channel.index)
                    return false
                }?.index ?? -1
                throw LearningProjectTemplateValidationError.duplicateObservationChannel(index: duplicate)
            default:
                throw LearningProjectTemplateValidationError.invalidObservationContract(reason: reason)
            }
        } catch {
            throw error
        }
    }

    func validateAction(_ action: LearningProjectActionContract) throws {
        do {
            try LearningProjectContractValidator().validateAction(action)
        } catch LearningProjectContractValidationError.invalidAction(let reason) {
            throw LearningProjectTemplateValidationError.invalidActionContract(reason: reason)
        } catch {
            throw error
        }
    }

    func validatePolicy(
        _ policy: LearningProjectPolicyContract,
        observation: LearningProjectObservationContract,
        action: LearningProjectActionContract
    ) throws {
        do {
            try LearningProjectContractValidator().validatePolicy(
                policy,
                observation: observation,
                action: action
            )
        } catch LearningProjectContractValidationError.invalidPolicy(let reason) {
            throw LearningProjectTemplateValidationError.invalidPolicyContract(reason: reason)
        } catch {
            throw error
        }
    }
}
