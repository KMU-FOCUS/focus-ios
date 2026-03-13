//
//  contentView.swift
//  focus
//
//  Created by 이동언 on 3/7/26.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var viewModel = FocusAppViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    headerSection
                    previewSection
                    statusSection
                    controlSection
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.prepareCameraIfNeeded()
            }
            .alert("오류", isPresented: $viewModel.showErrorAlert) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "알 수 없는 오류")
            }
        }
    }
}

// MARK: - UI Sections
private extension ContentView {
    var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOCUS")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text("스트리머는 그대로, 배경 인물은 안전하게")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text("초상권 걱정 없는 스마트 라이브 스트리밍")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var previewSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.08))

            if viewModel.isCameraReady {
                CameraPreviewView(session: viewModel.cameraSession)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.85))

                    Text("카메라 프리뷰 영역")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Text(viewModel.cameraStatusText)
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding()
            }
        }
        .frame(height: 360)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    var statusSection: some View {
        VStack(spacing: 12) {
            statusRow(title: "세션 상태", value: viewModel.sessionStateText)
            statusRow(title: "카메라 상태", value: viewModel.cameraRunningText)
            statusRow(title: "세션 ID", value: viewModel.sessionIDText)
            statusRow(title: "프레임 수", value: "\(viewModel.processedFrameCount)")
            statusRow(title: "메타데이터 전송", value: viewModel.metadataStateText)
            statusRow(title: "저장 상태", value: viewModel.recordingStateText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
    }

    var controlSection: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.toggleSession()
            } label: {
                Text(viewModel.isRunning ? "세션 종료" : "세션 시작")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                    )
            }

            Button {
                viewModel.resetDebugState()
            } label: {
                Text("상태 초기화")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.08))
                    )
            }
        }
    }
}

// MARK: - ViewModel
@MainActor
final class FocusAppViewModel: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var sessionID: String?
    @Published var processedFrameCount: Int = 0
    @Published var metadataConnected: Bool = false
    @Published var isRecording: Bool = false

    @Published var isCameraReady: Bool = false
    @Published var isCameraRunning: Bool = false
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String?

    let cameraManager = CameraSessionManager()

    private var pipelineController: FocusPipelineController?
    private let recorder = LocalRecorder()
    private let timestampCorrector = MonotonicTimestampCorrector()

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
        setupCameraRouter()
    }

    func prepareCameraIfNeeded() async {
        guard !isCameraReady else { return }

        let granted = await cameraManager.requestPermissionsIfNeeded()
        guard granted else {
            handleError("카메라 또는 마이크 권한이 거부되었습니다.")
            return
        }

        await withCheckedContinuation { continuation in
            cameraManager.configureSession(cameraPosition: .front) { [weak self] result in
                guard let self else {
                    continuation.resume()
                    return
                }

                switch result {
                case .success:
                    self.isCameraReady = true
                    self.buildPipelineIfPossible()
                case .failure(let error):
                    self.handleError(error.localizedDescription)
                }
                continuation.resume()
            }
        }
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

        do {
            try pipelineController.start(sessionID: newSessionID)
        } catch {
            handleError(error.localizedDescription)
            return
        }

        isRunning = true
        isRecording = true
        metadataConnected = false
        sessionID = newSessionID

        cameraManager.startRunning()
        isCameraRunning = true
    }

    func stopSession() {
        isRunning = false
        isRecording = false
        metadataConnected = false

        pipelineController?.stop()

        cameraManager.stopRunning()
        isCameraRunning = false
    }

    func resetDebugState() {
        processedFrameCount = 0
        if !isRunning {
            sessionID = nil
        }
    }

    private func setupCameraRouter() {
        cameraManager.router.onVideoSample = { [weak self] sampleBuffer in
            guard let self else { return }

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
                inputSize: 320,
                scoreThreshold: 0.5,
                nmsThreshold: 0.3,
                topK: 5000
            )

            let tdmmInferencer = try Facial3DMMTFLiteService(
                modelFileName: "facemap_3dmm-facial-landmark-detection-float",
                modelFileExtension: "tflite"
            )

            let arcFaceExtractor: ArcFaceONNXService? = nil
            let tracker = FaceTracker()

            let dummyOwnerEmbedding = Array(repeating: Float(0), count: 512)
            let stateMachine = TrackStateMachine(ownerReferenceEmbedding: dummyOwnerEmbedding)

            let pipeline = FocusPipelineController(
                detector: detector,
                tdmmInferencer: tdmmInferencer,
                arcFaceExtractor: arcFaceExtractor,
                tracker: tracker,
                stateMachine: stateMachine,
                recorder: recorder,
                timestampCorrector: timestampCorrector,
                maskRenderer: PrivacyMaskRenderer()
            )

            pipeline.onDebugSnapshot = { [weak self] snapshot in
                guard let self else { return }
                Task { @MainActor in
                    self.processedFrameCount = snapshot.frameIndex
                }
            }

            pipeline.onStateChanged = { newState in
                print("[Pipeline State] \(newState)")
            }

            pipeline.onPreviewFrame = { _, trackedFaces in
                print("[Pipeline Preview] tracked faces: \(trackedFaces.count)")
            }

            self.pipelineController = pipeline
        } catch {
            handleError("파이프라인 생성 실패: \(error.localizedDescription)")
        }
    }

    private func handleError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}

#Preview {
    ContentView()
}
