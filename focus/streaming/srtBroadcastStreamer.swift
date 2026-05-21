//
//  srtBroadcastStreamer.swift
//  focus
//
//  Created by Codex on 5/16/26.
//

import AVFoundation
import Foundation
import CoreGraphics
import VideoToolbox

#if canImport(SRTHaishinKit)
import SRTHaishinKit
#endif

#if canImport(HaishinKit)
import HaishinKit
#endif

final class SRTBroadcastStreamer {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
        case closed
    }

    private let backend: any SRTBroadcastBackend
    private let videoFrameRelay = VideoFrameAppendRelay()
    private(set) var state: State = .idle
    var onStateChanged: ((State) -> Void)?
    var onVideoFrameAppended: ((Int, Int64?) -> Void)? {
        get { videoFrameRelay.handler }
        set { videoFrameRelay.handler = newValue }
    }

    init() {
        backend = DefaultSRTBroadcastBackend(
            onVideoFrameAppended: { [videoFrameRelay] count, ptsUs in
                videoFrameRelay.handler?(count, ptsUs)
            }
        )
    }

    func start(host: String, port: Int, streamKey: String) async throws {
        updateState(.connecting)
        do {
            try await backend.start(host: host, port: port, streamKey: streamKey)
            updateState(.connected)
        } catch {
            updateState(.failed(error.localizedDescription))
            throw error
        }
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        Task {
            await backend.appendVideo(sampleBuffer)
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        Task {
            await backend.appendAudio(sampleBuffer)
        }
    }

    func stop() async {
        await backend.stop()
        updateState(.closed)
    }

    private func updateState(_ newState: State) {
        state = newState
        onStateChanged?(newState)
    }
}

private final class VideoFrameAppendRelay: @unchecked Sendable {
    var handler: ((Int, Int64?) -> Void)?
}

#if canImport(HaishinKit)
private final class AudioMixerLogOutput: @unchecked Sendable, MediaMixerOutput {
    private let lock = NSLock()
    private var hasLoggedAudioOutputFormat = false

    var videoTrackId: UInt8? {
        get async { nil }
    }

    var audioTrackId: UInt8? {
        get async { UInt8.max }
    }

    func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {}

    func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        lock.lock()
        defer { lock.unlock() }

        guard !hasLoggedAudioOutputFormat else { return }
        hasLoggedAudioOutputFormat = true

        let format = buffer.format
        FocusLogger.info(
            "SRT audio mixer 출력: sampleRate=\(Int(format.sampleRate.rounded())), channels=\(format.channelCount), commonFormat=\(format.commonFormat.rawValue), interleaved=\(format.isInterleaved)",
            category: .streaming
        )
    }

    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}
}
#endif

private protocol SRTBroadcastBackend: Sendable {
    func start(host: String, port: Int, streamKey: String) async throws
    func appendVideo(_ sampleBuffer: CMSampleBuffer) async
    func appendAudio(_ sampleBuffer: CMSampleBuffer) async
    func stop() async
}

#if canImport(SRTHaishinKit)
private actor DefaultSRTBroadcastBackend: SRTBroadcastBackend {
    private static let videoLogInterval = 30
    private static let audioLogInterval = 60

    private let connection = SRTConnection()
    private let stream: SRTStream
    private let onVideoFrameAppended: @Sendable (Int, Int64?) -> Void
#if canImport(HaishinKit)
    private let audioMixer = MediaMixer(multiCamSessionEnabled: false, multiTrackAudioMixingEnabled: false)
    private let audioMixerLogOutput = AudioMixerLogOutput()
#endif
    private var isPublishing = false
    private var isAudioMixerConfigured = false
    private var videoFrameCount = 0
    private var audioSampleCount = 0
    private var firstVideoPTSUs: Int64?
    private var lastVideoPTSUs: Int64?
    private var firstAudioPTSUs: Int64?
    private var lastAudioPTSUs: Int64?

    init(onVideoFrameAppended: @escaping @Sendable (Int, Int64?) -> Void) {
        self.stream = SRTStream(connection: connection)
        self.onVideoFrameAppended = onVideoFrameAppended
    }

    func start(host: String, port: Int, streamKey: String) async throws {
        guard !isPublishing else { return }
        resetMetrics()

        let urlString = "srt://\(host):\(port)?streamid=publish:live/\(streamKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(
                domain: "SRTBroadcastStreamer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "유효하지 않은 SRT URL입니다."]
            )
        }

        await configureCodecSettings()
        await configureAudioMixerIfNeeded()
        try await connection.open(url, mode: .caller)
        await stream.publish()
        isPublishing = true
        FocusLogger.info(
            "SRT publish 시작: host=\(host), port=\(port), streamKeyLength=\(streamKey.count), video=\(FocusConstants.srtVideoWidth)x\(FocusConstants.srtVideoHeight), videoBitrate=\(FocusConstants.srtVideoBitRate), audioBitrate=\(FocusConstants.srtAudioBitRate), audioSampleRate=\(Int(FocusConstants.srtAudioSampleRate)), audioChannels=\(FocusConstants.srtAudioChannelCount)",
            category: .streaming
        )
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) async {
        guard isPublishing else { return }
        let ptsUs = presentationTimestampMicroseconds(for: sampleBuffer)
        videoFrameCount += 1
        if firstVideoPTSUs == nil {
            firstVideoPTSUs = ptsUs
            FocusLogger.info(
                "SRT video 첫 프레임 append: ptsUs=\(ptsUs.map(String.init) ?? "nil")",
                category: .streaming
            )
        }
        lastVideoPTSUs = ptsUs
        await stream.append(sampleBuffer)
        onVideoFrameAppended(videoFrameCount, ptsUs)
        if videoFrameCount % Self.videoLogInterval == 0 {
            FocusLogger.info(
                """
                SRT video append 진행: count=\(videoFrameCount), firstPtsUs=\(firstVideoPTSUs.map(String.init) ?? "nil"), lastPtsUs=\(lastVideoPTSUs.map(String.init) ?? "nil")
                """,
                category: .streaming
            )
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) async {
        guard isPublishing else { return }
        let ptsUs = presentationTimestampMicroseconds(for: sampleBuffer)
        audioSampleCount += 1
        if firstAudioPTSUs == nil {
            firstAudioPTSUs = ptsUs
            FocusLogger.info(
                "SRT audio 첫 샘플 append: ptsUs=\(ptsUs.map(String.init) ?? "nil"), \(audioFormatSummary(for: sampleBuffer))",
                category: .streaming
            )
        }
        lastAudioPTSUs = ptsUs
        #if canImport(HaishinKit)
        await audioMixer.append(sampleBuffer)
        #else
        await stream.append(sampleBuffer)
        #endif
        if audioSampleCount % Self.audioLogInterval == 0 {
            FocusLogger.info(
                """
                SRT audio append 진행: count=\(audioSampleCount), firstPtsUs=\(firstAudioPTSUs.map(String.init) ?? "nil"), lastPtsUs=\(lastAudioPTSUs.map(String.init) ?? "nil")
                """,
                category: .streaming
            )
        }
    }

    func stop() async {
        guard isPublishing else { return }
        isPublishing = false
        FocusLogger.info(
            """
            SRT publish 종료: videoCount=\(videoFrameCount), audioCount=\(audioSampleCount), firstVideoPtsUs=\(firstVideoPTSUs.map(String.init) ?? "nil"), lastVideoPtsUs=\(lastVideoPTSUs.map(String.init) ?? "nil"), firstAudioPtsUs=\(firstAudioPTSUs.map(String.init) ?? "nil"), lastAudioPtsUs=\(lastAudioPTSUs.map(String.init) ?? "nil")
            """,
            category: .streaming
        )
        #if canImport(HaishinKit)
        if isAudioMixerConfigured {
            await audioMixer.removeOutput(stream)
            await audioMixer.removeOutput(audioMixerLogOutput)
            await audioMixer.stopRunning()
            isAudioMixerConfigured = false
        }
        #endif
        try? await connection.close()
    }

    private func resetMetrics() {
        videoFrameCount = 0
        audioSampleCount = 0
        firstVideoPTSUs = nil
        lastVideoPTSUs = nil
        firstAudioPTSUs = nil
        lastAudioPTSUs = nil
    }

    private func configureCodecSettings() async {
        var videoSettings = await stream.videoSettings
        videoSettings.videoSize = CGSize(
            width: FocusConstants.srtVideoWidth,
            height: FocusConstants.srtVideoHeight
        )
        videoSettings.bitRate = FocusConstants.srtVideoBitRate
        videoSettings.profileLevel = kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel as String
        videoSettings.bitRateMode = .average
        videoSettings.maxKeyFrameIntervalDuration = FocusConstants.srtVideoKeyFrameIntervalSeconds
        videoSettings.scalingMode = .normal
        videoSettings.frameInterval = VideoCodecSettings.frameInterval30
        videoSettings.allowFrameReordering = false
        videoSettings.dataRateLimits = nil
        await stream.setVideoSettings(videoSettings)

        FocusLogger.info(
            """
            SRT video codec 설정: profileLevel=\(videoSettings.profileLevel), bitRateMode=\(videoSettings.bitRateMode.rawValue), dataRateLimits=nil, frameInterval=\(videoSettings.frameInterval), keyFrameIntervalSec=\(videoSettings.maxKeyFrameIntervalDuration), allowFrameReordering=\(String(describing: videoSettings.allowFrameReordering)), scalingMode=\(videoSettings.scalingMode.rawValue)
            """,
            category: .streaming
        )

        var audioSettings = await stream.audioSettings
        audioSettings.bitRate = FocusConstants.srtAudioBitRate
        audioSettings.downmix = true
        await stream.setAudioSettings(audioSettings)
    }

    private func configureAudioMixerIfNeeded() async {
        #if canImport(HaishinKit)
        guard !isAudioMixerConfigured else { return }

        let settings = AudioMixerSettings(
            sampleRate: FocusConstants.srtAudioSampleRate,
            channels: UInt32(FocusConstants.srtAudioChannelCount)
        )
        await audioMixer.setAudioMixerSettings(settings)
        await audioMixer.addOutput(stream)
        await audioMixer.addOutput(audioMixerLogOutput)
        isAudioMixerConfigured = true

        FocusLogger.info(
            "SRT audio mixer 설정: sampleRate=\(Int(FocusConstants.srtAudioSampleRate)), channels=\(FocusConstants.srtAudioChannelCount)",
            category: .streaming
        )
        #endif
    }

    private func audioFormatSummary(for sampleBuffer: CMSampleBuffer) -> String {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamBasicDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return "audioFormat=unknown"
        }

        let asbd = streamBasicDescriptionPointer.pointee
        let formatID = fourCharCodeString(asbd.mFormatID)
        let sampleRate = Int(asbd.mSampleRate.rounded())
        let channelCount = Int(asbd.mChannelsPerFrame)
        let bitsPerChannel = Int(asbd.mBitsPerChannel)

        return "audioFormat=\(formatID), sampleRate=\(sampleRate), channels=\(channelCount), bitsPerChannel=\(bitsPerChannel)"
    }

    private func fourCharCodeString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]

        if bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) {
            return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
        }

        return "\(code)"
    }

    private func presentationTimestampMicroseconds(for sampleBuffer: CMSampleBuffer) -> Int64? {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid, pts.seconds.isFinite else {
            return nil
        }
        return Int64((pts.seconds * FocusConstants.ptsScaleMicroseconds).rounded())
    }
}
#else
private actor DefaultSRTBroadcastBackend: SRTBroadcastBackend {
    func start(host: String, port: Int, streamKey: String) async throws {
        throw NSError(
            domain: "SRTBroadcastStreamer",
            code: -99,
            userInfo: [NSLocalizedDescriptionKey: "SRTHaishinKit 패키지가 연결되지 않았습니다."]
        )
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) async {}
    func appendAudio(_ sampleBuffer: CMSampleBuffer) async {}
    func stop() async {}
}
#endif
