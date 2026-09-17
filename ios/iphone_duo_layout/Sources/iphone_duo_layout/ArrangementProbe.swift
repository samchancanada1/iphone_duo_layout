import UIKit

/// EXPERIMENTAL: public Arrangement APIs with empty primary/secondary content.
/// Empty child sizing equivalence and passive-host behavior need device validation.
@available(iOS 27.1, *)
final class ArrangementProbe {
  private weak var host: UIViewController?
  private weak var hostView: UIView?
  private weak var window: UIWindow?
  private let arrangement = UIArrangementViewController()
  private let primary = ArrangementPlaceholder()
  private let secondary = ArrangementPlaceholder()
  private var axis: String?

  init(host: UIViewController, view: UIView, window: UIWindow) {
    self.host = host
    self.hostView = view
    self.window = window
    arrangement.setViewController(primary, for: .primary)
    arrangement.setViewController(secondary, for: .secondary)
    host.addChild(arrangement)
    arrangement.view.backgroundColor = .clear
    arrangement.view.isUserInteractionEnabled = false
    arrangement.view.accessibilityElementsHidden = true
    // Do not set isHidden or alpha=0: UIKit must run real layout in this window.
    // All actual content remains in Flutter. The probe never receives input.
    view.addSubview(arrangement.view)
    arrangement.didMove(toParent: host)
  }

  func matches(host: UIViewController, view: UIView, window: UIWindow) -> Bool {
    self.host === host && hostView === view && self.window === window &&
      arrangement.parent === host && arrangement.viewIfLoaded?.superview === view
  }

  func measure(viewport: CGRect, axis: String) -> (primary: [String: Any], secondary: [String: Any])? {
    guard let hostView = hostView, hostView.window === window else { return nil }
    UIView.performWithoutAnimation {
      arrangement.view.frame = CGRect(x: viewport.minX + hostView.bounds.minX,
                                      y: viewport.minY + hostView.bounds.minY,
                                      width: viewport.width, height: viewport.height)
      if self.axis != axis {
        self.axis = axis
        switch axis {
        case "horizontal": arrangement.updateArrangement(.split.axes(.horizontal))
        case "vertical": arrangement.updateArrangement(.split.axes(.vertical))
        default: arrangement.updateArrangement(.split)
        }
      }
      arrangement.view.setNeedsLayout()
      arrangement.view.layoutIfNeeded()
    }
    let primaryState = arrangement.state(for: .primary)
    let secondaryState = arrangement.state(for: .secondary)
    guard primaryState != nil || secondaryState != nil else { return nil }
    guard let first = encode(primary, hasState: primaryState != nil, zIndex: Int(primaryState?.zIndex ?? 0)),
          let second = encode(secondary, hasState: secondaryState != nil, zIndex: Int(secondaryState?.zIndex ?? 0)) else { return nil }
    return (first, second)
  }

  private func encode(_ child: UIViewController, hasState: Bool, zIndex: Int) -> [String: Any]? {
    guard hasState, let view = child.viewIfLoaded, view.window === window,
          view.isDescendant(of: arrangement.view) else {
      return ["bounds": rectangle(.zero), "visible": false, "zIndex": zIndex]
    }
    let frame = view.convert(view.bounds, to: arrangement.view)
    guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }),
          frame.width >= 0, frame.height >= 0 else { return nil }
    var current: UIView? = view
    var visible = hasState && view.window === window && !frame.isEmpty
    // Visibility is observed from the actual hierarchy, not guessed from angle.
    while let ancestor = current, ancestor !== arrangement.view {
      if ancestor.isHidden || ancestor.alpha <= 0.01 { visible = false }
      current = ancestor.superview
    }
    if current == nil { visible = false }
    let intersection = frame.intersection(arrangement.view.bounds)
    if intersection.isNull || intersection.isEmpty { visible = false }
    return ["bounds": rectangle(frame), "visible": visible, "zIndex": zIndex]
  }

  private func rectangle(_ frame: CGRect) -> [String: Double] {
    ["x": Double(frame.minX), "y": Double(frame.minY),
     "width": Double(frame.width), "height": Double(frame.height)]
  }

  func detach() {
    arrangement.willMove(toParent: nil)
    arrangement.viewIfLoaded?.removeFromSuperview()
    arrangement.removeFromParent()
  }
}

private final class ArrangementPlaceholder: UIViewController {
  override func loadView() {
    view = UIView()
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    view.accessibilityElementsHidden = true
  }
}
