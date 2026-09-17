# Package rename — 2026-09-17

The package is now `iphone_duo_layout`, with Dart entry point
`package:iphone_duo_layout/iphone_duo_layout.dart` and native class
`IPhoneDuoLayoutPlugin`. Dart imports, channel namespaces, CocoaPods/SPM names,
source paths, generated registrants, example and tests were updated together.
The checkout directory is named `iphone_duo_layout`.
Older entries below retain the historical package name where applicable.

Rename verification: dependency resolution succeeded; analyzer has no issues;
41 package tests and 1 example widget test passed. Swift syntax parsing and iOS
plist/project-file validation passed. No native new-SDK build was performed.

# Code review and validation — 2026-09-17

Reviewed all authored Dart/plugin Swift sources, example entry points, test code,
plugin manifests and iOS host setup. Generated files and dependency implementations
were not modified. Older entries below record the state at their original dates.

Confirmed and fixed:
- Equal toolbar descriptions were compared by identity. An onError callback that
  rebuilt the example retriggered the same failed native request every frame.
  Value equality now suppresses equivalent Host updates; explicit controller calls,
  changed configuration and lifecycle resume can still retry.
- Arrangement kept polling when an ancestor TickerMode disabled a retained route
  or hidden pane. It now releases its probe, rejects pending old replies and
  resumes with a fresh probe. Offstage alone is not a suspension signal.
- Native stream end followed by failed cancel produced an unhandled Future error.
  Cleanup errors now reach stream onError before onDone; explicit cancel errors
  remain visible to callers awaiting subscription.cancel().

Additional corrections:
- Defer toolbar Host submissions while inactive and invalidate old replies when a
  configuration/lifecycle change is scheduled, rather than waiting for the frame.
- Release idle transport Future queues so they do not retain previous async zones.
- Reject reserved-region rectangles whose finite components overflow when added.
- Correct platform override teardown and async waiting in previously failing tests.
- Resolve analyzer findings and use the current TickerMode.valuesOf API.

Executed checks:
- `flutter analyze`: passed, no issues (includes the example).
- Package `flutter test --reporter expanded`: 41 passed.
- Example `flutter test --reporter expanded`: 1 passed.
- `xcrun swiftc -frontend -parse` for plugin, Runner and RunnerTests Swift sources:
  passed. Parsing checks syntax only, not symbol resolution or API availability.
- Dart source formatting completed.

Environment: Flutter 3.44.6 / Dart 3.12.2; selected Xcode 26.4 and iOS Simulator
SDK 26.4. No iOS build, XCTest, device or integration test was performed in this
review: the selected SDK does not contain the directly referenced iOS 27.1 APIs.

Remaining validation gaps (not claimed fixed by mocked Dart tests):
- New Apple SDK signatures, including hinge endpoint enum cases and Arrangement
  API availability, require compilation against the corresponding SDK.
- Empty native Arrangement children, observed visibility, transparency, intrinsic
  sizing and measured frames must be validated with the actual Duo simulator.
- Native toolbar root reparenting, safe areas, keyboard, modal transitions,
  hot restart and combined toolbar/Arrangement behavior need runtime tests.
- Sampling is up to 10 Hz, not frame-synchronized native animation.

# Current prototype — 2026-09-15

Module 2 now has a source implementation for the experimental layout-result bridge:
- Flutter split/span constructors and a config-based mode switch.
- Same-window UIKit Arrangement with two empty view controllers; measured child
  rectangles and observed visibility/zIndex are applied to Flutter widgets.
- Per-owner lifecycle, client reset, geometry validation and stale-result rejection.
- A standalone diagnostic example and Dart/native regression cases were added.

Only source review and Dart formatting were performed. NO compilation, analyzer,
unit/widget tests, XCTest, integration tests or device runs for this prototype.

Do NOT treat the presence of this source as validation of the D architecture.
Required native checks: SDK signatures and runtime availability; real placement
state with empty controllers; passive host remaining visually transparent;
full/native-toolbar/nested viewport coordinates; hidden-pane behavior; camera/fold
changes; containment teardown; background return; hot restart; modal coexistence.
The prototype reads model geometry at up to 10 Hz, not native presentation-layer
animation. It does not forward Flutter intrinsic sizes to placeholder controllers.
Widget tests exercise transport/layout using mock rectangles only; they cannot
prove that the original native arrangement computes usable results on hardware.

# Current change — 2026-09-14

Module 3 (native toolbar) is now implemented in source:
- Typed Dart configuration, app-level Host and explicit controller lifecycle.
- Native UINavigationController containment with Flutter in its content safe area.
- Native actions and overflow, priority/axis settings, stale action rejection.
- Root restoration, owner checks and deferred teardown while native modals remain.
- Example and Dart/native regression cases added, but NOT executed.

Only source review and Dart formatting were performed. NO compilation, analyzer,
unit/widget tests, XCTest, integration tests or device runs for the toolbar.

Toolbar validation still required:
- Compile the direct iOS 27.1 axisBehavior / visibilityPriority declarations.
- Verify actual horizontal/vertical bars, overflow compression, SF Symbols,
  touch targets and accessibility labels on supported devices.
- Verify Flutter text input/keyboard, rotation, content safe area, and viewport
  updates when hosted as a child of the navigation content controller.
- Verify appearance callbacks and modal completion during root restoration.
- Verify Flutter Navigator gestures and route-driven configuration updates.
- Main UI isolate and standalone Flutter root only. Existing native containers
  are rejected. Verify hot-restart client takeover and restoration on-device.


Development continued on modules 1 and 4:
- Regions: per-host scene lifecycle, explicit inactive/null geometry, stable frame ordering.
- Hinge: typed stream, SwiftUI observation host, native status and degrees, attachment cleanup.
- Shared Dart stream owner with independent caches/activation for each module.
- Added Dart decoding/isolation/recovery cases, a native missing-host/restart case,
  and a registration-only hinge integration smoke check; updated the example.

Only source review and Dart formatting were performed for these additions.
NO compilation, analysis, unit tests, XCTest, integration tests or device runs.

Native follow-up still required: verify exact new-SDK hinge status case names
(closed / partiallyOpen / fullyOpen), availability annotations, initial callback
behavior, and callback delivery through the passive UIHostingController.
The official session shows onHingeChange, context.hinge, partiallyOpen and Angle;
closed/fullyOpen case spellings are inferred from the described states and await
SDK compilation. The adapter stays at waiting until an actual callback arrives.
A passing registration smoke check would NOT validate live hinge measurement.
Check touch/accessibility behavior, resizing, foreground return, host replacement,
window transitions and stale callback rejection on a supported device.


Subscription logic was revised after code review: explicit EventChannel protocol
activation errors, per-listener replay, ordered start/stop, and session cleanup.
Five regression cases were added for missing channels, rejected activation/retry,
late subscribers/cache reset, overlapping cancel/restart, and native stream end.
These new cases have NOT been executed. No analysis, builds, or tests were run.

Direct native API access is enabled. The SDK compilation gate and sdkUnavailable
fallback were removed; the runtime iOS version and view-attachment checks remain.
Existing test fixtures were updated from sdkUnavailable to osUnavailable.

No builds, analysis, or tests were run for this change, per the user's request.
The historical results below apply to the previous, gated implementation only.
They do not validate the current directly enabled native API calls.

# Validation — 2026-09-12

Environment: Flutter 3.44.6, Dart 3.12.2, Xcode 26.4, iOS Simulator SDK 26.4.

- `flutter analyze`: passed, no issues.
- Package `flutter test`: 7 tests passed. Covers status semantics, region decoding,
  coordinate translation, invalid payload rejection, platform fallback,
  native method dispatch/errors, shared subscriptions/cancellation/restart.
- `cd example && flutter test`: 1 widget test passed.
- `cd example && flutter build ios --simulator --debug --no-codesign`:
  passed; Swift plugin and example compiled into Runner.app with the default
  (new SDK adapter disabled) build configuration.

Not verified:

- `IPHONE_DUO_SDK` conditional branch: no iOS 27.1 SDK installed.
- iPhone Duo hardware, actual reserved-region positions, camera/hinge changes.
- Device event timing, native sampling lifecycle and coordinate correctness during
  folding and multiwindow transitions.
- Native XCTest and device integration test execution: tests are provided, but
  no simulator was already booted. The successful build is not a runtime test.

An initial build in a temporary directory named `package` failed SwiftPM identity
resolution; rebuilding in `native_adaptive_layout` passed. The example widget test
must run from `example/` so its own package imports resolve correctly.
