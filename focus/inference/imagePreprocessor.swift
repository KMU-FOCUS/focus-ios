//
//  imagePreprocessor.swift
//  focus
//
//  Created by 이동언 on 3/8/26.
//

import Foundation
import CoreVideo
import CoreGraphics
import CoreImage
import UIKit

final class ImagePreprocessor {
    static let shared = ImagePreprocessor()

    private let ciContext = CIContext(options: nil)

    private init() {}

    // MARK: - Public

    /// short-side 기준으로 비율 유지 resize
    func resizeShortSideRGB(
        from pixelBuffer: CVPixelBuffer,
        shortSide: Int
    ) throws -> (tensor: ImageTensorData, meta: ResizeMeta) {
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)

        guard sourceWidth > 0, sourceHeight > 0 else {
            throw InferenceError.preprocessingFailed("원본 pixelBuffer 크기가 올바르지 않습니다.")
        }

        let minSide = min(sourceWidth, sourceHeight)
        let scale = CGFloat(shortSide) / CGFloat(minSide)

        let resizedWidth = max(1, Int(round(CGFloat(sourceWidth) * scale)))
        let resizedHeight = max(1, Int(round(CGFloat(sourceHeight) * scale)))

        let rgbData = try renderRGBData(
            from: pixelBuffer,
            cropRect: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight),
            outputSize: CGSize(width: resizedWidth, height: resizedHeight)
        )

        let meta = ResizeMeta(
            originalWidth: sourceWidth,
            originalHeight: sourceHeight,
            resizedWidth: resizedWidth,
            resizedHeight: resizedHeight,
            scale: scale
        )

        return (
            ImageTensorData(data: rgbData, width: resizedWidth, height: resizedHeight, channels: 3),
            meta
        )
    }

    func cropRGB(
        from pixelBuffer: CVPixelBuffer,
        rect: CGRect,
        outputSize: CGSize
    ) throws -> ImageTensorData {
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)

        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
        guard !clamped.isNull, !clamped.isEmpty, clamped.width >= 1, clamped.height >= 1 else {
            throw InferenceError.cropTooSmall
        }

        let rgbData = try renderRGBData(
            from: pixelBuffer,
            cropRect: clamped,
            outputSize: outputSize
        )

        return ImageTensorData(
            data: rgbData,
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            channels: 3
        )
    }

    /// HWC UInt8 RGB -> Float32 NHWC [0,1]
    func uint8RGBToFloatNHWC(_ image: ImageTensorData, scale: Float = 1.0 / 255.0) -> Data {
        let bytes = [UInt8](image.data)
        var floats = [Float]()
        floats.reserveCapacity(bytes.count)
        for b in bytes {
            floats.append(Float(b) * scale)
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// HWC UInt8 RGB -> Float32 NCHW with custom normalize
    func uint8RGBToFloatNCHW(
        _ image: ImageTensorData,
        normalize: (Float) -> Float
    ) -> Data {
        let bytes = [UInt8](image.data)
        let hw = image.width * image.height

        var floats = Array(repeating: Float(0), count: hw * 3)

        for i in 0..<hw {
            let base = i * 3
            let r = normalize(Float(bytes[base]))
            let g = normalize(Float(bytes[base + 1]))
            let b = normalize(Float(bytes[base + 2]))

            floats[i] = r
            floats[hw + i] = g
            floats[2 * hw + i] = b
        }

        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    func mapRectToOriginal(_ rect: CGRect, using meta: ResizeMeta) -> CGRect {
        let invScale = 1.0 / meta.scale
        return CGRect(
            x: rect.origin.x * invScale,
            y: rect.origin.y * invScale,
            width: rect.width * invScale,
            height: rect.height * invScale
        )
    }

    func mapPointToOriginal(_ point: CGPoint, using meta: ResizeMeta) -> CGPoint {
        let invScale = 1.0 / meta.scale
        return CGPoint(x: point.x * invScale, y: point.y * invScale)
    }

    func clampRectToOriginalBounds(_ rect: CGRect, width: Int, height: Int) -> CGRect {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        return rect.intersection(bounds)
    }

    func l2Normalize(_ vector: [Float]) -> [Float] {
        guard !vector.isEmpty else { return vector }
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    // MARK: - Private

    private func renderRGBData(
        from pixelBuffer: CVPixelBuffer,
        cropRect: CGRect,
        outputSize: CGSize
    ) throws -> Data {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let cropped = ciImage.cropped(to: cropRect)

        guard let cgImage = ciContext.createCGImage(cropped, from: cropped.extent) else {
            throw InferenceError.preprocessingFailed("CGImage 생성 실패")
        }

        let width = Int(outputSize.width)
        let height = Int(outputSize.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8

        var rgba = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw InferenceError.preprocessingFailed("CGContext 생성 실패")
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var rgb = [UInt8]()
        rgb.reserveCapacity(width * height * 3)

        for i in stride(from: 0, to: rgba.count, by: 4) {
            rgb.append(rgba[i])     // R
            rgb.append(rgba[i + 1]) // G
            rgb.append(rgba[i + 2]) // B
        }

        return Data(rgb)
    }
}
