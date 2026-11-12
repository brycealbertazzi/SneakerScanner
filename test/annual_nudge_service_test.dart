import 'package:flutter_test/flutter_test.dart';

import 'package:sneakscan/services/annual_nudge_service.dart';

void main() {
  // First paid month: Oct 1 → Nov 1; second: Nov 1 → Dec 1.
  final firstPayment = DateTime(2026, 10, 1, 9);

  AnnualNudgeMilestone? due(
    DateTime now, [
    Set<AnnualNudgeMilestone> shown = const {},
  ]) => AnnualNudgeService.dueMilestone(
    now: now,
    firstPayment: firstPayment,
    shown: shown,
  );

  group('dueMilestone', () {
    test('nothing in the first week of paying', () {
      expect(due(DateTime(2026, 10, 5)), isNull);
    });

    test('prompt 1 from a week into month one', () {
      expect(due(DateTime(2026, 10, 8, 9)), AnnualNudgeMilestone.firstCycle);
    });

    test('prompt 1 still shows if they open the app late in month one', () {
      expect(due(DateTime(2026, 10, 22)), AnnualNudgeMilestone.firstCycle);
      // ...and early in month two, before prompt 2's moment.
      expect(due(DateTime(2026, 11, 10)), AnnualNudgeMilestone.firstCycle);
    });

    test('prompt 1 never repeats', () {
      expect(
        due(DateTime(2026, 10, 22), {AnnualNudgeMilestone.firstCycle}),
        isNull,
      );
    });

    test('prompt 2 from two weeks into month two', () {
      expect(
        due(DateTime(2026, 11, 15, 9), {AnnualNudgeMilestone.firstCycle}),
        AnnualNudgeMilestone.secondCycle,
      );
    });

    test('missed prompt 1 entirely: only prompt 2', () {
      expect(due(DateTime(2026, 11, 22)), AnnualNudgeMilestone.secondCycle);
      // Having shown prompt 2, prompt 1 doesn't come back.
      expect(
        due(DateTime(2026, 11, 25), {AnnualNudgeMilestone.secondCycle}),
        isNull,
      );
    });

    test('prompt 2 never repeats', () {
      expect(
        due(DateTime(2026, 11, 25), {
          AnnualNudgeMilestone.firstCycle,
          AnnualNudgeMilestone.secondCycle,
        }),
        isNull,
      );
    });

    test('prompt 2 shows however late, until seen', () {
      // Month three, and months later — still shows if never seen.
      expect(due(DateTime(2026, 12, 2)), AnnualNudgeMilestone.secondCycle);
      expect(due(DateTime(2027, 3, 10)), AnnualNudgeMilestone.secondCycle);
      expect(
        due(DateTime(2027, 3, 10), {AnnualNudgeMilestone.firstCycle}),
        AnnualNudgeMilestone.secondCycle,
      );
      // ...and never again once seen.
      expect(
        due(DateTime(2027, 3, 10), {AnnualNudgeMilestone.secondCycle}),
        isNull,
      );
    });
  });

  group('firstPaymentDate', () {
    const trial = Duration(days: 7);

    test('no trial: the purchase was the first payment', () {
      // Bought Oct 1, renewed Nov 1, current period ends Dec 1.
      expect(
        AnnualNudgeService.firstPaymentDate(
          originalPurchase: DateTime(2026, 10, 1, 9),
          currentPeriodEnd: DateTime(2026, 12, 1, 9),
          inTrial: false,
          trialLength: trial,
        ),
        DateTime(2026, 10, 1, 9),
      );
    });

    test('trial: the first payment was when the trial ended', () {
      // Subscribed Sep 24, trial ended Oct 1, current period ends Nov 1.
      expect(
        AnnualNudgeService.firstPaymentDate(
          originalPurchase: DateTime(2026, 9, 24, 9),
          currentPeriodEnd: DateTime(2026, 11, 1, 9),
          inTrial: false,
          trialLength: trial,
        ),
        DateTime(2026, 10, 1, 9),
      );
    });

    test('still in the trial: nothing charged yet', () {
      expect(
        AnnualNudgeService.firstPaymentDate(
          originalPurchase: DateTime(2026, 11, 8),
          currentPeriodEnd: DateTime(2026, 11, 15),
          inTrial: true,
          trialLength: trial,
        ),
        isNull,
      );
    });
  });

  group('sandbox timing', () {
    const t = NudgeTiming.sandbox;
    final paid = DateTime(2026, 11, 12, 10);

    AnnualNudgeMilestone? dueAt(
      Duration after, [
      Set<AnnualNudgeMilestone> shown = const {},
    ]) => AnnualNudgeService.dueMilestone(
      now: paid.add(after),
      firstPayment: paid,
      shown: shown,
      timing: t,
    );

    test('runs the same sequence on 5-minute months', () {
      expect(dueAt(const Duration(seconds: 30)), isNull);
      expect(
        dueAt(const Duration(seconds: 80)),
        AnnualNudgeMilestone.firstCycle,
      );
      expect(
        dueAt(const Duration(minutes: 7, seconds: 30), {
          AnnualNudgeMilestone.firstCycle,
        }),
        AnnualNudgeMilestone.secondCycle,
      );
      // No end date: still due late, until shown.
      expect(
        dueAt(const Duration(minutes: 30)),
        AnnualNudgeMilestone.secondCycle,
      );
      expect(
        dueAt(const Duration(minutes: 30), {AnnualNudgeMilestone.secondCycle}),
        isNull,
      );
    });

    test('detects a sandbox trial from 5-minute renewals', () {
      // Subscribed 10:00 with a 3-minute trial: first charge 10:03, renewals
      // every 5 minutes; current period 10:08 → 10:13.
      expect(
        AnnualNudgeService.firstPaymentDate(
          originalPurchase: DateTime(2026, 11, 12, 10),
          currentPeriodEnd: DateTime(2026, 11, 12, 10, 13),
          inTrial: false,
          trialLength: t.trialLength!,
          timing: t,
        ),
        DateTime(2026, 11, 12, 10, 3),
      );
    });
  });

  group('addMonths', () {
    test('clamps to the end of shorter months', () {
      expect(
        AnnualNudgeService.addMonths(DateTime(2026, 1, 31), 1),
        DateTime(2026, 2, 28),
      );
    });

    test('rolls over years in both directions', () {
      expect(
        AnnualNudgeService.addMonths(DateTime(2026, 12, 15), 1),
        DateTime(2027, 1, 15),
      );
      expect(
        AnnualNudgeService.addMonths(DateTime(2027, 1, 15), -1),
        DateTime(2026, 12, 15),
      );
    });
  });
}
