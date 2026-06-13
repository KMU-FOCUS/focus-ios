//
//  broadcastModels.swift
//  focus
//
//  Created by Codex on 5/16/26.
//

import Foundation

struct BroadcastSession: Equatable {
    let broadcastID: String
    let title: String
    let status: String
    let outputMode: String
    let streamKey: String
    let watchURL: URL?
    let hlsURL: URL?
    let lastStartFailureReason: String?
    let memberName: String
    let memberID: String
    let startedAt: String?
    let endedAt: String?
}

struct BroadcastPage: Equatable {
    let content: [BroadcastSession]
    let totalElements: Int
    let totalPages: Int
    let size: Int
    let number: Int
    let first: Bool
    let last: Bool
    let empty: Bool
}

struct PreparedBroadcastSession: Equatable {
    let broadcast: BroadcastSession
    let accessToken: String
}

struct CreateBroadcastRequestDTO: Encodable {
    let title: String
}

struct StartBroadcastRequestDTO: Encodable {
    let avatarId: String?
}

struct UpdateBroadcastRequestDTO: Encodable {
    let title: String
}

struct BroadcastResponseDTO: Decodable {
    let broadcastId: String
    let title: String
    let status: String
    let outputMode: String?
    let streamKey: String
    let watchUrl: String?
    let hlsUrl: String?
    let lastStartFailureReason: String?
    let memberName: String
    let memberId: String
    let startedAt: String?
    let endedAt: String?
}

struct BroadcastPageResponseDTO: Decodable {
    let content: [BroadcastResponseDTO]
    let totalElements: Int
    let totalPages: Int
    let size: Int
    let number: Int
    let first: Bool
    let last: Bool
    let empty: Bool
}

extension BroadcastResponseDTO {
    func toDomain() -> BroadcastSession {
        BroadcastSession(
            broadcastID: broadcastId,
            title: title,
            status: status,
            outputMode: outputMode ?? "UNKNOWN",
            streamKey: streamKey,
            watchURL: watchUrl.flatMap(URL.init(string:)),
            hlsURL: hlsUrl.flatMap(URL.init(string:)),
            lastStartFailureReason: lastStartFailureReason,
            memberName: memberName,
            memberID: memberId,
            startedAt: startedAt,
            endedAt: endedAt
        )
    }
}

extension BroadcastPageResponseDTO {
    func toDomain() -> BroadcastPage {
        BroadcastPage(
            content: content.map { $0.toDomain() },
            totalElements: totalElements,
            totalPages: totalPages,
            size: size,
            number: number,
            first: first,
            last: last,
            empty: empty
        )
    }
}
