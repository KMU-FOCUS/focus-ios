//
//  contentView.swift
//  focus
//
//  Created by 이동언 on 3/7/26.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    var body: some View {
        DesignSystemTestView()
    }
}

#Preview {
    ContentView()
}

// MARK: - ViewModel
@MainActor
final class FocusAppViewModel: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var sessionID: String?
    @Published var processedFrameCount: Int = 0
    @Published var metadataConnected: Bool = false
    @Published var isRecording: Bool = false
    @Published var lastRecordingURL: URL?
    @Published var lastMetadataURL: URL?
    @Published private(set) var ownerProfiles: [OwnerProfileSummary] = []
    @Published private(set) var previewTrackedFaces: [TrackedFace] = []
    @Published private(set) var previewSourceSize: CGSize = .zero
    @Published var transientStatusMessage: String?

    @Published var isCameraReady: Bool = false
    @Published var isCameraRunning: Bool = false
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String?
    @Published var cameraFacing: CameraFacing = .front
    @Published var privacyMode: PrivacyMenuMode = .avatar

    let cameraManager = CameraSessionManager()

    private var pipelineController: FocusPipelineController?
    private let recorder = LocalRecorder()
    private let timestampCorrector = MonotonicTimestampCorrector()
    private let fileCoordinator = SessionFileCoordinator()
    private let ownerStore = OwnerEmbeddingStore()
    private let ownerClassifier = OwnerOtherClassifier()
    private lazy var metadataRepository = JSONMetadataRepository(fileCoordinator: fileCoordinator)
    private let syncMonitor = AudioVideoSyncMonitor()
    private let imagePreprocessor = ImagePreprocessor.shared
    private let photoLibraryVideoSaver = PhotoLibraryVideoSaver()
    private let previewHitTester = PreviewTrackHitTester()
    private let previewAnalysisQueue = DispatchQueue(label: "focus.preview.analysis", qos: .userInitiated)
    private lazy var previewFaceTracker = FaceTracker()
    private lazy var previewTrackStateMachine = TrackStateMachine(
        ownerStore: ownerStore,
        classifier: ownerClassifier
    )
    private var previewDetector: YuNetDetecting?
    private var previewTDMMInferencer: Facial3DMMInferring?
    private var manualOwnerArcFaceExtractor: ArcFaceEmbeddingExtracting?
    private var latestPreviewPixelBuffer: CVPixelBuffer?
    private var pendingOwnerRegistrationFeedback = false
    private var pendingOwnerFeedbackTask: Task<Void, Never>?
    private var statusDismissTask: Task<Void, Never>?
    private var previewAnalysisInFlight = false
    private var previewAnalysisFrameCounter = 0
    private var previewAnalysisSequence = 0
    private var previewAnalysisGeneration = 0
    private var previewPendingOwnerTrackIDs: Set<Int> = []
    private var previewManualOwnerTrackIDs: Set<Int> = []
    private var previewLabelByTrackID: [Int: Bool] = [:]
    private var previewOwnerIDByTrackID: [Int: UUID] = [:]

    var cameraSession: AVCaptureSession {
        cameraManager.session
    }

    var sessionStateText: String {
        isRunning ? "실행 중" : "중지됨"
    }

    var sessionIDText: String {
        sessionID ?? "-"
    }

    var metadataStateText: String {
        metadataConnected ? "연결됨" : "미연결"
    }

    var recordingStateText: String {
        isRecording ? "녹화 중" : "대기"
    }

    var cameraStatusText: String {
        isCameraReady ? "카메라 준비 완료" : "카메라 권한 확인 및 세션 준비 중"
    }

    var cameraRunningText: String {
        isCameraRunning ? "실행 중" : "중지됨"
    }

    init() {
        refreshOwnerProfiles()
        setupCameraRouter()
    }

    func prepareCameraIfNeeded() async {
        guard !isCameraReady else {
            startPreviewIfPossible()
            return
        }

        let granted = await cameraManager.requestPermissionsIfNeeded()
        guard granted else {
            handleError("카메라 또는 마이크 권한이 거부되었습니다.")
            return
        }

        await withCheckedContinuation { continuation in
            cameraManager.configureSession(cameraPosition: cameraFacing.capturePosition) { [weak self] result in
                guard let self else {
                    continuation.resume()
                    return
                }

                switch result {
                case .success:
                    self.isCameraReady = true
                    self.startPreviewIfPossible()
                    self.buildPipelineIfPossible()
                case .failure(let error):
                    self.handleError(error.localizedDescription)
                }
                continuation.resume()
            }
        }
    }

    func switchCamera(to facing: CameraFacing) {
        guard cameraFacing != facing else { return }

        cameraManager.reconfigureCamera(position: facing.capturePosition) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success:
                self.cameraFacing = facing
                self.isCameraReady = true
                self.clearPreviewTrackingState()
                self.startPreviewIfPossible()
            case .failure(let error):
                self.handleError(error.localizedDescription)
            }
        }
    }

    func setPrivacyMode(_ mode: PrivacyMenuMode) {
        privacyMode = mode
        pipelineController?.shouldMaskRecordingFaces = mode != .disabled
    }

    func toggleSession() {
        if isRunning {
            stopSession()
        } else {
            startSession()
        }
    }

    func startSession() {
        guard isCameraReady else {
            handleError("카메라가 아직 준비되지 않았습니다.")
            return
        }

        buildPipelineIfPossible()

        guard let pipelineController else {
            handleError("파이프라인 초기화에 실패했습니다.")
            return
        }

        let newSessionID = UUID().uuidString
        resetDebugState()
        lastRecordingURL = nil
        lastMetadataURL = nil

        do {
            try pipelineController.start(sessionID: newSessionID)
        } catch {
            handleError(error.localizedDescription)
            return
        }

        isRunning = true
        isRecording = true
        metadataConnected = true
        sessionID = newSessionID

        startPreviewIfPossible()
    }

    func stopSession() {
        isRunning = false
        isRecording = false
        clearPreviewTrackingState()
        pipelineController?.stop()
    }

    func resetDebugState() {
        processedFrameCount = 0
        if !isRunning {
            sessionID = nil
        }
    }

    func handlePreviewTap(at location: CGPoint, previewSize: CGSize) {
        let visibleTracks = activePreviewTracks()
        let selectedTrack = nearestPreviewTrack(
            to: location,
            previewSize: previewSize,
            visibleTracks: visibleTracks
        )

        if let selectedTrack, selectedTrack.label == .owner {
            removeOwnerForTrack(selectedTrack)
            return
        }

        if isRunning {
            let selectedTrackID = previewHitTester.nearestTrackID(
                to: location,
                previewSize: previewSize,
                tracks: visibleTracks,
                sourceSize: previewSourceSize,
                isMirrored: cameraFacing == .front
            )

            guard let selectedTrackID else {
                return
            }

            pendingOwnerRegistrationFeedback = true
            pendingOwnerFeedbackTask?.cancel()
            pipelineController?.requestManualOwnerRegistration(trackID: selectedTrackID)
            return
        }

        registerOwnerFromPreviewTap(
            at: location,
            previewSize: previewSize,
            selectedTrack: selectedTrack
        )
    }

    func removeOwner(ownerID: UUID) {
        _ = ownerStore.removeOwner(ownerID: ownerID)
        pipelineController?.removeManualOwner(ownerID: ownerID)
        markPreviewTracksAsOther(ownerID: ownerID)
        refreshOwnerProfiles()
    }

    private func startPreviewIfPossible() {
        cameraManager.startRunning()
        isCameraRunning = true
    }

    private func setupCameraRouter() {
        cameraManager.router.onVideoSample = { [weak self] sampleBuffer in
            guard let self else { return }

            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let sourceSize = CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )

                Task { @MainActor in
                    self.latestPreviewPixelBuffer = pixelBuffer
                    self.previewSourceSize = sourceSize
                    self.schedulePreviewAnalysisIfNeeded(pixelBuffer: pixelBuffer)
                }
            }

            if let pipelineController = self.pipelineController, self.isRunning {
                pipelineController.processVideoSampleBuffer(sampleBuffer)
            } else {
                Task { @MainActor in
                    self.processedFrameCount += 1
                }
            }
        }

        cameraManager.router.onAudioSample = { [weak self] sampleBuffer in
            guard let self else { return }
            guard self.isRunning else { return }
            self.pipelineController?.processAudioSampleBuffer(sampleBuffer)
        }
    }

    private func buildPipelineIfPossible() {
        guard pipelineController == nil else { return }

        do {
            let detector = try YuNetOpenCVService(
                modelFileName: "face_detection_yunet_2023mar",
                modelFileExtension: "onnx",
                inputSize: 360,
                scoreThreshold: FocusConstants.yunetScoreThreshold,
                nmsThreshold: 0.3,
                topK: 5000
            )

            let tdmmInferencer: Facial3DMMInferring
            do {
                tdmmInferencer = try Facial3DMMTFLiteService(
                    modelFileName: "facemap_3dmm-facial-landmark-detection-float",
                    modelFileExtension: "tflite"
                )
            } catch {
                FocusLogger.warning(
                    "3DMM이 비활성화된 상태로 파이프라인을 구성합니다. TensorFlowLite 연결 상태를 확인해 주세요. \(error.localizedDescription)",
                    category: .inference
                )
                tdmmInferencer = NoOpFacial3DMMService()
            }

            let arcFaceExtractor = try? ArcFaceONNXService()
            if arcFaceExtractor == nil {
                FocusLogger.warning(
                    "ArcFace가 비활성화된 상태로 파이프라인을 구성합니다. 모델 파일 또는 ONNX Runtime 연결 상태를 확인해 주세요.",
                    category: .inference
                )
            }
            previewDetector = detector
            previewTDMMInferencer = tdmmInferencer
            manualOwnerArcFaceExtractor = arcFaceExtractor
            let tracker = FaceTracker()
            let stateMachine = TrackStateMachine(
                ownerStore: ownerStore,
                classifier: ownerClassifier
            )

            let pipeline = FocusPipelineController(
                detector: detector,
                tdmmInferencer: tdmmInferencer,
                arcFaceExtractor: arcFaceExtractor,
                tracker: tracker,
                stateMachine: stateMachine,
                recorder: recorder,
                timestampCorrector: timestampCorrector,
                maskRenderer: PrivacyMaskRenderer(),
                metadataRepository: metadataRepository,
                sessionFileCoordinator: fileCoordinator,
                syncMonitor: syncMonitor,
                ownerStore: ownerStore
            )
            pipeline.shouldMaskRecordingFaces = privacyMode != .disabled

            pipeline.onDebugSnapshot = { [weak self] snapshot in
                guard let self else { return }
                Task { @MainActor in
                    self.processedFrameCount = snapshot.frameIndex
                }
            }

            pipeline.onStateChanged = { newState in
                FocusLogger.info("pipeline state: \(newState)", category: .pipeline)
            }

            pipeline.onPreviewFrame = { [weak self] pixelBuffer, trackedFaces in
                guard let self else { return }
                Task { @MainActor in
                    self.previewTrackedFaces = trackedFaces
                    self.previewSourceSize = CGSize(
                        width: CVPixelBufferGetWidth(pixelBuffer),
                        height: CVPixelBufferGetHeight(pixelBuffer)
                    )
                }
            }

            pipeline.onSessionFinished = { [weak self] outputs in
                guard let self else { return }
                Task { @MainActor in
                    self.isRecording = false
                    self.metadataConnected = false
                    self.sessionID = nil
                    self.lastRecordingURL = outputs.recordingURL
                    self.lastMetadataURL = outputs.metadataURL
                    self.clearPreviewTrackingState()

                    if let recordingURL = outputs.recordingURL {
                        await self.saveRecordingToPhotoLibrary(recordingURL)
                    }
                }
            }

            pipeline.onOwnerStoreChanged = { [weak self] in
                self?.refreshOwnerProfiles(showSuccessIfPending: true)
            }

            self.pipelineController = pipeline
        } catch {
            handleError("파이프라인 생성 실패: \(error.localizedDescription)")
        }
    }

    private func refreshOwnerProfiles(showSuccessIfPending: Bool = false) {
        let previousCount = ownerProfiles.count
        let summaries = ownerStore.summaries()
        ownerProfiles = summaries

        if showSuccessIfPending,
           pendingOwnerRegistrationFeedback,
           summaries.count > previousCount {
            pendingOwnerRegistrationFeedback = false
            pendingOwnerFeedbackTask?.cancel()
            showStatus("오너 등록이 완료되었습니다.")
        }
    }

    private func clearPreviewTrackingState() {
        previewAnalysisGeneration += 1
        previewAnalysisFrameCounter = 0
        previewAnalysisSequence = 0
        previewAnalysisInFlight = false
        previewPendingOwnerTrackIDs.removeAll()
        previewManualOwnerTrackIDs.removeAll()
        previewLabelByTrackID.removeAll()
        previewOwnerIDByTrackID.removeAll()
        previewTrackedFaces.removeAll()
        latestPreviewPixelBuffer = nil
        previewSourceSize = .zero

        previewAnalysisQueue.async { [weak self] in
            self?.previewFaceTracker.reset()
        }
    }

    func previewFaceOverlays(for previewSize: CGSize) -> [PreviewFaceOverlay] {
        let visibleTracks = overlayPreviewTracks()
        guard !visibleTracks.isEmpty else { return [] }

        let rects = previewHitTester.mappedTrackRects(
            tracks: visibleTracks,
            previewSize: previewSize,
            sourceSize: previewSourceSize,
            isMirrored: cameraFacing == .front
        )

        let labelByTrackID = Dictionary(uniqueKeysWithValues: visibleTracks.map { ($0.trackID, $0.label) })

        return rects.compactMap { rect in
            guard let label = labelByTrackID[rect.trackID] else { return nil }
            return PreviewFaceOverlay(trackID: rect.trackID, rect: rect.rect, label: label)
        }
    }

    private func schedulePreviewAnalysisIfNeeded(pixelBuffer: CVPixelBuffer) {
        guard !isRunning else { return }
        guard let previewDetector else { return }
        guard !previewAnalysisInFlight else { return }

        previewAnalysisFrameCounter += 1
        guard previewAnalysisFrameCounter % FocusConstants.previewAnalysisStride == 0 else { return }

        previewAnalysisSequence += 1
        let frameIndex = previewAnalysisSequence

        previewAnalysisInFlight = true
        let generation = previewAnalysisGeneration

        let detector = previewDetector
        let tdmmInferencer = previewTDMMInferencer
        let arcFaceExtractor = manualOwnerArcFaceExtractor
        let pendingOwnerTrackIDs = previewPendingOwnerTrackIDs
        let manualOwnerTrackIDs = previewManualOwnerTrackIDs
        let labelByTrackID = previewLabelByTrackID
        let ownerIDByTrackID = previewOwnerIDByTrackID

        previewAnalysisQueue.async { [weak self] in
            guard let self else { return }

            let tracks = self.makePreviewTracks(
                from: pixelBuffer,
                detector: detector,
                tdmmInferencer: tdmmInferencer,
                arcFaceExtractor: arcFaceExtractor,
                frameIndex: frameIndex,
                pendingOwnerTrackIDs: pendingOwnerTrackIDs,
                manualOwnerTrackIDs: manualOwnerTrackIDs,
                labelByTrackID: labelByTrackID,
                ownerIDByTrackID: ownerIDByTrackID
            )

            Task { @MainActor in
                guard !self.isRunning,
                      self.previewAnalysisGeneration == generation else {
                    self.previewAnalysisInFlight = false
                    return
                }

                let previousTracks = self.previewTrackedFaces
                self.reassignPreviewOwnerLatchesIfNeeded(
                    from: previousTracks,
                    to: tracks
                )

                var resolvedTracks = tracks
                self.applyPreviewOwnerBindings(
                    &resolvedTracks,
                    pendingOwnerTrackIDs: self.previewPendingOwnerTrackIDs,
                    manualOwnerTrackIDs: self.previewManualOwnerTrackIDs,
                    labelByTrackID: self.previewLabelByTrackID,
                    ownerIDByTrackID: self.previewOwnerIDByTrackID
                )

                self.previewTrackedFaces = resolvedTracks
                self.previewAnalysisInFlight = false
            }
        }
    }

    private func registerOwnerFromPreviewTap(
        at location: CGPoint,
        previewSize: CGSize,
        selectedTrack: TrackedFace?
    ) {
        guard let pixelBuffer = latestPreviewPixelBuffer,
              let previewDetector,
              let manualOwnerArcFaceExtractor else {
            return
        }

        if let selectedTrack {
            applyImmediatePreviewOwnerLabel(trackID: selectedTrack.trackID)
        }

        do {
            let detections = try previewDetector.detectFaces(from: pixelBuffer)
                .filter { $0.confidence >= FocusConstants.yunetConfidenceThreshold }

            guard !detections.isEmpty else {
                return
            }

            let temporaryTracks = detections.enumerated().map { index, detection in
                TrackedFace(
                    trackID: index,
                    bbox: detection.bbox,
                    landmarks: detection.landmarks,
                    tdmm: nil,
                    label: .pending,
                    ownerID: nil,
                    age: 1,
                    missedFrames: 0,
                    frontalEmbeddingSamples: [],
                    hasRetriedOther: false,
                    framesSeen: 1,
                    lastSeenFrameIndex: 1
                )
            }

            guard let selectedDetectionIndex = previewHitTester.nearestTrackID(
                to: location,
                previewSize: previewSize,
                tracks: temporaryTracks,
                sourceSize: previewSourceSize,
                isMirrored: cameraFacing == .front
            ) else {
                return
            }

            guard detections.indices.contains(selectedDetectionIndex) else { return }
            let detection = detections[selectedDetectionIndex]

            guard detection.bbox.width >= FocusConstants.minManualOwnerFaceSize,
                  detection.bbox.height >= FocusConstants.minManualOwnerFaceSize else {
                return
            }

            guard FocusPipelineController.isFrontalFace(landmarks: detection.landmarks) else {
                return
            }

            let ownerRecord = try addOwnerFromDetection(
                detection,
                pixelBuffer: pixelBuffer,
                arcFaceExtractor: manualOwnerArcFaceExtractor
            )

            if let selectedTrack {
                commitPreviewOwnerRegistration(trackID: selectedTrack.trackID, ownerID: ownerRecord.id)
            }
        } catch {
            if let selectedTrack {
                rollbackPreviewPendingOwner(trackID: selectedTrack.trackID)
            }
            handleError("owner 등록 실패: \(error.localizedDescription)")
        }
    }

    private func addOwnerFromDetection(
        _ detection: DetectedFace,
        pixelBuffer: CVPixelBuffer,
        arcFaceExtractor: ArcFaceEmbeddingExtracting
    ) throws -> OwnerEmbeddingStore.OwnerRecord {
        let embedding = try arcFaceExtractor.extractEmbedding(from: pixelBuffer, face: detection)
        let ownerRecord = ownerStore.addOwner(embedding: embedding)

        if let snapshotURL = try? persistOwnerSnapshot(
            from: pixelBuffer,
            rect: detection.bbox,
            identifier: ownerRecord.id.uuidString
        ) {
            _ = ownerStore.replaceOwnerEmbedding(
                ownerID: ownerRecord.id,
                embedding: embedding,
                snapshotURL: snapshotURL
            )
        }

        refreshOwnerProfiles()
        showStatus("오너 등록이 완료되었습니다.")
        return ownerRecord
    }

    private func nearestPreviewTrack(
        to location: CGPoint,
        previewSize: CGSize,
        visibleTracks: [TrackedFace]
    ) -> TrackedFace? {
        guard let selectedTrackID = previewHitTester.nearestTrackID(
            to: location,
            previewSize: previewSize,
            tracks: visibleTracks,
            sourceSize: previewSourceSize,
            isMirrored: cameraFacing == .front
        ) else {
            return nil
        }

        return visibleTracks.first(where: { $0.trackID == selectedTrackID })
    }

    private func removeOwnerForTrack(_ track: TrackedFace) {
        guard track.label == .owner else { return }

        if let ownerID = track.ownerID {
            if let pipelineController {
                pipelineController.removeOwner(ownerID: ownerID, trackID: track.trackID)
            } else {
                _ = ownerStore.removeOwner(ownerID: ownerID)
            }
            refreshOwnerProfiles()
            markPreviewTrackAsOther(trackID: track.trackID)
            showStatus("오너 등록이 해제되었습니다.")
            return
        }

        pipelineController?.removeOwner(ownerID: nil, trackID: track.trackID)
        markPreviewTrackAsOther(trackID: track.trackID)
        showStatus("오너 등록이 해제되었습니다.")
    }

    private func markPreviewTrackAsOther(trackID: Int) {
        previewPendingOwnerTrackIDs.remove(trackID)
        previewManualOwnerTrackIDs.remove(trackID)
        previewLabelByTrackID.removeValue(forKey: trackID)
        previewOwnerIDByTrackID.removeValue(forKey: trackID)
        previewTrackedFaces = previewTrackedFaces.map { track in
            guard track.trackID == trackID else { return track }

            return previewTrackMarkedAsOther(track)
        }

        schedulePreviewTrackerOwnerRemoval(trackID: trackID, ownerID: nil)
    }

    private func markPreviewTracksAsOther(ownerID: UUID) {
        let latchedTrackIDs = Set(
            previewOwnerIDByTrackID.compactMap { entry in
                entry.value == ownerID ? entry.key : nil
            }
        )
        previewPendingOwnerTrackIDs.subtract(latchedTrackIDs)
        previewManualOwnerTrackIDs.subtract(latchedTrackIDs)
        previewOwnerIDByTrackID = previewOwnerIDByTrackID.filter { $0.value != ownerID }
        previewLabelByTrackID = previewLabelByTrackID.filter { !latchedTrackIDs.contains($0.key) }
        previewTrackedFaces = previewTrackedFaces.map { track in
            guard track.ownerID == ownerID else { return track }

            return previewTrackMarkedAsOther(track)
        }

        schedulePreviewTrackerOwnerRemoval(trackID: nil, ownerID: ownerID)
    }

    private func previewTrackMarkedAsOther(_ track: TrackedFace) -> TrackedFace {
        var updatedTrack = track
        updatedTrack.label = .other
        updatedTrack.ownerID = nil
        updatedTrack.frontalEmbeddingSamples.removeAll()
        updatedTrack.hasRetriedOther = true
        return updatedTrack
    }

    private func previewTrackMarkedAsOwner(_ track: TrackedFace, ownerID: UUID?) -> TrackedFace {
        var updatedTrack = track
        updatedTrack.label = .owner
        updatedTrack.ownerID = ownerID
        return updatedTrack
    }

    private func applyImmediatePreviewOwnerLabel(trackID: Int) {
        previewPendingOwnerTrackIDs.insert(trackID)
        previewLabelByTrackID[trackID] = true
        previewTrackedFaces = previewTrackedFaces.map { track in
            guard track.trackID == trackID else { return track }

            return previewTrackMarkedAsOwner(track, ownerID: previewOwnerIDByTrackID[trackID])
        }

        schedulePreviewTrackerOwnerBinding(trackID: trackID, ownerID: previewOwnerIDByTrackID[trackID])
    }

    private func commitPreviewOwnerRegistration(trackID: Int, ownerID: UUID) {
        previewPendingOwnerTrackIDs.remove(trackID)
        previewManualOwnerTrackIDs.insert(trackID)
        previewLabelByTrackID[trackID] = true
        previewOwnerIDByTrackID[trackID] = ownerID
        previewTrackedFaces = previewTrackedFaces.map { track in
            guard track.trackID == trackID else { return track }

            return previewTrackMarkedAsOwner(track, ownerID: ownerID)
        }

        schedulePreviewTrackerOwnerBinding(trackID: trackID, ownerID: ownerID)
    }

    private func rollbackPreviewPendingOwner(trackID: Int) {
        previewPendingOwnerTrackIDs.remove(trackID)
        previewLabelByTrackID.removeValue(forKey: trackID)
        previewOwnerIDByTrackID.removeValue(forKey: trackID)
        previewTrackedFaces = previewTrackedFaces.map { track in
            guard track.trackID == trackID else { return track }

            return previewTrackMarkedAsOther(track)
        }

        schedulePreviewTrackerOwnerRemoval(trackID: trackID, ownerID: nil)
    }

    private func reassignPreviewOwnerLatchesIfNeeded(
        from previousTracks: [TrackedFace],
        to newTracks: [TrackedFace]
    ) {
        let currentTrackIDs = Set(newTracks.map(\.trackID))
        let latchedTrackIDs = Set(previewLabelByTrackID.keys)
        let lostTrackIDs = latchedTrackIDs.subtracting(currentTrackIDs)

        guard !lostTrackIDs.isEmpty else { return }

        var availableNewTrackIDs = Set<Int>(
            newTracks.compactMap { track in
                guard previewLabelByTrackID[track.trackID] != true,
                      !previewPendingOwnerTrackIDs.contains(track.trackID),
                      !previewManualOwnerTrackIDs.contains(track.trackID) else {
                    return nil
                }
                return track.trackID
            }
        )

        for lostTrackID in lostTrackIDs {
            guard let previousTrack = previousTracks.first(where: { $0.trackID == lostTrackID }) else {
                continue
            }

            var bestMatchTrackID: Int?
            var bestMatchCost = Float.greatestFiniteMagnitude

            for newTrack in newTracks where availableNewTrackIDs.contains(newTrack.trackID) {
                let candidateDetection = DetectedFace(
                    bbox: newTrack.bbox,
                    landmarks: newTrack.landmarks,
                    confidence: 1
                )

                guard let cost = TrackCost.combinedCost(
                    track: previousTrack,
                    detection: candidateDetection,
                    detectionTDMM: newTrack.tdmm
                ) else {
                    continue
                }

                if cost.cost < bestMatchCost {
                    bestMatchCost = cost.cost
                    bestMatchTrackID = newTrack.trackID
                }
            }

            guard let bestMatchTrackID else { continue }

            transferPreviewOwnerLatch(from: lostTrackID, to: bestMatchTrackID)
            availableNewTrackIDs.remove(bestMatchTrackID)
        }
    }

    private func transferPreviewOwnerLatch(from oldTrackID: Int, to newTrackID: Int) {
        if previewPendingOwnerTrackIDs.remove(oldTrackID) != nil {
            previewPendingOwnerTrackIDs.insert(newTrackID)
        }

        if previewManualOwnerTrackIDs.remove(oldTrackID) != nil {
            previewManualOwnerTrackIDs.insert(newTrackID)
        }

        if let label = previewLabelByTrackID.removeValue(forKey: oldTrackID) {
            previewLabelByTrackID[newTrackID] = label
        }

        if let ownerID = previewOwnerIDByTrackID.removeValue(forKey: oldTrackID) {
            previewOwnerIDByTrackID[newTrackID] = ownerID
        }
    }

    private func schedulePreviewTrackerOwnerRemoval(trackID: Int?, ownerID: UUID?) {
        previewAnalysisQueue.async { [weak self] in
            guard let self else { return }

            let updatedTracks = self.previewFaceTracker.tracks.map { track in
                let sameTrack = (trackID != nil && track.trackID == trackID)
                let sameOwner = (ownerID != nil && track.ownerID == ownerID)
                guard sameTrack || sameOwner else { return track }
                return self.previewTrackMarkedAsOther(track)
            }

            self.previewFaceTracker.replaceTracks(with: updatedTracks)
        }
    }

    private func schedulePreviewTrackerOwnerBinding(trackID: Int, ownerID: UUID?) {
        previewAnalysisQueue.async { [weak self] in
            guard let self else { return }

            let updatedTracks = self.previewFaceTracker.tracks.map { track in
                guard track.trackID == trackID else { return track }

                return self.previewTrackMarkedAsOwner(track, ownerID: ownerID)
            }

            self.previewFaceTracker.replaceTracks(with: updatedTracks)
        }
    }

    private func persistOwnerSnapshot(
        from pixelBuffer: CVPixelBuffer,
        rect: CGRect,
        identifier: String
    ) throws -> URL {
        let outputURL = try fileCoordinator.makeOwnerSnapshotURL(identifier: identifier)
        let jpegData = try imagePreprocessor.jpegData(
            from: pixelBuffer,
            rect: rect,
            rotationDegrees: FocusConstants.ownerSnapshotRotationDegrees
        )
        try jpegData.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private func saveRecordingToPhotoLibrary(_ recordingURL: URL) async {
        do {
            try await photoLibraryVideoSaver.saveVideo(at: recordingURL)
            showStatus("녹화 영상을 사진 보관함에 저장했어요.")
        } catch {
            handleError("녹화 영상 저장 실패: \(error.localizedDescription)")
        }
    }

    private func showStatus(_ message: String) {
        statusDismissTask?.cancel()
        transientStatusMessage = message

        statusDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            transientStatusMessage = nil
        }
    }

    private func handleError(_ message: String) {
        pendingOwnerRegistrationFeedback = false
        pendingOwnerFeedbackTask?.cancel()
        errorMessage = message
        showErrorAlert = true
    }
}

struct PreviewFaceOverlay: Identifiable, Equatable {
    let trackID: Int
    let rect: CGRect
    let label: TrackLabel

    var id: Int { trackID }
}

private extension FocusAppViewModel {
    func activePreviewTracks() -> [TrackedFace] {
        previewTrackedFaces.filter { $0.missedFrames == 0 }
    }

    func overlayPreviewTracks() -> [TrackedFace] {
        previewTrackedFaces.filter { $0.missedFrames <= FocusConstants.previewOverlayMaxMissedFrames }
    }

    func makePreviewTracks(
        from pixelBuffer: CVPixelBuffer,
        detector: YuNetDetecting,
        tdmmInferencer: Facial3DMMInferring?,
        arcFaceExtractor: ArcFaceEmbeddingExtracting?,
        frameIndex: Int,
        pendingOwnerTrackIDs: Set<Int>,
        manualOwnerTrackIDs: Set<Int>,
        labelByTrackID: [Int: Bool],
        ownerIDByTrackID: [Int: UUID]
    ) -> [TrackedFace] {
        let detections: [DetectedFace]

        do {
            detections = try detector.detectFaces(from: pixelBuffer)
                .filter { $0.confidence >= FocusConstants.yunetConfidenceThreshold }
        } catch {
            FocusLogger.warning(
                "preview 얼굴 검출 실패: \(error.localizedDescription)",
                category: .inference
            )
            return []
        }

        let previousTracks = previewFaceTracker.tracks
        let tdmmList = makePreviewTDMMList(
            from: pixelBuffer,
            detections: detections,
            tdmmInferencer: tdmmInferencer
        )
        var trackedFaces = previewFaceTracker.update(
            detections: detections,
            tdmmList: tdmmList,
            frameIndex: frameIndex
        )

        if let arcFaceExtractor {
            enrichPreviewLabelsIfNeeded(
                trackedFaces: &trackedFaces,
                detections: detections,
                tdmmList: tdmmList,
                pixelBuffer: pixelBuffer,
                arcFaceExtractor: arcFaceExtractor
            )
        }

        applyPreviewOwnerBindings(
            &trackedFaces,
            pendingOwnerTrackIDs: pendingOwnerTrackIDs,
            manualOwnerTrackIDs: manualOwnerTrackIDs,
            labelByTrackID: labelByTrackID,
            ownerIDByTrackID: ownerIDByTrackID
        )

        let displayTracks = trackedFaces.map { track in
            guard let previousTrack = previousTracks.first(where: { $0.trackID == track.trackID }) else {
                return track
            }

            var displayTrack = track
            displayTrack.bbox = interpolate(
                from: previousTrack.bbox,
                to: track.bbox,
                factor: FocusConstants.previewBoxInterpolationFactor
            )
            return displayTrack
        }

        previewFaceTracker.replaceTracks(with: trackedFaces)

        return displayTracks.filter { $0.missedFrames <= FocusConstants.previewOverlayMaxMissedFrames }
    }

    func applyPreviewOwnerBindings(
        _ trackedFaces: inout [TrackedFace],
        pendingOwnerTrackIDs: Set<Int>,
        manualOwnerTrackIDs: Set<Int>,
        labelByTrackID: [Int: Bool],
        ownerIDByTrackID: [Int: UUID]
    ) {
        guard !pendingOwnerTrackIDs.isEmpty ||
                !manualOwnerTrackIDs.isEmpty ||
                !labelByTrackID.isEmpty else {
            return
        }

        for index in trackedFaces.indices {
            let trackID = trackedFaces[index].trackID
            let hasLatchedOwner = labelByTrackID[trackID] == true ||
                pendingOwnerTrackIDs.contains(trackID) ||
                manualOwnerTrackIDs.contains(trackID)

            guard hasLatchedOwner else { continue }
            trackedFaces[index].label = .owner
            trackedFaces[index].ownerID = ownerIDByTrackID[trackID]
        }
    }

    func makePreviewTDMMList(
        from pixelBuffer: CVPixelBuffer,
        detections: [DetectedFace],
        tdmmInferencer: Facial3DMMInferring?
    ) -> [TDMMCoefficients?] {
        guard let tdmmInferencer else {
            return Array(repeating: nil, count: detections.count)
        }

        return detections.map { detection in
            do {
                return try tdmmInferencer.inferTDMM(from: pixelBuffer, face: detection)
            } catch {
                FocusLogger.debug(
                    "preview 3DMM skip: \(error.localizedDescription)",
                    category: .inference
                )
                return nil
            }
        }
    }

    func enrichPreviewLabelsIfNeeded(
        trackedFaces: inout [TrackedFace],
        detections: [DetectedFace],
        tdmmList: [TDMMCoefficients?],
        pixelBuffer: CVPixelBuffer,
        arcFaceExtractor: ArcFaceEmbeddingExtracting
    ) {
        for index in trackedFaces.indices {
            let isFrontal = FocusPipelineController.isFrontalFace(landmarks: trackedFaces[index].landmarks)

            guard let matchedDetection = bestPreviewMatchingDetection(
                for: trackedFaces[index],
                from: detections,
                tdmmList: tdmmList
            ) else {
                continue
            }

            if previewTrackStateMachine.shouldCollectEmbedding(for: trackedFaces[index]) && isFrontal {
                do {
                    let embedding = try arcFaceExtractor.extractEmbedding(
                        from: pixelBuffer,
                        face: matchedDetection
                    )
                    previewTrackStateMachine.updateLabel(
                        track: &trackedFaces[index],
                        newEmbedding: embedding,
                        isFrontal: true
                    )
                } catch {
                    FocusLogger.debug(
                        "preview embedding collect skip: \(error.localizedDescription)",
                        category: .inference
                    )
                }
            } else if previewTrackStateMachine.shouldRetryOther(for: trackedFaces[index], isFrontal: isFrontal) {
                do {
                    let embedding = try arcFaceExtractor.extractEmbedding(
                        from: pixelBuffer,
                        face: matchedDetection
                    )
                    previewTrackStateMachine.updateLabel(
                        track: &trackedFaces[index],
                        newEmbedding: embedding,
                        isFrontal: true
                    )
                } catch {
                    FocusLogger.debug(
                        "preview embedding retry skip: \(error.localizedDescription)",
                        category: .inference
                    )
                }
            }
        }
    }

    func bestPreviewMatchingDetection(
        for trackedFace: TrackedFace,
        from detections: [DetectedFace],
        tdmmList: [TDMMCoefficients?]
    ) -> DetectedFace? {
        var bestDetectionIndex: Int?
        var bestCost = Float.greatestFiniteMagnitude

        for detectionIndex in detections.indices {
            let detectionTDMM = tdmmList.indices.contains(detectionIndex) ? tdmmList[detectionIndex] : nil
            guard let candidate = TrackCost.combinedCost(
                track: trackedFace,
                detection: detections[detectionIndex],
                detectionTDMM: detectionTDMM
            ) else {
                continue
            }

            if candidate.cost < bestCost {
                bestCost = candidate.cost
                bestDetectionIndex = detectionIndex
            }
        }

        if let bestDetectionIndex {
            return detections[bestDetectionIndex]
        }

        return detections.max { lhs, rhs in
            previewIntersectionOverUnion(lhs.bbox, trackedFace.bbox) <
                previewIntersectionOverUnion(rhs.bbox, trackedFace.bbox)
        }
    }

    func previewIntersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        if intersection.isNull || intersection.isEmpty { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    func interpolate(from previous: CGRect, to current: CGRect, factor: CGFloat) -> CGRect {
        CGRect(
            x: previous.origin.x + (current.origin.x - previous.origin.x) * factor,
            y: previous.origin.y + (current.origin.y - previous.origin.y) * factor,
            width: previous.width + (current.width - previous.width) * factor,
            height: previous.height + (current.height - previous.height) * factor
        )
    }
}

enum CameraFacing: String, CaseIterable, Identifiable {
    case front
    case back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front:
            return "전면 카메라"
        case .back:
            return "후면 카메라"
        }
    }

    var capturePosition: AVCaptureDevice.Position {
        switch self {
        case .front:
            return .front
        case .back:
            return .back
        }
    }
}

enum PrivacyMenuMode: String, CaseIterable, Identifiable {
    case avatar
    case mosaic
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .avatar:
            return "아바타"
        case .mosaic:
            return "블러"
        case .disabled:
            return "비활성화"
        }
    }
}
