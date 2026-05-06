//
//  privacyMaskRenderer.swift
//  focus
//
//  Created by 이동언 on 3/7/26.
//

import Foundation
import CoreImage
import CoreGraphics
import CoreVideo

final class PrivacyMaskRenderer {
    private let ciContext = CIContext(options: nil)
    
    private struct EllipseMaskParameters {
        let center: CGPoint
        let radiusX: CGFloat
        let radiusY: CGFloat
        let angleRadians: CGFloat
    }

    func renderMasks(on pixelBuffer: CVPixelBuffer, tracks: [TrackedFace]) {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let maskedImage = applyMasks(to: sourceImage, tracks: tracks)
        ciContext.render(maskedImage, to: pixelBuffer)
    }

    func applyMasks(to image: CIImage, tracks: [TrackedFace]) -> CIImage {
        let facesToMask = tracks
            .filter { shouldMask(track: $0) }
            .prefix(FocusConstants.maxSimultaneousMaskFaces)

        var output = image

        for track in facesToMask {
            if track.landmarks != nil {
                output = applyLandmarkAwareMask(to: output, track: track)
            } else {
                output = applyBBoxFallbackMask(to: output, track: track)
            }
        }

        return output
    }

    private func shouldMask(track: TrackedFace) -> Bool {
        switch track.label {
        case .owner:
            return false
        case .pending, .other:
            return true
        }
    }

    private func applyLandmarkAwareMask(to image: CIImage, track: TrackedFace) -> CIImage {
        guard let landmarks = track.landmarks else {
            return applyBBoxFallbackMask(to: image, track: track)
        }

        let ellipse = ellipseParameters(for: landmarks)
        let faceRect = ellipseBounds(for: ellipse).intersection(image.extent)
        let maskImage = makeEllipticalMask(
            extent: image.extent,
            ellipse: ellipse
        )

        let pixelated = pixelatedImage(from: image, faceRect: faceRect)
        return blend(pixelated: pixelated, original: image, mask: maskImage)
    }

    private func applyBBoxFallbackMask(to image: CIImage, track: TrackedFace) -> CIImage {
        let rect = expandedFaceRect(from: track.bbox)
        let mask = solidRectMask(extent: image.extent, rect: rect)
        let pixelated = pixelatedImage(from: image, faceRect: rect)
        return blend(pixelated: pixelated, original: image, mask: mask)
    }

    private func expandedFaceRect(from rect: CGRect) -> CGRect {
        let expandX = rect.width * 0.15
        let expandY = rect.height * 0.20

        return CGRect(
            x: rect.origin.x - expandX,
            y: rect.origin.y - expandY,
            width: rect.width + (expandX * 2),
            height: rect.height + (expandY * 2)
        )
    }

    private func pixelatedImage(from image: CIImage, faceRect: CGRect) -> CIImage {
        guard let filter = CIFilter(name: "CIPixellate") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: faceRect.midX, y: faceRect.midY), forKey: kCIInputCenterKey)
        filter.setValue(FocusConstants.mosaicBlockSize, forKey: kCIInputScaleKey)

        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    private func makeEllipticalMask(
        extent: CGRect,
        ellipse: EllipseMaskParameters
    ) -> CIImage {
        let width = max(Int(ceil(extent.width)), 1)
        let height = max(Int(ceil(extent.height)), 1)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return solidRectMask(extent: extent, rect: ellipseBounds(for: ellipse))
        }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: CGSize(width: width, height: height)))

        context.setFillColor(gray: 1, alpha: 1)
        context.translateBy(
            x: ellipse.center.x - extent.origin.x,
            y: ellipse.center.y - extent.origin.y
        )
        context.rotate(by: ellipse.angleRadians)
        context.fillEllipse(
            in: CGRect(
                x: -ellipse.radiusX,
                y: -ellipse.radiusY,
                width: ellipse.radiusX * 2,
                height: ellipse.radiusY * 2
            )
        )

        guard let maskCGImage = context.makeImage() else {
            return solidRectMask(extent: extent, rect: ellipseBounds(for: ellipse))
        }

        return CIImage(cgImage: maskCGImage).cropped(to: extent)
    }

    private func ellipseParameters(
        for landmarks: FaceLandmarks5,
        paddingRatio: CGFloat = 1.05
    ) -> EllipseMaskParameters {
        let eyeCenter = CGPoint(
            x: (landmarks.leftEye.x + landmarks.rightEye.x) / 2.0,
            y: (landmarks.leftEye.y + landmarks.rightEye.y) / 2.0
        )
        let mouthCenter = CGPoint(
            x: (landmarks.leftMouth.x + landmarks.rightMouth.x) / 2.0,
            y: (landmarks.leftMouth.y + landmarks.rightMouth.y) / 2.0
        )
        let eyeDistance = hypot(landmarks.leftEye.x - landmarks.rightEye.x, landmarks.leftEye.y - landmarks.rightEye.y)
        let eyeMouthDistance = hypot(mouthCenter.x - eyeCenter.x, mouthCenter.y - eyeCenter.y)
        let center = CGPoint(
            x: eyeCenter.x + ((mouthCenter.x - eyeCenter.x) * 0.3),
            y: eyeCenter.y + ((mouthCenter.y - eyeCenter.y) * 0.3)
        )
        let angleRadians = atan2(
            landmarks.leftEye.y - landmarks.rightEye.y,
            landmarks.leftEye.x - landmarks.rightEye.x
        )

        return EllipseMaskParameters(
            center: center,
            radiusX: eyeDistance * paddingRatio,
            radiusY: eyeMouthDistance * 1.35 * paddingRatio,
            angleRadians: angleRadians
        )
    }

    private func ellipseBounds(for ellipse: EllipseMaskParameters) -> CGRect {
        let cosine = cos(ellipse.angleRadians)
        let sine = sin(ellipse.angleRadians)
        let ux = ellipse.radiusX * cosine
        let uy = ellipse.radiusX * sine
        let vx = ellipse.radiusY * -sine
        let vy = ellipse.radiusY * cosine
        let halfWidth = sqrt((ux * ux) + (vx * vx))
        let halfHeight = sqrt((uy * uy) + (vy * vy))

        return CGRect(
            x: ellipse.center.x - halfWidth,
            y: ellipse.center.y - halfHeight,
            width: halfWidth * 2,
            height: halfHeight * 2
        )
    }

    private func solidRectMask(extent: CGRect, rect: CGRect) -> CIImage {
        let color = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: rect)

        let clear = CIImage(color: .clear).cropped(to: extent)
        return color.composited(over: clear).cropped(to: extent)
    }

    private func blend(pixelated: CIImage, original: CIImage, mask: CIImage) -> CIImage {
        guard let blend = CIFilter(name: "CIBlendWithMask") else {
            return original
        }

        blend.setValue(pixelated, forKey: kCIInputImageKey)
        blend.setValue(original, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: "inputMaskImage")

        return blend.outputImage ?? original
    }
}
