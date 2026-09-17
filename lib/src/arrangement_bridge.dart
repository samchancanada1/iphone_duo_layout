import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'arrangement_snapshot.dart';

/// Internal, main-isolate transport. Each widget owns an independent native probe.
class ArrangementBridge {
  static const _channel = MethodChannel('iphone_duo_layout/arrangement');
  static final _client = 'arrangement-${DateTime.now().microsecondsSinceEpoch}';
  static int _serial = 0;
  static bool _initialized = false;
  static Future<void>? _pending;
  final _owner = '$_client-${++_serial}';
  int _revision = 0;
  bool _disposed = false;
  bool _attempted = false;
  Future<void>? _disposal;

  Future<ArrangementSnapshot> read({
    required Rect viewport,
    required Size viewSize,
    required NativeArrangementAxis axis,
  }) {
    if (_disposed) throw StateError('Arrangement probe disposed.');
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return Future.value(
        ArrangementSnapshot.unavailable(
          ArrangementAvailability.unsupportedPlatform,
        ),
      );
    }
    final revision = ++_revision;
    return _enqueue(() async {
      if (_disposed) {
        return ArrangementSnapshot.unavailable(
          ArrangementAvailability.viewUnavailable,
        );
      }
      if (!_initialized) {
        final reply = await _channel.invokeMethod<Object?>('beginClient', {
          'version': 1,
          'client': _client,
        });
        if (reply is! Map ||
            reply['version'] != 1 ||
            reply['client'] != _client) {
          throw const FormatException(
            'Invalid arrangement client acknowledgement.',
          );
        }
        _initialized = true;
      }
      if (_disposed) {
        return ArrangementSnapshot.unavailable(
          ArrangementAvailability.viewUnavailable,
        );
      }
      _attempted = true;
      final reply = await _channel.invokeMethod<Object?>('read', {
        'version': 1,
        'client': _client,
        'owner': _owner,
        'revision': revision,
        'axis': axis.name,
        'viewport': {
          'x': viewport.left,
          'y': viewport.top,
          'width': viewport.width,
          'height': viewport.height,
        },
        'viewSize': {'width': viewSize.width, 'height': viewSize.height},
      });
      if (reply is! Map ||
          reply['owner'] != _owner ||
          reply['revision'] != revision) {
        throw const FormatException('Mismatched arrangement response.');
      }
      final snapshot = ArrangementSnapshot.fromMessage(reply);
      if (snapshot.isAvailable &&
          (snapshot.viewport != viewport || snapshot.viewSize != viewSize)) {
        throw const FormatException(
          'Native geometry does not match the requested viewport.',
        );
      }
      return snapshot;
    });
  }

  static Future<T> _enqueue<T>(Future<T> Function() operation) {
    final previous = _pending;
    final result = previous == null
        ? Future<T>.sync(operation)
        : previous.then((_) => operation());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending = tail;
    tail.then((_) {
      if (identical(_pending, tail)) _pending = null;
    });
    return result;
  }

  Future<void> dispose() {
    if (_disposal != null) return _disposal!;
    _disposed = true;
    final result = _enqueue(() async {
      if (!_attempted) return;
      try {
        final reply = await _channel.invokeMethod<Object?>('dispose', {
          'version': 1,
          'client': _client,
          'owner': _owner,
        });
        if (reply is! Map ||
            reply['version'] != 1 ||
            reply['owner'] != _owner ||
            reply['disposed'] != true) {
          throw const FormatException(
            'Arrangement disposal was not acknowledged.',
          );
        }
      } on MissingPluginException {
        // A missing implementation cannot retain a native probe.
      }
    });
    _disposal = result;
    result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        _disposal = null;
      },
    );
    return result;
  }
}
