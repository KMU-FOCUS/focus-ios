//
//  grpcMetadataStreamer.swift
//  focus
//
//  Created by 이동언 on 3/8/26.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2

final class GRPCMetadataStreamer {
    enum StreamState: Equatable {
        case idle
        case connecting
        case connected
        case closing
        case closed
        case failed(String)
    }

    private let host: String
    private let port: Int
    private let useTLS: Bool
    private let descriptor = MethodDescriptor(
        fullyQualifiedService: "focus.metadata.v1.FaceMetadataIngestService",
        method: "PushFaceMetadata"
    )

    private let stateLock = NSLock()

    private var requestPipe: FaceMetadataRequestPipe?
    private var responseTask: Task<FaceMetadataPushResponse, Error>?
    private var state: StreamState = .idle

    init(host: String, port: Int, useTLS: Bool = false) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
    }

    func connect() async throws {
        if responseTask != nil {
            transition(to: .connected)
            return
        }

        transition(to: .connecting)

        let pipe = FaceMetadataRequestPipe()
        requestPipe = pipe

        let host = self.host
        let port = self.port
        let useTLS = self.useTLS
        let descriptor = self.descriptor

        let responseTask = Task<FaceMetadataPushResponse, Error> {
            try await withGRPCClient(
                transport: .http2NIOPosix(
                    target: .dns(host: host, port: port),
                    transportSecurity: useTLS ? .tls : .plaintext
                )
            ) { client in
                let request = StreamingClientRequest(
                    of: FaceMetadataPushRequest.self,
                    producer: { writer in
                        for try await message in pipe.stream {
                            try await writer.write(message)
                        }
                    }
                )

                return try await client.clientStreaming(
                    request: request,
                    descriptor: descriptor,
                    serializer: FaceMetadataRequestSerializer(),
                    deserializer: FaceMetadataResponseDeserializer(),
                    options: .defaults
                ) { response in
                    try response.message
                }
            }
        }

        self.responseTask = responseTask
        transition(to: .connected)
    }

    func send(_ message: FaceMetadataPushRequest) async throws {
        guard let requestPipe else {
            throw MetadataStreamError.notConnected
        }

        switch requestPipe.continuation.yield(message) {
        case .enqueued:
            return
        case .dropped:
            throw MetadataStreamError.backpressureDropped
        case .terminated:
            if let responseTask {
                _ = try? await responseTask.value
            }
            throw MetadataStreamError.streamTerminated
        @unknown default:
            throw MetadataStreamError.streamTerminated
        }
    }

    func finish() async throws -> FaceMetadataPushResponse? {
        transition(to: .closing)

        requestPipe?.finish()

        defer {
            cleanup()
            transition(to: .closed)
        }

        return try await responseTask?.value
    }

    func cancel() async {
        requestPipe?.finish(throwing: CancellationError())
        responseTask?.cancel()

        _ = try? await responseTask?.value

        cleanup()
        transition(to: .closed)
    }

    private func cleanup() {
        requestPipe = nil
        responseTask = nil
    }

    private func transition(to newState: StreamState) {
        stateLock.lock()
        state = newState
        stateLock.unlock()
    }
}

private enum MetadataStreamError: LocalizedError {
    case notConnected
    case backpressureDropped
    case streamTerminated

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "metadata gRPC stream이 아직 연결되지 않았습니다."
        case .backpressureDropped:
            return "metadata gRPC stream이 backpressure로 frame을 버렸습니다."
        case .streamTerminated:
            return "metadata gRPC stream이 이미 종료되었습니다."
        }
    }
}

private final class FaceMetadataRequestPipe {
    let stream: AsyncThrowingStream<FaceMetadataPushRequest, Error>
    let continuation: AsyncThrowingStream<FaceMetadataPushRequest, Error>.Continuation

    init() {
        var storedContinuation: AsyncThrowingStream<FaceMetadataPushRequest, Error>.Continuation?
        self.stream = AsyncThrowingStream { continuation in
            storedContinuation = continuation
        }
        self.continuation = storedContinuation!
    }

    func finish() {
        continuation.finish()
    }

    func finish(throwing error: Error) {
        continuation.finish(throwing: error)
    }
}

@available(gRPCSwift 2.0, *)
private struct FaceMetadataRequestSerializer: MessageSerializer {
    func serialize<Bytes: GRPCContiguousBytes>(_ message: FaceMetadataPushRequest) throws -> Bytes {
        Bytes(FaceMetadataProtobufCodec.encode(message))
    }
}

@available(gRPCSwift 2.0, *)
private struct FaceMetadataResponseDeserializer: MessageDeserializer {
    func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws -> FaceMetadataPushResponse {
        try FaceMetadataProtobufCodec.decodeResponse(serializedMessageBytes)
    }
}

private enum FaceMetadataProtobufCodec {
    static func encode(_ request: FaceMetadataPushRequest) -> [UInt8] {
        var bytes: [UInt8] = []
        appendStringField(1, request.sessionID, to: &bytes)
        appendSignedVarintField(2, Int64(request.ptsUs), to: &bytes)

        for face in request.faces {
            appendMessageField(3, encode(face), to: &bytes)
        }

        return bytes
    }

    static func decodeResponse<Bytes: GRPCContiguousBytes>(
        _ serializedMessageBytes: Bytes
    ) throws -> FaceMetadataPushResponse {
        let bytes = serializedMessageBytes.withUnsafeBytes { rawBuffer in
            Array(rawBuffer)
        }
        var index = 0

        var success = false
        var receivedFrames: Int64 = 0
        var acceptedFrames: Int64 = 0
        var droppedFrames: Int64 = 0
        var lastPtsUs: Int64 = 0

        while index < bytes.count {
            let key = try decodeVarint(from: bytes, index: &index)
            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 0x07)

            switch (fieldNumber, wireType) {
            case (1, 0):
                success = try decodeVarint(from: bytes, index: &index) != 0
            case (2, 0):
                receivedFrames = Int64(try decodeVarint(from: bytes, index: &index))
            case (3, 0):
                acceptedFrames = Int64(try decodeVarint(from: bytes, index: &index))
            case (4, 0):
                droppedFrames = Int64(try decodeVarint(from: bytes, index: &index))
            case (5, 0):
                lastPtsUs = Int64(try decodeVarint(from: bytes, index: &index))
            default:
                try skipField(wireType: wireType, bytes: bytes, index: &index)
            }
        }

        return FaceMetadataPushResponse(
            success: success,
            receivedFrames: receivedFrames,
            acceptedFrames: acceptedFrames,
            droppedFrames: droppedFrames,
            lastPtsUs: lastPtsUs
        )
    }

    private static func encode(_ face: FaceMetadataFaceEntry) -> [UInt8] {
        var bytes: [UInt8] = []
        appendSignedVarintField(1, Int64(face.trackingID), to: &bytes)
        appendMessageField(2, encode(face.bbox), to: &bytes)
        appendMessageField(3, encode(face.tdmmRaw), to: &bytes)
        return bytes
    }

    private static func encode(_ bbox: FaceMetadataBoundingBox) -> [UInt8] {
        var bytes: [UInt8] = []
        appendSignedVarintField(1, Int64(bbox.x), to: &bytes)
        appendSignedVarintField(2, Int64(bbox.y), to: &bytes)
        appendSignedVarintField(3, Int64(bbox.width), to: &bytes)
        appendSignedVarintField(4, Int64(bbox.height), to: &bytes)
        return bytes
    }

    private static func encode(_ tdmmRaw: FaceMetadataTdmmRaw) -> [UInt8] {
        var packed: [UInt8] = []
        packed.reserveCapacity(tdmmRaw.coeffs.count * 4)

        for coeff in tdmmRaw.coeffs {
            let littleEndian = coeff.bitPattern.littleEndian
            packed.append(UInt8(truncatingIfNeeded: littleEndian))
            packed.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
            packed.append(UInt8(truncatingIfNeeded: littleEndian >> 16))
            packed.append(UInt8(truncatingIfNeeded: littleEndian >> 24))
        }

        var bytes: [UInt8] = []
        appendLengthDelimitedFieldHeader(1, payloadLength: packed.count, to: &bytes)
        bytes.append(contentsOf: packed)
        return bytes
    }

    private static func appendStringField(_ fieldNumber: Int, _ value: String, to bytes: inout [UInt8]) {
        let payload = Array(value.utf8)
        appendLengthDelimitedFieldHeader(fieldNumber, payloadLength: payload.count, to: &bytes)
        bytes.append(contentsOf: payload)
    }

    private static func appendMessageField(_ fieldNumber: Int, _ payload: [UInt8], to bytes: inout [UInt8]) {
        appendLengthDelimitedFieldHeader(fieldNumber, payloadLength: payload.count, to: &bytes)
        bytes.append(contentsOf: payload)
    }

    private static func appendSignedVarintField(_ fieldNumber: Int, _ value: Int64, to bytes: inout [UInt8]) {
        appendVarint(UInt64(bitPattern: value), fieldNumber: fieldNumber, wireType: 0, to: &bytes)
    }

    private static func appendLengthDelimitedFieldHeader(
        _ fieldNumber: Int,
        payloadLength: Int,
        to bytes: inout [UInt8]
    ) {
        appendVarint(UInt64((fieldNumber << 3) | 2), to: &bytes)
        appendVarint(UInt64(payloadLength), to: &bytes)
    }

    private static func appendVarint(
        _ value: UInt64,
        fieldNumber: Int,
        wireType: Int,
        to bytes: inout [UInt8]
    ) {
        appendVarint(UInt64((fieldNumber << 3) | wireType), to: &bytes)
        appendVarint(value, to: &bytes)
    }

    private static func appendVarint(_ value: UInt64, to bytes: inout [UInt8]) {
        var remaining = value

        while remaining >= 0x80 {
            bytes.append(UInt8(remaining & 0x7F) | 0x80)
            remaining >>= 7
        }

        bytes.append(UInt8(remaining))
    }

    private static func decodeVarint(from bytes: [UInt8], index: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while index < bytes.count {
            let byte = bytes[index]
            index += 1

            result |= UInt64(byte & 0x7F) << shift

            if byte & 0x80 == 0 {
                return result
            }

            shift += 7
            if shift >= 64 {
                throw FaceMetadataProtobufError.malformedVarint
            }
        }

        throw FaceMetadataProtobufError.truncated
    }

    private static func skipField(
        wireType: Int,
        bytes: [UInt8],
        index: inout Int
    ) throws {
        switch wireType {
        case 0:
            _ = try decodeVarint(from: bytes, index: &index)
        case 1:
            guard index + 8 <= bytes.count else {
                throw FaceMetadataProtobufError.truncated
            }
            index += 8
        case 2:
            let length = Int(try decodeVarint(from: bytes, index: &index))
            guard index + length <= bytes.count else {
                throw FaceMetadataProtobufError.truncated
            }
            index += length
        case 5:
            guard index + 4 <= bytes.count else {
                throw FaceMetadataProtobufError.truncated
            }
            index += 4
        default:
            throw FaceMetadataProtobufError.unsupportedWireType(wireType)
        }
    }
}

private enum FaceMetadataProtobufError: LocalizedError {
    case malformedVarint
    case truncated
    case unsupportedWireType(Int)

    var errorDescription: String? {
        switch self {
        case .malformedVarint:
            return "protobuf varint가 손상되었습니다."
        case .truncated:
            return "protobuf payload가 중간에서 잘렸습니다."
        case .unsupportedWireType(let wireType):
            return "지원하지 않는 protobuf wireType입니다: \(wireType)"
        }
    }
}
