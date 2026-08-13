import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sneakscan/main.dart';

void main() {
  testWidgets('App renders the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SneakerScannerApp());

    expect(find.text('SneakScan'), findsOneWidget);
    expect(find.text('Scan. Identify. Collect.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // SplashScreen arms a 2.5s timer that routes on to onboarding/paywall/app.
    // Tear the tree down first so the callback short-circuits on its !mounted
    // guard, then let the clock run out — otherwise it reaches Firebase and the
    // timer is still pending when the test framework checks invariants.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
