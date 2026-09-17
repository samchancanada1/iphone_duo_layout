import Flutter
import UIKit
import CoreFoundation

/// Experimental layout-result bridge. Each owner has a separate, transparent
/// arrangement attached to this registrar's Flutter view, not an offscreen model.
final class ArrangementPlugin: NSObject {
  private let hostController: () -> UIViewController?
  private let channel: FlutterMethodChannel
  private var client: String?
  private var probes: [String: AnyObject] = [:]

  init(messenger: FlutterBinaryMessenger, hostController: @escaping () -> UIViewController?) {
    self.hostController = hostController
    channel = FlutterMethodChannel(name: "iphone_duo_layout/arrangement", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      self.handle(call, result: result)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard ["beginClient", "read", "dispose"].contains(call.method) else {
      result(FlutterMethodNotImplemented); return
    }
    guard let message = call.arguments as? [String: Any], message["version"] as? Int == 1,
          let nextClient = message["client"] as? String, !nextClient.isEmpty else {
      result(FlutterError(code: "invalid_arguments", message: "Invalid arrangement envelope.", details: nil)); return
    }
    if call.method == "beginClient" {
      if nextClient != client {
        // Native plugin survives Dart hot restart. Remove the old isolate's probes.
        removeAll()
        client = nextClient
      }
      result(["version": 1, "client": nextClient]); return
    }
    guard let owner = message["owner"] as? String, !owner.isEmpty else {
      result(FlutterError(code: "invalid_arguments", message: "Missing arrangement owner.", details: nil)); return
    }
    if call.method == "dispose" {
      if client == nextClient { remove(owner) }
      result(["version": 1, "owner": owner, "disposed": true]); return
    }
    guard client == nextClient else {
      result(FlutterError(code: "stale_client", message: "Initialize the UI client before reading.", details: nil)); return
    }
    guard let revision = metric(message["revision"]), revision > 0,
          revision.rounded() == revision, revision < Double(Int.max),
          let viewportMap = message["viewport"] as? [String: Any],
          let x = metric(viewportMap["x"]), let y = metric(viewportMap["y"]),
          let width = metric(viewportMap["width"]), width > 0,
          let height = metric(viewportMap["height"]), height > 0,
          let viewSize = message["viewSize"] as? [String: Any],
          let viewWidth = metric(viewSize["width"]), viewWidth > 0,
          let viewHeight = metric(viewSize["height"]), viewHeight > 0,
          let axis = message["axis"] as? String, ["automatic", "horizontal", "vertical"].contains(axis) else {
      result(FlutterError(code: "invalid_arguments", message: "Invalid arrangement geometry or axis.", details: nil)); return
    }
    let request = Int(revision)
    func unavailable(_ availability: String) {
      remove(owner)
      result(["version": 1, "owner": owner, "revision": request, "availability": availability,
              "primary": NSNull(), "secondary": NSNull(), "viewport": NSNull(), "viewSize": NSNull()])
    }
    guard #available(iOS 27.1, *) else { unavailable("osUnavailable"); return }
    guard let host = hostController(), let view = host.viewIfLoaded, let window = view.window else {
      unavailable("viewUnavailable"); return
    }
    let active = window.windowScene.map { $0.activationState == .foregroundActive }
      ?? (UIApplication.shared.applicationState == .active)
    guard active else { unavailable("inactive"); return }
    guard abs(Double(view.bounds.width) - viewWidth) < 0.5,
          abs(Double(view.bounds.height) - viewHeight) < 0.5 else {
      unavailable("geometryMismatch"); return
    }
    guard x >= 0, y >= 0, (x + width).isFinite, (y + height).isFinite,
          x + width <= viewWidth + 0.5, y + height <= viewHeight + 0.5 else {
      unavailable("unsupportedGeometry"); return
    }
    var probe = probes[owner] as? ArrangementProbe
    if let existing = probe, !existing.matches(host: host, view: view, window: window) {
      remove(owner); probe = nil
    }
    if probe == nil {
      let attached = ArrangementProbe(host: host, view: view, window: window)
      probes[owner] = attached
      probe = attached
    }
    let viewport = CGRect(x: x, y: y, width: width, height: height)
    guard let layout = probe?.measure(viewport: viewport, axis: axis) else {
      // Keep the attached probe alive while UIKit has not produced placement state.
      result(["version": 1, "owner": owner, "revision": request, "availability": "waiting",
              "primary": NSNull(), "secondary": NSNull(), "viewport": NSNull(), "viewSize": NSNull()])
      return
    }
    result(["version": 1, "owner": owner, "revision": request, "availability": "available",
            "coordinateSpace": "viewport", "viewport": viewportMap, "viewSize": viewSize,
            "primary": layout.primary, "secondary": layout.secondary])
  }

  private func metric(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite else { return nil }
    return number.doubleValue
  }

  private func remove(_ owner: String) {
    if #available(iOS 27.1, *), let probe = probes.removeValue(forKey: owner) as? ArrangementProbe {
      probe.detach()
    } else { probes.removeValue(forKey: owner) }
  }

  private func removeAll() {
    for owner in Array(probes.keys) { remove(owner) }
  }

  deinit { removeAll() }
}
