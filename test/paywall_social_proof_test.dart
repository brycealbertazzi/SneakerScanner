import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sneakscan/screens/paywall_page.dart';
import 'package:sneakscan/theme/app_theme.dart';

void main() {
  Widget harness() => const MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: PaywallSocialProof(),
      ),
    ),
  );

  testWidgets('shows five amber stars', (tester) async {
    await tester.pumpWidget(harness());

    final stars = find.byIcon(Icons.star_rounded);
    expect(stars, findsNWidgets(5));

    // Amber, not the brand orange, so the stars read as a rating rather than
    // blending into the paywall's orange card outline.
    const brand = AppColors.brand;
    for (final icon in tester.widgetList<Icon>(stars)) {
      expect(icon.color, const Color(0xFFFFC107));
      expect(icon.color, isNot(brand));
    }
  });

  testWidgets('shows the quote', (tester) async {
    await tester.pumpWidget(harness());

    expect(
      find.text('“It paid for itself after just one flip”'),
      findsOneWidget,
    );
  });

  testWidgets('carries no attribution line', (tester) async {
    await tester.pumpWidget(harness());

    // The block is deliberately unattributed. Assert on the rendered text
    // rather than on a specific string, so no future edit can quietly
    // reintroduce an author under the quote.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();

    expect(texts.length, 1);
    for (final t in texts) {
      expect(t, isNot(contains('—'))); // em dash
      expect(t.toLowerCase(), isNot(contains('user')));
    }
  });

  testWidgets('fits an iPhone SE without overflowing', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());

    expect(tester.takeException(), isNull);
  });
}
