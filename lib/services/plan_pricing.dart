import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'play_offers.dart';

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

/// [amount] formatted the way the store formatted [storePrice]: same currency
/// symbol, same side of the number, same decimal separator and places.
/// "$79.99" → "$6.67", "79,99 €" → "6,67 €", "¥1,200" → "¥100".
///
/// Deliberately not built from `ProductDetails.currencySymbol`: on Play the
/// plugin reads that from the offer's *first* pricing phase, which for a free
/// trial is the word "Free" — that's how the yearly card showed "Free6.67/mo".
String formatLikeStorePrice(String storePrice, double amount) {
  final match = RegExp(r'\d(?:[\d.,\u00A0\u202F ]*\d)?').firstMatch(storePrice);
  if (match == null) return amount.toStringAsFixed(2);
  final number = match.group(0)!;
  // A separator followed by one or two trailing digits is the decimal point;
  // three (",000") is a thousands group, i.e. a currency without decimals.
  final fraction = RegExp(r'([.,])(\d{1,2})$').firstMatch(number);
  final decimals = fraction?.group(2)!.length ?? 0;
  var formatted = amount.toStringAsFixed(decimals);
  if (fraction?.group(1) == ',') formatted = formatted.replaceAll('.', ',');
  return storePrice.replaceRange(match.start, match.end, formatted);
}

/// [amount] in [product]'s currency, formatted like its renewal price.
/// Null when the store gave no price to copy the format from.
String? priceLabelFor(ProductDetails? product, double amount) {
  final template = recurringPriceLabel(product);
  if (template == null) return null;
  return formatLikeStorePrice(template, amount);
}

/// [annual]'s renewal price spread over twelve months, e.g. "$6.67".
String? perMonthPriceLabel(ProductDetails annual) {
  final amount = recurringPriceAmount(annual);
  if (amount == null) return null;
  return priceLabelFor(annual, amount / 12);
}

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
