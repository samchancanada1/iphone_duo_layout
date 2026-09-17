import UIKit

/// Samples attachment/geometry, scoped to the registrar's view and its scene.
/// Hinge angles themselves are delivered by SwiftUI, not sampled here.
final class HostViewObserver {
  private let hostView: () -> UIView?
  private let interval: TimeInterval
  private let onUpdate: (UIView?, Bool) -> Void
  private var observers: [NSObjectProtocol] = []
  private var timer: Timer?
  private var running = false

  init(hostView: @escaping () -> UIView?, interval: TimeInterval = 0.1,
       onUpdate: @escaping (UIView?, Bool) -> Void) {
    self.hostView = hostView
    self.interval = interval
    self.onUpdate = onUpdate
  }

  func start() {
    stop()
    running = true
    let center = NotificationCenter.default
    for name in [UIScene.didActivateNotification, UIApplication.didBecomeActiveNotification] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] note in
        guard let self = self, self.isRelevant(note) else { return }
        self.refresh()
      })
    }
    for name in [UIScene.willDeactivateNotification, UIApplication.willResignActiveNotification] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] note in
        guard let self = self, self.isRelevant(note) else { return }
        // willDeactivate may arrive before activationState changes.
        self.pause()
        self.onUpdate(self.hostView(), false)
      })
    }
    refresh()
  }

  private func isRelevant(_ notification: Notification) -> Bool {
    if let scene = notification.object as? UIScene {
      guard let ownScene = hostView()?.window?.windowScene else { return true }
      return scene === ownScene
    }
    // Scene notifications own the lifecycle once this view has a scene.
    return hostView()?.window?.windowScene == nil
  }

  private func refresh() {
    guard running else { return }
    let view = hostView()
    let active: Bool
    if let scene = view?.window?.windowScene {
      active = scene.activationState == .foregroundActive
    } else {
      active = UIApplication.shared.applicationState == .active
    }
    onUpdate(view, active)
    guard running else { return }
    guard active else { pause(); return }
    guard timer == nil else { return }
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      self?.refresh()
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func pause() {
    timer?.invalidate()
    timer = nil
  }

  func stop() {
    running = false
    pause()
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
  }

  deinit { stop() }
}
