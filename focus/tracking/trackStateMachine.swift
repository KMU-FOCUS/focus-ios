//
//  trackStateMachine.swift
//  focus
//
//  Created by 이동언 on 3/7/26.
//

import Foundation

final class TrackStateMachine {
    private let ownerStore: OwnerEmbeddingStore
    private let classifier: OwnerOtherClassifier

    init(
        ownerStore: OwnerEmbeddingStore,
        classifier: OwnerOtherClassifier = OwnerOtherClassifier()
    ) {
        self.ownerStore = ownerStore
        self.classifier = classifier
    }

    func shouldCollectEmbedding(for track: TrackedFace) -> Bool {
        guard track.label == .pending else { return false }
        guard track.framesSeen > FocusConstants.skipFrames else { return false }
        guard track.frontalEmbeddingSamples.count < FocusConstants.collectFrames else { return false }
        return true
    }

    func shouldRetryOther(for track: TrackedFace, isFrontal: Bool) -> Bool {
        guard track.label == .other else { return false }
        guard isFrontal else { return false }
        return !track.hasRetriedOther
    }

    func updateLabel(
        track: inout TrackedFace,
        newEmbedding: [Float],
        isFrontal: Bool
    ) {
        guard isFrontal else { return }

        switch track.label {
        case .owner:
            return

        case .pending:
            handlePendingTrack(track: &track, newEmbedding: newEmbedding)

        case .other:
            handleOtherTrackRetry(track: &track, newEmbedding: newEmbedding)
        }
    }

    func resetOnReappearance(track: inout TrackedFace) {
        track.label = .pending
        track.ownerID = nil
        track.frontalEmbeddingSamples.removeAll()
        track.hasRetriedOther = false
        track.framesSeen = 0
    }

    // MARK: - Private

    private func handlePendingTrack(track: inout TrackedFace, newEmbedding: [Float]) {
        guard track.framesSeen > FocusConstants.skipFrames else {
            return
        }

        track.frontalEmbeddingSamples.append(newEmbedding)

        guard track.frontalEmbeddingSamples.count >= FocusConstants.collectFrames else {
            return
        }

        let result = classifier.classify(
            embeddings: track.frontalEmbeddingSamples,
            using: ownerStore
        )
        track.label = result.label
        track.ownerID = result.ownerID
    }

    private func handleOtherTrackRetry(track: inout TrackedFace, newEmbedding: [Float]) {
        guard !track.hasRetriedOther else { return }

        let result = classifier.classify(embedding: newEmbedding, using: ownerStore)
        track.label = result.label
        track.ownerID = result.ownerID

        track.hasRetriedOther = true
    }
}
