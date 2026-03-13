//
//  trackStateMachine.swift
//  focus
//
//  Created by 이동언 on 3/7/26.
//

import Foundation

final class TrackStateMachine {
    private let ownerReferenceEmbedding: [Float]

    init(ownerReferenceEmbedding: [Float]) {
        self.ownerReferenceEmbedding = ownerReferenceEmbedding
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

        let averagedEmbedding = average(track.frontalEmbeddingSamples)
        let similarity = cosineSimilarity(averagedEmbedding, ownerReferenceEmbedding)

        if similarity >= FocusConstants.ownerSimilarityThreshold {
            track.label = .owner
        } else {
            track.label = .other
        }
    }

    private func handleOtherTrackRetry(track: inout TrackedFace, newEmbedding: [Float]) {
        guard !track.hasRetriedOther else { return }

        let similarity = cosineSimilarity(newEmbedding, ownerReferenceEmbedding)
        if similarity >= FocusConstants.ownerSimilarityThreshold {
            track.label = .owner
        } else {
            track.label = .other
        }

        track.hasRetriedOther = true
    }

    private func average(_ samples: [[Float]]) -> [Float] {
        guard let first = samples.first else { return [] }

        var result = Array(repeating: Float(0), count: first.count)
        for sample in samples {
            guard sample.count == result.count else { continue }
            for i in 0..<sample.count {
                result[i] += sample[i]
            }
        }

        let count = Float(samples.count)
        guard count > 0 else { return result }

        return result.map { $0 / count }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return -1 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return -1 }

        return dot / denom
    }
}
