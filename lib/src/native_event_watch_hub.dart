import 'dart:async';

import 'package:flutter/services.dart';

/// One owner for the standard Flutter EventChannel wire protocol.
///
/// EventChannel.receiveBroadcastStream reports activation errors via FlutterError
/// rather than the returned stream. Handling listen/cancel here lets the caller
/// receive those errors and lets each listener receive the cached snapshot.
class NativeEventWatchHub<T extends Object> {
  NativeEventWatchHub(String channelName, this.decode)
    : _channel = MethodChannel(channelName);

  final MethodChannel _channel;
  final T Function(Object?) decode;
  static const _codec = StandardMethodCodec();

  late final Stream<T> stream = Stream.multi(_listen, isBroadcast: true);
  _WatchSession<T>? _session;
  Future<void> _pending = Future<void>.value();

  void _listen(MultiStreamController<T> listener) {
    final session = _session ??= _WatchSession<T>();
    final needsStart = session.listeners.isEmpty;
    session.listeners.add(listener);
    listener.onCancel = () {
      session.listeners.remove(listener);
      if (session.listeners.isEmpty) return _finish(session);
      return Future<void>.value();
    };
    final latest = session.latest;
    if (latest != null) listener.add(latest);
    if (needsStart) _enqueue(() => _start(session));
  }

  /// Serialize native transitions. A delayed old cancel cannot cancel a new
  /// session or remove the new session's binary message handler.
  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    // A failed cleanup must not poison the queue. The original result is still
    // returned to the cancelling subscription, which can await the error.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _start(_WatchSession<T> session) async {
    if (session.ended) return;
    try {
      _channel.binaryMessenger.setMessageHandler(_channel.name, (
        message,
      ) async {
        if (session.ended) return null;
        if (message == null) {
          _finish(session, notifyCleanupErrors: true);
          return null;
        }
        try {
          final snapshot = decode(_codec.decodeEnvelope(message));
          session.latest = snapshot;
          for (final listener in session.listeners.toList()) {
            listener.add(snapshot);
          }
        } catch (error, stack) {
          _report(session, error, stack);
        }
        return null;
      });
      session.handlerInstalled = true;
      // Install the handler first: Swift may emit its initial result before
      // replying to listen, so that event must not be lost.
      session.listenAttempted = true;
      await _channel.invokeMethod<void>('listen');
    } catch (error, stack) {
      session.startFailed = true;
      if (!session.ended) {
        _report(session, error, stack);
        _finish(session, notifyCleanupErrors: true);
      }
    }
  }

  void _report(_WatchSession<T> session, Object error, StackTrace stack) {
    for (final listener in session.listeners.toList()) {
      listener.addError(error, stack);
    }
  }

  Future<void> _finish(
    _WatchSession<T> session, {
    bool notifyCleanupErrors = false,
  }) {
    if (session.ended) return session.cleanup!;
    session.ended = true;
    if (identical(_session, session)) _session = null;
    session.latest = null;
    final listeners = session.listeners.toList();
    session.listeners.clear();
    // Do not await cleanup from _start: cleanup is queued after _start itself.
    final cleanup = _enqueue(() => _stop(session));
    if (notifyCleanupErrors) {
      // No caller awaits cancel() on a native-initiated close. Deliver failure
      // through onError before onDone, rather than an unhandled Future error.
      // Keep onCancel's completion successful after the error was delivered.
      session.cleanup = cleanup.then<void>(
        (_) {
          for (final listener in listeners) {
            listener.close();
          }
        },
        onError: (Object error, StackTrace stack) {
          for (final listener in listeners) {
            listener.addError(error, stack);
            listener.close();
          }
        },
      );
    } else {
      // Explicit cancellation returns its cleanup failure to the caller.
      session.cleanup = cleanup;
      for (final listener in listeners) {
        listener.close();
      }
    }
    return session.cleanup!;
  }

  Future<void> _stop(_WatchSession<T> session) async {
    if (session.handlerInstalled) {
      _channel.binaryMessenger.setMessageHandler(_channel.name, null);
    }
    if (!session.listenAttempted) return;
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {
      // A failed listen may not have created a native stream. Cleanup is best
      // effort in that case; the original startup error has already been sent.
      if (!session.startFailed) rethrow;
    }
  }
}

class _WatchSession<T extends Object> {
  final listeners = <MultiStreamController<T>>{};
  T? latest;
  bool handlerInstalled = false;
  bool listenAttempted = false;
  bool startFailed = false;
  bool ended = false;
  Future<void>? cleanup;
}
