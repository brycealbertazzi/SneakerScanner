import Flutter
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }

    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    let controller = FlutterViewController(engine: appDelegate.flutterEngine, nibName: nil, bundle: nil)

    // Set up OCR method channel
    let channel = FlutterMethodChannel(
      name: "com.sneakerscanner/ocr",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak appDelegate] call, result in
      guard call.method == "recognizeText",
            let args = call.arguments as? [String: Any],
            let imagePath = args["imagePath"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      appDelegate?.recognizeText(imagePath: imagePath, result: result)
    }

    window = UIWindow(windowScene: windowScene)
    window?.rootViewController = controller
    window?.makeKeyAndVisible()

    // Handle deep link that cold-launched the app
    if let url = connectionOptions.urlContexts.first?.url {
      _ = appDelegate.application(UIApplication.shared, open: url, options: [:])
    }
  }

  // Forward URLs while app is running (e.g. StockX OAuth callback)
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url else { return }
    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    _ = appDelegate.application(UIApplication.shared, open: url, options: [:])
  }
}
