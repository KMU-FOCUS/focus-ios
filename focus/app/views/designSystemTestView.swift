//
//  designSystemTestView.swift
//  focus
//
//  Created by Codex on 3/31/26.
//

import SwiftUI

struct DesignSystemTestView: View {
    @State private var selectedMode: PrivacyModeKind = .avatar

    private let modes: [PrivacyModePreview] = [
        PrivacyModePreview(
            kind: .avatar,
            title: "Avatar",
            shortTitle: "기본 권장",
            description: "배경 인물을 자연스러운 아바타로 치환해 방송 흐름을 유지합니다.",
            icon: "sparkles.rectangle.stack.fill",
            tint: FocusDesignTheme.primary,
            softTint: FocusDesignTheme.primarySoft
        ),
        PrivacyModePreview(
            kind: .blur,
            title: "Blur",
            shortTitle: "빠른 익명화",
            description: "현장 분위기는 남기고 얼굴 식별 정보만 부드럽게 흐립니다.",
            icon: "circle.grid.2x2.fill",
            tint: FocusDesignTheme.secondary,
            softTint: FocusDesignTheme.secondarySoft
        ),
        PrivacyModePreview(
            kind: .off,
            title: "Off",
            shortTitle: "보조 옵션",
            description: "보호를 비활성화합니다. 기본 경로가 아닌 조용한 보조 설정입니다.",
            icon: "eye.slash.fill",
            tint: FocusDesignTheme.disabled,
            softTint: FocusDesignTheme.disabledSoft
        )
    ]

    private var selectedModePreview: PrivacyModePreview {
        modes.first(where: { $0.kind == selectedMode }) ?? modes[0]
    }

    private var protectedCount: Int {
        selectedMode == .off ? 0 : 2
    }

    private var protectionSummary: String {
        switch selectedMode {
        case .avatar:
            return "배경 인물 2명 아바타 보호 중"
        case .blur:
            return "배경 인물 2명 블러 보호 중"
        case .off:
            return "배경 인물 보호 비활성"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                shellBackground
                cameraFeed(in: geometry.size)

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 18)
                        .padding(.top, 14)

                    Spacer()
                }

                VStack(spacing: 0) {
                    Spacer()

                    bottomPanel
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.22), value: selectedMode)
    }
}

private extension DesignSystemTestView {
    var shellBackground: some View {
        LinearGradient(
            colors: [
                FocusDesignTheme.shellTop,
                FocusDesignTheme.shellBottom
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    func cameraFeed(in size: CGSize) -> some View {
        ZStack {
            cameraBackdrop
            cityGlowLayer
            streetBaseLayer
            focusFrame
            bystanderSubjects(in: size)
            ownerSubject
            centerStatusBanner
            lowerCameraHints
        }
        .padding(.horizontal, 12)
        .padding(.top, 78)
        .padding(.bottom, 228)
    }

    var cameraBackdrop: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        FocusDesignTheme.cameraTop,
                        FocusDesignTheme.cameraMiddle,
                        FocusDesignTheme.cameraBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 30, x: 0, y: 20)
    }

    var cityGlowLayer: some View {
        ZStack {
            Circle()
                .fill(FocusDesignTheme.secondary.opacity(0.22))
                .frame(width: 240, height: 240)
                .blur(radius: 24)
                .offset(x: -96, y: -160)

            Circle()
                .fill(FocusDesignTheme.primary.opacity(0.18))
                .frame(width: 210, height: 210)
                .blur(radius: 20)
                .offset(x: 110, y: -70)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 160, height: 160)
                .blur(radius: 16)
                .offset(x: 0, y: -120)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    var streetBaseLayer: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<8, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(index.isMultiple(of: 2) ? 0.06 : 0.03))
                            .frame(width: geometry.size.width / 10, height: CGFloat(70 + index * 16))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.28)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    var focusFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [10, 10]))
                .frame(width: 214, height: 286)

            cornerBracket
                .rotationEffect(.degrees(0))
                .offset(x: -92, y: -128)

            cornerBracket
                .rotationEffect(.degrees(90))
                .offset(x: 92, y: -128)

            cornerBracket
                .rotationEffect(.degrees(-90))
                .offset(x: -92, y: 128)

            cornerBracket
                .rotationEffect(.degrees(180))
                .offset(x: 92, y: 128)
        }
        .offset(y: 8)
    }

    var cornerBracket: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 34))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 34, y: 0))
        }
        .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .frame(width: 34, height: 34)
    }

    func bystanderSubjects(in size: CGSize) -> some View {
        ZStack {
            bystanderCard(
                title: "Bystander",
                subtitle: bystanderSubtitle,
                tint: selectedModePreview.tint,
                fill: bystanderFill(opacity: 0.92),
                border: bystanderBorder,
                icon: selectedModePreview.icon,
                style: selectedMode
            )
            .frame(width: 118, height: 144)
            .offset(x: -112, y: -16)

            bystanderCard(
                title: "Bystander",
                subtitle: bystanderSubtitle,
                tint: selectedModePreview.tint,
                fill: bystanderFill(opacity: 0.84),
                border: bystanderBorder.opacity(0.84),
                icon: selectedModePreview.icon,
                style: selectedMode
            )
            .frame(width: 110, height: 138)
            .offset(x: 116, y: 18)
        }
    }

    var ownerSubject: some View {
        VStack(spacing: 0) {
            Spacer()

            HStack {
                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        statusChip(
                            title: "Owner 유지",
                            icon: "person.crop.circle.badge.checkmark",
                            fill: Color.white.opacity(0.12),
                            foreground: .white
                        )

                        statusChip(
                            title: "실시간",
                            icon: "dot.radiowaves.left.and.right",
                            fill: FocusDesignTheme.cta.opacity(0.20),
                            foreground: .white
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Jisang Lee")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("스트리머는 화면 그대로 유지되고, 배경 인물만 선택된 보호 모드로 처리됩니다.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .frame(width: 226, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .offset(y: -32)

                Spacer()
            }
        }
        .padding(.bottom, 54)
    }

    var centerStatusBanner: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: selectedModePreview.icon)
                            .font(.system(size: 13, weight: .bold))

                        Text(protectionSummary)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)

                    Text(centerDescription)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                Spacer()
            }

            Spacer()
        }
        .padding(.top, 178)
    }

    var lowerCameraHints: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    statusChip(
                        title: protectedCount == 0 ? "보호 꺼짐" : "시민 \(protectedCount)명 보호 중",
                        icon: protectedCount == 0 ? "eye.slash.fill" : "checkmark.shield.fill",
                        fill: protectedCount == 0 ? FocusDesignTheme.disabled.opacity(0.20) : FocusDesignTheme.cta.opacity(0.20),
                        foreground: .white
                    )

                    Text("감시가 아니라 배려")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    controlPill(icon: "line.3.horizontal.decrease.circle.fill", label: "Owner 관리")
                    controlPill(icon: "slider.horizontal.3", label: "세부 설정")
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                statusChip(
                    title: "LIVE PRIVACY",
                    icon: "shield.fill",
                    fill: FocusDesignTheme.primary.opacity(0.24),
                    foreground: .white
                )

                HStack(spacing: 8) {
                    statusChip(
                        title: selectedModePreview.title,
                        icon: selectedModePreview.icon,
                        fill: Color.white.opacity(0.12),
                        foreground: Color.white.opacity(0.94)
                    )

                    statusChip(
                        title: "00:16",
                        icon: "record.circle.fill",
                        fill: Color.white.opacity(0.12),
                        foreground: .white.opacity(0.94)
                    )
                }
            }

            Spacer()

            HStack(spacing: 10) {
                circularControl(icon: "line.3.horizontal")
                circularControl(icon: "gearshape.fill")
            }
        }
    }

    var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("실시간 보호 상태")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(FocusDesignTheme.text.opacity(0.74))

                    Text(selectedMode == .off ? "현재 보호 비활성" : "현재 \(selectedModePreview.title) 모드 활성")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(FocusDesignTheme.text)
                }

                Spacer()

                statusChip(
                    title: selectedMode == .off ? "주의" : "안정",
                    icon: selectedMode == .off ? "exclamationmark.triangle.fill" : "checkmark.shield.fill",
                    fill: selectedMode == .off ? FocusDesignTheme.warningSoft : FocusDesignTheme.ctaSoft,
                    foreground: selectedMode == .off ? FocusDesignTheme.warning : FocusDesignTheme.cta
                )
            }

            HStack(spacing: 10) {
                summaryTile(
                    icon: "person.crop.square.fill",
                    title: "Streamer",
                    value: "유지",
                    tint: FocusDesignTheme.primary
                )

                summaryTile(
                    icon: selectedModePreview.icon,
                    title: "Bystanders",
                    value: selectedMode == .off ? "Off" : "\(protectedCount) protected",
                    tint: selectedModePreview.tint
                )

                summaryTile(
                    icon: "hand.raised.fill",
                    title: "Tone",
                    value: "배려 중심",
                    tint: FocusDesignTheme.text
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("프라이버시 모드")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(FocusDesignTheme.text)

                HStack(spacing: 10) {
                    ForEach(modes) { mode in
                        Button {
                            selectedMode = mode.kind
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(mode.softTint)

                                        Image(systemName: mode.icon)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(mode.tint)
                                    }
                                    .frame(width: 36, height: 36)

                                    Spacer(minLength: 0)
                                }

                                Text(mode.title)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(FocusDesignTheme.text)

                                Text(mode.shortTitle)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(mode.tint)

                                Text(mode.description)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(FocusDesignTheme.text.opacity(0.68))
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(selectedMode == mode.kind ? mode.softTint.opacity(0.72) : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(selectedMode == mode.kind ? mode.tint : FocusDesignTheme.border, lineWidth: selectedMode == mode.kind ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("스트리머는 흐름을 잃지 않고, 시민은 노출 불안 없이 지나갈 수 있는 상태를 기본 경험으로 둡니다.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(FocusDesignTheme.text.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    quietButton(title: "Owner 관리", icon: "person.crop.circle.badge.plus")
                    quietButton(title: "상세 설정", icon: "slider.horizontal.3")
                }

                Button(action: {}) {
                    HStack {
                        Text("보호된 상태로 방송 준비하기")
                        Spacer()
                        Image(systemName: "play.fill")
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
                    .background(FocusDesignTheme.cta)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.54), lineWidth: 1)
        )
        .shadow(color: FocusDesignTheme.primary.opacity(0.16), radius: 24, x: 0, y: 18)
    }

    var bystanderSubtitle: String {
        switch selectedMode {
        case .avatar:
            return "Avatar"
        case .blur:
            return "Blur"
        case .off:
            return "Off"
        }
    }

    var centerDescription: String {
        switch selectedMode {
        case .avatar:
            return "기본 권장 모드. 시민 노출 부담을 줄이면서도 방송 맥락은 유지합니다."
        case .blur:
            return "빠른 익명화 모드. 현실감을 남기고 얼굴 식별 정보만 흐립니다."
        case .off:
            return "보호가 꺼져 있습니다. 기본 경로보다는 예외적 사용을 전제로 합니다."
        }
    }

    var bystanderBorder: Color {
        switch selectedMode {
        case .avatar:
            return Color.white.opacity(0.24)
        case .blur:
            return FocusDesignTheme.secondary.opacity(0.65)
        case .off:
            return FocusDesignTheme.disabled.opacity(0.68)
        }
    }

    func bystanderFill(opacity: Double) -> Color {
        switch selectedMode {
        case .avatar:
            return FocusDesignTheme.primary.opacity(opacity)
        case .blur:
            return FocusDesignTheme.secondary.opacity(opacity * 0.82)
        case .off:
            return Color.white.opacity(0.12)
        }
    }

    func bystanderCard(
        title: String,
        subtitle: String,
        tint: Color,
        fill: Color,
        border: Color,
        icon: String,
        style: PrivacyModeKind
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(fill)

            switch style {
            case .avatar:
                LinearGradient(
                    colors: [FocusDesignTheme.primary.opacity(0.92), FocusDesignTheme.secondary.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            case .blur:
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(fill)

                    VStack(spacing: 7) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                                .frame(height: 10)
                                .blur(radius: 2.2)
                        }
                    }
                    .padding(.horizontal, 14)
                }

            case .off:
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.10))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()

                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(style == .off ? Color.white.opacity(0.74) : .white)
                }

                Spacer()

                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))
            }
            .padding(14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(border, lineWidth: 1.2)
        )
        .shadow(color: tint.opacity(0.18), radius: 12, x: 0, y: 10)
    }

    func statusChip(title: String, icon: String, fill: Color, foreground: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(fill)
        .clipShape(Capsule())
    }

    func controlPill(icon: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))

            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }

    func circularControl(icon: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))

            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
    }

    func summaryTile(icon: String, title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(FocusDesignTheme.text.opacity(0.68))

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(FocusDesignTheme.text)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(FocusDesignTheme.surfaceMuted)
        )
    }

    func quietButton(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))

            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(FocusDesignTheme.primary)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FocusDesignTheme.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FocusDesignTheme.border, lineWidth: 1)
        )
    }
}

private enum PrivacyModeKind: String {
    case avatar
    case blur
    case off
}

private struct PrivacyModePreview: Identifiable {
    let kind: PrivacyModeKind
    let title: String
    let shortTitle: String
    let description: String
    let icon: String
    let tint: Color
    let softTint: Color

    var id: PrivacyModeKind { kind }
}

private enum FocusDesignTheme {
    static let primary = Color(red: 3.0 / 255.0, green: 105.0 / 255.0, blue: 161.0 / 255.0)
    static let secondary = Color(red: 14.0 / 255.0, green: 165.0 / 255.0, blue: 233.0 / 255.0)
    static let cta = Color(red: 34.0 / 255.0, green: 197.0 / 255.0, blue: 94.0 / 255.0)
    static let warning = Color(red: 245.0 / 255.0, green: 158.0 / 255.0, blue: 11.0 / 255.0)
    static let disabled = Color(red: 148.0 / 255.0, green: 163.0 / 255.0, blue: 184.0 / 255.0)
    static let text = Color(red: 12.0 / 255.0, green: 74.0 / 255.0, blue: 110.0 / 255.0)
    static let border = Color(red: 215.0 / 255.0, green: 234.0 / 255.0, blue: 245.0 / 255.0)
    static let background = Color(red: 240.0 / 255.0, green: 249.0 / 255.0, blue: 255.0 / 255.0)

    static let primarySoft = primary.opacity(0.14)
    static let secondarySoft = secondary.opacity(0.14)
    static let ctaSoft = cta.opacity(0.14)
    static let warningSoft = warning.opacity(0.16)
    static let disabledSoft = disabled.opacity(0.18)
    static let surfaceMuted = Color(red: 246.0 / 255.0, green: 251.0 / 255.0, blue: 255.0 / 255.0)

    static let shellTop = Color(red: 8.0 / 255.0, green: 29.0 / 255.0, blue: 43.0 / 255.0)
    static let shellBottom = Color(red: 3.0 / 255.0, green: 15.0 / 255.0, blue: 24.0 / 255.0)

    static let cameraTop = Color(red: 17.0 / 255.0, green: 54.0 / 255.0, blue: 76.0 / 255.0)
    static let cameraMiddle = Color(red: 12.0 / 255.0, green: 39.0 / 255.0, blue: 57.0 / 255.0)
    static let cameraBottom = Color(red: 8.0 / 255.0, green: 26.0 / 255.0, blue: 38.0 / 255.0)
}

struct DesignSystemTestView_Previews: PreviewProvider {
    static var previews: some View {
        DesignSystemTestView()
    }
}
