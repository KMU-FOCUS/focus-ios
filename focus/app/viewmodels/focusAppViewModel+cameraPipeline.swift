//
//  focusAppViewModel+cameraPipeline.swift
//  focus
//
//  Created by Codex on 4/11/26.
//

import SwiftUI
import AVFoundation

extension FocusAppViewModel {
    func startPreviewIfPossible() {
        cameraManager.startRunning()
        isCameraRunning = true
    }

    func setupCameraRouter() {
        cameraManager.router.onVideoSample = { [weak self] sampleBuffer in
            guard let self else { return }

            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let sourceSize = CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )

                Task { @MainActor in
                    self.previewRuntime.latestPixelBuffer = pixelBuffer
                    self.previewSourceSize = sourceSize
                }
            }

            if let pipelineController = self.pipelineController {
                if self.isRunning {
                    pipelineController.processVideoSampleBuffer(sampleBuffer)
                } else {
                    pipelineController.processPreviewSampleBuffer(sampleBuffer)
                }
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

    func buildPipelineIfPossible() {
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

            let tracker = previewRuntime.faceTracker
            let stateMachine = previewRuntime.trackStateMachine
            let frameProcessor = FocusFrameProcessor(
                detector: detector,
                tdmmInferencer: tdmmInferencer,
                tracker: tracker,
                stateMachine: stateMachine,
                arcFaceExtractor: arcFaceExtractor
            )
            let pipeline = FocusPipelineController(
                frameProcessor: frameProcessor,
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

            pipeline.onDebugSnapshot = { [weak self] (snapshot: PipelineDebugSnapshot) in
                guard let self else { return }
                Task { @MainActor in
                    self.processedFrameCount = snapshot.frameIndex
                }
            }

            pipeline.onStateChanged = { (newState: PipelineState) in
                FocusLogger.info("pipeline state: \(newState)", category: .pipeline)
            }

            pipeline.onPreviewFrame = { [weak self] (pixelBuffer: CVPixelBuffer, trackedFaces: [TrackedFace]) in
                guard let self else { return }
                Task { @MainActor in
                    self.previewTrackedFaces = self.sanitizedTracksForCurrentOwners(trackedFaces)
                    self.previewSourceSize = CGSize(
                        width: CVPixelBufferGetWidth(pixelBuffer),
                        height: CVPixelBufferGetHeight(pixelBuffer)
                    )
                }
            }

            pipeline.onSessionFinished = { [weak self] (outputs: PipelineSessionOutputs) in
                guard let self else { return }
                Task { @MainActor in
                    self.isRecording = false
                    self.metadataConnected = false
                    self.sessionID = nil
                    self.lastRecordingURL = outputs.recordingURL
                    self.lastMetadataURL = outputs.metadataURL

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

    func refreshOwnerProfiles(showSuccessIfPending: Bool = false) {
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

    func clearPreviewTrackingState() {
        previewTrackedFaces.removeAll()
        previewSourceSize = .zero
        pipelineController?.resetAnalysisState()
        previewRuntime.reset()
    }

    func previewFaceOverlays(for previewSize: CGSize) -> [PreviewFaceOverlay] {
        let visibleTracks = overlayPreviewTracks()
        guard !visibleTracks.isEmpty else { return [] }

        let rects = previewRuntime.hitTester.mappedTrackRects(
            tracks: visibleTracks,
            previewSize: previewSize,
            sourceSize: previewSourceSize,
            isMirrored: cameraFacing == .front
        )

        let labelByTrackID: [Int: TrackLabel] = Dictionary(
            uniqueKeysWithValues: visibleTracks.map { ($0.trackID, $0.label) }
        )

        return rects.compactMap { rect in
            guard let label = labelByTrackID[rect.trackID] else { return nil }
            return PreviewFaceOverlay(trackID: rect.trackID, rect: rect.rect, label: label)
        }
    }

}
