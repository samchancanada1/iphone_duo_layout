import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iphone_duo_layout/src/native_event_watch_hub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('test/watch_cleanup');
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('native stream end forwards cleanup failure before closing', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancel') {
        throw PlatformException(code: 'cleanup_failed');
      }
      return null;
    });
    final hub = NativeEventWatchHub<int>(channel.name, (v) => v as int);
    final errors = <Object>[];
    final done = Completer<void>();
    hub.stream.listen((_) {}, onError: errors.add, onDone: done.complete);
    await pumpEventQueue();
    await messenger.handlePlatformMessage(channel.name, null, (_) {});
    await done.future;
    await pumpEventQueue();
    expect(errors, hasLength(1));
    expect((errors.single as PlatformException).code, 'cleanup_failed');
  });

  test('explicit last cancellation returns cleanup error to caller', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancel') {
        throw PlatformException(code: 'cleanup_failed');
      }
      return null;
    });
    final hub = NativeEventWatchHub<int>(channel.name, (v) => v as int);
    final sub = hub.stream.listen((_) {});
    await pumpEventQueue();
    await expectLater(sub.cancel(), throwsA(isA<PlatformException>()));
  });
}
