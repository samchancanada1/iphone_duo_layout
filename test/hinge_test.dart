import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iphone_duo_layout/iphone_duo_layout.dart';

Map<String, Object?> hinge({
  Object angle = 90,
  String status = 'partiallyOpen',
}) => {
  'version': 1,
  'availability': 'available',
  'status': status,
  'angleDegrees': angle,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('iphone_duo_layout/hinge_changes');
  const regions = MethodChannel('iphone_duo_layout/region_changes');
  const codec = StandardMethodCodec();
  const api = NativeHinge();

  Future<void> send(Object? payload) async {
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeSuccessEnvelope(payload),
      (_) {},
    );
    await pumpEventQueue();
  }

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(regions, null);
  });

  test('preserves native degrees, zero, unknown state and derived radians', () {
    final result = HingeSnapshot.fromMessage(hinge());
    expect(result.isAvailable, true);
    expect(result.status, HingeStatus.partiallyOpen);
    expect(result.angleDegrees, 90);
    expect(result.angleRadians, closeTo(1.5707963267948966, 1e-12));
    expect(
      HingeSnapshot.fromMessage(hinge(angle: 0, status: 'closed')).angleDegrees,
      0,
    );
    expect(
      HingeSnapshot.fromMessage(
        hinge(angle: 181.5, status: 'fullyOpen'),
      ).angleDegrees,
      181.5,
    );
    expect(
      HingeSnapshot.fromMessage(hinge(status: 'unknown')).status,
      HingeStatus.unknown,
    );
  });

  test(
    'waiting, no hinge, inactive and unavailable never fabricate angles',
    () {
      for (final status in HingeAvailability.values.where(
        (value) => value != HingeAvailability.available,
      )) {
        final value = HingeSnapshot.fromMessage({
          'version': 1,
          'availability': status.name,
          'status': null,
          'angleDegrees': null,
        });
        expect(value.availability, status);
        expect(value.isAvailable, false);
        expect(value.status, isNull);
        expect(value.angleDegrees, isNull);
        expect(value.angleRadians, isNull);
      }
      expect(
        () => HingeSnapshot.unavailable(HingeAvailability.available),
        throwsArgumentError,
      );
    },
  );

  test('rejects malformed data rather than inventing a measurement', () {
    for (final invalid in <Object?>[
      null,
      {'version': 2},
      {...hinge(), 'availability': 'surprise'},
      {...hinge(), 'status': null},
      hinge(status: 'surprise'),
      hinge(angle: double.nan),
      hinge(angle: double.infinity),
      hinge(angle: '90'),
      {...hinge(), 'availability': 'noHinge'},
      {'version': 1, 'availability': 'waiting', 'angleDegrees': 0},
    ]) {
      expect(() => HingeSnapshot.fromMessage(invalid), throwsFormatException);
    }
  });

  test('non-iOS never activates the hinge channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('Unexpected native call');
    });
    expect(
      (await api.watch().first).availability,
      HingeAvailability.unsupportedPlatform,
    );
  });

  test(
    'startup failures close observation and a new subscription can retry',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await expectLater(
        api.watch(),
        emitsInOrder([emitsError(isA<MissingPluginException>()), emitsDone]),
      );
      await pumpEventQueue();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'listen') {
          await messenger.handlePlatformMessage(
            channel.name,
            codec.encodeSuccessEnvelope(hinge(angle: 135)),
            (_) {},
          );
        }
        return null;
      });
      expect((await api.watch().first).angleDegrees, 135);
      await pumpEventQueue();
    },
  );

  test(
    'independent channels share only their own listeners and caches',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add('hinge:${call.method}');
        return null;
      });
      messenger.setMockMethodCallHandler(regions, (call) async {
        calls.add('regions:${call.method}');
        return null;
      });
      final regionValues = <ReservedRegionsSnapshot>[];
      final regionSub = const NativeReservedRegions().watch().listen(
        regionValues.add,
      );
      final values = <HingeSnapshot>[];
      final first = api.watch().listen(values.add);
      await pumpEventQueue();
      await send(hinge(angle: 72));
      final lateValues = <HingeSnapshot>[];
      final second = const NativeHinge().watch().listen(lateValues.add);
      await pumpEventQueue();
      expect(lateValues.single.angleDegrees, 72);
      expect(calls.where((value) => value == 'hinge:listen'), hasLength(1));
      await first.cancel();
      expect(calls, isNot(contains('hinge:cancel')));
      await second.cancel();
      expect(calls, contains('hinge:cancel'));
      expect(calls, isNot(contains('regions:cancel')));
      await messenger.handlePlatformMessage(
        regions.name,
        codec.encodeSuccessEnvelope({
          'version': 1,
          'availability': 'available',
          'coordinateSpace': 'flutterView',
          'width': 800,
          'height': 600,
          'regions': [],
        }),
        (_) {},
      );
      await pumpEventQueue();
      expect(regionValues.single.regions, isEmpty);
      final freshValues = <HingeSnapshot>[];
      final fresh = api.watch().listen(freshValues.add);
      await pumpEventQueue();
      expect(freshValues, isEmpty);
      await fresh.cancel();
      await regionSub.cancel();
    },
  );

  test(
    'inactive replaces cached angles; malformed events do not end recovery',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final values = <HingeSnapshot>[];
      final errors = <Object>[];
      final subscription = api.watch().listen(values.add, onError: errors.add);
      await pumpEventQueue();
      await send(hinge(angle: 45));
      await send({
        'version': 1,
        'availability': 'inactive',
        'status': null,
        'angleDegrees': null,
      });
      final late = await api.watch().first;
      expect(late.availability, HingeAvailability.inactive);
      expect(late.angleDegrees, isNull);
      await send(hinge(angle: double.nan));
      expect(errors.single, isA<FormatException>());
      await send(hinge(angle: 120));
      expect(values.last.angleDegrees, 120);
      await subscription.cancel();
    },
  );
}
