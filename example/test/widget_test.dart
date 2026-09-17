import 'package:flutter_test/flutter_test.dart';
import 'package:iphone_duo_layout_example/main.dart';

void main() {
  testWidgets('unsupported platforms show no fabricated regions', (
    tester,
  ) async {
    await tester.pumpWidget(const RegionsExample());
    await tester.pumpAndSettle();
    expect(find.text('Status: unsupportedPlatform'), findsOneWidget);
    expect(find.text('Toolbar: unsupportedPlatform'), findsOneWidget);
    expect(
      find.textContaining('No fold or camera rectangles are simulated.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Hinge: unsupportedPlatform'));
    expect(find.text('No live angle available.'), findsOneWidget);
  });
}
