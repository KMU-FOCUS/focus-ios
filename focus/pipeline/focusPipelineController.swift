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
    private struct ManualOwnerBinding {
        let ownerID: UUID
        var lastUpgradeAt: Date?
    }

    // MARK: - Public
    private(set) var state: PipelineState = .idle
    var shouldMaskRecordingFaces = true

    var onPreviewFrame: ((CVPixelBuffer, [TrackedFace]) -> Void)?
    var onDebugSnapshot: ((PipelineDebugSnapshot) -> Void)?
    var onStateChanged: ((PipelineState) -> Void)?
    var onSessionFinished: ((PipelineSessionOutputs) -> Void)?
    var onOwnerStoreChanged: (() -> Void)?

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
    private let metadataRepository: MetadataFrameWriting?
    private let sessionFileCoordinator: SessionFileCoordinator?
    private let syncMonitor: AudioVideoSyncMonitor?
    private let ownerStore: OwnerEmbeddingStore?
    private let stopCoordinator = SessionStopCoordinator()
    private let imagePreprocessor = ImagePreprocessor.shared

    // MARK: - Runtime
    private var sessionID: String?
    private var frameIndex: Int = 0
    private var activeRecordingURL: URL?
    private var pendingManualOwnerTrackIDs: Set<Int> = []
    private var manualOwnerBindings: [Int: ManualOwnerBinding] = [:]
    private var manualOwnerRegistrationLastAttemptAt: [Int: Date] = [:]

    init(
        detector: YuNetDetecting,
        tdmmInferencer: Facial3DMMInferring,
        arcFaceExtractor: ArcFaceEmbeddingExtracting? = nil,
        tracker: FaceTracker,
        stateMachine: TrackStateMachine? = nil,
        recorder: LocalRecorder? = nil,
        timestampCorrector: MonotonicTimestampCorrector? = nil,
        maskRenderer: PrivacyMaskRenderer? = nil,
        metadataRepository: MetadataFrameWriting? = nil,
        sessionFileCoordinator: SessionFileCoordinator? = nil,
        syncMonitor: AudioVideoSyncMonitor? = nil,
        ownerStore: OwnerEmbeddingStore? = nil
    ) {
        self.detector = detector
        self.tdmmInferencer = tdmmInferencer
        self.arcFaceExtractor = arcFaceExtractor
        self.tracker = tracker
        self.stateMachine = stateMachine
        self.recorder = recorder
        self.timestampCorrector = timestampCorrector
        self.maskRenderer = maskRenderer
        self.metadataRepository = metadataRepository
        self.sessionFileCoordinator = sessionFileCoordinator
        self.syncMonitor = syncMonitor
        self.ownerStore = ownerStore
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
        self.activeRecordingURL = nil
        self.pendingManualOwnerTrackIDs.removeAll()
        self.manualOwnerBindings.removeAll()
        self.manualOwnerRegistrationLastAttemptAt.removeAll()

        tracker.reset()
        metadataRepository?.startSession(sessionID: sessionID)
        timestampCorrector?.reset()
        syncMonitor?.reset()
        stopCoordinator.reset()

        transition(to: .running)
    }

    func stop(completion: (() -> Void)? = nil) {
        guard stopCoordinator.beginStopping() else {
            completion?()
            return
        }

        transition(to: .stopping)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            _ = self.stopCoordinator.waitForAsyncWork(group: self.asyncGroup)

            self.finishSessionArtifacts { outputs in
                self.lock.lock()
                self.sessionID = nil
                self.frameIndex = 0
                self.activeRecordingURL = nil
                self.lock.unlock()

                self.transition(to: .stopped)
                DispatchQueue.main.async {
                    self.onSessionFinished?(outputs)
                    completion?()
                }
            }
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
              let currentSessionID,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
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

        syncMonitor?.recordAudioPTS(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

        encoderQueue.async { [weak self] in
            self?.recorder?.appendAudioSampleBuffer(sampleBuffer)
        }
    }

    func requestManualOwnerRegistration(trackID: Int) {
        lock.lock()
        pendingManualOwnerTrackIDs.insert(trackID)
        lock.unlock()
    }

    func removeManualOwner(ownerID: UUID) {
        lock.lock()
        manualOwnerBindings = manualOwnerBindings.filter { $0.value.ownerID != ownerID }
        lock.unlock()

        forceTracksToOther(ownerID: ownerID, trackID: nil)
    }

    func removeOwner(ownerID: UUID?, trackID: Int) {
        let shouldNotifyOwnerStoreChanged = ownerID != nil

        if let ownerID {
            _ = ownerStore?.removeOwner(ownerID: ownerID)
        }

        lock.lock()
        pendingManualOwnerTrackIDs.remove(trackID)
        manualOwnerBindings.removeValue(forKey: trackID)
        manualOwnerRegistrationLastAttemptAt[trackID] = nil
        if let ownerID {
            manualOwnerBindings = manualOwnerBindings.filter { $0.value.ownerID != ownerID }
        }
        lock.unlock()

        _ = forceTracksToOther(ownerID: ownerID, trackID: trackID)

        if shouldNotifyOwnerStoreChanged {
            notifyOwnerStoreChanged()
        }
    }

    // MARK: - Pipeline Core
    private func runSyncPipeline(context: FrameContext) {
        do {
            let detections = try detector.detectFaces(from: context.pixelBuffer)
                .filter { $0.confidence >= FocusConstants.yunetConfidenceThreshold }

            let tdmmList: [TDMMCoefficients?] = try detections.map {
                try tdmmInferencer.inferTDMM(from: context.pixelBuffer, face: $0)
            }

            var trackedFaces = tracker.update(
                detections: detections,
                tdmmList: tdmmList,
                frameIndex: context.frameIndex
            )

            if let stateMachine, let arcFaceExtractor {
                enrichLabelsIfNeeded(
                    trackedFaces: &trackedFaces,
                    detections: detections,
                    pixelBuffer: context.pixelBuffer,
                    stateMachine: stateMachine,
                    arcFaceExtractor: arcFaceExtractor
                )
            }

            applyManualOwnerOverrides(&trackedFaces)
            processManualOwnerRegistrationsIfNeeded(
                trackedFaces: &trackedFaces,
                detections: detections,
                pixelBuffer: context.pixelBuffer
            )
            tracker.replaceTracks(with: trackedFaces)

            let metadataFaceCount = metadataRepository?.appendFrame(
                sessionID: context.sessionID,
                ptsUs: context.ptsUs,
                tracks: trackedFaces
            ) ?? 0

            DispatchQueue.main.async { [weak self] in
                self?.onPreviewFrame?(context.pixelBuffer, trackedFaces)
            }

            dispatchLabelRefineIfNeeded(trackedFaces: trackedFaces)
            dispatchOwnerTaskIfNeeded(trackedFaces: trackedFaces)

            syncMonitor?.recordVideoPTS(context.pts)
            appendRecordingFrameIfNeeded(
                pixelBuffer: context.pixelBuffer,
                tracks: trackedFaces,
                pts: context.pts,
                sessionID: context.sessionID
            )

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
            FocusLogger.error(
                "pipeline error: \(error.localizedDescription)",
                category: .pipeline
            )
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
                    FocusLogger.warning(
                        "embedding collect error: \(error.localizedDescription)",
                        category: .inference
                    )
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
                    FocusLogger.warning(
                        "embedding retry error: \(error.localizedDescription)",
                        category: .inference
                    )
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

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        if intersection.isNull || intersection.isEmpty { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
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

    // MARK: - Recording / Finalize
    private func appendRecordingFrameIfNeeded(
        pixelBuffer: CVPixelBuffer,
        tracks: [TrackedFace],
        pts: CMTime,
        sessionID: String
    ) {
        guard let recorder else { return }

        prepareRecorderIfNeeded(
            recorder: recorder,
            pixelBuffer: pixelBuffer,
            sessionID: sessionID
        )

        if shouldMaskRecordingFaces {
            maskRenderer?.renderMasks(on: pixelBuffer, tracks: tracks)
        }

        encoderQueue.async {
            recorder.appendVideoPixelBuffer(pixelBuffer, pts: pts)
        }
    }

    private func prepareRecorderIfNeeded(
        recorder: LocalRecorder,
        pixelBuffer: CVPixelBuffer,
        sessionID: String
    ) {
        guard recorder.currentOutputURL == nil,
              let sessionFileCoordinator else {
            return
        }

        do {
            let outputURL = try sessionFileCoordinator.makeRecordingOutputURL(sessionID: sessionID)
            try recorder.prepareRecording(
                outputURL: outputURL,
                videoSize: CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )
            )

            lock.lock()
            activeRecordingURL = outputURL
            lock.unlock()
        } catch {
            FocusLogger.error(
                "녹화 준비 실패: \(error.localizedDescription)",
                category: .streaming
            )
        }
    }

    private func finishSessionArtifacts(completion: @escaping (PipelineSessionOutputs) -> Void) {
        let metadataURL: URL?
        do {
            metadataURL = try metadataRepository?.finishSession()
        } catch {
            FocusLogger.error(
                "metadata 저장 실패: \(error.localizedDescription)",
                category: .metadata
            )
            metadataURL = nil
        }

        let recordingURL: URL?
        lock.lock()
        recordingURL = activeRecordingURL
        lock.unlock()

        guard let recorder else {
            completion(PipelineSessionOutputs(recordingURL: recordingURL, metadataURL: metadataURL))
            return
        }

        recorder.finishWriting {
            completion(PipelineSessionOutputs(recordingURL: recordingURL, metadataURL: metadataURL))
        }
    }

    // MARK: - Helpers
    private func applyManualOwnerOverrides(_ trackedFaces: inout [TrackedFace]) {
        pruneManualOwnerState(validTrackIDs: Set(trackedFaces.map(\.trackID)))

        lock.lock()
        let pendingTrackIDs = pendingManualOwnerTrackIDs
        let boundOwnerIDsByTrackID = manualOwnerBindings.mapValues(\.ownerID)
        let boundTrackIDs = Set(manualOwnerBindings.keys)
        lock.unlock()

        for index in trackedFaces.indices {
            if pendingTrackIDs.contains(trackedFaces[index].trackID) || boundTrackIDs.contains(trackedFaces[index].trackID) {
                trackedFaces[index].label = .owner
                if let ownerID = boundOwnerIDsByTrackID[trackedFaces[index].trackID] {
                    trackedFaces[index].ownerID = ownerID
                }
            }
        }
    }

    private func processManualOwnerRegistrationsIfNeeded(
        trackedFaces: inout [TrackedFace],
        detections: [DetectedFace],
        pixelBuffer: CVPixelBuffer
    ) {
        for index in trackedFaces.indices {
            let track = trackedFaces[index]

            lock.lock()
            let isPendingManualOwner = pendingManualOwnerTrackIDs.contains(track.trackID)
            let binding = manualOwnerBindings[track.trackID]
            lock.unlock()

            if isPendingManualOwner {
                registerManualOwnerIfPossible(
                    track: &trackedFaces[index],
                    detections: detections,
                    pixelBuffer: pixelBuffer
                )
            } else if let binding {
                upgradeManualOwnerIfPossible(
                    track: &trackedFaces[index],
                    detections: detections,
                    pixelBuffer: pixelBuffer,
                    binding: binding
                )
            }
        }
    }

    private func registerManualOwnerIfPossible(
        track: inout TrackedFace,
        detections: [DetectedFace],
        pixelBuffer: CVPixelBuffer
    ) {
        guard shouldRetryManualOwnerRegistration(
            for: track.trackID,
            intervalMs: FocusConstants.ownerRegistrationRetryIntervalMs
        ) else {
            return
        }

        guard track.bbox.width >= FocusConstants.minManualOwnerFaceSize,
              track.bbox.height >= FocusConstants.minManualOwnerFaceSize,
              Self.isFrontalFace(landmarks: track.landmarks),
              let arcFaceExtractor,
              let ownerStore,
              let matchedDetection = bestMatchingDetection(for: track, from: detections) else {
            return
        }

        do {
            let embedding = try arcFaceExtractor.extractEmbedding(from: pixelBuffer, face: matchedDetection)
            let ownerRecord = ownerStore.addOwner(embedding: embedding)
            let snapshotURL = try? persistOwnerSnapshot(
                from: pixelBuffer,
                rect: matchedDetection.bbox,
                identifier: ownerRecord.id.uuidString
            )

            if let snapshotURL {
                _ = ownerStore.replaceOwnerEmbedding(
                    ownerID: ownerRecord.id,
                    embedding: embedding,
                    snapshotURL: snapshotURL
                )
            }

            lock.lock()
            pendingManualOwnerTrackIDs.remove(track.trackID)
            manualOwnerRegistrationLastAttemptAt[track.trackID] = nil
            manualOwnerBindings[track.trackID] = ManualOwnerBinding(
                ownerID: ownerRecord.id,
                lastUpgradeAt: Date()
            )
            lock.unlock()

            track.label = .owner
            track.ownerID = ownerRecord.id
            notifyOwnerStoreChanged()
        } catch {
            lock.lock()
            manualOwnerRegistrationLastAttemptAt[track.trackID] = Date()
            lock.unlock()

            FocusLogger.warning(
                "수동 owner 등록 실패(track \(track.trackID)): \(error.localizedDescription)",
                category: .pipeline
            )
        }
    }

    private func upgradeManualOwnerIfPossible(
        track: inout TrackedFace,
        detections: [DetectedFace],
        pixelBuffer: CVPixelBuffer,
        binding: ManualOwnerBinding
    ) {
        guard track.bbox.width >= FocusConstants.minManualOwnerFaceSize,
              track.bbox.height >= FocusConstants.minManualOwnerFaceSize,
              Self.isFrontalFace(landmarks: track.landmarks),
              let arcFaceExtractor,
              let ownerStore,
              let matchedDetection = bestMatchingDetection(for: track, from: detections),
              shouldRetryManualOwnerUpgrade(binding: binding, intervalMs: FocusConstants.ownerUpgradeRetryIntervalMs) else {
            return
        }

        do {
            let embedding = try arcFaceExtractor.extractEmbedding(from: pixelBuffer, face: matchedDetection)
            let snapshotURL = try? persistOwnerSnapshot(
                from: pixelBuffer,
                rect: matchedDetection.bbox,
                identifier: binding.ownerID.uuidString
            )

            _ = ownerStore.replaceOwnerEmbedding(
                ownerID: binding.ownerID,
                embedding: embedding,
                snapshotURL: snapshotURL
            )

            lock.lock()
            manualOwnerBindings[track.trackID]?.lastUpgradeAt = Date()
            lock.unlock()

            track.label = .owner
            track.ownerID = binding.ownerID
            notifyOwnerStoreChanged()
        } catch {
            FocusLogger.warning(
                "owner 임베딩 업그레이드 실패(track \(track.trackID)): \(error.localizedDescription)",
                category: .pipeline
            )
        }
    }

    private func shouldRetryManualOwnerRegistration(for trackID: Int, intervalMs: Int) -> Bool {
        lock.lock()
        let lastAttemptAt = manualOwnerRegistrationLastAttemptAt[trackID]
        lock.unlock()

        guard let lastAttemptAt else { return true }
        return Date().timeIntervalSince(lastAttemptAt) * 1_000.0 >= Double(intervalMs)
    }

    private func shouldRetryManualOwnerUpgrade(binding: ManualOwnerBinding, intervalMs: Int) -> Bool {
        guard let lastUpgradeAt = binding.lastUpgradeAt else { return true }
        return Date().timeIntervalSince(lastUpgradeAt) * 1_000.0 >= Double(intervalMs)
    }

    private func pruneManualOwnerState(validTrackIDs: Set<Int>) {
        lock.lock()
        pendingManualOwnerTrackIDs = Set(pendingManualOwnerTrackIDs.filter { validTrackIDs.contains($0) })
        manualOwnerBindings = manualOwnerBindings.reduce(into: [:]) { partialResult, entry in
            guard validTrackIDs.contains(entry.key) else { return }
            partialResult[entry.key] = entry.value
        }
        manualOwnerRegistrationLastAttemptAt = manualOwnerRegistrationLastAttemptAt.reduce(into: [:]) { partialResult, entry in
            guard validTrackIDs.contains(entry.key) else { return }
            partialResult[entry.key] = entry.value
        }
        lock.unlock()
    }

    private func persistOwnerSnapshot(
        from pixelBuffer: CVPixelBuffer,
        rect: CGRect,
        identifier: String
    ) throws -> URL {
        guard let sessionFileCoordinator else {
            throw InferenceError.preprocessingFailed("snapshot 저장 경로를 만들 수 없습니다.")
        }

        let outputURL = try sessionFileCoordinator.makeOwnerSnapshotURL(identifier: identifier)
        let jpegData = try imagePreprocessor.jpegData(
            from: pixelBuffer,
            rect: rect,
            rotationDegrees: FocusConstants.ownerSnapshotRotationDegrees
        )
        try jpegData.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private func notifyOwnerStoreChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.onOwnerStoreChanged?()
        }
    }

    @discardableResult
    private func forceTracksToOther(ownerID: UUID?, trackID: Int?) -> Bool {
        var tracks = tracker.tracks
        var didUpdate = false

        for index in tracks.indices {
            let sameTrack = (trackID != nil && tracks[index].trackID == trackID)
            let sameOwner = (ownerID != nil && tracks[index].ownerID == ownerID)
            guard sameTrack || sameOwner else { continue }

            tracks[index].label = .other
            tracks[index].ownerID = nil
            tracks[index].frontalEmbeddingSamples.removeAll()
            tracks[index].hasRetriedOther = true
            didUpdate = true
        }

        if didUpdate {
            tracker.replaceTracks(with: tracks)
        }

        return didUpdate
    }

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
