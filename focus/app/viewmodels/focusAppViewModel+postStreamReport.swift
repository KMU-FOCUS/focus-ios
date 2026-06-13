//
//  focusAppViewModel+postStreamReport.swift
//  focus
//
//  Created by Codex on 5/6/26.
//

import AVFoundation

extension FocusAppViewModel {
    func presentPostStreamReport(
        from outputs: PipelineSessionOutputs,
        sessionID: String?,
        broadcastID: String?,
        latestAnalysisResult: BroadcastAnalysisResult?,
        highlightCandidates: [BroadcastHighlightCandidate]?
    ) async {
        let resolvedDuration = await resolvedDurationSec(from: outputs)
        let draftReport = PostStreamAnalysisReport.dummy(
            sessionID: sessionID,
            durationSec: resolvedDuration,
            recordingURL: outputs.recordingURL
        )

        var finalReport = draftReport.updatingBroadcastContext(broadcastID: broadcastID)

        if let latestAnalysisResult {
            finalReport = finalReport.applyingLatestAnalysisResult(latestAnalysisResult)
        }

        if let highlightCandidates {
            finalReport = finalReport.updatingHighlightMoments(
                highlightCandidates.map { $0.toHighlightMoment() }
            )
        }

        completedStreamReport = finalReport
    }

    func dismissCompletedStreamReport() {
        completedStreamReport = nil
        latestAnalysisDebugPayloadText = nil
    }

    func presentReportArchive() {
        archivedStreamReports = PostStreamAnalysisReport.dummyArchive()
        isReportArchivePresented = true
    }

    func dismissReportArchive() {
        isReportArchivePresented = false
    }

    func updateAnalysisDebugPayload(
        latestAnalysisResult: BroadcastAnalysisResult?,
        highlightCandidates: [BroadcastHighlightCandidate]?
    ) {
        latestAnalysisDebugPayloadText = BroadcastAnalysisDebugPayloadFormatter.format(
            latestAnalysisResult: latestAnalysisResult,
            highlightCandidates: highlightCandidates
        )

        guard let payloadText = latestAnalysisDebugPayloadText, !payloadText.isEmpty else {
            return
        }

        FocusLogger.info(
            """
            방송 분석 응답 JSON:
            \(payloadText)
            """,
            category: .network
        )

        if let latestAnalysisJSONText = BroadcastAnalysisDebugPayloadFormatter.formatLatestAnalysisResult(latestAnalysisResult) {
            FocusLogger.info(
                """
                최신 방송 분석 결과 JSON:
                \(latestAnalysisJSONText)
                """,
                category: .network
            )
        }

        if let highlightCandidatesJSONText = BroadcastAnalysisDebugPayloadFormatter.formatHighlightCandidates(highlightCandidates) {
            FocusLogger.info(
                """
                방송 하이라이트 후보 JSON:
                \(highlightCandidatesJSONText)
                """,
                category: .network
            )
        }
    }

    private func resolvedDurationSec(from outputs: PipelineSessionOutputs) async -> Int {
        if let recordingURL = outputs.recordingURL {
            let asset = AVURLAsset(url: recordingURL)
            if let duration = try? await asset.load(.duration) {
                let seconds = Int(round(duration.seconds))
                if seconds > 0 {
                    return seconds
                }
            }
        }

        if processedFrameCount > 0 {
            return max(processedFrameCount / 30, 1)
        }

        return 70
    }

    func fetchLatestBroadcastAnalysisResultIfNeeded(
        broadcastID: String?
    ) async -> BroadcastAnalysisResult? {
        guard let broadcastAnalysisAPIClient else {
            return nil
        }
        guard let broadcastID, !broadcastID.isEmpty else {
            return nil
        }
        guard let accessToken = appTokenStore.getAccessToken(), !accessToken.isEmpty else {
            FocusLogger.warning(
                "최신 방송 분석 결과 조회 건너뜀: 서버 액세스 토큰이 없습니다.",
                category: .network
            )
            return nil
        }

        do {
            let result = try await broadcastAnalysisAPIClient.fetchLatestAnalysisResult(
                broadcastID: broadcastID,
                accessToken: accessToken
            )

            FocusLogger.info(
                "최신 방송 분석 결과 조회 성공: broadcastId=\(result.broadcastID), hasLatestJob=\(result.latestJob != nil), hasLatestReport=\(result.latestReport != nil), highlightCount=\(result.highlightCount)",
                category: .network
            )
            return result
        } catch {
            FocusLogger.warning("최신 방송 분석 결과 조회 실패: \(error.localizedDescription)", category: .network)
            return nil
        }
    }

    func fetchLatestBroadcastAnalysisResultWithPollingIfNeeded(
        broadcastID: String?,
        maxAttempts: Int = 5,
        delayNanoseconds: UInt64 = 1_000_000_000
    ) async -> BroadcastAnalysisResult? {
        guard let broadcastID, !broadcastID.isEmpty else {
            return nil
        }

        var lastResult: BroadcastAnalysisResult?
        for attempt in 1...max(maxAttempts, 1) {
            lastResult = await fetchLatestBroadcastAnalysisResultIfNeeded(broadcastID: broadcastID)

            if let lastResult,
               lastResult.latestJob != nil || lastResult.latestReport != nil {
                if attempt > 1 {
                    FocusLogger.info(
                        "최신 방송 분석 결과 polling 성공: broadcastId=\(broadcastID), attempt=\(attempt)",
                        category: .network
                    )
                }
                return lastResult
            }

            guard attempt < max(maxAttempts, 1) else { break }

            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                break
            }
        }

        return lastResult
    }

    func fetchBroadcastHighlightCandidatesIfNeeded(
        broadcastID: String?
    ) async -> [BroadcastHighlightCandidate]? {
        guard let broadcastAnalysisAPIClient else {
            return nil
        }
        guard let broadcastID, !broadcastID.isEmpty else {
            return nil
        }
        guard let accessToken = appTokenStore.getAccessToken(), !accessToken.isEmpty else {
            FocusLogger.warning(
                "방송 하이라이트 후보 조회 건너뜀: 서버 액세스 토큰이 없습니다.",
                category: .network
            )
            return nil
        }

        do {
            let highlightCandidates = try await broadcastAnalysisAPIClient.fetchHighlightCandidates(
                broadcastID: broadcastID,
                accessToken: accessToken
            )

            FocusLogger.info(
                "방송 하이라이트 후보 조회 성공: broadcastId=\(broadcastID), count=\(highlightCandidates.count)",
                category: .network
            )
            return highlightCandidates
        } catch {
            FocusLogger.warning("방송 하이라이트 후보 조회 실패: \(error.localizedDescription)", category: .network)
            return nil
        }
    }

}

private extension PostStreamAnalysisStatus {
    init(remoteStatus: BroadcastAnalysisJobStatusValue) {
        switch remoteStatus {
        case .pending, .running:
            self = .processing
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed
        }
    }
}

private extension BroadcastHighlightCandidate {
    func toHighlightMoment() -> PostStreamHighlightMoment {
        PostStreamHighlightMoment(
            timeLabel: Self.formatTimeLabel(seconds: startSec),
            title: title,
            description: reason
        )
    }

    static func formatTimeLabel(seconds: Int) -> String {
        let safeSeconds = max(seconds, 0)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let remainingSeconds = safeSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }
}

private extension PostStreamAnalysisReport {
    func applyingLatestAnalysisResult(_ result: BroadcastAnalysisResult) -> PostStreamAnalysisReport {
        let latestJob = result.latestJob
        let latestReport = result.latestReport

        return PostStreamAnalysisReport(
            id: latestJob?.analysisJobID ?? latestReport?.aiReportID ?? id,
            title: latestReport?.title ?? title,
            broadcastID: result.broadcastID,
            analysisJobID: latestJob?.analysisJobID ?? analysisJobID,
            durationSec: latestJob?.mediaAsset.durationSec ?? durationSec,
            analysisStatus: latestJob.map { PostStreamAnalysisStatus(remoteStatus: $0.jobStatus) } ?? analysisStatus,
            summary: latestReport?.summary ?? summary,
            strengths: latestReport?.strengths ?? strengths,
            weaknesses: latestReport?.weaknesses ?? weaknesses,
            actionItems: latestReport?.actionItems ?? actionItems,
            totalReplacedFaceCount: latestReport?.totalReplacedFaceCount ?? totalReplacedFaceCount,
            maxSimultaneousCrowdCount: latestReport?.maxSimultaneousCrowdCount ?? maxSimultaneousCrowdCount,
            highlightCount: result.highlightCount,
            peakViewerCount: latestReport?.peakViewerCount ?? peakViewerCount,
            peakOccurredAtLabel: latestReport.flatMap {
                $0.peakOccurredAt.flatMap { BroadcastAnalysisDateFormatter.displayLabel(from: $0) }
            } ?? peakOccurredAtLabel,
            peakSceneDescription: latestReport?.peakSceneDescription ?? peakSceneDescription,
            contentRatios: latestReport?.contentRatios.map {
                PostStreamContentRatio(
                    contentType: $0.contentType,
                    percentage: $0.percentage,
                    durationSec: $0.durationSec
                )
            } ?? contentRatios,
            highlightMoments: highlightMoments,
            generatedAt: latestReport.flatMap { BroadcastAnalysisDateFormatter.date(from: $0.createdAt) } ?? generatedAt,
            recordingURL: recordingURL
        )
    }
}

private enum BroadcastAnalysisDateFormatter {
    private static let inputWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let inputDefault: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let outputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter
    }()

    static func date(from value: String) -> Date? {
        inputWithFractionalSeconds.date(from: value) ?? inputDefault.date(from: value)
    }

    static func displayLabel(from value: String) -> String? {
        guard let date = date(from: value) else { return nil }
        return outputFormatter.string(from: date)
    }
}

private enum BroadcastAnalysisDebugPayloadFormatter {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private struct Payload: Encodable {
        let latestAnalysisResult: BroadcastAnalysisResult?
        let highlightCandidates: [BroadcastHighlightCandidate]?
    }

    static func format(
        latestAnalysisResult: BroadcastAnalysisResult?,
        highlightCandidates: [BroadcastHighlightCandidate]?
    ) -> String? {
        guard latestAnalysisResult != nil || highlightCandidates != nil else {
            return nil
        }

        let payload = Payload(
            latestAnalysisResult: latestAnalysisResult,
            highlightCandidates: highlightCandidates
        )

        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return text
    }

    static func formatLatestAnalysisResult(_ latestAnalysisResult: BroadcastAnalysisResult?) -> String? {
        guard let latestAnalysisResult else { return nil }
        guard let data = try? encoder.encode(latestAnalysisResult),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    static func formatHighlightCandidates(_ highlightCandidates: [BroadcastHighlightCandidate]?) -> String? {
        guard let highlightCandidates else { return nil }
        guard let data = try? encoder.encode(highlightCandidates),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
