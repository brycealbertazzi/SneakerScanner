import Flutter
import UIKit
import Vision

class OcrPlugin {

  static func setup(on controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.sneakerscanner/ocr",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognizeText",
            let args = call.arguments as? [String: Any],
            let imagePath = args["imagePath"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      Self.recognizeText(imagePath: imagePath, result: result)
    }
  }

  private static func recognizeText(imagePath: String, result: @escaping FlutterResult) {
    guard let image = UIImage(contentsOfFile: imagePath),
          let cgImage = image.cgImage
    else {
      result(FlutterError(code: "INVALID_IMAGE", message: "Could not load image at path", details: nil))
      return
    }

    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        result(FlutterError(code: "OCR_ERROR", message: error.localizedDescription, details: nil))
        return
      }
      let observations = request.results as? [VNRecognizedTextObservation] ?? []
      let text = observations
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
      result(text)
    }

    // Highest accuracy model — critical for alphanumeric SKU codes.
    request.recognitionLevel = .accurate
    // Disable language correction so it never "fixes" 0→O, 1→I, etc.
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        result(FlutterError(code: "OCR_ERROR", message: error.localizedDescription, details: nil))
      }
    }
  }
}
