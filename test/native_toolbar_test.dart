import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iphone_duo_layout/iphone_duo_layout.dart';

NativeToolbarConfiguration configuration({bool enabled = true}) =>
    NativeToolbarConfiguration(
      title: 'Document',
      items: [
        NativeToolbarItem(
          id: 'share',
          title: 'Share',
          systemImage: 'square.and.arrow.up',
          enabled: enabled,
          priority: NativeToolbarPriority.high,
          axis: NativeToolbarAxis.verticalPreferred,
        ),
      ],
      overflowItems: const [NativeToolbarItem(id: 'archive', title: 'Archive')],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('iphone_duo_layout/toolbar');
  const codec = StandardMethodCodec();
  final controllers = <NativeToolbarController>[];

  NativeToolbarController controller() {
    final value = NativeToolbarController();
    controllers.add(value);
    return value;
  }

  Map<String, Object?> reply(MethodCall call, {String status = 'available'}) {
    final args = call.arguments as Map;
    if (call.method == 'beginToolbarClient') {
      return {'version': 1, 'client': args['client']};
    }
    return {
      'version': 1,
      'owner': args['owner'],
      'revision': args['revision'],
      'availability': call.method == 'detachToolbar' ? 'detached' : status,
    };
  }

  Future<void> action(Map args, String id, {int? revision}) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        MethodCall('action', {
          'version': 1,
          'owner': args['owner'],
          'revision': revision ?? args['revision'],
          'id': id,
        }),
      ),
      (_) {
        done.complete();
      },
    );
    await done.future;
    await pumpEventQueue();
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(channel, (call) async => reply(call));
  });

  tearDown(() async {
    for (final value in controllers) {
      await value.dispose();
    }
    controllers.clear();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'configuration copies collections and rejects ambiguous action identifiers',
    () {
      final items = [const NativeToolbarItem(id: 'save', title: 'Save')];
      final config = NativeToolbarConfiguration(title: 'Editor', items: items);
      items.clear();
      expect(config.items, hasLength(1));
      expect(() => config.items.clear(), throwsUnsupportedError);
      expect(
        () => NativeToolbarConfiguration(
          title: '',
          items: const [NativeToolbarItem(id: 'same', title: 'A')],
          overflowItems: const [NativeToolbarItem(id: 'same', title: 'B')],
        ),
        throwsArgumentError,
      );
      expect(
        () => NativeToolbarConfiguration(
          title: '',
          items: const [NativeToolbarItem(id: ' ', title: 'A')],
        ),
        throwsArgumentError,
      );
      expect(
        () => NativeToolbarConfiguration(
          title: '',
          items: const [NativeToolbarItem(id: 'a', title: ' ')],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'non-iOS keeps Flutter content without attempting native attachment',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(channel, (_) async {
        fail('Unexpected native toolbar call');
      });
      final value = controller();
      expect(
        (await value.setConfiguration(configuration())).availability,
        NativeToolbarAvailability.unsupportedPlatform,
      );
      await value.dispose();
    },
  );

  test(
    'serializes title, icon, placement, axis, priority and overflow',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'beginToolbarClient') calls.add(call);
        return reply(call);
      });
      final value = controller();
      expect((await value.setConfiguration(configuration())).isAvailable, true);
      final message = calls.single.arguments as Map;
      final config = message['configuration'] as Map;
      expect(config['title'], 'Document');
      expect(
        (config['items'] as List).single,
        containsPair('systemImage', 'square.and.arrow.up'),
      );
      expect(
        (config['items'] as List).single,
        containsPair('priority', 'high'),
      );
      expect(
        (config['items'] as List).single,
        containsPair('axis', 'verticalPreferred'),
      );
      expect(
        (config['overflowItems'] as List).single,
        containsPair('id', 'archive'),
      );
      await value.dispose();
      expect(calls.map((call) => call.method), ['setToolbar', 'detachToolbar']);
    },
  );

  test(
    'actions reject old revisions, disabled items and foreign identifiers',
    () async {
      final calls = <Map>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setToolbar') calls.add(call.arguments as Map);
        return reply(call);
      });
      final value = controller();
      final tapped = <String>[];
      final sub = value.actions.listen(tapped.add);
      await value.setConfiguration(configuration());
      await action(calls.last, 'share');
      await value.setConfiguration(configuration(enabled: false));
      await action(calls.first, 'share');
      await action(calls.last, 'share');
      await action(calls.last, 'missing');
      await action(calls.last, 'archive');
      expect(tapped, ['share', 'archive']);
      await value.dispose();
      await action(calls.last, 'archive');
      expect(tapped, ['share', 'archive']);
      await sub.cancel();
    },
  );

  test(
    'dispose during attachment restores before a replacement owner attaches',
    () async {
      final firstReply = Completer<void>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'beginToolbarClient') calls.add(call);
        if (calls.length == 1) await firstReply.future;
        return reply(call);
      });
      final old = controller();
      final attached = old.setConfiguration(configuration());
      await pumpEventQueue();
      final disposed = old.dispose();
      final next = controller();
      final nextAttach = next.setConfiguration(configuration());
      await pumpEventQueue();
      expect(calls, hasLength(1));
      firstReply.complete();
      await attached;
      await disposed;
      await nextAttach;
      expect(calls.map((call) => call.method), [
        'setToolbar',
        'detachToolbar',
        'setToolbar',
      ]);
      expect(
        (calls.first.arguments as Map)['owner'],
        isNot((calls.last.arguments as Map)['owner']),
      );
    },
  );

  test(
    'missing plugin throws and detach does not hide other native failures',
    () async {
      messenger.setMockMethodCallHandler(channel, null);
      final missing = controller();
      await expectLater(
        missing.setConfiguration(configuration()),
        throwsA(isA<MissingPluginException>()),
      );
      await missing.dispose();
      var rejectDetach = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'detachToolbar' && rejectDetach) {
          throw PlatformException(code: 'detach_failed');
        }
        return reply(call);
      });
      final value = controller();
      await value.setConfiguration(configuration());
      await expectLater(value.dispose(), throwsA(isA<PlatformException>()));
      await pumpEventQueue();
      rejectDetach = false;
      await value.dispose();
      expect(() => value.setConfiguration(configuration()), throwsStateError);
    },
  );

  test('status and ownership mismatches are not reported as success', () async {
    expect(
      () => NativeToolbarStatus.fromMessage({'version': 2}),
      throwsFormatException,
    );
    expect(
      () => NativeToolbarStatus.fromMessage({
        'version': 1,
        'availability': 'unknown',
      }),
      throwsFormatException,
    );
    final value = controller();
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'setToolbar'
          ? {...reply(call), 'owner': 'wrong-owner'}
          : reply(call),
    );
    await expectLater(
      value.setConfiguration(configuration()),
      throwsFormatException,
    );
  });

  testIOSWidgets('host updates actions and releases ownership on unmount', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'beginToolbarClient') calls.add(call);
      return reply(call);
    });
    final tapped = <String>[];
    Widget host(NativeToolbarConfiguration config) => Directionality(
      textDirection: TextDirection.ltr,
      child: NativeToolbarHost(
        configuration: config,
        onAction: tapped.add,
        child: const Text('Flutter content'),
      ),
    );
    await tester.pumpWidget(host(configuration()));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    expect(find.text('Flutter content'), findsOneWidget);
    expect(calls.where((call) => call.method == 'setToolbar'), hasLength(1));
    await tester.pumpWidget(host(configuration(enabled: false)));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'setToolbar'), hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    expect(calls.last.method, 'detachToolbar');
  });
}

// Set the override inside the widget-test zone, and restore it before the
// binding checks invariants (package:test tearDown runs after that check).
void testIOSWidgets(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
