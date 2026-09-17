import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'reserved_regions_snapshot.dart';
import 'native_event_watch_hub.dart';

/// Access to Apple's native reserved-region queries, not inferred fold geometry.
class NativeReservedRegions {
  const NativeReservedRegions();

  static const _methods = MethodChannel('iphone_duo_layout/regions');
  static final _watchHub = NativeEventWatchHub<ReservedRegionsSnapshot>(
    'iphone_duo_layout/region_changes',
    ReservedRegionsSnapshot.fromMessage,
  );

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Reads active division and occlusion regions for this Flutter engine's view.
  ///
  /// May return viewUnavailable before attachment, inactive outside an active
  /// scene, or osUnavailable on older iOS.
  /// Native API access is enabled by default. Unexpected channel errors
  /// propagate instead of becoming empty data.
  Future<ReservedRegionsSnapshot> read() async {
    if (!_isIOS) return _unsupported();
    try {
      return ReservedRegionsSnapshot.fromMessage(
        await _methods.invokeMethod<Object?>('getReservedRegions'),
      );
    } on MissingPluginException {
      return ReservedRegionsSnapshot.unavailable(
        ReservedRegionsAvailability.pluginUnavailable,
      );
    }
  }

  /// Shared observation that replays the latest received snapshot to new listeners.
  ///
  /// The first listener receives the native initial result. Later listeners get
  /// the latest successful snapshot, then subsequent changes, without read().
  /// If the initial result is still pending, all listeners wait for it together.
  /// Startup failures, including MissingPluginException, are stream errors and
  /// close that observation session. A new subscription can retry afterwards.
  /// Errors in individual native events are forwarded without closing the stream.
  ///
  /// The native adapter samples at up to 10 Hz in the foreground. A replay is the
  /// latest received sample, not a fresh synchronous query or animation frame.
  /// Cancel subscriptions when done. The last cancellation releases native
  /// resources and clears the cache; a subsequent session obtains new data.
  /// Await cancel() to observe any error releasing the native subscription.
  Stream<ReservedRegionsSnapshot> watch() =>
      _isIOS ? _watchHub.stream : Stream.value(_unsupported());

  ReservedRegionsSnapshot _unsupported() => ReservedRegionsSnapshot.unavailable(
    ReservedRegionsAvailability.unsupportedPlatform,
  );
}
