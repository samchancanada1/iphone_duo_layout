import Flutter
import UIKit
import XCTest
@testable import iphone_duo_layout

class RunnerTests: XCTestCase {
  func testMissingViewNeverReportsAnEmptySupportedQuery() {
    let plugin = IPhoneDuoLayoutPlugin(hostView: { nil })
    plugin.handle(FlutterMethodCall(methodName: "getReservedRegions", arguments: nil)) { value in
      let result = value as! [String: Any]
      XCTAssertEqual(result["version"] as? Int, 1)
      XCTAssertNotEqual(result["availability"] as? String, "available")
      XCTAssertTrue(result["regions"] is NSNull)
    }
  }
  func testHingeMissingHostNeverFabricatesAnAngleAndCanRestart() {
    let hinge = HingeStreamHandler(hostController: { nil })
    for _ in 0..<2 {
      var received: [[String: Any]] = []
      XCTAssertNil(hinge.onListen(withArguments: nil) { value in
        if let payload = value as? [String: Any] { received.append(payload) }
      })
      XCTAssertEqual(received.count, 1)
      XCTAssertNotEqual(received.first?["availability"] as? String, "available")
      XCTAssertTrue(received.first?["angleDegrees"] is NSNull)
      XCTAssertTrue(received.first?["status"] is NSNull)
      XCTAssertNil(hinge.onCancel(withArguments: nil))
    }
  }

  private func toolbarItem(_ id: String) -> [String: Any] {
    ["id": id, "title": "Share", "systemImage": "square.and.arrow.up",
     "enabled": true, "visible": true, "placement": "trailing",
     "priority": "high", "axis": "automatic"]
  }

  func testToolbarRejectsDuplicateActionsAndInvalidEnums() {
    XCTAssertThrowsError(try ToolbarConfiguration([
      "title": "Test", "items": [toolbarItem("same")],
      "overflowItems": [toolbarItem("same")],
    ]))
    var invalid = toolbarItem("share")
    invalid["axis"] = "diagonal"
    XCTAssertThrowsError(try ToolbarConfiguration([
      "title": "Test", "items": [invalid], "overflowItems": [],
    ]))
  }

  func testToolbarContainerRestoresOriginalRootAndAutoresizing() throws {
    guard #available(iOS 27.1, *) else { return }
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let host = UIViewController()
    window.rootViewController = host
    window.isHidden = false
    defer { window.isHidden = true }
    let originalTranslates = host.view.translatesAutoresizingMaskIntoConstraints
    let originalMask = host.view.autoresizingMask
    let config = try ToolbarConfiguration([
      "title": "Test", "items": [toolbarItem("share")], "overflowItems": [],
    ])
    let session = NativeToolbarSession(owner: "test", host: host, window: window) { _, _ in }
    session.install(config, revision: 1)
    XCTAssertTrue(window.rootViewController is UINavigationController)
    XCTAssertTrue(session.stillOwnsHierarchy)
    XCTAssertNotNil(host.parent)
    XCTAssertFalse(host.view.translatesAutoresizingMaskIntoConstraints)
    let finished = expectation(description: "restore root")
    session.close { finished.fulfill() }
    wait(for: [finished], timeout: 2)
    XCTAssertTrue(window.rootViewController === host)
    XCTAssertNil(host.parent)
    XCTAssertEqual(host.view.translatesAutoresizingMaskIntoConstraints, originalTranslates)
    XCTAssertEqual(host.view.autoresizingMask, originalMask)
  }

  func testToolbarDisposalDoesNotOverwriteAnExternalRootReplacement() throws {
    guard #available(iOS 27.1, *) else { return }
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let host = UIViewController()
    window.rootViewController = host
    window.isHidden = false
    defer { window.isHidden = true }
    let config = try ToolbarConfiguration(["title": "Test", "items": [], "overflowItems": []])
    let session = NativeToolbarSession(owner: "test", host: host, window: window) { _, _ in }
    session.install(config, revision: 1)
    let replacement = UIViewController()
    window.rootViewController = replacement
    let finished = expectation(description: "release old hierarchy")
    session.close { finished.fulfill() }
    wait(for: [finished], timeout: 2)
    XCTAssertTrue(window.rootViewController === replacement)
  }

  func testArrangementProbeUsesPassiveContainmentAndDetaches() {
    guard #available(iOS 27.1, *) else { return }
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let host = UIViewController()
    window.rootViewController = host
    window.isHidden = false
    defer { window.isHidden = true }
    let probe = ArrangementProbe(host: host, view: host.view, window: window)
    XCTAssertTrue(probe.matches(host: host, view: host.view, window: window))
    XCTAssertEqual(host.children.count, 1)
    XCTAssertFalse(host.children[0].view.isHidden)
    XCTAssertFalse(host.children[0].view.isUserInteractionEnabled)
    XCTAssertTrue(host.children[0].view.accessibilityElementsHidden)
    _ = probe.measure(viewport: CGRect(x: 10, y: 20, width: 700, height: 500), axis: "horizontal")
    // Placement output itself needs supported-device tests, not just containment.
    probe.detach()
    XCTAssertTrue(host.children.isEmpty)
    XCTAssertFalse(probe.matches(host: host, view: host.view, window: window))
    XCTAssertTrue(window.rootViewController === host)
  }

}
