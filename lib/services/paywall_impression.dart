import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

/// Reporting paywall views to RevenueCat.
///
/// RevenueCat only counts a view of a *custom* paywall when the app says so —
/// without this call every customer is filed under "Not viewed", and filtering
/// a price experiment by Viewed returns nobody. (RevenueCat's own paywalls are
/// counted automatically; ours are not.)
///
/// Split out of `SubscriptionService` so it can be tested against a mock
/// `purchases_flutter` method channel instead of a live Firebase singleton.

/// Paywall id for the variant the user is actually looking at.
///
/// The trial timeline and the lapsed feature-row paywall are different enough
/// screens that a blended conversion number would hide which one is working.
String paywallIdFor({required bool trialEligible}) =>
    trialEligible ? 'main_trial' : 'main_lapsed';

/// Records one paywall view against the current RevenueCat customer.
///
/// [offering] is what ties the impression to an experiment arm — RevenueCat
/// reads placement and targeting context off the offering object, so passing it
/// matters more than the id alone. Null when the paywall fell back to the
/// legacy SKU; the native SDK then attributes to the current offering, which
/// can file a fallback-priced view under a variant. That's the same skew
/// `ab_variant_delivered` already measures in Mixpanel.
///
/// Never throws. Analytics must not be able to take the paywall down, matching
/// the fire-and-forget rule `_syncPurchaseToRevenueCat` already follows.
Future<void> trackPaywallImpression({
  required String paywallId,
  rc.Offering? offering,
}) async {
  try {
    await rc.Purchases.trackCustomPaywallImpression(
      params: rc.CustomPaywallImpressionParams(
        paywallId: paywallId,
        offering: offering,
      ),
    );
    debugPrint(
      '[RC] Paywall impression: $paywallId '
      'offering=${offering?.identifier ?? "<none>"}',
    );
  } catch (e) {
    debugPrint('[RC] Paywall impression failed (non-fatal): $e');
  }
}
