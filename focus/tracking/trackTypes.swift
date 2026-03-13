//
//  trackTypes.swift
//  focus
//
//  Created by 이동언 on 3/7/26.
//

import Foundation
import CoreGraphics

struct TrackMatchCandidate: Equatable {
    let trackIndex: Int
    let detectionIndex: Int
    let cost: Float
    let iouDistance: Float
    let cosineDistance: Float
}

struct TrackAssignmentResult {
    let matches: [(trackIndex: Int, detectionIndex: Int)]
    let unmatchedTrackIndices: [Int]
    let unmatchedDetectionIndices: [Int]
}

enum TrackCost {
    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> Float {
        let inter = a.intersection(b)
        if inter.isNull || inter.isEmpty { return 0 }

        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        guard unionArea > 0 else { return 0 }
        return Float(interArea / unionArea)
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    static func combinedCost(
        track: TrackedFace,
        detection: DetectedFace,
        detectionTDMM: TDMMCoefficients?
    ) -> TrackMatchCandidate? {
        let iou = intersectionOverUnion(track.bbox, detection.bbox)
        let iouDistance = 1 - iou

        guard iouDistance <= FocusConstants.maxIouDistance else {
            return nil
        }

        var cosineDistance: Float = 1.0

        if let trackTDMM = track.tdmm, let detectionTDMM {
            let similarity = cosineSimilarity(trackTDMM.idVector, detectionTDMM.idVector)
            cosineDistance = 1 - similarity
        }

        let cosineThreshold: Float
        if iou > 0.5 {
            cosineThreshold = FocusConstants.maxCosineDistance * FocusConstants.maxCosineRelaxedMultiplier
        } else {
            cosineThreshold = FocusConstants.maxCosineDistance
        }

        guard cosineDistance <= cosineThreshold else {
            return nil
        }

        let cost =
            FocusConstants.trackIouWeight * iouDistance +
            FocusConstants.trackCosineWeight * cosineDistance

        return TrackMatchCandidate(
            trackIndex: -1,
            detectionIndex: -1,
            cost: cost,
            iouDistance: iouDistance,
            cosineDistance: cosineDistance
        )
    }
}
