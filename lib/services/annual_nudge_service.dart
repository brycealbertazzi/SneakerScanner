import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two points at which a monthly subscriber is invited to switch to
/// annual, counted from their first *paid* month (after any free trial).
enum AnnualNudgeMilestone {
  /// One week into the first paid month.
  firstCycle,

  /// Two weeks into the second paid month.
  secondCycle,
}

/// Debug-build testing modes for the prompt. Release builds always behave as
/// [off].
enum AnnualNudgeDebugMode {
  /// The real rules on real calendar time.
  off,

  /// Skip the rules: a monthly subscriber sees the prompt once per launch.
  /// For checking the popup and the Switch flow.
  alwaysPrompt,

  /// The real rules on sandbox time (a "month" is 5 minutes), so the whole
  /// prompt 1 → prompt 2 → nothing sequence can be watched end to end with a
  /// sandbox monthly subscription.
  sandboxTiming,
}

/// The clock the milestone rules run on. [real] is calendar months; [sandbox]
/// mirrors the App Store / Play sandbox, where a month lasts 5 minutes.
class NudgeTiming {
  const NudgeTiming._({
    required this.period,
    required this.firstPromptAfter,
    required this.secondPromptAfter,
    required this.trialLength,
    required this.tolerance,
  });

  /// Length of one billing period, or null for calendar months.
  final Duration? period;

  /// Prompt 1: this long after the first payment.
  final Duration firstPromptAfter;

  /// Prompt 2: this long after the second period's payment.
  final Duration secondPromptAfter;

  /// Free-trial length, or null to use the app's configured trial.
  final Duration? trialLength;

  /// Slack when lining renewals up against the current billing period.
  final Duration tolerance;

  static const real = NudgeTiming._(
    period: null,
    firstPromptAfter: Duration(days: 7),
    secondPromptAfter: Duration(days: 14),
    trialLength: null,
    tolerance: Duration(days: 3),
  );

  /// Sandbox: 1 month = 5 minutes, scaled from 30 days — 7 days ≈ 70 s,
  /// 14 days ≈ 140 s. Apple documents a 1-week trial as 3 minutes in
  /// sandbox; Play's test value is assumed to match.
  static const sandbox = NudgeTiming._(
    period: Duration(minutes: 5),
    firstPromptAfter: Duration(seconds: 70),
    secondPromptAfter: Duration(seconds: 140),
    trialLength: Duration(minutes: 3),
    tolerance: Duration(seconds: 60),
  );

  bool get isSandbox => period != null;

  DateTime addPeriods(DateTime date, int count) {
    final p = period;
    return p == null
        ? AnnualNudgeService.addMonths(date, count)
        : date.add(p * count);
  }
}

/// When to nudge a monthly subscriber to switch to annual.
///
/// Exactly two prompts, ever: a week into their first paid month, and two
/// weeks into their second. Each one stays available until the next one's
/// moment arrives, so a user who opens the app late still gets it; prompt 2
/// has no end date. The rules are pure functions so they
/// can be tested without a clock or a store; persistence is a thin layer on top.
class AnnualNudgeService {
  AnnualNudgeService._();

  /// TESTING SWITCH — see [AnnualNudgeDebugMode]. Only applies to debug
  /// builds ([kDebugMode] is compile-time false in release), so TestFlight,
  /// Play test tracks and production always use the real rules on real time.
  static const debugMode = AnnualNudgeDebugMode.sandboxTiming;

  static AnnualNudgeDebugMode get _activeDebugMode =>
      kDebugMode ? debugMode : AnnualNudgeDebugMode.off;

  /// Skip the rules entirely (debug [AnnualNudgeDebugMode.alwaysPrompt]).
  static bool get debugBypass =>
      _activeDebugMode == AnnualNudgeDebugMode.alwaysPrompt;

  /// The clock the rules run on in this build.
  static NudgeTiming get timing =>
      _activeDebugMode == AnnualNudgeDebugMode.sandboxTiming
      ? NudgeTiming.sandbox
      : NudgeTiming.real;

  static const _shownKey = 'annual_nudge_milestones_shown';

  /// The milestone due at [now], or null when nothing should show.
  ///
  /// - Before a week into month one: nothing.
  /// - From a week into month one until two weeks into month two: prompt 1.
  /// - From two weeks into month two onward, however long after: prompt 2,
  ///   if they haven't seen it. That includes people who were already months
  ///   into a monthly plan when this shipped.
  ///
  /// A prompt already in [shown] never repeats, and prompt 1 is skipped once
  /// its moment has passed — a user who first opens the app after prompt 2's
  /// moment gets only prompt 2, not two upsells back to back.
  static AnnualNudgeMilestone? dueMilestone({
    required DateTime now,
    required DateTime firstPayment,
    required Set<AnnualNudgeMilestone> shown,
    NudgeTiming timing = NudgeTiming.real,
  }) {
    final firstDue = firstPayment.add(timing.firstPromptAfter);
    final secondMonth = timing.addPeriods(firstPayment, 1);
    final secondDue = secondMonth.add(timing.secondPromptAfter);

    if (now.isBefore(firstDue)) return null;
    if (!now.isBefore(secondDue)) {
      return shown.contains(AnnualNudgeMilestone.secondCycle)
          ? null
          : AnnualNudgeMilestone.secondCycle;
    }
    return shown.isEmpty ? AnnualNudgeMilestone.firstCycle : null;
  }

  /// When the subscriber was first charged, from what the store/RevenueCat
  /// know about the subscription. Null while still in a free trial (nothing
  /// has been charged yet).
  ///
  /// The first charge is either the purchase itself or the end of the trial
  /// that started it. Renewals land on whole months from the first charge, so
  /// whichever candidate lines up with the current billing period is the
  /// right one. Falls back to the purchase date if neither lines up (e.g. a
  /// billing retry shifted the renewal day).
  static DateTime? firstPaymentDate({
    required DateTime originalPurchase,
    required DateTime currentPeriodEnd,
    required bool inTrial,
    required Duration trialLength,
    NudgeTiming timing = NudgeTiming.real,
  }) {
    if (inTrial) return null;
    final periodStart = timing.addPeriods(currentPeriodEnd, -1);
    final tolerance = timing.tolerance;
    for (final candidate in [
      originalPurchase,
      originalPurchase.add(trialLength),
    ]) {
      for (var months = 0; months <= 120; months++) {
        final renewal = timing.addPeriods(candidate, months);
        if (renewal.difference(periodStart).abs() <= tolerance) {
          return candidate;
        }
        if (renewal.isAfter(periodStart.add(tolerance))) break;
      }
    }
    return originalPurchase;
  }

  /// [date] moved by whole [months] (negative goes back), keeping the day of
  /// month and clamping to shorter months the way the stores do
  /// (Jan 31 + 1 month → Feb 28).
  static DateTime addMonths(DateTime date, int months) {
    final total = date.year * 12 + (date.month - 1) + months;
    final year = total ~/ 12 - (total < 0 && total % 12 != 0 ? 1 : 0);
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(
      year,
      month,
      day,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
    );
  }

  /// [dueMilestone] against what's been shown on this device, on [timing].
  static Future<AnnualNudgeMilestone?> dueNow(DateTime firstPayment) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return dueMilestone(
        now: DateTime.now(),
        firstPayment: firstPayment,
        shown: _readShown(prefs, firstPayment),
        timing: timing,
      );
    } catch (e) {
      debugPrint('[AnnualNudge] Could not read state: $e');
      return null;
    }
  }

  static Future<void> recordShown(
    AnnualNudgeMilestone milestone,
    DateTime firstPayment,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shown = _readShown(prefs, firstPayment)..add(milestone);
      await prefs.setStringList(_key, [for (final m in shown) m.name]);
      if (timing.isSandbox) {
        await prefs.setString(
          _sandboxSubscriptionKey,
          firstPayment.toIso8601String(),
        );
      }
    } catch (e) {
      debugPrint('[AnnualNudge] Could not record prompt: $e');
    }
  }

  /// Sandbox runs keep their own record, tied to the subscription it was for:
  /// buying a fresh sandbox monthly plan starts a new test run without
  /// reinstalling, and test runs never touch the real record.
  static const _sandboxShownKey = 'annual_nudge_milestones_shown_sandbox';
  static const _sandboxSubscriptionKey = 'annual_nudge_sandbox_first_payment';

  static String get _key => timing.isSandbox ? _sandboxShownKey : _shownKey;

  static Set<AnnualNudgeMilestone> _readShown(
    SharedPreferences prefs,
    DateTime firstPayment,
  ) {
    if (timing.isSandbox) {
      final recordedFor = DateTime.tryParse(
        prefs.getString(_sandboxSubscriptionKey) ?? '',
      );
      if (recordedFor == null ||
          recordedFor.difference(firstPayment).abs() > timing.tolerance) {
        return {};
      }
    }
    final names = prefs.getStringList(_key) ?? const [];
    return {
      for (final m in AnnualNudgeMilestone.values)
        if (names.contains(m.name)) m,
    };
  }
}
