import UIKit

@available(iOS 27.1, *)
final class NativeToolbarSession {
  let owner: String
  private(set) var revision = 0
  private(set) var isClosing = false
  private let host: UIViewController
  private weak var window: UIWindow?
  private let content: ToolbarContentController
  private let navigation: UINavigationController
  private let onAction: (String, Int) -> Void
  private var configuration: ToolbarConfiguration?
  private var constraints: [NSLayoutConstraint] = []
  private let originalTranslates: Bool
  private let originalAutoresizing: UIView.AutoresizingMask
  private var closeTimer: Timer?
  private var closeCompletions: [() -> Void] = []
  private var closed = false

  init(owner: String, host: UIViewController, window: UIWindow,
       onAction: @escaping (String, Int) -> Void) {
    let content = ToolbarContentController()
    self.content = content
    self.owner = owner
    self.host = host
    self.window = window
    self.onAction = onAction
    self.navigation = UINavigationController(rootViewController: content)
    self.originalTranslates = host.view.translatesAutoresizingMaskIntoConstraints
    self.originalAutoresizing = host.view.autoresizingMask
  }

  var stillOwnsHierarchy: Bool {
    window?.rootViewController === navigation && host.parent === content &&
      host.viewIfLoaded?.superview === content.viewIfLoaded
  }

  func install(_ configuration: ToolbarConfiguration, revision: Int) {
    // The original root is retained by this session before UIWindow releases it.
    // Only the registrar's verified root window is changed.
    window?.rootViewController = navigation
    content.flutterHost = host
    content.addChild(host)
    content.view.addSubview(host.view)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    // UIKit supplies the actual content area, including adaptive side bars.
    // Resizing Flutter's view keeps its metrics and reserved-region coordinates
    // local to that area; no hard-coded bar heights or Dart padding are needed.
    let safe = content.view.safeAreaLayoutGuide
    constraints = [
      host.view.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: safe.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
    ]
    NSLayoutConstraint.activate(constraints)
    host.didMove(toParent: content)
    // Flutter owns its routes. There is one native content controller, so UIKit
    // must not start a separate interactive-pop navigation operation.
    navigation.interactivePopGestureRecognizer?.isEnabled = false
    apply(configuration, revision: revision)
    content.setNeedsStatusBarAppearanceUpdate()
    navigation.setNeedsStatusBarAppearanceUpdate()
    navigation.view.layoutIfNeeded()
  }

  func apply(_ configuration: ToolbarConfiguration, revision: Int) {
    self.configuration = configuration
    self.revision = revision
    content.navigationItem.title = configuration.title
    content.navigationItem.largeTitleDisplayMode = .never
    let items = configuration.items.filter(\.visible)
    let leading = items.filter { $0.placement == "leading" }.map(makeItem)
    let trailing = items.filter { $0.placement == "trailing" }.map(makeItem)
    let bottom = items.filter { $0.placement == "bottom" }.map(makeItem)
    content.navigationItem.leadingItemGroups = leading.isEmpty ? [] : [
      UIBarButtonItemGroup(barButtonItems: leading, representativeItem: nil),
    ]
    content.navigationItem.trailingItemGroups = trailing.isEmpty ? [] : [
      UIBarButtonItemGroup(barButtonItems: trailing, representativeItem: nil),
    ]
    content.setToolbarItems(bottom, animated: false)
    navigation.setToolbarHidden(bottom.isEmpty, animated: false)

    let overflow = configuration.overflowItems.filter(\.visible)
    if overflow.isEmpty {
      content.navigationItem.additionalOverflowItems = nil
    } else {
      let currentRevision = revision
      content.navigationItem.additionalOverflowItems = UIDeferredMenuElement { [weak self] completion in
        guard let self = self, !self.isClosing, self.revision == currentRevision else {
          completion([])
          return
        }
        completion(overflow.map { self.makeAction($0, revision: currentRevision) })
      }
    }
    content.view.setNeedsLayout()
  }

  private func makeAction(_ item: ToolbarItemConfiguration, revision: Int) -> UIAction {
    // Unknown SF Symbol names fall back to the supplied title, not a fake icon.
    let image = item.systemImage.flatMap { UIImage(systemName: $0) }
    return UIAction(title: item.title, image: image,
                    attributes: item.enabled ? [] : [.disabled]) { [weak self] _ in
      guard let self = self, !self.isClosing, self.stillOwnsHierarchy,
            self.revision == revision, let configuration = self.configuration,
            (configuration.items + configuration.overflowItems).contains(where: {
              $0.id == item.id && $0.enabled && $0.visible
            }) else { return }
      self.onAction(item.id, revision)
    }
  }

  private func makeItem(_ item: ToolbarItemConfiguration) -> UIBarButtonItem {
    let button = UIBarButtonItem(title: item.title, image: nil,
                                 primaryAction: makeAction(item, revision: revision), menu: nil)
    button.isEnabled = item.enabled
    button.accessibilityLabel = item.title
    switch item.priority {
    case "high": button.visibilityPriority = .high
    case "low": button.visibilityPriority = .low
    default: break
    }
    switch item.axis {
    case "horizontalOnly": button.axisBehavior = .horizontalOnly
    case "verticalPreferred": button.axisBehavior = .verticalPreferred
    default: break
    }
    return button
  }

  func close(completion: @escaping () -> Void) {
    if closed { completion(); return }
    isClosing = true
    closeCompletions.append(completion)
    attemptClose()
    guard !closed, closeTimer == nil else { return }
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.attemptClose() }
    closeTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func attemptClose() {
    guard !closed else { return }
    // Do not dismiss native dialogs, pickers or sheets owned by the app. Wait
    // until their transitions finish before moving their presenting controller.
    let controllers = [host, content, navigation]
    guard controllers.allSatisfy({
      $0.presentedViewController == nil && !$0.isBeingPresented &&
        !$0.isBeingDismissed && $0.transitionCoordinator == nil
    }) else { return }
    closeTimer?.invalidate()
    closeTimer = nil
    let ownsRoot = window?.rootViewController === navigation
    if host.parent === content {
      host.willMove(toParent: nil)
      NSLayoutConstraint.deactivate(constraints)
      constraints.removeAll()
      host.viewIfLoaded?.removeFromSuperview()
      host.removeFromParent()
      host.viewIfLoaded?.translatesAutoresizingMaskIntoConstraints = originalTranslates
      host.viewIfLoaded?.autoresizingMask = originalAutoresizing
    }
    content.flutterHost = nil
    // Another owner may have replaced the root. Never overwrite its controller.
    if ownsRoot, host.parent == nil { window?.rootViewController = host }
    configuration = nil
    closed = true
    let completions = closeCompletions
    closeCompletions.removeAll()
    completions.forEach { $0() }
  }

  deinit { closeTimer?.invalidate() }
}

/// Owns the navigation item while forwarding system preferences to Flutter.
private final class ToolbarContentController: UIViewController {
  weak var flutterHost: UIViewController?

  override func loadView() {
    view = UIView()
    view.backgroundColor = .systemBackground
  }

  override var childForStatusBarStyle: UIViewController? { flutterHost }
  override var childForStatusBarHidden: UIViewController? { flutterHost }
  override var childForHomeIndicatorAutoHidden: UIViewController? { flutterHost }
  override var childForScreenEdgesDeferringSystemGestures: UIViewController? { flutterHost }
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    flutterHost?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
  }
  override var shouldAutorotate: Bool { flutterHost?.shouldAutorotate ?? super.shouldAutorotate }
}
