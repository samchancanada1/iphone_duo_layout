import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iphone_duo_layout/iphone_duo_layout.dart';
import 'package:iphone_duo_layout/src/arrangement_bridge.dart';

Map<String, Object?> pane(double x, double width, {bool visible = true}) => {
  'bounds': {'x': x, 'y': 0, 'width': width, 'height': 600},
  'visible': visible,
  'zIndex': 0,
};
Map<String, Object?> geometry(Map args) => {
  'version': 1,
  'owner': args['owner'],
  'revision': args['revision'],
  'availability': 'available',
  'coordinateSpace': 'viewport',
  'viewport': args['viewport'],
  'viewSize': args['viewSize'],
  'primary': pane(0, 250),
  'secondary': pane(300, 500),
};
Map<String, Object?> reply(MethodCall call) {
  final args = call.arguments as Map;
  if (call.method == 'beginClient') {
    return {'version': 1, 'client': args['client']};
  }
  if (call.method == 'dispose') {
    return {'version': 1, 'owner': args['owner'], 'disposed': true};
  }
  return geometry(args);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('iphone_duo_layout/arrangement');
  const viewport = Rect.fromLTWH(0, 0, 800, 600);
  const size = Size(800, 600);
  final bridges = <ArrangementBridge>[];
  ArrangementBridge bridge() {
    final value = ArrangementBridge();
    bridges.add(value);
    return value;
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(channel, (call) async => reply(call));
  });
  tearDown(() async {
    for (final value in bridges) {
      await value.dispose();
    }
    bridges.clear();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'decodes unequal native panes and distinguishes hidden from missing data',
    () {
      final message = geometry({
        'viewport': {'x': 10, 'y': 20, 'width': 800, 'height': 600},
        'viewSize': {'width': 900, 'height': 700},
      });
      final snapshot = ArrangementSnapshot.fromMessage(message);
      expect(snapshot.viewport, const Rect.fromLTWH(10, 20, 800, 600));
      expect(snapshot.primary!.bounds.width, 250);
      expect(snapshot.secondary!.bounds.left, 300);
      final hidden = ArrangementSnapshot.fromMessage({
        ...message,
        'secondary': pane(0, 0, visible: false),
      });
      expect(hidden.isAvailable, true);
      expect(hidden.secondary!.visible, false);
      expect(snapshot, ArrangementSnapshot.fromMessage(message));
      expect(
        ArrangementSnapshot.unavailable(
          ArrangementAvailability.inactive,
        ).primary,
        isNull,
      );
    },
  );

  test('rejects corrupt geometry and unknown contracts', () {
    final base = geometry({
      'viewport': {'x': 0, 'y': 0, 'width': 800, 'height': 600},
      'viewSize': {'width': 800, 'height': 600},
    });
    for (final message in <Object?>[
      null,
      {...base, 'version': 2},
      {...base, 'coordinateSpace': 'screen'},
      {...base, 'availability': 'other'},
      {...base, 'primary': pane(0, -1)},
      {...base, 'primary': pane(double.nan, 100)},
      {...base, 'availability': 'waiting'},
    ]) {
      expect(
        () => ArrangementSnapshot.fromMessage(message),
        throwsFormatException,
      );
    }
  });

  test('bridge rejects responses for a different requested geometry', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'read'
          ? {
              ...reply(call),
              'viewport': {'x': 1, 'y': 0, 'width': 800, 'height': 600},
            }
          : reply(call),
    );
    await expectLater(
      bridge().read(
        viewport: viewport,
        viewSize: size,
        axis: NativeArrangementAxis.horizontal,
      ),
      throwsFormatException,
    );
  });

  test(
    'queued disposal cleans up a read completed after cancellation',
    () async {
      final waiting = Completer<void>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'read') await waiting.future;
        return reply(call);
      });
      final value = bridge();
      final read = value.read(
        viewport: viewport,
        viewSize: size,
        axis: NativeArrangementAxis.automatic,
      );
      await pumpEventQueue();
      final disposed = value.dispose();
      expect(calls.last, 'read');
      waiting.complete();
      await read;
      await disposed;
      expect(calls.last, 'dispose');
      expect(
        () => value.read(
          viewport: viewport,
          viewSize: size,
          axis: NativeArrangementAxis.automatic,
        ),
        throwsStateError,
      );
    },
  );

  Future<void> settleSample(WidgetTester tester) async {
    // The prototype samples periodically; pumpAndSettle would keep advancing it.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump();
    }
  }

  Widget host(Widget child) =>
      Directionality(textDirection: TextDirection.ltr, child: child);

  testIOSWidgets('span fills the container without any native request', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('Span must not call native');
    });
    await tester.pumpWidget(
      host(
        const NativeArrangement.span(child: SizedBox(key: ValueKey('span'))),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('span'))),
      tester.getSize(find.byType(NativeArrangement)),
    );
    await tester.pumpWidget(const SizedBox());
    await settleSample(tester);
  });

  testIOSWidgets(
    'split follows native rectangles and retains both States across span',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return reply(call);
      });
      Widget build(NativeArrangementMode mode) => host(
        NativeArrangement(
          mode: mode,
          primary: const CounterPane(key: ValueKey('first'), label: 'first'),
          secondary: const CounterPane(
            key: ValueKey('second'),
            label: 'second',
          ),
        ),
      );
      await tester.pumpWidget(build(NativeArrangementMode.split));
      await settleSample(tester);
      expect(
        tester.getRect(find.byKey(const ValueKey('first'))),
        const Rect.fromLTWH(0, 0, 250, 600),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('second'))),
        const Rect.fromLTWH(300, 0, 500, 600),
      );
      await tester.tap(find.text('second: 0'));
      await tester.pump();
      await tester.pumpWidget(build(NativeArrangementMode.span));
      await settleSample(tester);
      expect(find.text('second: 1'), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('first'))),
        const Size(800, 600),
      );
      expect(calls.last, 'dispose');
      await tester.pumpWidget(build(NativeArrangementMode.split));
      await settleSample(tester);
      expect(find.text('second: 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settleSample(tester);
    },
  );

  testIOSWidgets('an old split reply cannot replace a newer span layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final gate = Completer<void>();
    var requested = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'read') {
        requested = true;
        await gate.future;
      }
      return reply(call);
    });
    Widget build(NativeArrangementMode mode) => host(
      NativeArrangement(
        mode: mode,
        primary: const SizedBox(key: ValueKey('content')),
        secondary: const Text('secondary'),
      ),
    );
    await tester.pumpWidget(build(NativeArrangementMode.split));
    await settleSample(tester);
    expect(requested, true);
    await tester.pumpWidget(build(NativeArrangementMode.span));
    gate.complete();
    await settleSample(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('content'))),
      const Size(800, 600),
    );
    expect(find.text('secondary'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await settleSample(tester);
  });

  testIOSWidgets(
    'unsupported native split shows status without a fabricated division',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(
        host(
          const NativeArrangement.split(
            primary: Text('primary content'),
            secondary: Text('secondary content'),
          ),
        ),
      );
      await settleSample(tester);
      expect(find.text('Arrangement: unsupportedPlatform'), findsOneWidget);
      expect(find.text('primary content'), findsNothing);
      expect(find.text('secondary content'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await settleSample(tester);
    },
  );
}

class CounterPane extends StatefulWidget {
  const CounterPane({super.key, required this.label});
  final String label;
  @override
  State<CounterPane> createState() => _CounterPaneState();
}

class _CounterPaneState extends State<CounterPane> {
  int count = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => count++),
    child: SizedBox.expand(
      child: Center(child: Text('${widget.label}: $count')),
    ),
  );
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
