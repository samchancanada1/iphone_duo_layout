import Flutter
import UIKit
import CoreFoundation

/// Owns a root-controller lease for this registrar only. Other engines, windows
/// and pre-existing navigation hierarchies are never searched or replaced.
final class NativeToolbarPlugin: NSObject {
  private let hostController: () -> UIViewController?
  private let channel: FlutterMethodChannel
  private var storage: AnyObject?
  private var client: String?

  init(messenger: FlutterBinaryMessenger, hostController: @escaping () -> UIViewController?) {
    self.hostController = hostController
    channel = FlutterMethodChannel(name: "iphone_duo_layout/toolbar", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      self.handle(call, result: result)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "beginToolbarClient" {
      guard let message = call.arguments as? [String: Any], message["version"] as? Int == 1,
            let next = message["client"] as? String, !next.isEmpty else {
        result(FlutterError(code: "invalid_arguments", message: "Invalid toolbar client.", details: nil))
        return
      }
      let acknowledge = { [weak self] in
        self?.client = next
        result(["version": 1, "client": next])
      }
      if client != next, #available(iOS 27.1, *), let session = storage as? NativeToolbarSession {
        // Hot restart replaces the Dart isolate without destroying this plugin.
        // Reclaim its orphaned root lease before accepting the new UI client.
        session.close { [weak self, weak session] in
          if let self = self, let session = session, self.storage === session { self.storage = nil }
          acknowledge()
        }
      } else {
        acknowledge()
      }
      return
    }
    guard call.method == "setToolbar" || call.method == "detachToolbar" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let message = call.arguments as? [String: Any],
          let version = message["version"] as? Int, version == 1,
          let owner = message["owner"] as? String, !owner.isEmpty else {
      result(FlutterError(code: "invalid_arguments", message: "Invalid toolbar envelope.", details: nil))
      return
    }
    guard let requestedClient = message["client"] as? String, requestedClient == client else {
      if call.method == "detachToolbar" {
        // A stale isolate's cleanup must never detach the replacement client.
        result(Self.status("detached", owner: owner))
      } else {
        result(FlutterError(code: "stale_client", message: "Initialize the toolbar UI client first.", details: nil))
      }
      return
    }
    if call.method == "detachToolbar" {
      guard #available(iOS 27.1, *), let session = storage as? NativeToolbarSession,
            session.owner == owner else {
        result(Self.status("detached", owner: owner))
        return
      }
      session.close { [weak self, weak session] in
        if let self = self, let session = session,
           self.storage === session { self.storage = nil }
        result(Self.status("detached", owner: owner))
      }
      return
    }
    guard let revision = message["revision"] as? NSNumber,
          CFGetTypeID(revision) != CFBooleanGetTypeID(),
          revision.doubleValue.isFinite, revision.doubleValue > 0,
          revision.doubleValue.rounded() == revision.doubleValue,
          revision.doubleValue < Double(Int.max),
          let configMap = message["configuration"] as? [String: Any] else {
      result(FlutterError(code: "invalid_arguments", message: "Invalid toolbar revision/configuration.", details: nil))
      return
    }
    let sequence = revision.intValue
    let configuration: ToolbarConfiguration
    do {
      configuration = try ToolbarConfiguration(configMap)
    } catch {
      result(FlutterError(code: "invalid_arguments", message: String(describing: error), details: nil))
      return
    }
    guard #available(iOS 27.1, *) else {
      result(Self.status("osUnavailable", owner: owner, revision: sequence))
      return
    }
    if let session = storage as? NativeToolbarSession {
      guard session.owner == owner, !session.isClosing else {
        result(Self.status("busy", owner: owner, revision: sequence))
        return
      }
      guard session.stillOwnsHierarchy else {
        result(FlutterError(code: "ownership_lost", message: "The app replaced the native root hierarchy. Dispose this toolbar owner.", details: nil))
        return
      }
      guard sequence > session.revision else {
        result(FlutterError(code: "stale_revision", message: "Toolbar revisions must increase.", details: nil))
        return
      }
      session.apply(configuration, revision: sequence)
      result(Self.status("available", owner: owner, revision: sequence))
      return
    }
    guard let host = hostController(), let view = host.viewIfLoaded,
          let window = view.window else {
      result(Self.status("viewUnavailable", owner: owner, revision: sequence))
      return
    }
    guard window.rootViewController === host, host.parent == nil else {
      result(Self.status("hostUnsupported", owner: owner, revision: sequence))
      return
    }
    guard host.presentedViewController == nil, !host.isBeingPresented,
          !host.isBeingDismissed, host.transitionCoordinator == nil else {
      result(Self.status("viewUnavailable", owner: owner, revision: sequence))
      return
    }
    let active = window.windowScene.map { $0.activationState == .foregroundActive }
      ?? (UIApplication.shared.applicationState == .active)
    guard active else {
      result(Self.status("viewUnavailable", owner: owner, revision: sequence))
      return
    }
    let session = NativeToolbarSession(owner: owner, host: host, window: window) {
      [weak self] id, revision in
      self?.channel.invokeMethod("action", arguments: [
        "version": 1, "owner": owner, "revision": revision, "id": id,
      ])
    }
    storage = session
    session.install(configuration, revision: sequence)
    result(Self.status("available", owner: owner, revision: sequence))
  }

  static func status(_ availability: String, owner: String, revision: Int? = nil) -> [String: Any] {
    var value: [String: Any] = ["version": 1, "owner": owner, "availability": availability]
    if let revision = revision { value["revision"] = revision }
    return value
  }
}

struct ToolbarItemConfiguration {
  let id: String
  let title: String
  let systemImage: String?
  let enabled: Bool
  let visible: Bool
  let placement: String
  let priority: String
  let axis: String

  init(_ map: [String: Any]) throws {
    guard let id = map["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let title = map["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let enabled = map["enabled"] as? NSNumber, CFGetTypeID(enabled) == CFBooleanGetTypeID(),
          let visible = map["visible"] as? NSNumber, CFGetTypeID(visible) == CFBooleanGetTypeID(),
          let placement = map["placement"] as? String, ["leading", "trailing", "bottom"].contains(placement),
          let priority = map["priority"] as? String, ["automatic", "low", "high"].contains(priority),
          let axis = map["axis"] as? String, ["automatic", "horizontalOnly", "verticalPreferred"].contains(axis) else {
      throw ToolbarContractError.invalid("Invalid toolbar action.")
    }
    let image = map["systemImage"]
    if let image = image, !(image is NSNull) {
      guard let value = image as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ToolbarContractError.invalid("Invalid system image name.")
      }
    }
    self.id = id
    self.title = title
    self.systemImage = image as? String
    self.enabled = enabled.boolValue
    self.visible = visible.boolValue
    self.placement = placement
    self.priority = priority
    self.axis = axis
  }
}

enum ToolbarContractError: Error { case invalid(String) }

struct ToolbarConfiguration {
  let title: String
  let items: [ToolbarItemConfiguration]
  let overflowItems: [ToolbarItemConfiguration]

  init(_ map: [String: Any]) throws {
    guard let title = map["title"] as? String,
          let items = map["items"] as? [[String: Any]],
          let overflow = map["overflowItems"] as? [[String: Any]] else {
      throw ToolbarContractError.invalid("Invalid toolbar configuration.")
    }
    self.title = title
    self.items = try items.map(ToolbarItemConfiguration.init)
    self.overflowItems = try overflow.map(ToolbarItemConfiguration.init)
    let ids = (self.items + self.overflowItems).map(\.id)
    guard Set(ids).count == ids.count else {
      throw ToolbarContractError.invalid("Toolbar action ids must be unique across both collections.")
    }
  }
}
