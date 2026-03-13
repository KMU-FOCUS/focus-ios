//
//  arcfaceonxxService.swift
//  focus
//
//  Created by 이동언 on 3/8/26.
//

import Foundation
import CoreGraphics
import CoreVideo
import onnxruntime_objc

final class ArcFaceONNXService: ArcFaceEmbeddingExtracting {
    private let env: ORTEnv
    private let session: ORTSession
    private let inputName: String
    private let outputName: String
    private let preprocessor = ImagePreprocessor.shared

    init(
        modelFileName: String = "arcface",
        modelFileExtension: String = "onnx",
        inputName: String = "input",
        outputName: String = "output"
    ) throws {
        guard let path = Bundle.main.path(forResource: modelFileName, ofType: modelFileExtension) else {
            throw InferenceError.modelFileNotFound("\(modelFileName).\(modelFileExtension)")
        }

        do {
            self.env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
            let options = try ORTSessionOptions()
            try options.setIntraOpNumThreads(2)
            self.session = try ORTSession(env: env, modelPath: path, sessionOptions: options)
            self.inputName = inputName
            self.outputName = outputName
        } catch {
            throw InferenceError.sessionInitializationFailed(error.localizedDescription)
        }
    }

    func extractEmbedding(from pixelBuffer: CVPixelBuffer, face: DetectedFace) throws -> [Float] {
        let bbox = face.bbox
        guard bbox.width >= FocusConstants.minEmbeddingCropSize,
              bbox.height >= FocusConstants.minEmbeddingCropSize else {
            throw InferenceError.cropTooSmall
        }

        let image = try preprocessor.cropRGB(
            from: pixelBuffer,
            rect: bbox,
            outputSize: FocusConstants.arcFaceInputSize
        )

        let nchw = preprocessor.uint8RGBToFloatNCHW(image) { pixel in
            (pixel - 127.5) / 128.0
        }

        let shape: [NSNumber] = [1, 3, NSNumber(value: image.height), NSNumber(value: image.width)]

        let inputTensor: ORTValue
        do {
            inputTensor = try ORTValue(
                tensorData: NSMutableData(data: nchw),
                elementType: ORTTensorElementDataType.float,
                shape: shape
            )
        } catch {
            throw InferenceError.tensorCreationFailed(error.localizedDescription)
        }

        let outputs: [String: ORTValue]
        do {
            outputs = try session.run(
                withInputs: [inputName: inputTensor],
                outputNames: [outputName],
                runOptions: nil
            )
        } catch {
            throw InferenceError.inferenceFailed("ArcFace run 실패: \(error.localizedDescription)")
        }

        guard let outputTensor = outputs[outputName] else {
            throw InferenceError.invalidModelOutput("ArcFace output '\(outputName)' 없음")
        }

        let outputData: Data
        do {
            outputData = try outputTensor.tensorData() as Data
        } catch {
            throw InferenceError.invalidModelOutput("ArcFace output tensorData 변환 실패: \(error.localizedDescription)")
        }

        let embedding = outputData.toFloatArray()
        guard !embedding.isEmpty else {
            throw InferenceError.emptyEmbedding
        }

        return preprocessor.l2Normalize(embedding)
    }
}

// MARK: - Data Helpers
private extension Data {
    func toFloatArray() -> [Float] {
        let count = self.count / MemoryLayout<Float>.stride
        return self.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: Float.self)
            return Array(ptr.prefix(count))
        }
    }
}
