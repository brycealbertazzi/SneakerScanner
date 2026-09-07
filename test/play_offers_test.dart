import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'package:sneakscan/services/play_offers.dart';

/// A Play subscription offer, built from the real plugin wrappers so these
/// tests exercise the same shape `queryProductDetails` returns.
ProductDetails _offer({
  required String basePlanId,
  String? offerId,
  required String offerIdToken,
  required List<PricingPhaseWrapper> phases,
  String productId = 'sneakscan_annual',
}) {
  final wrapper = ProductDetailsWrapper(
    description: 'SneakScan annual',
    name: 'SneakScan',
    productId: productId,
    productType: ProductType.subs,
    title: 'SneakScan Annual',
    subscriptionOfferDetails: <SubscriptionOfferDetailsWrapper>[
      SubscriptionOfferDetailsWrapper(
        basePlanId: basePlanId,
        offerId: offerId,
        offerTags: const <String>[],
        offerIdToken: offerIdToken,
        pricingPhases: phases,
      ),
    ],
  );
  return GooglePlayProductDetails.fromProductDetails(wrapper).single;
}

PricingPhaseWrapper _phase({
  required int micros,
  required String formatted,
  String period = 'P1Y',
}) => PricingPhaseWrapper(
  billingCycleCount: 1,
  billingPeriod: period,
  formattedPrice: formatted,
  priceAmountMicros: micros,
  priceCurrencyCode: 'USD',
  recurrenceMode: RecurrenceMode.infiniteRecurring,
);

/// What Play returns to a trial-eligible account: a free phase, then the price.
ProductDetails trialOffer() => _offer(
  basePlanId: 'annual',
  offerId: 'free-trial',
  offerIdToken: 'TRIAL_TOKEN',
  phases: <PricingPhaseWrapper>[
    _phase(micros: 0, formatted: 'Free', period: 'P7D'),
    _phase(micros: 59990000, formatted: r'$59.99'),
  ],
);

/// What Play returns once the trial is spent: the base plan alone.
ProductDetails basePlanOffer() => _offer(
  basePlanId: 'annual',
  offerIdToken: 'BASE_TOKEN',
  phases: <PricingPhaseWrapper>[
    _phase(micros: 59990000, formatted: r'$59.99'),
  ],
);

void main() {
  group('eligibility', () {
    test('a free first phase means Play is still offering a trial', () {
      expect(hasFreeTrialOffer([trialOffer(), basePlanOffer()]), isTrue);
    });

    test('base plan only means the trial is spent', () {
      // Play answers by omission — this is the exact list an account that has
      // already used its trial gets back.
      expect(hasFreeTrialOffer([basePlanOffer()]), isFalse);
    });

    test('no offers reads as not eligible, never as eligible', () {
      // A failed or empty query must fail closed: promising a trial Play won't
      // honour is the bug this whole module exists to prevent.
      expect(hasFreeTrialOffer(const []), isFalse);
    });
  });

  group('offer selection', () {
    test('an eligible user buys the trial offer', () {
      final picked = pickOffer([
        trialOffer(),
        basePlanOffer(),
      ], wantTrial: true);

      expect((picked! as GooglePlayProductDetails).offerToken, 'TRIAL_TOKEN');
    });

    test('order does not decide which offer is bought', () {
      // The regression that charged eligible users immediately: Play does not
      // guarantee offer order, and the old code bought whichever came first.
      final picked = pickOffer([
        basePlanOffer(),
        trialOffer(),
      ], wantTrial: true);

      expect((picked! as GooglePlayProductDetails).offerToken, 'TRIAL_TOKEN');
    });

    test('an ineligible user buys the base plan', () {
      final picked = pickOffer([
        trialOffer(),
        basePlanOffer(),
      ], wantTrial: false);

      expect((picked! as GooglePlayProductDetails).offerToken, 'BASE_TOKEN');
    });

    test('wanting a trial that is not offered falls back to the base plan', () {
      final picked = pickOffer([basePlanOffer()], wantTrial: true);

      expect((picked! as GooglePlayProductDetails).offerToken, 'BASE_TOKEN');
    });

    test('no offers returns null rather than throwing', () {
      expect(pickOffer(const [], wantTrial: true), isNull);
    });
  });

  group('price label', () {
    test('reads past the trial phase to the renewal price', () {
      // ProductDetails.price is the *first* phase, so a trial offer reports
      // "Free" — which used to leave the paywall's price line on its skeleton.
      expect(trialOffer().price, 'Free');
      expect(recurringPriceLabel(trialOffer()), r'$59.99');
    });

    test('is the plain price for a base plan', () {
      expect(recurringPriceLabel(basePlanOffer()), r'$59.99');
    });

    test('is null with nothing to price', () {
      expect(recurringPriceLabel(null), isNull);
    });
  });
}
