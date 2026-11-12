import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Price math for the annual-vs-monthly plan cards.
///
/// Free functions rather than methods on `SubscriptionService` so they can be
/// tested without standing up Firebase, same as `play_offers.dart`.

/// The renewal price of [product] as a number, or null if there isn't one.
///
/// On Play a trial offer's `rawPrice` is its *first* phase — zero — so this
/// reads the last pricing phase instead, matching `recurringPriceLabel`.
double? recurringPriceAmount(ProductDetails? product) {
  if (product == null) return null;
  if (product is GooglePlayProductDetails) {
    final index = product.subscriptionIndex;
    final offers = product.productDetails.subscriptionOfferDetails;
    if (index != null && offers != null && index < offers.length) {
      final phases = offers[index].pricingPhases;
      if (phases.isNotEmpty) return phases.last.priceAmountMicros / 1000000;
    }
  }
  return product.rawPrice > 0 ? product.rawPrice : null;
}

/// Percent saved by paying [annual] once instead of [monthly] twelve times,
/// rounded *down* so the badge never claims more than the real saving.
/// Null when there's no saving to advertise.
int? annualSavingsPercent({required double? annual, required double? monthly}) {
  if (annual == null || monthly == null || annual <= 0 || monthly <= 0) {
    return null;
  }
  final percent = ((1 - annual / (monthly * 12)) * 100).floor();
  return percent > 0 ? percent : null;
}

/// [amount] as a price, e.g. "$99.89".
///
/// [currencySymbol] comes from the store product, so a non-US storefront gets
/// its own symbol; the decimal format stays plain since the app ships no
/// locale formatting package.
String priceLabel(double amount, String currencySymbol) =>
    '$currencySymbol${amount.toStringAsFixed(2)}';

/// [annual] spread over twelve months, e.g. "$6.67".
String perMonthPriceLabel(double annual, String currencySymbol) =>
    priceLabel(annual / 12, currencySymbol);

/// Money saved per year by paying [annual] instead of [monthly] twelve times,
/// rounded down to the cent so it's never overstated. Null when there's no
/// saving.
double? annualSavingsAmount({
  required double? annual,
  required double? monthly,
}) {
  if (annual == null || monthly == null || annual <= 0 || monthly <= 0) {
    return null;
  }
  final cents = ((monthly * 12 - annual) * 100 + 1e-6).floor();
  return cents > 0 ? cents / 100 : null;
}
