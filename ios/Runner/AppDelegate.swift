import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate {
  let flutterEngine = FlutterEngine(name: "SneakerScannerEngine")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)
    return true
  }

  override func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    return UISceneConfiguration(
      name: "Default Configuration",
      sessionRole: connectingSceneSession.role
    )
  }

  func recognizeText(imagePath: String, result: @escaping FlutterResult) {
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

    request.recognitionLevel = .accurate
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
