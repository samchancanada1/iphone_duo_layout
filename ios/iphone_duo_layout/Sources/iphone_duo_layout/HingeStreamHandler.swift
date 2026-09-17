import Flutter
import SwiftUI
import UIKit

/// One passive SwiftUI observer attached to this engine's Flutter controller.
/// Public onHingeChange is the data source; no screen-size or angle inference.
final class HingeStreamHandler: NSObject, FlutterStreamHandler {
  private let hostController: () -> UIViewController?
  private var eventSink: FlutterEventSink?
  private var viewObserver: HostViewObserver?
  private var hostingController: UIViewController?
  private weak var attachedParent: UIViewController?
  private weak var attachedView: UIView?
  private weak var attachedWindow: UIWindow?
  private var generation = UUID()
  private var previous: NSDictionary?

  init(hostController: @escaping () -> UIViewController?) {
    self.hostController = hostController
    super.init()
  }

  func onListen(withArguments arguments: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    stop()
    eventSink = events
    guard #available(iOS 27.1, *) else {
      emitUnavailable("osUnavailable")
      return nil
    }
    let observer = HostViewObserver(
      hostView: { [weak self] in self?.hostController()?.viewIfLoaded },
      interval: 0.25
    ) { [weak self] view, active in
      self?.updateAttachment(view: view, active: active)
    }
    viewObserver = observer
    observer.start()
    return nil
  }

  @available(iOS 27.1, *)
  private func updateAttachment(view: UIView?, active: Bool) {
    guard let parent = hostController(), let view = view, let window = view.window,
          parent.viewIfLoaded === view else {
      detach()
      emitUnavailable("viewUnavailable")
      return
    }
    guard active else {
      detach()
      emitUnavailable("inactive")
      return
    }
    if attachedParent === parent, attachedView === view, attachedWindow === window,
       hostingController?.viewIfLoaded?.superview === view { return }
    detach()
    emitUnavailable("waiting")
    let token = generation
    let content = HingeObserverView { [weak self] payload in
      // Queue outside the SwiftUI update. A detached observer may have already
      // scheduled a callback; its generation must never populate a new session.
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.generation == token,
              let currentView = self.attachedView,
              let currentWindow = currentView.window,
              currentWindow === self.attachedWindow,
              self.hostController() === self.attachedParent,
              self.hostController()?.viewIfLoaded === currentView,
              self.hostingController?.viewIfLoaded?.superview === currentView else { return }
        let active = currentWindow.windowScene.map { $0.activationState == .foregroundActive }
          ?? (UIApplication.shared.applicationState == .active)
        guard active else { return }
        self.emit(payload)
      }
    }
    let controller = UIHostingController(rootView: content)
    hostingController = controller
    attachedParent = parent
    attachedView = view
    attachedWindow = window
    parent.addChild(controller)
    controller.view.backgroundColor = .clear
    controller.view.isUserInteractionEnabled = false
    controller.view.accessibilityElementsHidden = true
    controller.view.frame = view.bounds
    controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(controller.view)
    controller.didMove(toParent: parent)
  }

  private func emitUnavailable(_ reason: String) {
    emit(["version": 1, "availability": reason,
          "status": NSNull(), "angleDegrees": NSNull()])
  }

  private func emit(_ payload: [String: Any]) {
    guard eventSink != nil else { return }
    let dictionary = NSDictionary(dictionary: payload)
    guard previous == nil || !dictionary.isEqual(previous) else { return }
    previous = dictionary
    eventSink?(payload)
  }

  private func detach() {
    generation = UUID()
    hostingController?.willMove(toParent: nil)
    hostingController?.viewIfLoaded?.removeFromSuperview()
    hostingController?.removeFromParent()
    hostingController = nil
    attachedParent = nil
    attachedView = nil
    attachedWindow = nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stop()
    return nil
  }

  private func stop() {
    viewObserver?.stop()
    viewObserver = nil
    detach()
    eventSink = nil
    previous = nil
  }

  deinit { stop() }
}

@available(iOS 27.1, *)
private struct HingeObserverView: View {
  let onChange: ([String: Any]) -> Void

  var body: some View {
    Color.clear
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .onHingeChange { _, context in
        guard let hinge = context.hinge else {
          onChange(["version": 1, "availability": "noHinge",
                    "status": NSNull(), "angleDegrees": NSNull()])
          return
        }
        let status: String
        switch hinge.status {
        case .closed: status = "closed"
        case .partiallyOpen: status = "partiallyOpen"
        case .fullyOpen: status = "fullyOpen"
        @unknown default: status = "unknown"
        }
        onChange(["version": 1, "availability": "available",
                  "status": status, "angleDegrees": hinge.angle.degrees])
      }
  }
}
