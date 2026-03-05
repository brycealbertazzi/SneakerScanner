import Flutter
import StoreKit
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

    // OCR method channel
    let ocrChannel = FlutterMethodChannel(
      name: "com.sneakerscanner/ocr",
      binaryMessenger: controller.binaryMessenger
    )
    ocrChannel.setMethodCallHandler { [weak appDelegate] call, result in
      guard call.method == "recognizeText",
            let args = call.arguments as? [String: Any],
            let imagePath = args["imagePath"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      appDelegate?.recognizeText(imagePath: imagePath, result: result)
    }

    // StoreKit method channel
    let storeKitChannel = FlutterMethodChannel(
      name: "com.sneakerscanner/storekit",
      binaryMessenger: controller.binaryMessenger
    )
    storeKitChannel.setMethodCallHandler { call, result in
      guard call.method == "checkTrialEligibility",
            let productId = call.arguments as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      if #available(iOS 15.0, *) {
        Task {
          do {
            let products = try await Product.products(for: [productId])
            if let product = products.first,
               let subscription = product.subscription {
              let eligible = await subscription.isEligibleForIntroOffer
              result(eligible)
            } else {
              result(true)
            }
          } catch {
            result(true)
          }
        }
      } else {
        result(true)
      }
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
