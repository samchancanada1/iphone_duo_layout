import 'package:flutter/foundation.dart';

import 'hinge_snapshot.dart';
import 'native_event_watch_hub.dart';

/// Live native hinge information for interactions and effects.
/// Use reserved regions, rather than hinge angles, to place content.
class NativeHinge {
  const NativeHinge();

  static final _watchHub = NativeEventWatchHub<HingeSnapshot>(
    'iphone_duo_layout/hinge_changes',
    HingeSnapshot.fromMessage,
  );

  /// Shares one native observer and replays its latest snapshot per Dart isolate.
  ///
  /// Native callbacks provide angles; there is no inferred angle or read().
  /// [HingeAvailability.waiting] means no native hinge callback has arrived yet.
  /// [HingeAvailability.noHinge] requires an explicit native no-hinge result.
  /// Inactive/detached views clear live data and reattach when available again.
  ///
  /// Activation errors reach onError and close the session; subscribe again to
  /// retry. Malformed events reach onError without ending observation. Await
  /// cancellation to release resources; the last listener clears the cache.
  Stream<HingeSnapshot> watch() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return Stream.value(
        HingeSnapshot.unavailable(HingeAvailability.unsupportedPlatform),
      );
    }
    return _watchHub.stream;
  }
}
