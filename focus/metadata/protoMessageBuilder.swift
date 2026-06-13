//
//  protoMessageBuilder.swift
//  focus
//
//  Created by 이동언 on 3/8/26.
//

import Foundation
import CoreGraphics

struct FaceMetadataPushRequest: Sendable {
    let sessionID: String
    let ptsUs: Int64
    let faces: [FaceMetadataFaceEntry]
}

struct FaceMetadataFaceEntry: Sendable {
    let trackingID: Int32
    let bbox: FaceMetadataBoundingBox
    let tdmmRaw: FaceMetadataTdmmRaw
}

struct FaceMetadataBoundingBox: Sendable {
    let x: Int32
    let y: Int32
    let width: Int32
    let height: Int32
}

struct FaceMetadataTdmmRaw: Sendable {
    let coeffs: [Float]
}

struct FaceMetadataPushResponse: Sendable {
    let success: Bool
    let receivedFrames: Int64
    let acceptedFrames: Int64
    let droppedFrames: Int64
    let lastPtsUs: Int64
}

final class ProtoMessageBuilder {
    struct BuildResult {
        let message: FaceMetadataPushRequest
        let includedTrackIDs: [Int]
        let dropped: [(trackID: Int, reason: MetadataDropReason)]
    }

    func buildFrameMetadata(
        sessionID: String,
        ptsUs: Int64,
        tracks: [TrackedFace]
    ) -> BuildResult {
        var faces: [FaceMetadataFaceEntry] = []
        var includedTrackIDs: [Int] = []
        var dropped: [(trackID: Int, reason: MetadataDropReason)] = []

        for track in tracks {
            let policy = MetadataPolicy.evaluate(track: track)
            guard policy.shouldInclude else {
                if let reason = policy.reason {
                    dropped.append((track.trackID, reason))
                }
                continue
            }

            guard let tdmm = track.tdmm else {
                dropped.append((track.trackID, .missingTDMM))
                continue
            }

            let face = makeFaceData(trackID: track.trackID, bbox: track.bbox, tdmm: tdmm)
            faces.append(face)
            includedTrackIDs.append(track.trackID)
        }

        return BuildResult(
            message: FaceMetadataPushRequest(
                sessionID: sessionID,
                ptsUs: ptsUs,
                faces: faces
            ),
            includedTrackIDs: includedTrackIDs,
            dropped: dropped
        )
    }

    private func makeFaceData(
        trackID: Int,
        bbox: CGRect,
        tdmm: TDMMCoefficients
    ) -> FaceMetadataFaceEntry {
        FaceMetadataFaceEntry(
            trackingID: Int32(trackID),
            bbox: makeBBox(bbox),
            tdmmRaw: makeTDMMRaw(tdmm)
        )
    }

    private func makeBBox(_ rect: CGRect) -> FaceMetadataBoundingBox {
        let values = MetadataPolicy.clampBBoxToInt(rect)
        return FaceMetadataBoundingBox(
            x: values.x,
            y: values.y,
            width: values.width,
            height: values.height
        )
    }

    private func makeTDMMRaw(_ tdmm: TDMMCoefficients) -> FaceMetadataTdmmRaw {
        FaceMetadataTdmmRaw(coeffs: tdmm.merged)
    }
}
