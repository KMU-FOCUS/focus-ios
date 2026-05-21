import Foundation
import VideoToolbox

private let hkCompressionLogLock = NSLock()
private var hkCompressionLogCount = 0

private func shouldLogCompressedOutput(_ keyframe: Bool) -> Bool {
    hkCompressionLogLock.lock()
    defer { hkCompressionLogLock.unlock() }
    if keyframe {
        return true
    }
    if hkCompressionLogCount < 10 {
        hkCompressionLogCount += 1
        return true
    }
    return false
}

extension VTCompressionSession {
    func prepareToEncodeFrames() -> OSStatus {
        VTCompressionSessionPrepareToEncodeFrames(self)
    }
}

extension VTCompressionSession: VTSessionConvertible {
    @inline(__always)
    func convert(
        _ sampleBuffer: CMSampleBuffer,
        continuation: AsyncStream<CMSampleBuffer>.Continuation?,
        forceKeyFrame: Bool
    ) throws {
        guard let imageBuffer = sampleBuffer.imageBuffer else {
            return
        }
        var flags: VTEncodeInfoFlags = []
        let frameProperties: CFDictionary? = forceKeyFrame
            ? [VTSessionOptionKey.forceKeyFrame.CFString: kCFBooleanTrue] as CFDictionary
            : nil
        if forceKeyFrame, logger.isEnabledFor(level: .info) {
            logger.info("H264 encode forcing keyframe at pts:", sampleBuffer.presentationTimeStamp.seconds)
        }
        let status = VTCompressionSessionEncodeFrame(
            self,
            imageBuffer: imageBuffer,
            presentationTimeStamp: sampleBuffer.presentationTimeStamp,
            duration: sampleBuffer.duration,
            frameProperties: frameProperties,
            infoFlagsOut: &flags,
            outputHandler: { status, infoFlags, sampleBuffer in
                guard status == noErr else {
                    logger.error("H264 compressed output failed:", status)
                    return
                }
                if let sampleBuffer {
                    let keyframe = !sampleBuffer.isNotSync
                    if shouldLogCompressedOutput(keyframe), logger.isEnabledFor(level: .info) {
                        let parameterSetSizes = sampleBuffer.formatDescription?.parameterSets.map(\.count) ?? []
                        logger.info(
                            "H264 compressed output:",
                            " keyframe=", keyframe,
                            ", sampleSize=", CMSampleBufferGetTotalSampleSize(sampleBuffer),
                            ", parameterSetCount=", parameterSetSizes.count,
                            ", parameterSetSizes=", parameterSetSizes,
                            ", pts=", sampleBuffer.presentationTimeStamp.seconds,
                            ", dts=", sampleBuffer.decodeTimeStamp.seconds,
                            ", infoFlags=", infoFlags.rawValue
                        )
                    }
                    continuation?.yield(sampleBuffer)
                }
            }
        )
        if status != noErr {
            throw VTSessionError.failedToConvert(status: status)
        }
    }

    func invalidate() {
        VTCompressionSessionInvalidate(self)
    }
}
