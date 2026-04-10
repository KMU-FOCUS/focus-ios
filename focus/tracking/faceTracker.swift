//
//  faceTracker.swift
//  focus
//
//  Created by 이동언 on 3/7/26.
//

import Foundation
import CoreGraphics

final class FaceTracker {
    private(set) var tracks: [TrackedFace] = []
    private var nextTrackID: Int = 1

    func update(
        detections: [DetectedFace],
        tdmmList: [TDMMCoefficients?],
        frameIndex: Int
    ) -> [TrackedFace] {
        let assignment = assignDetections(
            to: tracks,
            detections: detections,
            tdmmList: tdmmList
        )

        var updatedTracks: [TrackedFace] = []

        // matched tracks
        for (trackIndex, detectionIndex) in assignment.matches {
            guard trackIndex < tracks.count, detectionIndex < detections.count else { continue }

            let detection = detections[detectionIndex]
            let detectionTDMM = tdmmList[detectionIndex]

            var track = tracks[trackIndex]

            let wasMissingLastFrame = track.lastSeenFrameIndex == frameIndex - 2

            track.bbox = detection.bbox
            track.landmarks = detection.landmarks
            track.tdmm = detectionTDMM
            track.age += 1
            track.missedFrames = 0
            track.framesSeen += 1
            track.lastSeenFrameIndex = frameIndex

            if wasMissingLastFrame {
                resetTrackStateForReappearance(&track)
            }

            updatedTracks.append(track)
        }

        // unmatched old tracks
        for trackIndex in assignment.unmatchedTrackIndices {
            guard trackIndex < tracks.count else { continue }
            var track = tracks[trackIndex]
            track.age += 1
            track.missedFrames += 1

            if track.missedFrames <= FocusConstants.maxAge {
                updatedTracks.append(track)
            }
        }

        // unmatched new detections -> new tracks
        for detectionIndex in assignment.unmatchedDetectionIndices {
            guard detectionIndex < detections.count else { continue }

            let detection = detections[detectionIndex]
            let track = TrackedFace(
                trackID: nextTrackID,
                bbox: detection.bbox,
                landmarks: detection.landmarks,
                tdmm: tdmmList[detectionIndex],
                label: .pending,
                ownerID: nil,
                age: 1,
                missedFrames: 0,
                frontalEmbeddingSamples: [],
                hasRetriedOther: false,
                framesSeen: 1,
                lastSeenFrameIndex: frameIndex
            )

            nextTrackID += 1
            updatedTracks.append(track)
        }

        tracks = updatedTracks
        return updatedTracks
    }

    func replaceTracks(with newTracks: [TrackedFace]) {
        self.tracks = newTracks
    }

    func reset() {
        tracks.removeAll()
        nextTrackID = 1
    }

    // MARK: - Assignment

    private func assignDetections(
        to tracks: [TrackedFace],
        detections: [DetectedFace],
        tdmmList: [TDMMCoefficients?]
    ) -> TrackAssignmentResult {
        guard !tracks.isEmpty, !detections.isEmpty else {
            return TrackAssignmentResult(
                matches: [],
                unmatchedTrackIndices: Array(tracks.indices),
                unmatchedDetectionIndices: Array(detections.indices)
            )
        }

        var candidates: [TrackMatchCandidate] = []

        for (trackIndex, track) in tracks.enumerated() {
            for (detectionIndex, detection) in detections.enumerated() {
                guard let baseCandidate = TrackCost.combinedCost(
                    track: track,
                    detection: detection,
                    detectionTDMM: tdmmList[detectionIndex]
                ) else {
                    continue
                }

                let candidate = TrackMatchCandidate(
                    trackIndex: trackIndex,
                    detectionIndex: detectionIndex,
                    cost: baseCandidate.cost,
                    iouDistance: baseCandidate.iouDistance,
                    cosineDistance: baseCandidate.cosineDistance
                )
                candidates.append(candidate)
            }
        }

        candidates.sort { $0.cost < $1.cost }

        var usedTrackIndices = Set<Int>()
        var usedDetectionIndices = Set<Int>()
        var matches: [(trackIndex: Int, detectionIndex: Int)] = []

        for candidate in candidates {
            if usedTrackIndices.contains(candidate.trackIndex) { continue }
            if usedDetectionIndices.contains(candidate.detectionIndex) { continue }

            usedTrackIndices.insert(candidate.trackIndex)
            usedDetectionIndices.insert(candidate.detectionIndex)
            matches.append((candidate.trackIndex, candidate.detectionIndex))
        }

        let unmatchedTracks = tracks.indices.filter { !usedTrackIndices.contains($0) }
        let unmatchedDetections = detections.indices.filter { !usedDetectionIndices.contains($0) }

        return TrackAssignmentResult(
            matches: matches,
            unmatchedTrackIndices: unmatchedTracks,
            unmatchedDetectionIndices: unmatchedDetections
        )
    }

    private func resetTrackStateForReappearance(_ track: inout TrackedFace) {
        track.label = .pending
        track.ownerID = nil
        track.frontalEmbeddingSamples.removeAll()
        track.hasRetriedOther = false
        track.framesSeen = 1
    }
}
