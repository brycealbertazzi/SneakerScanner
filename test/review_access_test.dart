import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sneaker_scanner/services/review_access.dart';
import 'package:sneaker_scanner/services/subscription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ReviewAccess.instance.load();
  });

  test('accepts the code regardless of case and surrounding whitespace', () {
    expect(ReviewAccess.instance.matches('SNEAKSCAN-REVIEW-2026'), isTrue);
    expect(ReviewAccess.instance.matches('sneakscan-review-2026'), isTrue);
    expect(ReviewAccess.instance.matches('  SneakScan-Review-2026  '), isTrue);
  });

  test('rejects near-misses', () {
    for (final wrong in [
      '',
      'SNEAKSCAN-REVIEW-2025',
      'SNEAKSCANREVIEW2026',
      'SNEAKSCAN-REVIEW-2026 X',
      ReviewAccess.instance.hashCode.toString(),
    ]) {
      expect(
        ReviewAccess.instance.matches(wrong),
        isFalse,
        reason: 'should reject "$wrong"',
      );
    }
  });

  test('granting persists and survives a reload', () async {
    expect(ReviewAccess.instance.isGranted, isFalse);

    await ReviewAccess.instance.grant();
    expect(ReviewAccess.instance.isGranted, isTrue);

    // Simulate a fresh launch reading the flag back off disk.
    await ReviewAccess.instance.load();
    expect(ReviewAccess.instance.isGranted, isTrue);
  });

  test('grant unlocks both entitlement getters without a purchase', () async {
    final sub = SubscriptionService.instance;

    expect(sub.status, SubscriptionStatus.loading);
    expect(sub.canScan, isFalse);
    expect(sub.isSubscribed, isFalse);

    await ReviewAccess.instance.grant();

    expect(sub.canScan, isTrue, reason: 'scan gates read canScan');
    expect(sub.isSubscribed, isTrue, reason: 'paywall routing reads this');
    expect(
      sub.status,
      SubscriptionStatus.loading,
      reason: 'real store status must be left untouched',
    );
  });
}
