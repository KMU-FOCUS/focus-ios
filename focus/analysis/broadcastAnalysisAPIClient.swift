//
//  broadcastAnalysisAPIClient.swift
//  focus
//
//  Created by Codex on 5/17/26.
//

import Foundation

enum BroadcastMediaAssetTypeValue: String, Codable, Sendable {
    case analysisMP4 = "ANALYSIS_MP4"
}

enum BroadcastAnalysisJobTypeValue: String, Codable, Sendable {
    case fullSummary = "FULL_SUMMARY"
}

enum BroadcastAnalysisJobStatusValue: String, Codable, Sendable {
    case pending = "PENDING"
    case running = "RUNNING"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
}

struct BroadcastAnalysisViewerPeakInsightRequestDTO: Encodable, Sendable {
    let peakViewerCount: Int?
    let occurredAt: String?
    let sceneDescription: String?
}

struct BroadcastAnalysisFaceStatisticsRequestDTO: Encodable, Sendable {
    let totalReplacedFaceCount: Int?
    let maxSimultaneousCrowdCount: Int?
}

struct BroadcastAnalysisContentRatioRequestDTO: Encodable, Sendable {
    let contentType: String
    let percentage: Double
    let durationSec: Int
}

struct CreateBroadcastAnalysisJobRequestDTO: Encodable, Sendable {
    let assetType: BroadcastMediaAssetTypeValue
    let jobType: BroadcastAnalysisJobTypeValue
    let storageProvider: String
    let storageKey: String
    let storageUrl: String?
    let durationSec: Int?
    let resolutionWidth: Int?
    let resolutionHeight: Int?
    let fileSizeBytes: Int64?
    let summary: String?
    let strengths: [String]
    let weaknesses: [String]
    let actionItems: [String]
    let viewerPeakInsight: BroadcastAnalysisViewerPeakInsightRequestDTO?
    let faceStatistics: BroadcastAnalysisFaceStatisticsRequestDTO?
    let contentRatios: [BroadcastAnalysisContentRatioRequestDTO]
}

struct CompleteBroadcastAnalysisJobRequestDTO: Encodable, Sendable {
    let storageUrl: String?
    let durationSec: Int?
    let resolutionWidth: Int?
    let resolutionHeight: Int?
    let fileSizeBytes: Int64?
    let summary: String?
    let strengths: [String]
    let weaknesses: [String]
    let actionItems: [String]
    let viewerPeakInsight: BroadcastAnalysisViewerPeakInsightRequestDTO?
    let faceStatistics: BroadcastAnalysisFaceStatisticsRequestDTO?
    let contentRatios: [BroadcastAnalysisContentRatioRequestDTO]
}

struct BroadcastAnalysisMediaAsset: Codable, Equatable, Sendable {
    let mediaAssetID: String
    let assetType: String
    let storageProvider: String
    let storageKey: String
    let storageURL: String?
    let durationSec: Int?
    let resolutionWidth: Int?
    let resolutionHeight: Int?
    let fileSizeBytes: Int64?
    let createdAt: String
}

struct BroadcastAnalysisJob: Codable, Equatable, Sendable {
    let analysisJobID: String
    let broadcastID: String
    let jobType: BroadcastAnalysisJobTypeValue
    let jobStatus: BroadcastAnalysisJobStatusValue
    let completedAt: String?
    let errorMessage: String?
    let createdAt: String
    let mediaAsset: BroadcastAnalysisMediaAsset
}

struct BroadcastHighlightCandidate: Codable, Equatable, Sendable {
    let highlightCandidateID: String
    let startSec: Int
    let endSec: Int
    let title: String
    let reason: String
    let score: Double
    let createdAt: String
}

struct BroadcastAnalysisLatestReport: Codable, Equatable, Sendable {
    let aiReportID: String
    let reportType: String
    let title: String
    let summary: String
    let strengths: [String]
    let weaknesses: [String]
    let actionItems: [String]
    let peakViewerCount: Int?
    let peakOccurredAt: String?
    let peakSceneDescription: String?
    let totalReplacedFaceCount: Int?
    let maxSimultaneousCrowdCount: Int?
    let contentRatios: [BroadcastAnalysisContentRatio]
    let createdAt: String
}

struct BroadcastAnalysisContentRatio: Codable, Equatable, Sendable {
    let contentType: String
    let percentage: Double
    let durationSec: Int
}

struct BroadcastAnalysisResult: Codable, Equatable, Sendable {
    let broadcastID: String
    let latestJob: BroadcastAnalysisJob?
    let latestReport: BroadcastAnalysisLatestReport?
    let highlightCount: Int
}

private struct BroadcastAnalysisMediaAssetResponseDTO: Decodable {
    let mediaAssetId: String
    let assetType: String
    let storageProvider: String
    let storageKey: String
    let storageUrl: String?
    let durationSec: Int?
    let resolutionWidth: Int?
    let resolutionHeight: Int?
    let fileSizeBytes: Int64?
    let createdAt: String
}

private struct BroadcastAnalysisJobResponseDTO: Decodable {
    let analysisJobId: String
    let broadcastId: String
    let jobType: BroadcastAnalysisJobTypeValue
    let jobStatus: BroadcastAnalysisJobStatusValue
    let completedAt: String?
    let errorMessage: String?
    let createdAt: String
    let mediaAsset: BroadcastAnalysisMediaAssetResponseDTO
}

private struct BroadcastHighlightCandidateResponseDTO: Decodable {
    let highlightCandidateId: String
    let startSec: Int
    let endSec: Int
    let title: String
    let reason: String
    let score: Double
    let createdAt: String
}

private struct BroadcastAnalysisResultResponseDTO: Decodable {
    let broadcastId: String
    let latestJob: BroadcastAnalysisJobResponseDTO?
    let latestReport: BroadcastAnalysisLatestReportResponseDTO?
    let highlightCount: Int
}

private struct BroadcastAnalysisLatestReportResponseDTO: Decodable {
    let aiReportId: String
    let reportType: String
    let title: String
    let summary: String
    let strengths: [String]
    let weaknesses: [String]
    let actionItems: [String]
    let viewerPeakInsight: BroadcastAnalysisLatestViewerPeakInsightResponseDTO?
    let faceStatistics: BroadcastAnalysisLatestFaceStatisticsResponseDTO
    let contentRatios: [BroadcastAnalysisLatestContentRatioResponseDTO]
    let createdAt: String
}

private struct BroadcastAnalysisLatestViewerPeakInsightResponseDTO: Decodable {
    let peakViewerCount: Int
    let occurredAt: String?
    let sceneDescription: String?
}

private struct BroadcastAnalysisLatestFaceStatisticsResponseDTO: Decodable {
    let totalReplacedFaceCount: Int?
    let maxSimultaneousCrowdCount: Int?
}

private struct BroadcastAnalysisLatestContentRatioResponseDTO: Decodable {
    let contentType: String
    let percentage: Double
    let durationSec: Int
}

private extension BroadcastAnalysisMediaAssetResponseDTO {
    func toDomain() -> BroadcastAnalysisMediaAsset {
        BroadcastAnalysisMediaAsset(
            mediaAssetID: mediaAssetId,
            assetType: assetType,
            storageProvider: storageProvider,
            storageKey: storageKey,
            storageURL: storageUrl,
            durationSec: durationSec,
            resolutionWidth: resolutionWidth,
            resolutionHeight: resolutionHeight,
            fileSizeBytes: fileSizeBytes,
            createdAt: createdAt
        )
    }
}

private extension BroadcastAnalysisJobResponseDTO {
    func toDomain() -> BroadcastAnalysisJob {
        BroadcastAnalysisJob(
            analysisJobID: analysisJobId,
            broadcastID: broadcastId,
            jobType: jobType,
            jobStatus: jobStatus,
            completedAt: completedAt,
            errorMessage: errorMessage,
            createdAt: createdAt,
            mediaAsset: mediaAsset.toDomain()
        )
    }
}

private extension BroadcastHighlightCandidateResponseDTO {
    func toDomain() -> BroadcastHighlightCandidate {
        BroadcastHighlightCandidate(
            highlightCandidateID: highlightCandidateId,
            startSec: startSec,
            endSec: endSec,
            title: title,
            reason: reason,
            score: score,
            createdAt: createdAt
        )
    }
}

private extension BroadcastAnalysisLatestContentRatioResponseDTO {
    func toDomain() -> BroadcastAnalysisContentRatio {
        BroadcastAnalysisContentRatio(
            contentType: contentType,
            percentage: percentage,
            durationSec: durationSec
        )
    }
}

private extension BroadcastAnalysisLatestReportResponseDTO {
    func toDomain() -> BroadcastAnalysisLatestReport {
        BroadcastAnalysisLatestReport(
            aiReportID: aiReportId,
            reportType: reportType,
            title: title,
            summary: summary,
            strengths: strengths,
            weaknesses: weaknesses,
            actionItems: actionItems,
            peakViewerCount: viewerPeakInsight?.peakViewerCount,
            peakOccurredAt: viewerPeakInsight?.occurredAt,
            peakSceneDescription: viewerPeakInsight?.sceneDescription,
            totalReplacedFaceCount: faceStatistics.totalReplacedFaceCount,
            maxSimultaneousCrowdCount: faceStatistics.maxSimultaneousCrowdCount,
            contentRatios: contentRatios.map { $0.toDomain() },
            createdAt: createdAt
        )
    }
}

private extension BroadcastAnalysisResultResponseDTO {
    func toDomain() -> BroadcastAnalysisResult {
        BroadcastAnalysisResult(
            broadcastID: broadcastId,
            latestJob: latestJob?.toDomain(),
            latestReport: latestReport?.toDomain(),
            highlightCount: highlightCount
        )
    }
}

final class BroadcastAnalysisAPIClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    init(baseURL: URL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func createAnalysisJob(
        broadcastID: String,
        requestBody: CreateBroadcastAnalysisJobRequestDTO,
        accessToken: String
    ) async throws -> BroadcastAnalysisJob {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("broadcasts")
            .appendingPathComponent(broadcastID)
            .appendingPathComponent("analysis-jobs")

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(requestBody)

        let (data, response) = try await urlSession.data(for: request)
        try validateHTTP(response: response, data: data)

        let envelope = try jsonDecoder.decode(APIEnvelope<BroadcastAnalysisJobResponseDTO>.self, from: data)
        guard envelope.success, let dto = envelope.data else {
            throw NSError(
                domain: "BroadcastAnalysisAPIClient",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: envelope.message.isEmpty
                        ? "방송 분석 작업 생성에 실패했습니다."
                        : envelope.message
                ]
            )
        }

        return dto.toDomain()
    }

    func completeAnalysisJob(
        broadcastID: String,
        analysisJobID: String,
        requestBody: CompleteBroadcastAnalysisJobRequestDTO,
        accessToken: String
    ) async throws -> BroadcastAnalysisJob {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("broadcasts")
            .appendingPathComponent(broadcastID)
            .appendingPathComponent("analysis-jobs")
            .appendingPathComponent(analysisJobID)
            .appendingPathComponent("complete")

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(requestBody)

        let (data, response) = try await urlSession.data(for: request)
        try validateHTTP(response: response, data: data)

        let envelope = try jsonDecoder.decode(APIEnvelope<BroadcastAnalysisJobResponseDTO>.self, from: data)
        guard envelope.success, let dto = envelope.data else {
            throw NSError(
                domain: "BroadcastAnalysisAPIClient",
                code: -4,
                userInfo: [
                    NSLocalizedDescriptionKey: envelope.message.isEmpty
                        ? "방송 분석 작업 완료 처리에 실패했습니다."
                        : envelope.message
                ]
            )
        }

        return dto.toDomain()
    }

    func fetchHighlightCandidates(
        broadcastID: String,
        accessToken: String
    ) async throws -> [BroadcastHighlightCandidate] {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("broadcasts")
            .appendingPathComponent(broadcastID)
            .appendingPathComponent("highlights")

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "GET"

        let (data, response) = try await urlSession.data(for: request)
        try validateHTTP(response: response, data: data)

        let envelope = try jsonDecoder.decode(APIEnvelope<[BroadcastHighlightCandidateResponseDTO]>.self, from: data)
        guard envelope.success else {
            throw NSError(
                domain: "BroadcastAnalysisAPIClient",
                code: -5,
                userInfo: [
                    NSLocalizedDescriptionKey: envelope.message.isEmpty
                        ? "방송 하이라이트 후보 조회에 실패했습니다."
                        : envelope.message
                ]
            )
        }

        return (envelope.data ?? []).map { $0.toDomain() }
    }

    func fetchLatestAnalysisResult(
        broadcastID: String,
        accessToken: String
    ) async throws -> BroadcastAnalysisResult {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("broadcasts")
            .appendingPathComponent(broadcastID)
            .appendingPathComponent("analysis")

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "GET"

        let (data, response) = try await urlSession.data(for: request)
        try validateHTTP(response: response, data: data)

        let envelope = try jsonDecoder.decode(APIEnvelope<BroadcastAnalysisResultResponseDTO>.self, from: data)
        guard envelope.success, let dto = envelope.data else {
            throw NSError(
                domain: "BroadcastAnalysisAPIClient",
                code: -6,
                userInfo: [
                    NSLocalizedDescriptionKey: envelope.message.isEmpty
                        ? "최신 방송 분석 결과 조회에 실패했습니다."
                        : envelope.message
                ]
            )
        }

        return dto.toDomain()
    }

    private func authorizedRequest(url: URL, accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else {
            throw NSError(
                domain: "BroadcastAnalysisAPIClient",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "액세스 토큰이 비어 있습니다."]
            )
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "BroadcastAnalysisAPIClient",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "HTTP 응답이 아닙니다."]
            )
        }

        guard (200...299).contains(http.statusCode) else {
            let message = parseServerErrorMessage(from: data)
            throw NSError(
                domain: "BroadcastAnalysisAPIClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(message)"]
            )
        }
    }

    private func parseServerErrorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "unknown" }

        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var parts: [String] = []

            if let message = payload["message"] as? String, !message.isEmpty {
                parts.append(message)
            }
            if let error = payload["error"] as? String, !error.isEmpty, !parts.contains(error) {
                parts.append(error)
            }
            if let path = payload["path"] as? String, !path.isEmpty {
                parts.append("path: \(path)")
            }

            if !parts.isEmpty {
                return parts.joined(separator: " | ")
            }
        }

        return String(data: data, encoding: .utf8) ?? "unknown"
    }
}
