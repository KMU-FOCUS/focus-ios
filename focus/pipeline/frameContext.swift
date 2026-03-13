//
//  frameContext.swift
//  focus
//
//  Created by 이동언 on 3/7/26.
//

import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics

struct FrameContext {
    let sampleBuffer: CMSampleBuffer
    let pixelBuffer: CVPixelBuffer
    let pts: CMTime
    let ptsUs: Int64
    let sessionID: String
    let frameIndex: Int
    let isVideo: Bool
}
