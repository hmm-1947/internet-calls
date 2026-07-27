import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let secureField = UITextField()
  private var isSecureOverlayApplied = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    enableScreenshotProtection()
  }

  // Blocks screenshots and screen recording by rendering the app's content
  // through a "secure" layer (the same mechanism UITextField.isSecureTextEntry
  // uses for passwords). iOS has no direct FLAG_SECURE equivalent, so this
  // layer-swap is the standard workaround: the OS shows a blank/black view in
  // screenshots, screen recordings, and the app switcher preview instead of
  // the real content.
  private func enableScreenshotProtection() {
    guard !isSecureOverlayApplied, let window = self.window else { return }

    secureField.isSecureTextEntry = true
    window.addSubview(secureField)
    secureField.centerXAnchor.constraint(equalTo: window.centerXAnchor).isActive = true
    secureField.centerYAnchor.constraint(equalTo: window.centerYAnchor).isActive = true
    window.layer.superlayer?.addSublayer(secureField.layer)
    secureField.layer.sublayers?.last?.addSublayer(window.layer)

    isSecureOverlayApplied = true
  }
}
