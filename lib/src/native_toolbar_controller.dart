import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_toolbar_configuration.dart';

/// Owns one native toolbar session. Prefer NativeToolbarHost for widget cleanup.
/// Only one owner may wrap the root Flutter controller at a time.
class NativeToolbarController {
  NativeToolbarController() {
    _owners[_owner] = this;
    if (!_handlerInstalled) {
      _channel.setMethodCallHandler(_handleNativeCall);
      _handlerInstalled = true;
    }
  }

  static const _channel = MethodChannel('iphone_duo_layout/toolbar');
  static final _owners = <String, NativeToolbarController>{};
  static bool _handlerInstalled = false;
  static int _serial = 0;
  static final _client = 'ui-${DateTime.now().microsecondsSinceEpoch}';
  static bool _initialized = false;
  // Serializes operations across widget replacements, including old disposal.
  static Future<void>? _pending;

  final String _owner = '${DateTime.now().microsecondsSinceEpoch}-${++_serial}';
  final _actions = StreamController<String>.broadcast();
  int _revision = 0;
  NativeToolbarConfiguration? _configuration;
  bool _disposed = false;
  bool _attemptedNativeSet = false;
  Future<void>? _disposal;

  Stream<String> get actions => _actions.stream;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Attaches on the first successful call and replaces content on later calls.
  /// Unavailable statuses are explicit; channel failures throw.
  Future<NativeToolbarStatus> setConfiguration(
    NativeToolbarConfiguration configuration,
  ) {
    if (_disposed) throw StateError('Toolbar controller has been disposed.');
    _configuration = configuration;
    final revision = ++_revision;
    if (!_isIOS) {
      return Future.value(
        const NativeToolbarStatus(
          NativeToolbarAvailability.unsupportedPlatform,
        ),
      );
    }
    return _enqueue(() async {
      if (_disposed) {
        return const NativeToolbarStatus(NativeToolbarAvailability.detached);
      }
      if (!_initialized) {
        final ready = await _channel.invokeMethod<Object?>(
          'beginToolbarClient',
          {'version': 1, 'client': _client},
        );
        if (ready is! Map ||
            ready['version'] != 1 ||
            ready['client'] != _client) {
          throw const FormatException(
            'Invalid toolbar client acknowledgement.',
          );
        }
        _initialized = true;
      }
      if (_disposed) {
        return const NativeToolbarStatus(NativeToolbarAvailability.detached);
      }
      _attemptedNativeSet = true;
      final response = await _channel.invokeMethod<Object?>('setToolbar', {
        'version': 1,
        'owner': _owner,
        'client': _client,
        'revision': revision,
        'configuration': configuration.toMessage(),
      });
      final status = NativeToolbarStatus.fromMessage(response);
      if (response is! Map ||
          response['owner'] != _owner ||
          response['revision'] != revision) {
        throw const FormatException('Mismatched toolbar response.');
      }
      return status;
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

  static Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'action') throw MissingPluginException();
    final message = call.arguments;
    if (message is! Map ||
        message['version'] != 1 ||
        message['owner'] is! String ||
        message['revision'] is! int ||
        message['id'] is! String) {
      throw const FormatException('Invalid toolbar action message.');
    }
    final owner = _owners[message['owner']];
    if (owner == null ||
        owner._disposed ||
        owner._revision != message['revision']) {
      return;
    }
    final configuration = owner._configuration;
    if (configuration == null) return;
    final id = message['id'] as String;
    final matches = [
      ...configuration.items,
      ...configuration.overflowItems,
    ].where((item) => item.id == id && item.enabled && item.visible);
    if (matches.isNotEmpty) owner._actions.add(id);
  }

  /// Restores the original root controller. If a native modal is presented,
  /// completion waits for its dismissal; the plugin never dismisses it itself.
  /// Actions are ignored immediately. A failed detach can be retried with dispose().
  Future<void> dispose() {
    if (_disposal != null) return _disposal!;
    _disposed = true;
    _owners.remove(_owner);
    _configuration = null;
    if (!_actions.isClosed) unawaited(_actions.close());
    final result = _enqueue(() async {
      if (!_attemptedNativeSet) return;
      try {
        final response = await _channel.invokeMethod<Object?>('detachToolbar', {
          'version': 1,
          'owner': _owner,
          'client': _client,
        });
        final status = NativeToolbarStatus.fromMessage(response);
        if (response is! Map ||
            response['owner'] != _owner ||
            status.availability != NativeToolbarAvailability.detached) {
          throw const FormatException('Toolbar detach was not acknowledged.');
        }
      } on MissingPluginException {
        // No registered native implementation means no native owner to release.
      }
    });
    _disposal = result;
    // Preserve retry after a real native failure without poisoning the queue.
    result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        _disposal = null;
      },
    );
    return result;
  }
}
