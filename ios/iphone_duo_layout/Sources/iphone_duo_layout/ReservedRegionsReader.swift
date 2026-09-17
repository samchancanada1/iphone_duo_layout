import UIKit

/// All messages use the attached Flutter host view's coordinate space, in points.
/// No device-name detection, screen-width heuristic, or invented hinge is used.
enum ReservedRegionsReader {
  static var canObserve: Bool {
    if #available(iOS 27.1, *) { return true }
    return false
  }

  static func unavailable(_ reason: String) -> [String: Any] {
    return ["version": 1, "availability": reason, "regions": NSNull()]
  }

  static func read(view: UIView?) -> [String: Any] {
    // Direct native API access. Build with an SDK providing these declarations.
    guard #available(iOS 27.1, *) else { return unavailable("osUnavailable") }
    guard let view = view, view.window != nil else {
      return unavailable("viewUnavailable")
    }
    let active = view.window?.windowScene.map { $0.activationState == .foregroundActive }
      ?? (UIApplication.shared.applicationState == .active)
    if !active {
      return unavailable("inactive")
    }
    // Default queries return ACTIVE regions only. Do not infer inactive regions.
    let divisions = view.reservedRegions(kind: .division)
    let occlusions = view.reservedRegions(kind: .occlusion)
    let regions = divisions.map(\.frame).sorted(by: frameOrder).map { encode($0, kind: "division") }
      + occlusions.map(\.frame).sorted(by: frameOrder).map { encode($0, kind: "occlusion") }
    return [
      "version": 1,
      "availability": "available",
      "coordinateSpace": "flutterView",
      "width": Double(view.bounds.width),
      "height": Double(view.bounds.height),
      "regions": regions,
    ]
  }

  // Region ordering is not an identity. Canonicalize frames so reordered native
  // collections do not produce duplicate geometry events.
  private static func frameOrder(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    let left = [lhs.minX, lhs.minY, lhs.width, lhs.height]
    let right = [rhs.minX, rhs.minY, rhs.width, rhs.height]
    return left.lexicographicallyPrecedes(right)
  }

  private static func encode(_ rect: CGRect, kind: String) -> [String: Any] {
    return ["kind": kind, "x": Double(rect.minX), "y": Double(rect.minY),
            "width": Double(rect.width), "height": Double(rect.height)]
  }
}
