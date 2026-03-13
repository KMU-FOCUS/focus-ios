//
//  focusPipelineController.swift
//  focus
//
//  Created by 이동언 on 3/7/26.
//

import Foundation
import AVFoundation
import CoreVideo

final class FocusPipelineController {
    // MARK: - Public
    private(set) var state: PipelineState = .idle

    var onPreviewFrame: ((CVPixelBuffer, [TrackedFace]) -> Void)?
    var onDebugSnapshot: ((PipelineDebugSnapshot) -> Void)?
    var onStateChanged: ((PipelineState) -> Void)?

    // MARK: - Queues
    private let inferenceQueue = DispatchQueue(label: "focus.pipeline.inferenceQueue", qos: .userInitiated)
    private let labelRefineQueue = DispatchQueue(label: "focus.pipeline.labelRefineQueue", qos: .utility)
    private let ownerTaskQueue = DispatchQueue(label: "focus.pipeline.ownerTaskQueue", qos: .utility)
    private let encoderQueue = DispatchQueue(label: "focus.pipeline.encoderQueue", qos: .userInitiated)

    private let asyncGroup = DispatchGroup()
    private let lock = NSLock()

    // MARK: - Dependencies
    private let detector: YuNetDetecting
    private let tdmmInferencer: Facial3DMMInferring
    private let arcFaceExtractor: ArcFaceEmbeddingExtracting?
    private let tracker: FaceTracker
    private let stateMachine: TrackStateMachine?
    private let recorder: LocalRecorder?
    private let timestampCorrector: MonotonicTimestampCorrector?
    private let maskRenderer: PrivacyMaskRenderer?
    private let stopCoordinator = SessionStopCoordinator()

    // MARK: - Runtime
    private var sessionID: String?
    private var frameIndex: Int = 0

    init(
        detector: YuNetDetecting,
        tdmmInferencer: Facial3DMMInferring,
        arcFaceExtractor: ArcFaceEmbeddingExtracting? = nil,
        tracker: FaceTracker,
        stateMachine: TrackStateMachine? = nil,
        recorder: LocalRecorder? = nil,
        timestampCorrector: MonotonicTimestampCorrector? = nil,
        maskRenderer: PrivacyMaskRenderer? = nil
    ) {
        self.detector = detector
        self.tdmmInferencer = tdmmInferencer
        self.arcFaceExtractor = arcFaceExtractor
        self.tracker = tracker
        self.stateMachine = stateMachine
        self.recorder = recorder
        self.timestampCorrector = timestampCorrector
        self.maskRenderer = maskRenderer
    }

    // MARK: - Session Lifecycle
    func start(sessionID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard state == .idle || state == .stopped else {
            throw PipelineError.alreadyRunning
        }

        self.sessionID = sessionID
        self.frameIndex = 0
        stopCoordinator.reset()
        transition(to: .running)
    }

    func stop(completion: (() -> Void)? = nil) {
        guard stopCoordinator.beginStopping() else {
            completion?()
            return
        }

        transition(to: .stopping)

        encoderQueue.async(group: asyncGroup) { [weak self] in
            guard let self else { return }
            self.recorder?.finishWriting {}
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            _ = self.stopCoordinator.waitForAsyncWork(group: self.asyncGroup)

            self.lock.lock()
            self.sessionID = nil
            self.frameIndex = 0
            self.lock.unlock()

            self.transition(to: .stopped)
            completion?()
        }
    }

    // MARK: - Input
    func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        let currentState = state
        let currentSessionID = sessionID
        if currentState == .running {
            frameIndex += 1
        }
        let currentFrameIndex = frameIndex
        lock.unlock()

        guard currentState == .running,
              let currentSessionID else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ptsUs: Int64

        if let timestampCorrector {
            ptsUs = timestampCorrector.correctedPTSUs(from: pts)
        } else {
            ptsUs = Int64(CMTimeGetSeconds(pts) * FocusConstants.ptsScaleMicroseconds)
        }

        let context = FrameContext(
            sampleBuffer: sampleBuffer,
            pixelBuffer: pixelBuffer,
            pts: pts,
            ptsUs: ptsUs,
            sessionID: currentSessionID,
            frameIndex: currentFrameIndex,
            isVideo: true
        )

        inferenceQueue.async { [weak self] in
            self?.runSyncPipeline(context: context)
        }
    }

    func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        let currentState = state
        lock.unlock()

        guard currentState == .running else { return }

        encoderQueue.async(group: asyncGroup) { [weak self] in
            self?.recorder?.appendAudioSampleBuffer(sampleBuffer)
        }
    }

    // MARK: - Pipeline Core
    private func runSyncPipeline(context: FrameContext) {
        do {
            let detections = try detector.detectFaces(from: context.pixelBuffer)
            print("[Detections] count:", detections.count)
            if let first = detections.first {
                print("[Detections] first bbox:", first.bbox, "confidence:", first.confidence)
            }

            let tdmmList: [TDMMCoefficients?] = try detections.map {
                try tdmmInferencer.inferTDMM(from: context.pixelBuffer, face: $0)
            }

            var trackedFaces = tracker.update(
                detections: detections,
                tdmmList: tdmmList,
                frameIndex: context.frameIndex
            )
            
            print("[Tracked] count:", trackedFaces.count)

            if let stateMachine, let arcFaceExtractor {
                enrichLabelsIfNeeded(
                    trackedFaces: &trackedFaces,
                    detections: detections,
                    pixelBuffer: context.pixelBuffer,
                    stateMachine: stateMachine,
                    arcFaceExtractor: arcFaceExtractor
                )
            }

            maskRenderer?.renderMasks(on: context.pixelBuffer, tracks: trackedFaces)

            DispatchQueue.main.async { [weak self] in
                self?.onPreviewFrame?(context.pixelBuffer, trackedFaces)
            }

            dispatchLabelRefineIfNeeded(trackedFaces: trackedFaces)
            dispatchOwnerTaskIfNeeded(trackedFaces: trackedFaces)

            encoderQueue.async(group: asyncGroup) { [weak self] in
                self?.recorder?.appendVideoPixelBuffer(
                    context.pixelBuffer,
                    pts: context.pts
                )
            }

            let metadataFaceCount = 0

            let snapshot = PipelineDebugSnapshot(
                frameIndex: context.frameIndex,
                detectedFaceCount: detections.count,
                trackedFaceCount: trackedFaces.count,
                metadataFaceCount: metadataFaceCount,
                ptsUs: context.ptsUs
            )

            DispatchQueue.main.async { [weak self] in
                self?.onDebugSnapshot?(snapshot)
            }

        } catch {
            print("[FocusPipelineController] pipeline error:", error.localizedDescription)
        }
    }

    private func enrichLabelsIfNeeded(
        trackedFaces: inout [TrackedFace],
        detections: [DetectedFace],
        pixelBuffer: CVPixelBuffer,
        stateMachine: TrackStateMachine,
        arcFaceExtractor: ArcFaceEmbeddingExtracting
    ) {
        for index in trackedFaces.indices {
            let isFrontal = Self.isFrontalFace(landmarks: trackedFaces[index].landmarks)

            guard let matchedDetection = bestMatchingDetection(
                for: trackedFaces[index],
                from: detections
            ) else {
                continue
            }

            if stateMachine.shouldCollectEmbedding(for: trackedFaces[index]) && isFrontal {
                do {
                    let embedding = try arcFaceExtractor.extractEmbedding(
                        from: pixelBuffer,
                        face: matchedDetection
                    )
                    stateMachine.updateLabel(
                        track: &trackedFaces[index],
                        newEmbedding: embedding,
                        isFrontal: true
                    )
                } catch {
                    print("[FocusPipelineController] embedding collect error:", error.localizedDescription)
                }
            } else if stateMachine.shouldRetryOther(for: trackedFaces[index], isFrontal: isFrontal) {
                do {
                    let embedding = try arcFaceExtractor.extractEmbedding(
                        from: pixelBuffer,
                        face: matchedDetection
                    )
                    stateMachine.updateLabel(
                        track: &trackedFaces[index],
                        newEmbedding: embedding,
                        isFrontal: true
                    )
                } catch {
                    print("[FocusPipelineController] embedding retry error:", error.localizedDescription)
                }
            }
        }

        tracker.replaceTracks(with: trackedFaces)
    }

    private func bestMatchingDetection(
        for trackedFace: TrackedFace,
        from detections: [DetectedFace]
    ) -> DetectedFace? {
        detections.max { lhs, rhs in
            intersectionOverUnion(lhs.bbox, trackedFace.bbox) < intersectionOverUnion(rhs.bbox, trackedFace.bbox)
        }
    }

    private func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        if inter.isNull || inter.isEmpty { return 0 }

        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        guard unionArea > 0 else { return 0 }
        return interArea / unionArea
    }

    // MARK: - Async Branches
    private func dispatchLabelRefineIfNeeded(trackedFaces: [TrackedFace]) {
        labelRefineQueue.async(group: asyncGroup) {
            _ = trackedFaces
            // TODO:
            // 원본 재디코드 기반 라벨 보정
            // Owner 강등 금지 병합 규칙 유지
        }
    }

    private func dispatchOwnerTaskIfNeeded(trackedFaces: [TrackedFace]) {
        ownerTaskQueue.async(group: asyncGroup) {
            _ = trackedFaces
            // TODO:
            // 수동 Owner 등록 / 업그레이드 큐
            // throttle 적용
        }
    }

    // MARK: - Helpers
    private func transition(to newState: PipelineState) {
        DispatchQueue.main.async { [weak self] in
            self?.state = newState
            self?.onStateChanged?(newState)
        }
    }

    static func isFrontalFace(landmarks: FaceLandmarks5?) -> Bool {
        guard let lm = landmarks else { return false }

        let eyeCenterX = (lm.leftEye.x + lm.rightEye.x) / 2.0
        let dx = lm.leftEye.x - lm.rightEye.x
        let dy = lm.leftEye.y - lm.rightEye.y
        let eyeDistance = sqrt(dx * dx + dy * dy)

        guard eyeDistance > 0 else { return false }

        let noseOffset = abs(lm.nose.x - eyeCenterX) / eyeDistance
        return noseOffset < FocusConstants.frontalThreshold
    }
}
