import Flutter
import QuickLook
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Kept alive for the app's lifetime (it is the QuickLook data source).
  private var attachmentPreviewer: AttachmentPreviewer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: route notification presentation and taps
    // through the Flutter app delegate so reminders show while the app is in
    // the foreground and a tap opens the claim (spec §10).
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Attachment preview channel (spec §12): iOS cannot hand a sandboxed
    // file:// URL to another app via url_launcher, so non-image attachments
    // (PDF, Office documents, ...) are shown with the system QuickLook viewer.
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "ClaimTrackerAttachmentPreviewer")
    {
      let previewer = AttachmentPreviewer()
      let channel = FlutterMethodChannel(
        name: "com.claimtracker/files",
        binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        previewer.handle(call, result: result)
      }
      attachmentPreviewer = previewer
    }
  }
}

/// Presents a local file in QLPreviewController. Method `previewFile`
/// takes `{"path": String}` and returns true when the viewer was shown.
final class AttachmentPreviewer: NSObject, QLPreviewControllerDataSource {
  private var fileURL: URL?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "previewFile" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
      let path = args["path"] as? String,
      FileManager.default.fileExists(atPath: path)
    else {
      result(false)
      return
    }
    let url = URL(fileURLWithPath: path)
    guard QLPreviewController.canPreview(url as NSURL),
      let presenter = AttachmentPreviewer.topViewController()
    else {
      result(false)
      return
    }
    fileURL = url
    let controller = QLPreviewController()
    controller.dataSource = self
    presenter.present(controller, animated: true, completion: nil)
    result(true)
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    return fileURL == nil ? 0 : 1
  }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int)
    -> QLPreviewItem
  {
    return (fileURL ?? URL(fileURLWithPath: "/")) as NSURL
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
