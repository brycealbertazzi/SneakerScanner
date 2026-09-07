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
    // The factual proof band — no star rating, no testimonial.
    expect(find.text('StockX · GOAT · eBay'), findsOneWidget);
    expect(find.text('Live market data'), findsOneWidget);
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
    // Not pumpAndSettle: the marketplace band pulses forever, so the tree
    // never reaches a steady state.
    await tester.pump(const Duration(milliseconds: 100));

    expect(continued, 1);
  });

  testWidgets('marketplace band pulses in the brand orange', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: PaywallPrimingScreen(onContinue: () {})),
    );

    Decoration decorationAroundBand() {
      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('StockX · GOAT · eBay'),
              matching: find.byType(Container),
            )
            .first,
      );
      return container.decoration!;
    }

    double scaleOfBand() {
      return tester
          .widget<Transform>(
            find
                .ancestor(
                  of: find.text('StockX · GOAT · eBay'),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .getMaxScaleOnAxis();
    }

    final first = decorationAroundBand() as BoxDecoration;
    final firstScale = scaleOfBand();

    // Glow is the app's orange, not a neutral shadow.
    expect(first.boxShadow, isNotEmpty);
    expect(
      Color(first.boxShadow!.first.color.toARGB32()).withAlpha(255),
      const Color(0xFFBA6A37),
    );

    // Half a cycle later both the glow and the size have moved.
    await tester.pump(const Duration(milliseconds: 1100));
    final second = decorationAroundBand() as BoxDecoration;

    expect(second.boxShadow!.first.blurRadius, isNot(first.boxShadow!.first.blurRadius));
    expect(scaleOfBand(), isNot(firstScale));

    // Leave no timer running for the framework's end-of-test invariants.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('content scrolls while the CTA stays pinned', (tester) async {
    // iPhone SE — the size at which six rows plus the band overflow.
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
