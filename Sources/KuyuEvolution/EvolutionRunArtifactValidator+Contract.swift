import Foundation
import KuyuTrainingContracts

extension EvolutionRunArtifactValidator {
    func validate(contract: EvolutionRunArtifactContract, directory: URL) throws {
        guard contract.schemaVersion == EvolutionRunArtifactContract.currentSchemaVersion else {
            throw ValidationError.unsupportedSchemaVersion(contract.schemaVersion)
        }
        guard contract.contractVersion == EvolutionRunArtifactContract.currentContractVersion else {
            throw ValidationError.unsupportedContractVersion(contract.contractVersion)
        }
        for fileName in contract.requiredFiles + [EvolutionRunArtifactContract.fileName] {
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) else {
                throw ValidationError.missingFile(fileName)
            }
        }
    }
}
