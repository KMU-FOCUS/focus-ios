//
//  grpcMetadataSessionSideEffect.swift
//  focus
//
//  Created by Codex on 5/19/26.
//

import Foundation

actor GRPCMetadataSessionSideEffect: MetadataSessionSideEffecting {
    private let streamer: GRPCMetadataStreamer
    private let messageBuilder = ProtoMessageBuilder()
    private let onConnectionStateChanged: (@Sendable (Bool) -> Void)?

    private var activeSessionID: String?
    private var isConnected = false
    private var hasLoggedFirstSuccessfulFrame = false

    init(
        host: String,
        port: Int,
        useTLS: Bool,
        onConnectionStateChanged: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.streamer = GRPCMetadataStreamer(host: host, port: port, useTLS: useTLS)
        self.onConnectionStateChanged = onConnectionStateChanged
    }

    func startSession(sessionID: String) async {
        activeSessionID = sessionID
        hasLoggedFirstSuccessfulFrame = false

        guard !isConnected else {
            FocusLogger.info(
                "원격 metadata stream 재사용: sessionID=\(sessionID)",
                category: .metadata
            )
            return
        }

        do {
            try await streamer.connect()
            isConnected = true
            onConnectionStateChanged?(true)
            FocusLogger.info(
                "원격 metadata stream 연결 성공: sessionID=\(sessionID)",
                category: .metadata
            )
        } catch {
            isConnected = false
            onConnectionStateChanged?(false)
            FocusLogger.warning(
                "원격 metadata stream 연결 실패: \(error.localizedDescription)",
                category: .metadata
            )
        }
    }

    func appendFrame(sessionID: String, ptsUs: Int64, tracks: [TrackedFace]) async {
        guard isConnected, activeSessionID == sessionID else {
            return
        }

        let result = messageBuilder.buildFrameMetadata(
            sessionID: sessionID,
            ptsUs: ptsUs,
            tracks: tracks
        )

        do {
            try await streamer.send(result.message)
            if !hasLoggedFirstSuccessfulFrame {
                hasLoggedFirstSuccessfulFrame = true
                FocusLogger.info(
                    """
                    원격 metadata 첫 frame 전송 성공: sessionID=\(sessionID), ptsUs=\(ptsUs), includedFaces=\(result.includedTrackIDs.count), trackIDs=\(result.includedTrackIDs)
                    """,
                    category: .metadata
                )
            }
        } catch {
            isConnected = false
            onConnectionStateChanged?(false)
            FocusLogger.warning(
                """
                원격 metadata frame 전송 실패: sessionID=\(sessionID), ptsUs=\(ptsUs), includedFaces=\(result.includedTrackIDs.count), error=\(error.localizedDescription)
                """,
                category: .metadata
            )
        }
    }

    func finishSession() async {
        guard isConnected else {
            activeSessionID = nil
            hasLoggedFirstSuccessfulFrame = false
            onConnectionStateChanged?(false)
            return
        }

        do {
            _ = try await streamer.finish()
            FocusLogger.info(
                "원격 metadata stream 종료 성공: sessionID=\(activeSessionID ?? "-")",
                category: .metadata
            )
        } catch {
            FocusLogger.warning(
                "원격 metadata stream 종료 실패: \(error.localizedDescription)",
                category: .metadata
            )
        }

        activeSessionID = nil
        isConnected = false
        hasLoggedFirstSuccessfulFrame = false
        onConnectionStateChanged?(false)
    }

    func reset() async {
        await streamer.cancel()
        activeSessionID = nil
        isConnected = false
        hasLoggedFirstSuccessfulFrame = false
        onConnectionStateChanged?(false)
    }
}
