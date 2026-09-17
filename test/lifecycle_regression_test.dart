import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iphone_duo_layout/iphone_duo_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const arrangement = MethodChannel('iphone_duo_layout/arrangement');
  const toolbar = MethodChannel('iphone_duo_layout/toolbar');
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);
  tearDown(() {
    messenger.setMockMethodCallHandler(arrangement, null);
    messenger.setMockMethodCallHandler(toolbar, null);
  });

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets(
    'covered arrangements release probes and reject pending replies',
    (tester) async {
      final calls = <String>[];
      final pending = Completer<Object?>();
      Map? request;
      messenger.setMockMethodCallHandler(arrangement, (call) async {
        calls.add(call.method);
        final args = call.arguments as Map;
        if (call.method == 'beginClient') {
          return {'version': 1, 'client': args['client']};
        }
        if (call.method == 'dispose') {
          return {'version': 1, 'owner': args['owner'], 'disposed': true};
        }
        request = args;
        if (!pending.isCompleted) return pending.future;
        return {
          'version': 1,
          'owner': args['owner'],
          'revision': args['revision'],
          'availability': 'waiting',
        };
      });
      final snapshots = <ArrangementSnapshot>[];
      Widget build(bool enabled) => Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: enabled,
          child: NativeArrangement.split(
            primary: const Text('first'),
            secondary: const Text('second'),
            onSnapshotChanged: snapshots.add,
          ),
        ),
      );
      await tester.pumpWidget(build(true));
      await flush(tester);
      expect(request, isNotNull);
      await tester.pumpWidget(build(false));
      pending.complete({
        'version': 1,
        'owner': request!['owner'],
        'revision': request!['revision'],
        'availability': 'viewUnavailable',
      });
      await flush(tester);
      expect(calls.last, 'dispose');
      expect(
        snapshots.any(
          (s) => s.availability == ArrangementAvailability.viewUnavailable,
        ),
        false,
      );
      final before = calls.length;
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      expect(calls.length, before);
      await tester.pumpWidget(build(true));
      await flush(tester);
      expect(calls.last, 'read');
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
    variant: ios,
  );

  testWidgets('equivalent toolbar rebuilds do not loop after a channel error', (
    tester,
  ) async {
    var sets = 0;
    var errors = 0;
    messenger.setMockMethodCallHandler(toolbar, (call) async {
      final args = call.arguments as Map;
      if (call.method == 'beginToolbarClient') {
        return {'version': 1, 'client': args['client']};
      }
      if (call.method == 'setToolbar') {
        sets++;
        throw PlatformException(code: 'attach_failed');
      }
      return {'version': 1, 'owner': args['owner'], 'availability': 'detached'};
    });
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) => NativeToolbarHost(
            configuration: NativeToolbarConfiguration(
              title: 'Test',
              items: const [NativeToolbarItem(id: 'save', title: 'Save')],
            ),
            onAction: (_) {},
            onError: (_, _) => setState(() => errors++),
            child: Text('Errors: $errors'),
          ),
        ),
      ),
    );
    await flush(tester);
    expect(sets, 1);
    expect(errors, 1);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  }, variant: ios);

  testWidgets('toolbar defers configuration while app is inactive', (
    tester,
  ) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(toolbar, (call) async {
      calls.add(call.method);
      final args = call.arguments as Map;
      if (call.method == 'beginToolbarClient') {
        return {'version': 1, 'client': args['client']};
      }
      return {
        'version': 1,
        'owner': args['owner'],
        'revision': args['revision'],
        'availability': call.method == 'detachToolbar'
            ? 'detached'
            : 'available',
      };
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpWidget(
      NativeToolbarHost(
        configuration: NativeToolbarConfiguration(title: 'Deferred'),
        onAction: (_) {},
        child: const SizedBox(),
      ),
    );
    await flush(tester);
    expect(calls.where((c) => c == 'setToolbar'), isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush(tester);
    expect(calls.where((c) => c == 'setToolbar'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  }, variant: ios);
}
