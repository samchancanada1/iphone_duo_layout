import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iphone_duo_layout/iphone_duo_layout.dart';

Map<String, Object?> available(List<Map<String, Object?>> regions) => {
  'version': 1,
  'availability': 'available',
  'coordinateSpace': 'flutterView',
  'width': 800,
  'height': 600.0,
  'regions': regions,
};

Map<String, Object?> region({String kind = 'division', Object width = 20}) => {
  'kind': kind,
  'x': 390,
  'y': 0,
  'width': width,
  'height': 600,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel('iphone_duo_layout/regions');
  const events = MethodChannel('iphone_duo_layout/region_changes');
  const codec = StandardMethodCodec();
  const bridge = NativeReservedRegions();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test('empty successful query differs from unavailable capability', () {
    final success = ReservedRegionsSnapshot.fromMessage(available([]));
    final failure = ReservedRegionsSnapshot.fromMessage({
      'version': 1,
      'availability': 'osUnavailable',
      'regions': null,
    });
    expect(success.isAvailable, true);
    expect(success.regions, isEmpty);
    expect(failure.isAvailable, false);
    expect(failure.regions, isNull);
    expect(failure.viewSize, isNull);
  });

  test(
    'parses both region kinds, numeric types, and local coordinate offset',
    () {
      final snapshot = ReservedRegionsSnapshot.fromMessage(
        available([region(), region(kind: 'occlusion', width: 32.5)]),
      );
      expect(snapshot.viewSize, const Size(800, 600));
      expect(snapshot.regions![0].kind, ReservedRegionKind.division);
      expect(snapshot.regions![1].kind, ReservedRegionKind.occlusion);
      expect(snapshot.regions![1].bounds.width, 32.5);
      expect(
        snapshot.regions![0].boundsRelativeTo(const Offset(10, 50)),
        const Rect.fromLTWH(380, -50, 20, 600),
      );
      expect(() => snapshot.regions!.clear(), throwsUnsupportedError);
    },
  );

  test('rejects corrupt contracts instead of reporting safe empty space', () {
    final invalid = <Object?>[
      null,
      {'version': 2},
      {...available([]), 'coordinateSpace': 'screen'},
      {...available([]), 'availability': 'surprise'},
      {...available([]), 'regions': null},
      available([region(width: -1)]),
      available([region(width: double.nan)]),
      available([region(kind: 'unknown')]),
      available([
        {...region(width: 1.7e308), 'x': 1.7e308},
      ]),
      {'version': 1, 'availability': 'osUnavailable', 'regions': []},
    ];
    for (final message in invalid) {
      expect(
        () => ReservedRegionsSnapshot.fromMessage(message),
        throwsFormatException,
      );
    }
  });

  test('Android does not call the iOS bridge', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(methods, (_) async {
      fail('Non-iOS clients must not call native iOS methods.');
    });
    expect(
      (await bridge.read()).availability,
      ReservedRegionsAvailability.unsupportedPlatform,
    );
    expect(
      (await bridge.watch().first).availability,
      ReservedRegionsAvailability.unsupportedPlatform,
    );
  });

  test('iOS uses the native query and decodes actual region data', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(methods, (call) async {
      expect(call.method, 'getReservedRegions');
      expect(call.arguments, isNull);
      return available([region()]);
    });
    expect(
      (await bridge.read()).regions!.single.bounds,
      const Rect.fromLTWH(390, 0, 20, 600),
    );
  });

  test('missing plugin and unexpected platform error are distinct', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      (await bridge.read()).availability,
      ReservedRegionsAvailability.pluginUnavailable,
    );
    messenger.setMockMethodCallHandler(methods, (_) async {
      throw PlatformException(code: 'native_failure');
    });
    await expectLater(bridge.read(), throwsA(isA<PlatformException>()));
  });

  test(
    'clients share observation; native cancel waits for last subscriber',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(events, (call) async {
        calls.add(call.method);
        return null;
      });
      final firstResults = <ReservedRegionsSnapshot>[];
      final secondResults = <ReservedRegionsSnapshot>[];
      final first = bridge.watch().listen(firstResults.add);
      final second = const NativeReservedRegions().watch().listen(
        secondResults.add,
      );
      await pumpEventQueue();
      expect(calls, ['listen']);
      await messenger.handlePlatformMessage(
        'iphone_duo_layout/region_changes',
        codec.encodeSuccessEnvelope(available([region()])),
        (_) {},
      );
      await pumpEventQueue();
      expect(firstResults.single.regions, hasLength(1));
      expect(secondResults.single.regions, hasLength(1));
      await first.cancel();
      expect(calls, ['listen']);
      await second.cancel();
      await pumpEventQueue();
      expect(calls, ['listen', 'cancel']);
      final restart = bridge.watch().listen((_) {});
      await pumpEventQueue();
      expect(calls.last, 'listen');
      await restart.cancel();
    },
  );
  test('missing native event channel reaches onError and closes', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await expectLater(
      bridge.watch(),
      emitsInOrder([emitsError(isA<MissingPluginException>()), emitsDone]),
    );
    await pumpEventQueue();
  });

  test(
    'native listen rejection closes the session and permits retry',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var reject = true;
      messenger.setMockMethodCallHandler(events, (call) async {
        if (call.method == 'listen') {
          if (reject) throw PlatformException(code: 'listen_failed');
          // Native iOS sends this before replying to the listen method.
          await messenger.handlePlatformMessage(
            events.name,
            codec.encodeSuccessEnvelope(available([region()])),
            (_) {},
          );
        }
        return null;
      });
      await expectLater(
        bridge.watch(),
        emitsInOrder([
          emitsError(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'listen_failed',
            ),
          ),
          emitsDone,
        ]),
      );
      await pumpEventQueue();
      reject = false;
      final snapshot = await bridge.watch().first;
      expect(snapshot.regions!.single.bounds.width, 20);
      await pumpEventQueue();
    },
  );

  test(
    'late listeners receive the cache without another native listen',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(events, (call) async {
        calls.add(call.method);
        return null;
      });
      final stream = bridge.watch();
      final earlyValues = <ReservedRegionsSnapshot>[];
      final early = stream.listen(earlyValues.add);
      await pumpEventQueue();
      await messenger.handlePlatformMessage(
        events.name,
        codec.encodeSuccessEnvelope(available([region(width: 42)])),
        (_) {},
      );
      await pumpEventQueue();
      final lateValues = <ReservedRegionsSnapshot>[];
      final late = stream.listen(lateValues.add);
      await pumpEventQueue();
      expect(calls, ['listen']);
      expect(lateValues.single.regions!.single.bounds.width, 42);
      await messenger.handlePlatformMessage(
        events.name,
        codec.encodeSuccessEnvelope(available([])),
        (_) {},
      );
      await pumpEventQueue();
      expect(earlyValues.last.regions, isEmpty);
      expect(lateValues.last.regions, isEmpty);
      await early.cancel();
      await late.cancel();

      final freshValues = <ReservedRegionsSnapshot>[];
      final fresh = stream.listen(freshValues.add);
      await pumpEventQueue();
      expect(calls, ['listen', 'cancel', 'listen']);
      expect(freshValues, isEmpty, reason: 'Do not replay an ended session.');
      await fresh.cancel();
    },
  );

  test(
    'old cancellation completes before a replacement native listen',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final firstListenReply = Completer<void>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(events, (call) async {
        calls.add(call.method);
        if (calls.length == 1) await firstListenReply.future;
        return null;
      });
      final first = bridge.watch().listen((_) {});
      await pumpEventQueue();
      final cancelled = first.cancel();
      final nextValues = <ReservedRegionsSnapshot>[];
      final next = bridge.watch().listen(nextValues.add);
      await pumpEventQueue();
      expect(calls, ['listen']);

      // An old event while the first native listen is pending must be discarded.
      await messenger.handlePlatformMessage(
        events.name,
        codec.encodeSuccessEnvelope(available([region(width: 11)])),
        (_) {},
      );
      firstListenReply.complete();
      await cancelled;
      await pumpEventQueue();
      expect(calls, ['listen', 'cancel', 'listen']);
      expect(nextValues, isEmpty);
      await messenger.handlePlatformMessage(
        events.name,
        codec.encodeSuccessEnvelope(available([region(width: 33)])),
        (_) {},
      );
      await pumpEventQueue();
      expect(nextValues.single.regions!.single.bounds.width, 33);
      await next.cancel();
    },
  );

  test(
    'native end-of-stream closes clients and permits a fresh session',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(events, (call) async {
        calls.add(call.method);
        return null;
      });
      final completed = Completer<void>();
      bridge.watch().listen((_) {}, onDone: completed.complete);
      await pumpEventQueue();
      await messenger.handlePlatformMessage(events.name, null, (_) {});
      await completed.future;
      await pumpEventQueue();
      final next = bridge.watch().listen((_) {});
      await pumpEventQueue();
      expect(calls, ['listen', 'cancel', 'listen']);
      await next.cancel();
    },
  );
  test(
    'inactive invalidates cached geometry before foreground recovery',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      messenger.setMockMethodCallHandler(events, (_) async => null);
      final values = <ReservedRegionsSnapshot>[];
      final subscription = bridge.watch().listen(values.add);
      await pumpEventQueue();
      for (final message in [
        available([region()]),
        {'version': 1, 'availability': 'inactive', 'regions': null},
      ]) {
        await messenger.handlePlatformMessage(
          events.name,
          codec.encodeSuccessEnvelope(message),
          (_) {},
        );
        await pumpEventQueue();
      }
      final late = await bridge.watch().first;
      expect(late.availability, ReservedRegionsAvailability.inactive);
      expect(late.regions, isNull);
      expect(late.viewSize, isNull);
      await messenger.handlePlatformMessage(
        events.name,
        codec.encodeSuccessEnvelope(available([region(width: 44)])),
        (_) {},
      );
      await pumpEventQueue();
      expect(values.last.regions!.single.bounds.width, 44);
      await subscription.cancel();
    },
  );
}
