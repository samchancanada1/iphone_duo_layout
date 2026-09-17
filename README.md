# iphone_duo_layout

**English** | [繁體中文](https://github.com/samchancanada1/iphone_duo_layout/blob/main/README.zh-TW.md)

![iPhone Duo layout package overview](https://raw.githubusercontent.com/samchancanada1/iphone_duo_layout/main/doc/media/hero.png)

A Flutter package for **iPhone Duo layout adaptation**, bridging native layouts,
reserved regions, hinge information, and system toolbars.

The package exposes native iOS **Reserved Regions** and **Hinge** information to
Flutter. It implements region queries and observation, native toolbars, and hinge
state and angle bridging. An experimental split/span prototype uses Swift to
measure native Arrangement layouts while Flutter renders the content.
Native SDK compilation and device validation of this layout bridge are still
pending. Multi-window and external-display interfaces are left for future modules.

## Feature preview

![Illustrated split, span, reserved regions and native toolbar preview](https://raw.githubusercontent.com/samchancanada1/iphone_duo_layout/main/doc/media/layout-preview.gif)

These interfaces and animations use sample data and are **concept illustrations,
not simulator or device recordings**. Native SDK compilation and device behavior
still need validation. The animation does not demonstrate frame-by-frame native
synchronization.

[View the split/span comparison](https://raw.githubusercontent.com/samchancanada1/iphone_duo_layout/main/doc/media/layout-modes.png) · [Assets and regeneration instructions](doc/media/README.md)

## Current status

**Native API calls are enabled directly. Dart analysis and tests pass; compilation
with the required native SDK and device validation are still pending.**

- `read()` calls `UIView.reservedRegions(kind:)` directly.
- `NativeReservedRegions.watch()` subscribes to region updates on supported iOS versions.
- `NativeHinge.watch()` reports hinge state and angle through SwiftUI `onHingeChange`.
- `NativeToolbarHost` accepts Dart configuration, creates native navigation toolbars,
  and returns button events.
- No custom SDK compilation switch or additional Swift flag is required.
- Compile with an SDK that includes the referenced API declarations. Runtime checks
  for iOS 27.1 remain in place.
- Only native API data is reported; the package does not infer folds from screen dimensions.
- `0.1.0-dev.2` is an experimental prerelease under the [MIT license](LICENSE).
- The Swift source requires an SDK with the corresponding iOS 27.1 API declarations;
  Xcode 26.4 cannot compile these references.

## Installation

Add the prerelease version to your application's `pubspec.yaml`:

```yaml
dependencies:
  iphone_duo_layout: 0.1.0-dev.2
```

## Usage

```dart
import 'package:iphone_duo_layout/iphone_duo_layout.dart';

final regionsApi = NativeReservedRegions();
final snapshot = await regionsApi.read();

if (snapshot.isAvailable) {
  // An empty collection means the query succeeded with no active reserved regions.
  for (final region in snapshot.regions!) {
    print('${region.kind}: ${region.bounds}');
  }
} else {
  // Unavailable data does not imply the absence of fold or camera regions.
  print(snapshot.availability);
}

final subscription = regionsApi.watch().listen(
  (snapshot) {
    // Pass native region information to your existing Flutter page.
  },
  onError: (Object error) {
    // Channel and data format errors are not converted into empty region lists.
  },
);

// Cancel when leaving the page or when the data is no longer needed.
await subscription.cancel();
```

All `watch()` listeners share one native subscription. The first listener receives
the initial native result. Later listeners receive the most recently received
snapshot before subsequent updates, without needing a separate `read()` call.
If the initial result has not arrived, all listeners wait for it. Replayed data
is the latest sample, not a new synchronous query for each listener.

Channel startup failures, including an unregistered plugin, reach `onError` and
end that observation session. Subscribe again to retry. Individual native event
or data format errors reach `onError`, but the stream can continue receiving
later events. If the plugin is missing, `read()` returns `pluginUnavailable`.

Canceling the last listener clears the snapshot cache and releases the native
subscription. The next subscription obtains a fresh initial native result.
Native startup and cancellation are serialized so that cancellation from a
previous page cannot interfere with a new subscription during rapid navigation.
Use `await subscription.cancel()` if you need to know whether native cleanup succeeded.

## Arrangement split/span prototype (experimental)

```dart
// Split: place two Flutter widgets using native Arrangement measurements.
NativeArrangement.split(
  axis: NativeArrangementAxis.horizontal,
  primary: VideoWidget(),
  secondary: PlaylistWidget(),
);

// Span: fill the container with one widget without querying native Arrangement.
NativeArrangement.span(child: MapWidget());
```

Both modes use a single Flutter engine. The two regions belong to the same app
window, not separate inner/outer displays or another app's window. Span fills
the space available to the widget; it does not hide native toolbars.

To switch modes while preserving state in both panes, keep the same component
and preserve each child's type and key:

```dart
Expanded(
  child: NativeArrangement(
    mode: splitEnabled ? NativeArrangementMode.split : NativeArrangementMode.span,
    primary: VideoWidget(key: const ValueKey('video')),
    secondary: PlaylistWidget(key: const ValueKey('playlist')),
    onSnapshotChanged: (snapshot) => print(snapshot.availability),
    onError: (error, stack) => print(error),
  ),
);
```

Span displays the primary child. The retained secondary child is placed
`Offstage`, with touch input, focus, semantics, and `TickerMode` disabled.
This preserves ordinary widget state but does not automatically pause timers,
network activity, or media playback. Changing a child's type/key or removing the
secondary child still follows Flutter's normal unmounting rules.
Children should use `LayoutBuilder` constraints to adapt to their pane size;
`MediaQuery` continues to describe the Flutter view.

**Split data flow**

1. After layout, Flutter obtains the container's position and size and the logical
   dimensions of the Flutter view.
2. Swift adds a transparent, noninteractive `UIArrangementViewController` inside
   the same Flutter view, matching the container's frame. Its primary and secondary
   children are empty native view controllers.
3. The controller uses `.split` or `.split.axes(...)`. The bridge reads converted
   coordinates for the child views' actual bounds, the placement state's `zIndex`,
   and visibility observable in the view hierarchy.
4. Dart accepts results matching the current viewport and uses `Positioned` to
   place the actual Flutter widgets.

`axis` supports `automatic`, `horizontal`, and `vertical`. The system may retain
only one visible pane; two visible panes are not guaranteed. This release does
not provide an overlay style. Queries run at most once every 100 ms in the
foreground, with only one query in flight at a time. This is a layout snapshot
prototype: **it does not claim frame-by-frame animation synchronization and is
not an official Apple Flutter layout API.**

`ArrangementSnapshot` contains `availability`, `viewport` relative to the Flutter
view, `viewSize`, and the primary/secondary panes' `bounds` relative to the viewport,
`visible`, and `zIndex`. Pane fields are null when data is unavailable.
Span does not fabricate a native snapshot. `onSnapshotChanged` only reports
snapshot changes in split mode.

**Scope and error handling**

- Width and height must be finite and nonzero; use `Expanded` or `SizedBox`.
  This version supports translation only, without rotation or scaling, and requires
  the viewport to fit entirely inside the Flutter view. Do not place the entire
  Arrangement widget inside a scrolling container; each pane's content may scroll.
- When native data is unavailable, the default UI displays the status instead of
  inventing a 50/50 split. Supply your own fallback with
  `unavailableBuilder(context, snapshot, error)`.
- Availability values are `available`, `waiting`, `osUnavailable`,
  `unsupportedPlatform`, `viewUnavailable`, `inactive`, `geometryMismatch`, and
  `unsupportedGeometry`. The referenced APIs require iOS 27.1.
- Polling stops on unsupported platforms or operating systems. Channel and format
  errors are reported through `onError`/`FlutterError` and stop polling. Retry by
  switching modes, changing the axis, or remounting the widget. Temporary attachment
  or geometry mismatches continue to retry in the foreground.
- Switching to span, entering the background, disabling an ancestor `TickerMode`,
  or unmounting releases the native probe container. It is recreated when split
  mode, foreground activity, or `TickerMode` resumes. `Offstage` alone does not
  disable sampling; custom hidden containers should also use
  `TickerMode(enabled: false)`. UI client initialization removes stale probe
  containers left behind by a Dart hot restart.
- The probe does not replace the window root and can coexist with the native
  toolbar container. This integration still requires device validation.

**Key assumptions awaiting validation:** whether empty native children produce
the same Arrangement decisions as real content; whether the transparent container
has any visible decorations; and whether safe areas, pane visibility, transitions,
and coordinates stay aligned with Flutter. Visibility currently uses the native
hierarchy and placement state; this has not been confirmed to capture the full
Arrangement visibility semantics. The prototype does not pass Flutter intrinsic
sizes to native children or synchronize native presentation-layer animations.

The example is in `example/lib/arrangement_demo.dart`. The diagnostic page also
has an "Open split / span prototype" button. Counters, text input, and scrolling
content help check state preservation when switching modes. You can still try
span on platforms where native split is unavailable.

## Native toolbars

Place one `NativeToolbarHost` at the app level. Flutter supplies content and
actions; Swift uses native toolbars managed by `UINavigationController`, leaving
their appearance and adaptive layout to iOS.

```dart
MaterialApp(
  builder: (context, child) => NativeToolbarHost(
    configuration: NativeToolbarConfiguration(
      title: 'Documents',
      items: const [
        NativeToolbarItem(
          id: 'share',
          title: 'Share',
          systemImage: 'square.and.arrow.up',
          priority: NativeToolbarPriority.high,
        ),
        NativeToolbarItem(
          id: 'refresh',
          title: 'Refresh',
          systemImage: 'arrow.clockwise',
          placement: NativeToolbarPlacement.bottom,
          axis: NativeToolbarAxis.verticalPreferred,
        ),
      ],
      overflowItems: const [
        NativeToolbarItem(id: 'settings', title: 'Settings', systemImage: 'gearshape'),
      ],
    ),
    onAction: (id) {
      // Handle actions in Flutter, such as share, refresh, or settings.
    },
    onStatusChanged: (status) => print(status.availability),
    onError: (error, stack) => print(error),
    child: child!,
  ),
  home: const MyPage(),
);
```

`NativeToolbarItem` exposes the following options:

| Parameter | Description |
| --- | --- |
| `id` / `title` | Required; IDs must be unique across regular and overflow items |
| `systemImage` | Optional SF Symbols name; text is retained if the symbol cannot be found |
| `enabled` | Whether the action is enabled; defaults to true |
| `visible` | Whether the item is included in the toolbar/menu; defaults to true |
| `placement` | `leading`, `trailing` (default), or `bottom` |
| `priority` | `automatic`, `low`, or `high`; affects the order in which items move into overflow |
| `axis` | `automatic`, `horizontalOnly`, or `verticalPreferred` |

`overflowItems` are actions kept in the system "⋯" menu. Their `placement`,
`priority`, and `axis` do not participate in toolbar layout. A `high` priority
asks the system to move an item into overflow later; it does not guarantee that
the item stays visible. The system decides whether and where a vertical toolbar
appears and when items move into overflow based on available space.
Custom styling, Dart widgets as native buttons, badges, groups, and native tab
bars are not exposed in this version.

**Container and navigation integration**

- This version supports standalone Flutter apps: the registrar's Flutter
  controller must be its window's root controller, with no parent container.
  Existing UIKit navigation, tab, or add-to-app hierarchies return
  `hostUnsupported`; the plugin does not rearrange them.
- Each engine can have only one toolbar owner at a time. Conflicts return `busy`.
  Add the host once in the app builder and update its configuration as Flutter
  routes change, rather than creating a host on each page.
- The native container constrains the Flutter view to the native content safe
  area, resizing it around top, bottom, or side toolbars. Dart does not need to
  estimate bar heights or add extra toolbar padding. Flutter content does not
  extend behind native bars in this version. Reserved-region coordinates are
  relative to the resized Flutter view.
- Flutter's `Navigator` continues to manage routes. For a back button, provide an
  action and call your navigator's `maybePop` in Dart. Route titles are not
  automatically synchronized, and no UIKit navigation stack or native
  interactive-pop gesture is created.
- Configuration updates do not rebuild the container. Events from outdated
  configurations or removed, hidden, or disabled buttons are ignored.
- Removing the widget releases the native container and restores the original
  Flutter root. If the app has replaced the window root, cleanup does not
  overwrite it. When a native modal or transition is active, restoration waits
  for it to finish instead of dismissing the user's native screen.

You can also use `NativeToolbarController` directly: subscribe to `actions`, call
`setConfiguration()`, and `await dispose()` when finished. Disposal waits for
actual restoration and may remain pending while a native modal is open. When the
widget manages the controller, asynchronous disposal errors go to `onError` or
`FlutterError`.

| Status | Meaning |
| --- | --- |
| `available` | The native toolbar was created/updated; it is not necessarily displayed at the side |
| `viewUnavailable` | The window is unattached, inactive, or presenting/transitioning native UI; the host retries in the foreground |
| `hostUnsupported` | The Flutter controller is inside another native container or is not the window root |
| `busy` | Another toolbar owner is active |
| `osUnavailable` | This module requires iOS 27.1; no toolbar was created |
| `unsupportedPlatform` | The platform is not iOS; the Flutter child remains, without a substitute toolbar |
| `detached` | The toolbar owner has been released |

A missing plugin or channel failure throws an error. Use this API on the main UI
isolate. Hot reload can update the configuration. After a Dart hot restart, the
new UI client restores the previous native owner before creating a new toolbar.
If a native modal remains open, initialization waits for it to close.

## Hinge state and angle

```dart
final subscription = const NativeHinge().watch().listen(
  (snapshot) {
    if (snapshot.isAvailable) {
      print('${snapshot.status}: ${snapshot.angleDegrees}°');
      // angleRadians is also available for animation, sound, or other interactions.
    } else {
      print(snapshot.availability);
    }
  },
  onError: (Object error) => print(error),
);
await subscription.cancel();
```

| Availability | Meaning |
| --- | --- |
| `available` | Native state and angle are available; `status` and `angleDegrees` are non-null |
| `waiting` | The native observer is attached but has not received a hinge callback |
| `noHinge` | The native callback explicitly reports that no hinge is present |
| `inactive` | The owning scene is inactive; the previous angle is cleared |
| `viewUnavailable` | No Flutter controller/view/window is available for attachment |
| `osUnavailable` | The operating system is older than iOS 27.1 |
| `unsupportedPlatform` | The current platform is not iOS |

`status` values are `closed`, `partiallyOpen`, `fullyOpen`, and `unknown`.
Angles use the native degree values directly, without clamping to 0–180 or
inferring screen positions. Unavailable angles are `null`; a real zero-degree
reading remains valid. `watch().first` may return `waiting` rather than a hardware
measurement. The state stays `waiting` until the initial callback; a timeout is
not used to infer that no hinge exists.

Swift attaches a transparent `UIHostingController` inside the current engine's
Flutter controller. It does not receive touch input or accessibility focus and
obtains data through `onHingeChange`. Native callbacks push angle updates. A
foreground check every 250 ms only detects host attachment or replacement; it
does not poll the angle. Entering the background or detaching the view removes
the observer. Reattachment waits for a fresh callback. Canceling the last listener
removes the controller, lifecycle listeners, and cache. Delayed callbacks from
old observers are ignored.

The reserved-region and hinge modules each share their own native subscription
and manage their own caching and cancellation; stopping one does not stop the
other. The hinge API has no `read()` method because its source is callback-based;
cached data is not presented as a live hardware query. Channel startup failures
emit a stream error and close that observation session; subscribe again to retry.
If cleanup fails after the native stream ends, the error reaches `onError` before
`onDone`. Explicit cancellation reports cleanup failures through the Future
returned by `cancel()`.

**Use angles for interactions and effects. Use reserved-region data to keep
content clear of obstructed or divided areas.**

## Returned data and coordinates

- `division`: for example, a fold region dividing content into two sides.
- `occlusion`: for example, an area obstructed by a camera.
- Only currently **active** regions are queried. Inactive regions and inferred
  postures are not provided. Hinge angles have a separate API.
- `bounds` uses the current Flutter host view's coordinate system, in UIKit
  points. In the standard iOS Flutter embedder, these correspond to Flutter
  logical pixels.
- `viewSize` is the size of the queried view, not the device's full screen.
- Swift gets the view from the engine's registrar rather than a global key window.
  This version targets a standard single Flutter view per engine and does not
  claim support for multiple views within one engine.

Convert coordinates when a widget sits inside `SafeArea`, `AppBar`, or `Padding`:

```dart
final box = context.findRenderObject() as RenderBox;
final origin = box.localToGlobal(Offset.zero);
final localBounds = region.boundsRelativeTo(origin);
```

This helper handles translation only. Rotated or scaled widgets require the full
transform to be applied separately. Query results are asynchronous snapshots;
during rotation or resizing, do not treat a snapshot with an old `viewSize` as
the exact geometry of the current frame. The example places its overlay in a
`Stack` covering the entire Flutter view.

## Reserved-region availability

| Status | Meaning |
| --- | --- |
| `available` | The API query succeeded; `regions` is a collection that may be empty |
| `inactive` | The view's scene is not `foregroundActive`; geometry is null |
| `osUnavailable` | The operating system is older than iOS 27.1 |
| `viewUnavailable` | The engine has no attached native view that can be queried |
| `unsupportedPlatform` | This iOS plugin does not handle the current platform |
| `pluginUnavailable` | `read()` could not find the native channel implementation |

When unavailable, `regions` is `null` so that unknown geometry is not mistaken for
an absence of regions. `available` means the API can be queried; it does not imply
that the device has a hinge.

## Observation strategy and limitations

Native subscriptions sample at up to 10 Hz in the foreground and suppress
identical snapshots. Sampling follows the lifecycle of the scene owning the
current Flutter view, rather than another window's activity. When that scene
becomes inactive, the stream emits an `inactive` snapshot, clears geometry, and
stops the timer. Queries resume when the scene becomes active.

While the view is unattached, attachment checks continue in the foreground.
Timers and lifecycle observers are removed when no subscribers remain. Native
regions of the same kind are sorted by coordinates so that array order changes
alone do not emit duplicate events.

This is the initial observation strategy, **not an Apple native region-change
notification API**. It does not guarantee frame-by-frame synchronization and is
not suitable for driving hinge animations. Unsupported OS versions report
`osUnavailable` without starting sampling.

## Build requirements and pending validation

The Swift source references the new APIs directly. Neither CocoaPods nor Swift
Package Manager requires an additional opt-in flag. Compilation requires an SDK
containing `UIView.reservedRegions(kind:)`, `.division`, `.occlusion`, `frame`,
and the SwiftUI `onHingeChange`, hinge state, and angle declarations.

`#available(iOS 27.1, *)` preserves runtime fallback behavior on older operating
systems; it does not supply declarations missing from an older SDK. On
2026-09-17, Dart static analysis, 41 package tests, and one example widget test
all passed. Swift passed syntax parsing only; compilation with the required SDK
and device validation remain pending. See [VALIDATION.md](VALIDATION.md).

Pending checks include compilation against the new APIs, folding/unfolding,
inner/outer displays, split windows, camera toggling, rotation, foreground and
background transitions, `SafeArea` coordinate conversion, subscription
cancellation, and view attachment/detachment.

Hinge validation also needs to cover initial callback timing, state case
declarations, angle units, event delivery to the transparent SwiftUI observer,
absence of touch/accessibility interference, and suppression of stale events
after cancellation.

## Validation

```sh
flutter pub get --offline
flutter analyze
flutter test
cd example
flutter pub get --offline
flutter test
flutter build ios --simulator --debug --no-codesign
# Once an iOS simulator or device is available:
flutter test integration_test/plugin_integration_test.dart -d <device-id>
```

Dart mock tests validate the channel protocol; they do not establish that the new
Apple APIs have passed hardware tests. See `VALIDATION.md` for the checks that
have actually been performed.

## Official references

- [Apple: Reserved Regions and Arrangement views](https://developer.apple.com/videos/play/tech-talks/111463/)
- [Apple: Native toolbars and Duo side placement](https://developer.apple.com/videos/play/tech-talks/111462/)
- [Apple: Hinges, scenes, and multiple displays](https://developer.apple.com/videos/play/tech-talks/111464/)
- [Apple: Duo tools and SDK status](https://developer.apple.com/iphone-duo/)
- [Flutter: displayFeatures data is currently populated only on Android](https://api.flutter.dev/flutter/widgets/MediaQueryData/displayFeatures.html)
