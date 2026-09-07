import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Reading Google Play's subscription offers.
///
/// Play answers the trial-eligibility question itself: `queryProductDetails`
/// returns only the offers the user is *eligible for*, so a spent free-trial
/// offer simply isn't in the response. The plugin surfaces one [ProductDetails]
/// per offer, each with its own `offerToken`, which makes both questions —
/// "can this account still get a trial?" and "which offer should we actually
/// buy?" — answerable from the store rather than from a device record.
///
/// These are free functions rather than methods on `SubscriptionService` so
/// they can be tested without standing up Firebase.

/// The Play offer behind [product], or null if this isn't a Play subscription.
SubscriptionOfferDetailsWrapper? _offerOf(ProductDetails product) {
  if (product is! GooglePlayProductDetails) return null;
  final index = product.subscriptionIndex;
  final offers = product.productDetails.subscriptionOfferDetails;
  if (index == null || offers == null || index >= offers.length) return null;
  return offers[index];
}

/// Whether [product] is an offer that starts with a free phase.
///
/// A trial is always the *first* pricing phase, so a later zero-priced phase
/// (which would be a strange offer anyway) doesn't count. Always false off
/// Android — iOS resolves eligibility through StoreKit instead.
bool offerIsFreeTrial(ProductDetails product) {
  final phases = _offerOf(product)?.pricingPhases;
  if (phases == null || phases.isEmpty) return false;
  return phases.first.priceAmountMicros == 0;
}

/// Whether Play is still offering this account a free trial.
///
/// An empty list — a failed query, or a product that didn't load — reads as
/// *not* eligible. That's the safe direction: showing the plain paywall to
/// someone who could have had a trial costs them nothing at checkout, whereas
/// promising a trial Play won't honour is the bug this exists to prevent.
bool hasFreeTrialOffer(List<ProductDetails> offers) =>
    offers.any(offerIsFreeTrial);

/// The offer to actually purchase.
///
/// Play doesn't guarantee the order offers come back in, so this must choose
/// explicitly rather than taking the first: buying whatever landed first is how
/// an eligible user ends up charged immediately.
ProductDetails? pickOffer(
  List<ProductDetails> offers, {
  required bool wantTrial,
}) {
  if (offers.isEmpty) return null;
  if (wantTrial) {
    for (final offer in offers) {
      if (offerIsFreeTrial(offer)) return offer;
    }
  }
  for (final offer in offers) {
    if (!offerIsFreeTrial(offer)) return offer;
  }
  return offers.first;
}

/// The price the user will be charged on renewal, formatted for display.
///
/// Takes the *last* pricing phase, so a trial or intro phase in front of the
/// real price doesn't leak "Free" into the paywall's price line. Falls back to
/// [ProductDetails.price] off Android, where that is already the recurring
/// price.
String? recurringPriceLabel(ProductDetails? product) {
  if (product == null) return null;
  final phases = _offerOf(product)?.pricingPhases;
  if (phases != null && phases.isNotEmpty) {
    return phases.last.formattedPrice;
  }
  final price = product.price;
  if (price.isEmpty || price.toLowerCase() == 'free') return null;
  return price;
}
