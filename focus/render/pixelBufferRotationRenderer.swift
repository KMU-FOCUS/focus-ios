//
//  pixelBufferRotationRenderer.swift
//  focus
//
//  Created by Codex on 5/19/26.
//

import CoreGraphics
import CoreImage
import CoreVideo

final class PixelBufferRotationRenderer {
    private let ciContext = CIContext(options: nil)

    func makeRotatedPixelBuffer(
        from pixelBuffer: CVPixelBuffer,
        degrees: CGFloat
    ) -> CVPixelBuffer? {
        let normalizedDegrees = normalizedRotationDegrees(degrees)
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)

        guard abs(normalizedDegrees) > 0.01 else {
            return render(
                image: sourceImage,
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer),
                pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer)
            )
        }

        let sourceSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        let radians = normalizedDegrees * .pi / 180.0
        let rotatedBounds = CGRect(origin: .zero, size: sourceSize)
            .applying(CGAffineTransform(rotationAngle: radians))
        let canvasSize = CGSize(
            width: max(1, ceil(abs(rotatedBounds.width))),
            height: max(1, ceil(abs(rotatedBounds.height)))
        )
        let canvasRect = CGRect(origin: .zero, size: canvasSize)

        let transform = CGAffineTransform(translationX: canvasSize.width / 2.0, y: canvasSize.height / 2.0)
            .rotated(by: radians)
            .translatedBy(x: -sourceSize.width / 2.0, y: -sourceSize.height / 2.0)

        let rotatedImage = sourceImage
            .transformed(by: transform)
            .cropped(to: canvasRect)

        return render(
            image: rotatedImage,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer)
        )
    }

    private func render(
        image: CIImage,
        width: Int,
        height: Int,
        pixelFormat: OSType
    ) -> CVPixelBuffer? {
        var outputPixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attributes as CFDictionary,
            &outputPixelBuffer
        )

        guard status == kCVReturnSuccess,
              let outputPixelBuffer else {
            return nil
        }

        ciContext.render(image, to: outputPixelBuffer)
        return outputPixelBuffer
    }

    private func normalizedRotationDegrees(_ degrees: CGFloat) -> CGFloat {
        var normalized = degrees.truncatingRemainder(dividingBy: 360)
        if normalized > 180 {
            normalized -= 360
        } else if normalized <= -180 {
            normalized += 360
        }
        return normalized
    }
}
