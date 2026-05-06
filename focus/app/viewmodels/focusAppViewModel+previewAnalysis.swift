//
//  focusAppViewModel+previewAnalysis.swift
//  focus
//
//  Created by Codex on 4/11/26.
//

import Foundation

extension FocusAppViewModel {
    func activePreviewTracks() -> [TrackedFace] {
        previewTrackedFaces.filter { $0.missedFrames == 0 }
    }

    func overlayPreviewTracks() -> [TrackedFace] {
        activePreviewTracks()
    }
}
