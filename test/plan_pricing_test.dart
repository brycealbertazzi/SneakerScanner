import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'package:sneakscan/services/plan_pricing.dart';
import 'package:sneakscan/services/subscription_service.dart';

/// A Play subscription offer, built from the real plugin wrappers.
ProductDetails _playOffer({
  required String productId,
  required List<PricingPhaseWrapper> phases,
}) {
  final wrapper = ProductDetailsWrapper(
    description: 'SneakScan',
    name: 'SneakScan',
    productId: productId,
    productType: ProductType.subs,
    title: 'SneakScan',
    subscriptionOfferDetails: <SubscriptionOfferDetailsWrapper>[
      SubscriptionOfferDetailsWrapper(
        basePlanId: 'base',
        offerId: 'free-trial',
        offerTags: const <String>[],
        offerIdToken: 'TOKEN',
        pricingPhases: phases,
      ),
    ],
  );
  return GooglePlayProductDetails.fromProductDetails(wrapper).single;
}

PricingPhaseWrapper _phase(int micros, String formatted, String period) =>
    PricingPhaseWrapper(
      billingCycleCount: 1,
      billingPeriod: period,
      formattedPrice: formatted,
      priceAmountMicros: micros,
      priceCurrencyCode: 'USD',
      recurrenceMode: RecurrenceMode.infiniteRecurring,
    );

void main() {
  group('recurringPriceAmount', () {
    test('reads past a Play free-trial phase to the renewal price', () {
      final monthly = _playOffer(
        productId: 'sneakscan_monthly_1499',
        phases: [
          _phase(0, 'Free', 'P7D'),
          _phase(14990000, r'$14.99', 'P1M'),
        ],
      );
      // rawPrice is the first (free) phase — the trap this function avoids.
      expect(monthly.rawPrice, 0);
      expect(recurringPriceAmount(monthly), 14.99);
    });

    test('uses rawPrice for a plain store product (iOS)', () {
      final product = ProductDetails(
        id: 'sneakscan_annual_ab_7999',
        title: 'Annual',
        description: '',
        price: r'$79.99',
        rawPrice: 79.99,
        currencyCode: 'USD',
        currencySymbol: r'$',
      );
      expect(recurringPriceAmount(product), 79.99);
    });

    test('is null with nothing to price', () {
      expect(recurringPriceAmount(null), isNull);
    });
  });

  group('annualSavingsPercent', () {
    test(r'$79.99/yr vs $14.99/mo', () {
      // 1 - 79.99 / 179.88 = 55.5% → floored, never overstated.
      expect(annualSavingsPercent(annual: 79.99, monthly: 14.99), 55);
    });

    test(r'$89.99/yr vs $19.99/mo', () {
      // 1 - 89.99 / 239.88 = 62.5%
      expect(annualSavingsPercent(annual: 89.99, monthly: 19.99), 62);
    });

    test('no badge when annual is not actually cheaper', () {
      expect(annualSavingsPercent(annual: 120, monthly: 10), isNull);
      expect(annualSavingsPercent(annual: 150, monthly: 10), isNull);
    });

    test('no badge when either price is missing', () {
      expect(annualSavingsPercent(annual: null, monthly: 14.99), isNull);
      expect(annualSavingsPercent(annual: 79.99, monthly: null), isNull);
    });
  });

  group('perMonthPriceLabel', () {
    test('spreads the annual price over twelve months', () {
      expect(perMonthPriceLabel(79.99, r'$'), r'$6.67');
      expect(perMonthPriceLabel(89.99, r'$'), r'$7.50');
    });
  });

  group('product id checks', () {
    test('annual ids', () {
      expect(isAnnualVariantProductId('sneakscan_annual'), isTrue);
      expect(isAnnualVariantProductId('sneakscan_annual_ab_7999'), isTrue);
      expect(isAnnualVariantProductId('sneakscan_annual_8999'), isTrue);
      expect(isAnnualVariantProductId('sneakscan_monthly_1499'), isFalse);
      expect(isAnnualVariantProductId('other_annual'), isFalse);
    });

    test('monthly ids', () {
      expect(isMonthlyVariantProductId('sneakscan_monthly_1499'), isTrue);
      expect(isMonthlyVariantProductId('sneakscan_monthly_1999'), isTrue);
      expect(isMonthlyVariantProductId('sneakscan_annual_ab_7999'), isFalse);
    });
  });
}
