import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sneakscan/screens/paywall_page.dart';
import 'package:sneakscan/services/subscription_service.dart';

void main() {
  Widget harness() => const MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: TrialTimeline(),
      ),
    ),
  );

  testWidgets('renders all three beats of the trial', (tester) async {
    await tester.pumpWidget(harness());

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Your free trial starts'), findsOneWidget);

    expect(
      find.text('We\'ll remind you 1 day before your free trial ends'),
      findsOneWidget,
    );
    expect(
      find.text('Your subscription starts unless you cancelled beforehand'),
      findsOneWidget,
    );
  });

  testWidgets('day labels derive from kTrialDays, not literals', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    // Asserting against the constant rather than '6'/'7' is the point: this
    // fails if the copy is ever hardcoded back, instead of silently passing.
    expect(find.text('In ${kTrialDays - 1} days'), findsOneWidget);
    expect(find.text('In $kTrialDays days'), findsOneWidget);
  });

  testWidgets('the billing beat is muted, the earlier two are not', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    Color tileColorBehind(IconData icon) {
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.byIcon(icon), matching: find.byType(Container))
            .first,
      );
      return (container.decoration! as BoxDecoration).color!;
    }

    const brand = Color(0xFFBA6A37);
    expect(tileColorBehind(Icons.lock_open_rounded).withAlpha(255), brand);
    expect(
      tileColorBehind(Icons.notifications_active_rounded).withAlpha(255),
      brand,
    );
    // The charge hasn't happened yet, so this one must not read as brand.
    expect(
      tileColorBehind(Icons.workspace_premium_rounded).withAlpha(255),
      isNot(brand),
    );
  });

  testWidgets('nodes are sized to carry the screen, not sit in a list', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    // The timeline is the only content on the trial variant, so its tiles are
    // deliberately larger than PaywallFeatureRow's 44pt. Asserting a floor
    // rather than an exact value leaves room to tune without breaking.
    final tile = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Icons.lock_open_rounded),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(tile.constraints!.maxWidth, greaterThanOrEqualTo(56));

    final title = tester.widget<Text>(find.text('Today'));
    expect(title.style!.fontSize, greaterThanOrEqualTo(19));

    final body = tester.widget<Text>(find.text('Your free trial starts'));
    expect(body.style!.fontSize, greaterThanOrEqualTo(15));
  });

  testWidgets('the long middle line wraps rather than overflowing', (
    tester,
  ) async {
    // iPhone SE — the narrowest width the paywall has to survive.
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());

    expect(tester.takeException(), isNull);
  });
}
