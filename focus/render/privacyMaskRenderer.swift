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

        let faceRect = expandedFaceRect(from: track.bbox)
        let maskImage = makeEllipticalMask(
            extent: image.extent,
            faceRect: faceRect,
            landmarks: landmarks
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
        faceRect: CGRect,
        landmarks: FaceLandmarks5
    ) -> CIImage {
        let centerX = (landmarks.leftEye.x + landmarks.rightEye.x + landmarks.nose.x) / 3.0
        let centerY = (landmarks.leftEye.y + landmarks.rightEye.y + landmarks.nose.y) / 3.0

        guard let radial = CIFilter(name: "CIRadialGradient") else {
            return solidRectMask(extent: extent, rect: faceRect)
        }

        radial.setValue(CIVector(x: centerX, y: centerY), forKey: "inputCenter")
        radial.setValue(min(faceRect.width, faceRect.height) * 0.28, forKey: "inputRadius0")
        radial.setValue(max(faceRect.width, faceRect.height) * 0.60, forKey: "inputRadius1")
        radial.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
        radial.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 0), forKey: "inputColor1")

        let gradient = radial.outputImage?.cropped(to: extent)
            ?? CIImage(color: .clear).cropped(to: extent)

        let cropMask = solidRectMask(extent: extent, rect: faceRect)

        guard let blend = CIFilter(name: "CIBlendWithAlphaMask") else {
            return cropMask
        }

        blend.setValue(gradient, forKey: kCIInputImageKey)
        blend.setValue(CIImage(color: .clear).cropped(to: extent), forKey: kCIInputBackgroundImageKey)
        blend.setValue(cropMask, forKey: "inputMaskImage")

        return blend.outputImage ?? cropMask
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
