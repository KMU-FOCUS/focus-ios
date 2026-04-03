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
    @State private var isMenuPresented = false
    @State private var ownerProfiles = OwnerProfile.samples

    var body: some View {
        ZStack {
            cameraBackgroundLayer
            cameraDimLayer

            if isMenuPresented {
                menuBackdrop
            }
        }
        .overlay(alignment: .topTrailing) {
            menuButton
                .padding(.top, 24)
                .padding(.trailing, 24)
        }
        .overlay {
            overlayContent
                .allowsHitTesting(!isMenuPresented)
        }
        .overlay(alignment: .trailing) {
            if isMenuPresented {
                menuPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.24), value: isMenuPresented)
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

// MARK: - UI Sections
private extension ContentView {
    var cameraBackgroundLayer: some View {
        Group {
            if viewModel.isCameraReady {
                PortraitLockedCameraPreview(session: viewModel.cameraSession)
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
    }

    var cameraDimLayer: some View {
        Color.black.opacity(0.08)
        .ignoresSafeArea()
    }

    var overlayContent: some View {
        Group {
            if viewModel.isCameraReady {
                mainActionButton
            } else {
                VStack(spacing: 18) {
                    cameraPlaceholderContent
                    mainActionButton
                }
            }
        }
    }

    var menuBackdrop: some View {
        Color.black.opacity(0.28)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                isMenuPresented = false
            }
    }

    var menuButton: some View {
        Button {
            isMenuPresented.toggle()
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.86, green: 0.10, blue: 1.00),
                            Color(red: 0.24, green: 0.12, blue: 1.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    var menuPanel: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Jisang Lee")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black.opacity(0.9))

                    Divider()

                    ownerSection

                    cameraToggleSection

                    privacyToggleSection
                }
                .padding(.top, 30)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: min(380, max(320, geometry.size.width * 0.42)))
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
            .shadow(color: Color.black.opacity(0.14), radius: 26, x: -10, y: 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .ignoresSafeArea()
    }

    var ownerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(Color.black.opacity(0.55))

                Text("Owner 관리")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black.opacity(0.88))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(ownerProfiles) { profile in
                        ownerCard(for: profile)
                    }
                }
                .padding(.trailing, 8)
            }
        }
    }

    func ownerCard(for profile: OwnerProfile) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: profile.colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Spacer()

                        Text(profile.initials)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)

                        Text(profile.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                    }
                    .padding(12)
                }

            Button {
                ownerProfiles.removeAll { $0.id == profile.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black.opacity(0.9))
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 116, height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    var cameraToggleSection: some View {
        SelectionBar(
            items: CameraFacing.allCases,
            selection: viewModel.cameraFacing,
            title: { $0.title },
            onSelect: { viewModel.switchCamera(to: $0) }
        )
    }

    var privacyToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("개인정보 처리")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black.opacity(0.6))

            SelectionBar(
                items: PrivacyMenuMode.allCases,
                selection: viewModel.privacyMode,
                title: { $0.title },
                onSelect: { viewModel.setPrivacyMode($0) }
            )
        }
    }

    var cameraPlaceholderContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.fill")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.85))

            Text("카메라 프리뷰 준비 중")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text(viewModel.cameraStatusText)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.72))
        }
        .padding(.horizontal, 24)
    }

    var mainActionButton: some View {
        Button {
            viewModel.toggleSession()
        } label: {
            Text(viewModel.isRunning ? "방송 종료하기" : "방송 준비하기")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 38)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.86, green: 0.10, blue: 1.00),
                            Color(red: 0.24, green: 0.12, blue: 1.00)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 10)
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
    @Published var cameraFacing: CameraFacing = .front
    @Published var privacyMode: PrivacyMenuMode = .avatar

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
                self.startPreviewIfPossible()
            case .failure(let error):
                self.handleError(error.localizedDescription)
            }
        }
    }

    func setPrivacyMode(_ mode: PrivacyMenuMode) {
        privacyMode = mode
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

        startPreviewIfPossible()
    }

    func stopSession() {
        isRunning = false
        isRecording = false
        metadataConnected = false

        pipelineController?.stop()
    }

    func resetDebugState() {
        processedFrameCount = 0
        if !isRunning {
            sessionID = nil
        }
    }

    private func startPreviewIfPossible() {
        cameraManager.startRunning()
        isCameraRunning = true
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

private struct OwnerProfile: Identifiable {
    let id = UUID()
    let name: String
    let initials: String
    let colors: [Color]

    static let samples: [OwnerProfile] = [
        OwnerProfile(
            name: "Jisang",
            initials: "JL",
            colors: [Color(red: 0.97, green: 0.50, blue: 0.58), Color(red: 0.79, green: 0.16, blue: 0.39)]
        ),
        OwnerProfile(
            name: "Minsu",
            initials: "MS",
            colors: [Color(red: 0.98, green: 0.78, blue: 0.52), Color(red: 0.78, green: 0.49, blue: 0.23)]
        ),
        OwnerProfile(
            name: "Dylan",
            initials: "DL",
            colors: [Color(red: 0.57, green: 0.65, blue: 0.77), Color(red: 0.29, green: 0.36, blue: 0.51)]
        )
    ]
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

private struct SelectionBar<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let selection: Item
    let title: (Item) -> String
    let onSelect: (Item) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    Text(title(item))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background {
                            if item == selection {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 6)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.94, green: 0.94, blue: 0.95))
        )
    }
}
