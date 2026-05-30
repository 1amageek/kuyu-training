import Foundation
import KuyuPhysics

public extension TrainingObservationMetadata {
    init(observation: ObservationContract) {
        let mappedClock: TrainingObservationClockMetadata?
        if let clock = observation.clock {
            mappedClock = TrainingObservationClockMetadata(
                timebase: clock.timebase,
                epoch: clock.epoch,
                maxSkewMs: clock.maxSkewSeconds * 1000.0,
                syncPolicy: clock.syncPolicy.rawValue
            )
        } else {
            mappedClock = nil
        }

        let mappedModalities: [TrainingObservationModalityMetadata]?
        if let modalities = observation.modalities {
            mappedModalities = modalities.map { modality in
                let mappedProvenance: TrainingObservationProvenanceMetadata?
                if let provenance = modality.provenance {
                    mappedProvenance = TrainingObservationProvenanceMetadata(
                        producer: provenance.producer,
                        transport: provenance.transport,
                        notes: provenance.notes
                    )
                } else {
                    mappedProvenance = nil
                }
                return TrainingObservationModalityMetadata(
                    id: modality.id,
                    type: modality.type.rawValue,
                    channels: modality.channels,
                    timestampSource: modality.timestampSource,
                    provenance: mappedProvenance
                )
            }
        } else {
            mappedModalities = nil
        }

        self.init(clock: mappedClock, modalities: mappedModalities)
    }
}
