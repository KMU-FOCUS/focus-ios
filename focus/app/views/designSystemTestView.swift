//
//  designSystemTestView.swift
//  focus
//
//  Created by Codex on 4/1/26.
//

import SwiftUI
import AVFoundation

struct DesignSystemTestView: View {
    @StateObject private var viewModel = FocusAppViewModel()
    @State private var isMenuPresented = false
    @State private var ownerProfiles = PreviewOwnerProfile.samples

    var body: some View {
        ZStack {
            cameraBackgroundLayer
            cameraDimLayer
            cameraGuideLayer

            if isMenuPresented {
                menuBackdrop
            }
        }
        .overlay(alignment: .topLeading) {
            topStatusCluster
                .padding(.top, 18)
                .padding(.leading, 22)
        }
        .overlay(alignment: .topTrailing) {
            menuButton
                .padding(.top, 22)
                .padding(.trailing, 22)
        }
        .overlay(alignment: .bottomTrailing) {
            overlayContent
                .padding(.trailing, 24)
                .padding(.bottom, 26)
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

private extension DesignSystemTestView {
    var cameraBackgroundLayer: some View {
        Group {
            if viewModel.isCameraReady {
                PortraitLockedCameraPreview(session: viewModel.cameraSession)
            } else {
                LinearGradient(
                    colors: [
                        PreviewTheme.cameraFallbackTop,
                        PreviewTheme.cameraFallbackBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }

    var cameraDimLayer: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.22),
                Color.black.opacity(0.10),
                Color.black.opacity(0.28)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    var cameraGuideLayer: some View {
        EmptyView()
    }

    var topStatusCluster: some View {
        HStack(spacing: 8) {
            if viewModel.isRunning {
                liveStatusChip
            }

            previewChip(
                icon: "dot.radiowaves.left.and.right",
                title: viewModel.isCameraReady ? "Camera Ready" : "Camera Loading"
            )

            previewChip(
                icon: privacyIconName(for: viewModel.privacyMode),
                title: viewModel.privacyMode.title
            )
        }
    }

    var overlayContent: some View {
        mainActionButton
    }

    var menuBackdrop: some View {
        Color.black.opacity(0.32)
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
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PreviewTheme.primary.opacity(0.78))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    var menuPanel: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    panelHeader

                    Divider()
                        .overlay(PreviewTheme.border)

                    ownerSection

                    cameraToggleSection

                    privacyToggleSection
                }
                .padding(.top, 30)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: min(396, max(328, geometry.size.width * 0.40)))
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.white.opacity(0.92))
                    .background(.ultraThinMaterial)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(PreviewTheme.border)
                    .frame(width: 1)
            }
            .shadow(color: Color.black.opacity(0.16), radius: 26, x: -10, y: 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .ignoresSafeArea()
    }

    var panelHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jisang Lee")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(PreviewTheme.text)
        }
    }

    var ownerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(PreviewTheme.primary.opacity(0.74))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Owner 관리")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(PreviewTheme.text)

                    Text("화면에 그대로 유지할 스트리머 프로필")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PreviewTheme.text.opacity(0.62))
                }
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

    func ownerCard(for profile: PreviewOwnerProfile) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(profile.name)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .padding(12)
                }

            Button {
                ownerProfiles.removeAll { $0.id == profile.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PreviewTheme.text.opacity(0.82))
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 120, height: 136)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PreviewTheme.border, lineWidth: 1)
        )
    }

    var cameraToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("카메라 전환")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PreviewTheme.text.opacity(0.68))

            PreviewSelectionBar(
                items: CameraFacing.allCases,
                selection: viewModel.cameraFacing,
                title: { $0.title },
                onSelect: { viewModel.switchCamera(to: $0) }
            )
        }
    }

    var privacyToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("개인정보 처리")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PreviewTheme.text.opacity(0.68))

            PreviewSelectionBar(
                items: PrivacyMenuMode.allCases,
                selection: viewModel.privacyMode,
                title: { $0.title },
                onSelect: { viewModel.setPrivacyMode($0) }
            )
        }
    }

    var mainActionButton: some View {
        Button {
            viewModel.toggleSession()
        } label: {
            Text(viewModel.isRunning ? "방송 종료하기" : "방송 시작하기")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .frame(height: 60)
            .background(
                LinearGradient(
                    colors: [
                        viewModel.isRunning ? PreviewTheme.stop : PreviewTheme.cta,
                        viewModel.isRunning ? PreviewTheme.stopBright : PreviewTheme.ctaBright
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(
                color: (viewModel.isRunning ? PreviewTheme.stop : PreviewTheme.cta).opacity(0.34),
                radius: 18,
                x: 0,
                y: 12
            )
        }
        .buttonStyle(.plain)
    }

    var liveStatusChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)

            Text("LIVE")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(PreviewTheme.live)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: PreviewTheme.live.opacity(0.34), radius: 12, x: 0, y: 6)
    }

    func previewChip(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.22))
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    func previewPanelChip(icon: String, title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(PreviewTheme.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(PreviewTheme.primary.opacity(0.10))
        )
    }

    func privacyIconName(for mode: PrivacyMenuMode) -> String {
        switch mode {
        case .avatar:
            return "sparkles.rectangle.stack.fill"
        case .mosaic:
            return "circle.grid.2x2.fill"
        case .disabled:
            return "eye.slash.fill"
        }
    }
}

private struct PreviewOwnerProfile: Identifiable {
    let id = UUID()
    let name: String
    let initials: String
    let colors: [Color]

    static let samples: [PreviewOwnerProfile] = [
        PreviewOwnerProfile(
            name: "Jisang",
            initials: "JL",
            colors: [PreviewTheme.primary, PreviewTheme.secondary]
        ),
        PreviewOwnerProfile(
            name: "Minsu",
            initials: "MS",
            colors: [Color(red: 0.13, green: 0.55, blue: 0.39), Color(red: 0.18, green: 0.76, blue: 0.42)]
        ),
        PreviewOwnerProfile(
            name: "Dylan",
            initials: "DL",
            colors: [Color(red: 0.18, green: 0.35, blue: 0.56), Color(red: 0.06, green: 0.65, blue: 0.91)]
        )
    ]
}

private struct PreviewSelectionBar<Item: Identifiable & Hashable>: View {
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
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PreviewTheme.text.opacity(0.90))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background {
                            if item == selection {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: PreviewTheme.primary.opacity(0.12), radius: 12, x: 0, y: 6)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(PreviewTheme.surfaceMuted)
        )
    }
}

private enum PreviewTheme {
    static let primary = Color(red: 3.0 / 255.0, green: 105.0 / 255.0, blue: 161.0 / 255.0)
    static let secondary = Color(red: 14.0 / 255.0, green: 165.0 / 255.0, blue: 233.0 / 255.0)
    static let cta = Color(red: 34.0 / 255.0, green: 197.0 / 255.0, blue: 94.0 / 255.0)
    static let ctaBright = Color(red: 61.0 / 255.0, green: 220.0 / 255.0, blue: 120.0 / 255.0)
    static let stop = Color(red: 214.0 / 255.0, green: 48.0 / 255.0, blue: 49.0 / 255.0)
    static let stopBright = Color(red: 239.0 / 255.0, green: 82.0 / 255.0, blue: 84.0 / 255.0)
    static let live = Color(red: 255.0 / 255.0, green: 78.0 / 255.0, blue: 79.0 / 255.0)
    static let text = Color(red: 12.0 / 255.0, green: 74.0 / 255.0, blue: 110.0 / 255.0)
    static let border = Color(red: 215.0 / 255.0, green: 234.0 / 255.0, blue: 245.0 / 255.0)
    static let surfaceMuted = Color(red: 243.0 / 255.0, green: 249.0 / 255.0, blue: 253.0 / 255.0)
    static let cameraFallbackTop = Color(red: 15.0 / 255.0, green: 42.0 / 255.0, blue: 58.0 / 255.0)
    static let cameraFallbackBottom = Color(red: 6.0 / 255.0, green: 20.0 / 255.0, blue: 29.0 / 255.0)
}

struct DesignSystemTestView_Previews: PreviewProvider {
    static var previews: some View {
        DesignSystemTestView()
            .previewInterfaceOrientation(.landscapeRight)
    }
}
