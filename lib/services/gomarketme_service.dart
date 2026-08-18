import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gomarketme/gomarketme.dart';

import '../api_keys.dart';

/// Affiliate attribution for influencer-driven installs.
///
/// The SDK attributes an install to whichever affiliate link brought the user
/// in, then matches that install against store transactions so GoMarketMe can
/// pay out commission. Two touchpoints matter: [initialize] on every launch
/// (this is also what flips the dashboard's app status from "SDK Not Detected"
/// to "Active"), and [syncTransactions] after a purchase settles.
class GoMarketMeService {
  GoMarketMeService._();
  static final GoMarketMeService instance = GoMarketMeService._();

  final GoMarketMe _sdk = GoMarketMe();

  /// Completes once the launch-time initialize attempt has finished, whether it
  /// succeeded or not. [syncTransactions] waits on it so a purchase that lands
  /// while attribution is still in flight isn't dropped.
  Completer<void>? _ready;

  bool get isInitialized => _sdk.isInitialized;

  /// Affiliate/campaign attached to this install, or null when the user didn't
  /// arrive through an affiliate link. Only meaningful after [_ready] resolves.
  GoMarketMeAffiliateMarketingData? get affiliateMarketingData =>
      _sdk.affiliateMarketingData;

  /// Fire-and-forget: the SDK does a network round trip here, and nothing in
  /// the app's launch path depends on the result, so awaiting it would just
  /// delay the splash screen. The SDK swallows its own errors internally.
  Future<void> initialize() async {
    if (ApiKeys.goMarketMeApiKey.isEmpty) {
      debugPrint('[GoMarketMe] No API key configured — attribution disabled.');
      return;
    }
    if (_ready != null) return _ready!.future;

    final ready = Completer<void>();
    _ready = ready;
    try {
      await _sdk.initialize(ApiKeys.goMarketMeApiKey);
      final affiliateId = _sdk.affiliateMarketingData?.affiliate.id;
      debugPrint(
        '[GoMarketMe] Initialized — affiliate: ${affiliateId ?? 'none'}',
      );
    } catch (e) {
      debugPrint('[GoMarketMe] Initialization failed: $e');
    } finally {
      ready.complete();
    }
  }

  /// Hands GoMarketMe the store's transaction history so an affiliate's
  /// commission can be calculated. Safe to call more than once per purchase —
  /// the SDK syncs the full history and dedupes server-side.
  ///
  /// Never throws: revenue attribution failing must not disturb the purchase
  /// flow, which has already granted entitlement by the time this runs.
  Future<void> syncTransactions() async {
    if (ApiKeys.goMarketMeApiKey.isEmpty) return;
    try {
      await _ready?.future;
      if (!_sdk.isInitialized) {
        debugPrint('[GoMarketMe] Skipping sync — SDK not initialized.');
        return;
      }
      final result = await _sdk.syncAllTransactions();
      debugPrint(
        '[GoMarketMe] Synced transactions: fetched=${result.fetchedCount} '
        'sent=${result.sentCount} failed=${result.failedCount} '
        'success=${result.success}',
      );
    } catch (e) {
      debugPrint('[GoMarketMe] Transaction sync failed: $e');
    }
  }
}
