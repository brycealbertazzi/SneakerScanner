import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sneakscan/screens/paywall_page.dart';
import 'package:sneakscan/screens/paywall_priming_screen.dart';

void main() {
  testWidgets('renders the full pitch and the CTA', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: PaywallPrimingScreen(onContinue: () {})),
    );

    expect(
      find.text(
        'Everything you need to find the most profitable sneaker flips',
      ),
      findsOneWidget,
    );
    // Six benefits, sharing the paywall's own row widget.
    expect(find.byType(PaywallFeatureRow), findsNWidgets(6));
    expect(find.text('Start Finding Flips'), findsOneWidget);
  });

  testWidgets('CTA hands off to the analysis screen', (tester) async {
    var continued = 0;
    await tester.pumpWidget(
      MaterialApp(home: PaywallPrimingScreen(onContinue: () => continued++)),
    );

    await tester.tap(find.text('Start Finding Flips'));
    await tester.pumpAndSettle();

    expect(continued, 1);
  });

  testWidgets('content scrolls while the CTA stays pinned', (tester) async {
    // iPhone SE — the size at which the headline and six rows overflow.
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: PaywallPrimingScreen(onContinue: () {})),
    );
    expect(tester.takeException(), isNull);

    final ctaBefore = tester.getRect(find.text('Start Finding Flips'));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -260),
    );
    await tester.pump();

    expect(find.text('Full history of every scan'), findsOneWidget);
    expect(tester.getRect(find.text('Start Finding Flips')), ctaBefore);
  });
}
