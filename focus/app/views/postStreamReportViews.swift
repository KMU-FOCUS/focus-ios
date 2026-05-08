//
//  postStreamReportViews.swift
//  focus
//
//  Created by Codex on 5/6/26.
//

import SwiftUI

struct PostStreamReportSummarySheetView: View {
    let report: PostStreamAnalysisReport
    let onClose: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                capsuleHandle
                summaryHeader
                metaCards
                summarySection
                bulletSection("잘한 점", items: report.strengths, accent: ReportTheme.positive)
                bulletSection("아쉬운 점", items: report.weaknesses, accent: ReportTheme.warning)
                bulletSection("다음 방송 팁", items: report.actionItems, accent: ReportTheme.primary)
                statsRow

                Button(action: onClose) {
                    Text("닫기")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(ReportTheme.text.opacity(0.74))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(ReportTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .background(ReportTheme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    var capsuleHandle: some View {
        Capsule()
            .fill(ReportTheme.border)
            .frame(width: 56, height: 6)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(report.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(ReportTheme.text)

                    Text("방송 종료 직후 확인할 수 있는 AI 요약 리포트")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(ReportTheme.text.opacity(0.58))
                }

                Spacer(minLength: 12)

                statusBadge(report.analysisStatus)
            }
        }
    }

    var metaCards: some View {
        HStack(spacing: 12) {
            reportInfoCard(
                icon: "clock.fill",
                title: "방송 길이",
                value: report.durationSec.durationLabel
            )

            reportInfoCard(
                icon: "checkmark.seal.fill",
                title: "분석 상태",
                value: report.analysisStatus.title
            )
        }
    }

    var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("요약")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(ReportTheme.text)

            Text(report.summary)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(ReportTheme.text.opacity(0.78))
                .lineSpacing(4)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ReportTheme.border, lineWidth: 1)
        )
    }

    func bulletSection(_ title: String, items: [String], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(ReportTheme.text)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(accent)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        Text(item)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(ReportTheme.text.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ReportTheme.border, lineWidth: 1)
        )
    }

    var statsRow: some View {
        HStack(spacing: 12) {
            metricCard(
                title: "보호 처리",
                value: "\(report.totalReplacedFaceCount)",
                subtitle: "얼굴 수"
            )
            metricCard(
                title: "최대 혼잡도",
                value: "\(report.maxSimultaneousCrowdCount)",
                subtitle: "동시 인원"
            )
            metricCard(
                title: "하이라이트",
                value: "\(report.highlightCount)",
                subtitle: "추천 구간"
            )
        }
    }

    func reportInfoCard(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(ReportTheme.primary)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(ReportTheme.primary.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(ReportTheme.text.opacity(0.54))

                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(ReportTheme.text)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ReportTheme.border, lineWidth: 1)
        )
    }

    func metricCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ReportTheme.text.opacity(0.54))

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(ReportTheme.text)

            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(ReportTheme.text.opacity(0.60))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ReportTheme.border, lineWidth: 1)
        )
    }
}

private func statusBadge(_ status: PostStreamAnalysisStatus) -> some View {
    Text(status.title)
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(status.badgeTextColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(status.badgeBackgroundColor)
        )
}

private enum ReportTheme {
    static let canvas = Color(red: 244.0 / 255.0, green: 249.0 / 255.0, blue: 252.0 / 255.0)
    static let text = Color(red: 16.0 / 255.0, green: 47.0 / 255.0, blue: 67.0 / 255.0)
    static let border = Color(red: 214.0 / 255.0, green: 232.0 / 255.0, blue: 242.0 / 255.0)
    static let primary = Color(red: 3.0 / 255.0, green: 105.0 / 255.0, blue: 161.0 / 255.0)
    static let primaryBright = Color(red: 14.0 / 255.0, green: 165.0 / 255.0, blue: 233.0 / 255.0)
    static let positive = Color(red: 21.0 / 255.0, green: 128.0 / 255.0, blue: 61.0 / 255.0)
    static let warning = Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 6.0 / 255.0)
}

private extension PostStreamAnalysisStatus {
    var badgeBackgroundColor: Color {
        switch self {
        case .processing:
            return ReportTheme.primary.opacity(0.12)
        case .succeeded:
            return ReportTheme.positive.opacity(0.12)
        case .failed:
            return Color.red.opacity(0.12)
        }
    }

    var badgeTextColor: Color {
        switch self {
        case .processing:
            return ReportTheme.primary
        case .succeeded:
            return ReportTheme.positive
        case .failed:
            return .red
        }
    }
}

private extension Int {
    var durationLabel: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private extension Date {
    var reportGeneratedLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd HH:mm 생성"
        return formatter.string(from: self)
    }
}
