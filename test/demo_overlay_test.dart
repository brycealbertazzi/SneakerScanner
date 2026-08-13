import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sneakscan/screens/demo/demo_controller.dart';

const _mechanicsSteps = <DemoStep>[
  DemoStep(
    target: DemoTarget.enterSkuButton,
    title: 'Step one',
    body: 'Absorbs taps.',
  ),
  DemoStep(
    target: DemoTarget.enterSkuButton,
    title: 'Step two',
    body: 'Passes the tap through.',
    awaitEvent: DemoEvent.manualDialogOpened,
    actionHint: 'Tap it',
  ),
  DemoStep(title: 'Step three', body: 'Drawn over the dialog.'),
  DemoStep(title: 'Step four', body: 'Last one.'),
];

class _Harness extends StatelessWidget {
  const _Harness({
    required this.navKey,
    required this.onTargetTapped,
    this.onDecoyTapped,
  });

  final GlobalKey<NavigatorState> navKey;
  final VoidCallback onTargetTapped;

  /// Stands in for every button the demo isn't pointing at.
  final VoidCallback? onDecoyTapped;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navKey,
      home: Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              key: DemoKeys.key(DemoTarget.enterSkuButton),
              onPressed: onTargetTapped,
              child: const Text('Enter SKU Manually'),
            ),
            const SizedBox(height: 120),
            ElevatedButton(
              onPressed: onDecoyTapped ?? () {},
              child: const Text('Decoy'),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  tearDown(() {
    if (DemoController.instance.isActive) DemoController.instance.finish();
  });

  testWidgets('scrim absorbs taps, spotlight passes them through on action '
      'steps, and the overlay stays above a pushed dialog', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    var targetTaps = 0;
    var decoyTaps = 0;

    await tester.pumpWidget(
      _Harness(
        navKey: navKey,
        onDecoyTapped: () => decoyTaps++,
        onTargetTapped: () {
          targetTaps++;
          showDialog<void>(
            context: navKey.currentContext!,
            builder: (_) => const Dialog(child: Text('Dialog body')),
          );
          DemoController.instance.handleEvent(DemoEvent.manualDialogOpened);
        },
      ),
    );

    DemoController.instance.start(
      tester.element(find.byType(Scaffold)),
      steps: _mechanicsSteps,
      switchTab: (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Step one'), findsOneWidget);

    // Info step: the scrim must swallow the press on the spotlit button.
    await tester.tapAt(
      tester.getCenter(find.byKey(DemoKeys.key(DemoTarget.enterSkuButton))),
    );
    await tester.pump();
    expect(targetTaps, 0, reason: 'info steps must not be tappable');

    await tester.tapAt(tester.getCenter(find.text('Next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Step two'), findsOneWidget);
    expect(find.text('Next'), findsNothing, reason: 'action steps have no Next');

    // Even on an action step, only the spotlit widget is live — every other
    // control in the app stays sealed off.
    await tester.tapAt(tester.getCenter(find.text('Decoy')));
    await tester.pump();
    expect(decoyTaps, 0, reason: 'only the spotlit widget may be pressed');

    // Action step: the same press now reaches the real button underneath.
    await tester.tapAt(
      tester.getCenter(find.byKey(DemoKeys.key(DemoTarget.enterSkuButton))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(targetTaps, 1);
    expect(find.text('Dialog body'), findsOneWidget);
    expect(find.text('Step three'), findsOneWidget);

    // The real check: with a dialog route on top, the overlay's own button must
    // still receive the tap rather than the dialog's barrier.
    await tester.tapAt(tester.getCenter(find.text('Next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Step four'), findsOneWidget);
    expect(
      find.text('Dialog body'),
      findsOneWidget,
      reason: 'the tap must not have leaked to the barrier and closed it',
    );

    // Last step tears the overlay down.
    await tester.tapAt(tester.getCenter(find.text('Start Scanning')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(DemoController.instance.isActive, isFalse);
    expect(find.text('Step four'), findsNothing);
  });

  testWidgets('an action step whose target never appears falls back to Next', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    DemoController.instance.start(
      tester.element(find.byType(Scaffold)),
      steps: const [
        DemoStep(
          target: DemoTarget.lookUpButton, // never mounted in this harness
          title: 'Stalled',
          body: 'Target is missing.',
          awaitEvent: DemoEvent.manualDialogOpened,
          actionHint: 'Tap it',
        ),
      ],
      switchTab: (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Tap it'), findsOneWidget);
    expect(find.text('Start Scanning'), findsNothing);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    await tester.pump();

    expect(
      find.text('Start Scanning'),
      findsOneWidget,
      reason: 'must not trap the user on an unreachable target',
    );
  });
}
