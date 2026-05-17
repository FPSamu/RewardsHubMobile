import Flutter
import PassKit
import UIKit

class WalletPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "rewardshub/wallet", binaryMessenger: registrar.messenger())
    let instance = WalletPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "addPassToWallet" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let typedData = call.arguments as? FlutterStandardTypedData else {
      result(FlutterError(code: "INVALID_ARGS", message: "Expected bytes", details: nil))
      return
    }
    addPass(data: typedData.data, result: result)
  }

  private func addPass(data: Data, result: @escaping FlutterResult) {
    do {
      let pass = try PKPass(data: data)
      guard PKAddPassesViewController.canAddPasses() else {
        result(FlutterError(code: "WALLET_UNAVAILABLE", message: "Apple Wallet no está disponible", details: nil))
        return
      }
      let vc = PKAddPassesViewController(pass: pass)!
      vc.delegate = self
      DispatchQueue.main.async {
        UIApplication.shared.windows.first?.rootViewController?.present(vc, animated: true) {
          result(nil)
        }
      }
    } catch {
      result(FlutterError(code: "WALLET_ERROR", message: error.localizedDescription, details: nil))
    }
  }
}

extension WalletPlugin: PKAddPassesViewControllerDelegate {
  func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
    controller.dismiss(animated: true)
  }
}
