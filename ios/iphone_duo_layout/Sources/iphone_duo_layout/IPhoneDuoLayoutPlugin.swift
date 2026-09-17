import Flutter
import UIKit

public class IPhoneDuoLayoutPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let hostView: () -> UIView?
  private var eventSink: FlutterEventSink?
  private var previous: NSDictionary?
  private var viewObserver: HostViewObserver?
  private var hingeHandler: HingeStreamHandler?
  private var toolbarPlugin: NativeToolbarPlugin?
  private var arrangementPlugin: ArrangementPlugin?

  // Injectable host view also permits tests without creating a Flutter engine.
  init(hostView: @escaping () -> UIView?) {
    self.hostView = hostView
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = IPhoneDuoLayoutPlugin(hostView: {
      // Uses this engine's registrar, never UIApplication's global key window.
      registrar.viewController?.viewIfLoaded
    })
    let methods = FlutterMethodChannel(name: "iphone_duo_layout/regions",
                                       binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: methods)
    let events = FlutterEventChannel(name: "iphone_duo_layout/region_changes",
                                     binaryMessenger: registrar.messenger())
    events.setStreamHandler(plugin)

    let hinge = HingeStreamHandler(hostController: { registrar.viewController })
    plugin.hingeHandler = hinge
    let hingeEvents = FlutterEventChannel(name: "iphone_duo_layout/hinge_changes",
                                          binaryMessenger: registrar.messenger())
    hingeEvents.setStreamHandler(hinge)

    plugin.arrangementPlugin = ArrangementPlugin(
      messenger: registrar.messenger(), hostController: { registrar.viewController }
    )

    plugin.toolbarPlugin = NativeToolbarPlugin(
      messenger: registrar.messenger(), hostController: { registrar.viewController }
    )
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "getReservedRegions" else {
      result(FlutterMethodNotImplemented)
      return
    }
    result(ReservedRegionsReader.read(view: hostView()))
  }

  public func onListen(withArguments arguments: Any?,
                       eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    stop()
    eventSink = events
    guard ReservedRegionsReader.canObserve else {
      emit(ReservedRegionsReader.unavailable("osUnavailable"))
      return nil
    }
    let observer = HostViewObserver(hostView: hostView) { [weak self] view, active in
      guard let self = self else { return }
      if !active, view?.window != nil {
        self.emit(ReservedRegionsReader.unavailable("inactive"))
      } else {
        self.emit(ReservedRegionsReader.read(view: view))
      }
    }
    viewObserver = observer
    observer.start()
    return nil
  }

  private func emit(_ payload: [String: Any]) {
    let dictionary = NSDictionary(dictionary: payload)
    guard previous == nil || !dictionary.isEqual(previous) else { return }
    previous = dictionary
    eventSink?(payload)
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stop()
    return nil
  }

  private func stop() {
    viewObserver?.stop()
    viewObserver = nil
    eventSink = nil
    previous = nil
  }

  deinit { stop() }
}
