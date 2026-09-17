## Unreleased — Package rename

- Rename the package to `iphone_duo_layout` to describe its iPhone Duo layout focus.
- Update the Dart entry point, iOS plugin class/module, channels, CocoaPods/SPM,
  example, tests and documentation. The checkout directory is now `iphone_duo_layout`.
- New import: `package:iphone_duo_layout/iphone_duo_layout.dart`.

## Unreleased — 2026-09-17

- Fix repeated toolbar error submissions on equivalent configuration rebuilds.
- Suspend Arrangement probes with ancestor TickerMode and discard delayed replies.
- Forward native stream-end cleanup errors before closing subscribers.
- Defer toolbar Host submissions in background and invalidate superseded replies.
- Clear idle transport queues and reject overflowing reserved-region bounds.
- Repair widget test isolation, add lifecycle/cleanup regressions and resolve lints.
- Validation: analyzer clean, 41 package tests and 1 example test pass; Swift syntax
  parsing passes. New-SDK compilation and native runtime validation still pending.

## Unreleased — 2026-09-15

- Add experimental NativeArrangement split/span with a single Flutter widget tree.
- Attach a passive native UIArrangementViewController, measure actual child frames,
  and return versioned viewport-relative snapshots; no inferred 50/50 split.
- Reject stale/changed view geometry, expose unavailable states and channel errors.
- Preserve supplied child slots across mode changes, excluding hidden panes from
  input/focus/semantics and disabling their tickers.
- Dispose probes on span/background/unmount and reclaim old hot-restart clients.
- Add split/span diagnostic example and deferred Dart/native regression cases.
- Prototype only: no compilation, analysis, tests or device validation performed.

## Unreleased — 2026-09-14

- Add native toolbar configuration, controller and app-level NativeToolbarHost.
- Bridge title, SF Symbols, enabled/visible actions, placement, axis preference,
  visibility priority, and persistent system overflow entries.
- Host the Flutter root inside a UIKit navigation container and use its safe area
  for the Flutter viewport; restore the original root after disposal.
- Forward versioned action IDs, reject stale/disabled callbacks, and serialize
  attachment/update/disposal across Dart owners.
- Reclaim orphaned native ownership when a new UI client starts after hot restart.
- Add example controls, Dart contract/lifecycle tests, and native restore checks.
  Source formatting/review only; compilation and tests remain deferred.


- Add NativeHinge.watch(), typed status/angle snapshots and a passive SwiftUI onHingeChange adapter.
- Distinguish waiting, noHinge, inactive and unavailable states; never invent an angle.
- Share channel subscription machinery while keeping regions and hinge streams independent.
- Scope region sampling to the host scene; invalidate inactive snapshots and sort native frames.
- Detach hinge observers on inactivity/cancellation and discard callbacks from old attachments.
- Extend the example, Dart/native regression cases and integration smoke checks. Not executed.

- Forward watch startup failures to onError and close the failed session.
- Replay the latest snapshot to late subscribers of the same observation session.
- Serialize native start/stop, discard ended-session events, and clear stale cache.
- Add five subscription regression cases for later execution; not run in this change.

- Remove the IPHONE_DUO_SDK compilation gate and sdkUnavailable fallback.
- Directly call native reserved-region APIs, retaining the iOS 27.1 runtime guard.
- Align Dart statuses, existing test fixtures, and documentation with direct use.
- Build and test execution deferred at the user's request.

## 0.1.0-dev.1

- Focus on native iOS reserved-region data and updates.
- Add typed results, explicit unsupported states, and local-coordinate helper.
- Add shared event subscription, foreground sampling, deduplication and cleanup.
- Directly enable the Apple reserved-regions adapter (unverified).
- Remove generic layout widgets and standalone safe-area metrics bridge.
