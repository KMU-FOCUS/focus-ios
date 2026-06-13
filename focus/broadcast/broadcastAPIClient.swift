//
//  broadcastAPIClient.swift
//  focus
//
//  Created by Codex on 5/16/26.
//

import Foundation

final class BroadcastAPIClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    init(baseURL: URL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func createBroadcast(
        title: String,
        accessToken: String
    ) async throws -> BroadcastSession {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("broadcasts")

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(CreateBroadcastRequestDTO(title: title))

        return try await executeBroadcastRequest(request)
    }

    func startBroadcast(
        broadcastID: String,
        avatarID: String?,
        accessToken: String
    ) async throws -> BroadcastSession {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("broadcasts")
            .appendingPathComponent(broadcastID)
            .appendingPathComponent("start")

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(StartBroadcastRequestDTO(avatarId: avatarID))

        return try await executeBroadcastRequest(request)
    }

    func fetchBroadcastList(
        page: Int,
        size: Int,
        accessToken: String
    ) async throws -> BroadcastPage {
        guard var components = URLComponents(
            url: baseURL
                .appendingPathComponent("api")
                .appendingPathComponent("v1")
                .appendingPathComponent("broadcasts"),
            resolvingAgainstBaseURL: false
        ) else {
            throw NSError(
                domain: "BroadcastAPIClient",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "방송 목록 URL 생성에 실패했습니다."]
            )
        }
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(size))
        ]
        guard let url = components.url else {
            throw NSError(
                domain: "BroadcastAPIClient",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "방송 목록 URL이 유효하지 않습니다."]
            )
        }

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "GET"
        return try await executeEnvelopeRequest(request) { (dto: BroadcastPageResponseDTO) in
            dto.toDomain()
        }
    }

    func fetchBroadcastDetail(
        broadcastID: String,
        accessToken: String
    ) async throws -> BroadcastSession {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("broadcasts")
            .appendingPathComponent(broadcastID)

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "GET"
        return try await executeBroadcastRequest(request)
    }

    func updateBroadcast(
        broadcastID: String,
        title: String,
        accessToken: String
    ) async throws -> BroadcastSession {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("broadcasts")
            .appendingPathComponent(broadcastID)

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(UpdateBroadcastRequestDTO(title: title))

        return try await executeBroadcastRequest(request)
    }

    func deleteBroadcast(
        broadcastID: String,
        accessToken: String
    ) async throws {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("broadcasts")
            .appendingPathComponent(broadcastID)

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "DELETE"
        try await executeEnvelopeUnitRequest(request)
    }

    func fetchAvailableAvatarIDs(
        accessToken: String
    ) async throws -> [String] {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("avatars")

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "GET"

        let (data, response) = try await urlSession.data(for: request)
        try validateHTTP(response: response, data: data)

        let envelope = try jsonDecoder.decode(APIEnvelope<[String]>.self, from: data)
        guard envelope.success else {
            throw NSError(
                domain: "BroadcastAPIClient",
                code: -4,
                userInfo: [
                    NSLocalizedDescriptionKey: envelope.message.isEmpty
                        ? "아바타 목록 조회에 실패했습니다."
                        : envelope.message
                ]
            )
        }

        return envelope.data ?? []
    }

    func stopBroadcast(
        broadcastID: String,
        accessToken: String
    ) async throws -> BroadcastSession {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("broadcasts")
            .appendingPathComponent(broadcastID)
            .appendingPathComponent("stop")

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        return try await executeBroadcastRequest(request)
    }

    func streamerHeartbeat(
        broadcastID: String,
        accessToken: String
    ) async throws {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("broadcasts")
            .appendingPathComponent(broadcastID)
            .appendingPathComponent("streamer-heartbeat")

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"

        let (data, response) = try await urlSession.data(for: request)
        try validateHTTP(response: response, data: data)
    }

    func viewerHeartbeat(
        broadcastID: String,
        accessToken: String
    ) async throws {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("broadcasts")
            .appendingPathComponent(broadcastID)
            .appendingPathComponent("heartbeat")

        var request = try authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"

        let (data, response) = try await urlSession.data(for: request)
        try validateHTTP(response: response, data: data)
    }

    private func executeBroadcastRequest(_ request: URLRequest) async throws -> BroadcastSession {
        try await executeEnvelopeRequest(request) { (dto: BroadcastResponseDTO) in
            dto.toDomain()
        }
    }

    private func executeEnvelopeRequest<T: Decodable, R>(
        _ request: URLRequest,
        map: (T) -> R
    ) async throws -> R {
        let (data, response) = try await urlSession.data(for: request)
        try validateHTTP(response: response, data: data)

        let envelope = try jsonDecoder.decode(APIEnvelope<T>.self, from: data)
        guard envelope.success, let dto = envelope.data else {
            throw NSError(
                domain: "BroadcastAPIClient",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: envelope.message.isEmpty
                        ? "방송 요청에 실패했습니다."
                        : envelope.message
                ]
            )
        }
        return map(dto)
    }

    private func executeEnvelopeUnitRequest(_ request: URLRequest) async throws {
        let (data, response) = try await urlSession.data(for: request)
        try validateHTTP(response: response, data: data)

        if let envelope = try? jsonDecoder.decode(BasicSuccessEnvelope.self, from: data),
           envelope.success == false {
            throw NSError(
                domain: "BroadcastAPIClient",
                code: -7,
                userInfo: [
                    NSLocalizedDescriptionKey: envelope.message.isEmpty
                        ? "요청이 성공으로 처리되지 않았습니다."
                        : envelope.message
                ]
            )
        }
    }

    private func authorizedRequest(
        url: URL,
        accessToken: String
    ) throws -> URLRequest {
        guard !accessToken.isEmpty else {
            throw NSError(
                domain: "BroadcastAPIClient",
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
                domain: "BroadcastAPIClient",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "HTTP 응답이 아닙니다."]
            )
        }

        guard (200...299).contains(http.statusCode) else {
            let message = parseServerErrorMessage(from: data)
            throw NSError(
                domain: "BroadcastAPIClient",
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

private struct BasicSuccessEnvelope: Decodable {
    let success: Bool
    let message: String
}
