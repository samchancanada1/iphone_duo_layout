import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iphone_duo_layout/iphone_duo_layout.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('registered iOS bridge returns an explicit native status', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
    await tester.pumpAndSettle();
    final bridge = NativeReservedRegions();
    final result = await bridge.read();
    expect(
      result.availability,
      isNot(ReservedRegionsAvailability.pluginUnavailable),
    );
    expect(
      result.availability,
      isNot(ReservedRegionsAvailability.unsupportedPlatform),
    );
    if (result.isAvailable) {
      expect(result.viewSize, isNotNull);
      expect(result.regions, isNotNull);
    } else {
      expect(result.regions, isNull);
    }
    final update = await bridge.watch().first.timeout(
      const Duration(seconds: 5),
    );
    expect(update.availability, result.availability);
  });
  testWidgets(
    'hinge channel is registered and reports an explicit initial status',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
      await tester.pumpAndSettle();
      final snapshot = await const NativeHinge().watch().first.timeout(
        const Duration(seconds: 5),
      );
      expect(
        snapshot.availability,
        isNot(HingeAvailability.unsupportedPlatform),
      );
      if (snapshot.isAvailable) {
        expect(snapshot.angleDegrees!.isFinite, true);
        expect(snapshot.status, isNotNull);
      } else {
        expect(snapshot.angleDegrees, isNull);
        expect(snapshot.status, isNull);
      }
      // The initial waiting event proves registration only, not a hardware sample.
    },
  );
}
