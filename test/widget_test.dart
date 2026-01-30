import 'package:flutter_test/flutter_test.dart';

import 'package:sneaker_scanner/main.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const SneakerScannerApp());

    expect(find.text('Sneaker Scanner'), findsOneWidget);
    expect(find.text('Scan barcodes from sneaker boxes'), findsOneWidget);
    expect(find.text('Start Scanning'), findsOneWidget);
  });
}
