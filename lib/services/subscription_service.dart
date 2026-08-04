import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_keys.dart';
import 'mixpanel_service.dart';
import 'review_access.dart';

/// Fallback when RevenueCat can't name a product. Deliberately NOT one of the
/// price-experiment SKUs, so a user who never got assigned a variant can't be
/// miscounted as a conversion for one.
const String kAnnualProductId = 'sneakscan_annual';

/// Every SKU the paywall may need to price, including the RevenueCat price
/// A/B variants. Queried in a single store round trip so whichever product
/// RevenueCat assigns is already loaded by the time the experiment resolves.
const Set<String> kAllAnnualProductIds = {
  kAnnualProductId,
  'sneakscan_annual_ab_2999',
  'sneakscan_annual_ab_3999',
  'sneakscan_annual_ab_4999',
};

enum SubscriptionStatus { loading, freeTrial, active, expired, cancelled }

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  static const _storeKitChannel = MethodChannel('com.sneakerscanner/storekit');
  static const _androidIdChannel = MethodChannel(
    'com.sneakerscanner/androidid',
  );

  SubscriptionStatus _status = SubscriptionStatus.loading;

  /// Every store product from [kAllAnnualProductIds] that loaded, keyed by id.
  final Map<String, ProductDetails> _products = {};

  // Price A/B test: RevenueCat picks which product this user is offered.
  String? _assignedProductId;
  String? _assignedOfferingId;
  bool _offeringsResolved = false;
  Timer? _offeringsTimer;

  bool _purchasePending = false;
  bool _purchaseCancelled = false;
  String? _purchaseError;
  bool _purchaseInitiated = false;
  bool _lastActivationWasRestore = false;
  bool _initialized = false;

  // null = unknown (not yet checked), true = eligible, false = not eligible
  bool? _isEligibleForTrial;

  // Launch check state — resolves once StoreKit confirms status on startup.
  bool _isLaunchCheck = false;
  Timer? _launchCheckTimer;
  Completer<void>? _launchCheckCompleter;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  SubscriptionStatus get status => _status;
  bool get purchasePending => _purchasePending;
  bool get purchaseCancelled => _purchaseCancelled;
  String? get purchaseError => _purchaseError;

  /// The product this user should see and buy — the RevenueCat-assigned A/B
  /// variant, falling back to the legacy SKU whenever RevenueCat didn't name
  /// one (offline, misconfigured dashboard, tracking disabled).
  ProductDetails? get annualProduct =>
      _products[_assignedProductId ?? kAnnualProductId] ??
      _products[kAnnualProductId];

  /// False until RevenueCat has had its say. The paywall skeletons the price
  /// and blocks the subscribe button while this is false, so nobody can buy at
  /// a price that's about to change under them.
  bool get offeringsResolved => _offeringsResolved;
  String? get assignedProductId => _assignedProductId;
  String? get assignedOfferingId => _assignedOfferingId;

  /// True only when the subscription is currently active (including trial period).
  ///
  /// Review access short-circuits both entitlement getters, which is the only
  /// place the bypass needs to exist: splash routing, the lapse kick-out in
  /// MainScreen and every scan gate all read through these two.
  bool get canScan =>
      ReviewAccess.instance.isGranted || _status == SubscriptionStatus.active;

  bool get isSubscribed =>
      ReviewAccess.instance.isGranted || _status == SubscriptionStatus.active;
  bool get lastActivationWasRestore => _lastActivationWasRestore;

  bool get isLapsedSubscriber =>
      _status == SubscriptionStatus.expired ||
      _status == SubscriptionStatus.cancelled;

  /// Re-queries StoreKit/Play Billing for current status.
  /// Called when the app returns to the foreground.
  void recheckSubscription() {
    if (_isLaunchCheck) return; // Already checking
    if (_purchasePending || _purchaseInitiated) {
      return; // Purchase in flight — let it resolve naturally
    }
    _startLaunchCheck();
  }

  // RevenueCat observer-mode tracking (purchases completed by this app).
  // Purchase flow and entitlements stay on in_app_purchase; RevenueCat only
  // receives purchase events for analytics.
  static bool _revenueCatConfigured = false;
  static const _rcBackfillPrefsKey = 'rc_purchases_backfilled_v1';

  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Never awaited, so a slow RevenueCat SDK can't delay or block the purchase
    // flow. The product query below runs in parallel with it, so the paywall
    // waits on the slower of the two rather than their sum.
    unawaited(_configureRevenueCat());

    // Backstop on the A/B variant lookup. The subscribe button is disabled
    // until offerings resolve, and RevenueCat's own timeouts add up to far
    // longer than anyone should stare at a dead hard paywall. Resolving early
    // just means falling back to kAnnualProductId.
    _offeringsTimer?.cancel();
    _offeringsTimer = Timer(const Duration(seconds: 6), () {
      if (!_offeringsResolved) {
        debugPrint('[RC] Offerings timed out — using fallback product');
        _resolveOfferings();
      }
    });

    // Detect lapsed subscribers to show correct button label.
    // iOS: query StoreKit intro offer eligibility (from Apple).
    // Android: query Firebase androidTrialIds table by ANDROID_ID.
    if (Platform.isIOS) {
      _checkTrialEligibility().then((eligible) {
        _isEligibleForTrial = eligible;
        if (!eligible && _status == SubscriptionStatus.loading) {
          _status = SubscriptionStatus.cancelled;
          notifyListeners();
        }
      });
    } else if (Platform.isAndroid) {
      _checkAndroidTrialEligibility().then((eligible) {
        _isEligibleForTrial = eligible;
        if (!eligible && _status == SubscriptionStatus.loading) {
          _status = SubscriptionStatus.cancelled;
          notifyListeners();
        }
      });
    } else {
      _isEligibleForTrial = true;
    }

    // Set up purchase stream listener FIRST.
    _purchaseSubscription?.cancel();
    _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (error) {
        _purchaseError = error.toString();
        _completeLaunchCheck(SubscriptionStatus.freeTrial);
        notifyListeners();
      },
    );

    // Load IAP products. Capped so a stalled store query can't prevent the
    // launch check below from ever starting — that would leave status stuck on
    // `loading` and spin the paywall button forever.
    try {
      await _loadProducts().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[IAP] Product load failed or timed out: $e');
    }

    // Silently query StoreKit/Play Billing for current subscription status.
    // Results arrive via the purchase stream. _startLaunchCheck is non-blocking;
    // call awaitLaunchCheck() to wait for resolution.
    _startLaunchCheck();
  }

  Future<void> _configureRevenueCat() async {
    if (_revenueCatConfigured) {
      // Configuration is static and survives reset(), but the offerings state
      // does not — re-resolve it or a re-initialize (e.g. after deleteAccount)
      // would leave the paywall skeleton up and its button dead forever.
      await _loadOfferings();
      return;
    }
    final apiKey = Platform.isIOS
        ? ApiKeys.revenueCatAppleApiKey
        : Platform.isAndroid
        ? ApiKeys.revenueCatGoogleApiKey
        : '';
    if (apiKey.isEmpty) {
      debugPrint('[RC] No API key for this platform — tracking disabled');
      _resolveOfferings();
      return;
    }
    try {
      final configuration = rc.PurchasesConfiguration(apiKey)
        ..purchasesAreCompletedBy = rc.PurchasesAreCompletedByMyApp(
          storeKitVersion: rc.StoreKitVersion.storeKit2,
        );
      await rc.Purchases.configure(
        configuration,
      ).timeout(const Duration(seconds: 15));
      _revenueCatConfigured = true;
      debugPrint('[RC] Configured (observer mode)');
      _backfillRevenueCatPurchases();
      await _loadOfferings();
    } catch (e) {
      debugPrint('[RC] Configure failed — tracking disabled: $e');
      _resolveOfferings();
    }
  }

  /// Resolves the price A/B variant from RevenueCat's current offering.
  ///
  /// RevenueCat assigns the experiment variant server-side; all we do is honor
  /// whichever offering it hands back. Any failure leaves [_assignedProductId]
  /// null, which falls the paywall back to [kAnnualProductId].
  Future<void> _loadOfferings() async {
    try {
      final offerings = await rc.Purchases.getOfferings().timeout(
        const Duration(seconds: 6),
      );
      final current = offerings.current;
      // `annual` covers the standard $rc_annual package; fall back to the first
      // package so a custom package identifier still works.
      final package =
          current?.annual ??
          (current != null && current.availablePackages.isNotEmpty
              ? current.availablePackages.first
              : null);
      final rawId = package?.storeProduct.identifier;
      if (rawId == null) {
        debugPrint('[RC] No current offering — using fallback product');
        return;
      }
      // Play returns subscriptions as `productId:basePlanId`; the store query
      // and purchase flow both key off the bare product id.
      final productId = rawId.split(':').first;
      if (!kAllAnnualProductIds.contains(productId)) {
        // A dashboard typo would otherwise leave `annualProduct` null and dead
        // -button the paywall. Fall back rather than ship a broken purchase.
        debugPrint(
          '[RC] Offering names unknown product "$productId" — ignored',
        );
        return;
      }
      if (_offeringsResolved) {
        // The backstop timer already committed this session to the fallback.
        // Switching now would move the price under a user whose subscribe
        // button is live — they could tap one price and be charged another.
        debugPrint('[RC] Offerings arrived after timeout — keeping fallback');
        return;
      }
      _assignedProductId = productId;
      _assignedOfferingId = current!.identifier;
      debugPrint('[RC] Assigned $productId from offering $_assignedOfferingId');
    } catch (e) {
      debugPrint('[RC] Offerings fetch failed — using fallback product: $e');
    } finally {
      _resolveOfferings();
    }
  }

  /// Unblocks the paywall and records which variant this user was shown.
  void _resolveOfferings() {
    if (_offeringsResolved) return;
    _offeringsResolved = true;
    _offeringsTimer?.cancel();
    _offeringsTimer = null;
    _trackVariantAssigned();
    notifyListeners();
  }

  /// Our own record of the assignment. RevenueCat's `recordPurchase` carries no
  /// offering identifier in observer mode, so this is the ground truth for the
  /// price test funnel rather than a duplicate of it.
  void _trackVariantAssigned() {
    final productId = _assignedProductId ?? kAnnualProductId;
    final offeringId = _assignedOfferingId;
    final price = _products[productId]?.price;
    // Nulls are omitted rather than sent: a null *super* property would ride
    // along on every event from here on, which is worse than an absent one.
    final properties = <String, dynamic>{
      'ab_product_id': productId,
      'ab_assigned': _assignedProductId != null,
      'ab_offering_id': ?offeringId,
    };
    // Rides along on Subscribe Button Tapped and Purchase Completed, making the
    // whole funnel sliceable by variant.
    MixpanelService.instance.registerSuperProperties(properties);
    MixpanelService.instance.track(
      'Paywall Variant Assigned',
      properties: {...properties, 'price': ?price},
    );
  }

  /// One-time (per install) sync so subscribers who purchased before
  /// RevenueCat was added still show up in its dashboard.
  void _backfillRevenueCatPurchases() {
    Future(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_rcBackfillPrefsKey) ?? false) return;
        await rc.Purchases.syncPurchases();
        await prefs.setBool(_rcBackfillPrefsKey, true);
        debugPrint('[RC] One-time purchase backfill complete');
      } catch (e) {
        debugPrint('[RC] Backfill failed (will retry next launch): $e');
      }
    });
  }

  /// Reports a completed purchase/restore to RevenueCat. Fire-and-forget —
  /// tracking must never affect the purchase flow.
  void _syncPurchaseToRevenueCat(PurchaseDetails purchase) {
    if (!_revenueCatConfigured) return;
    Future(() async {
      try {
        if (Platform.isIOS && purchase.status == PurchaseStatus.purchased) {
          // StoreKit 2 observer mode: new purchases must be recorded
          // explicitly; renewals are observed automatically.
          await rc.Purchases.recordPurchase(purchase.productID);
        } else {
          await rc.Purchases.syncPurchases();
        }
        debugPrint('[RC] Purchase synced');
      } catch (e) {
        debugPrint('[RC] recordPurchase failed, falling back to sync: $e');
        try {
          await rc.Purchases.syncPurchases();
        } catch (e2) {
          debugPrint('[RC] Sync failed (non-fatal): $e2');
        }
      }
    });
  }

  Future<String?> _getAndroidId() async {
    try {
      return await _androidIdChannel.invokeMethod<String>('getAndroidId');
    } catch (e) {
      debugPrint('[Android] Failed to get ANDROID_ID: $e');
      return null;
    }
  }

  Future<bool> _checkAndroidTrialEligibility() async {
    final androidId = await _getAndroidId();
    if (androidId == null) return true;
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('androidTrialIds/$androidId')
          .get();
      return !snapshot.exists;
    } catch (e) {
      debugPrint(
        '[Android] Failed to check trial eligibility (defaulting to eligible): $e',
      );
      return true;
    }
  }

  Future<void> _recordAndroidSubscription() async {
    final androidId = await _getAndroidId();
    if (androidId == null) return;
    try {
      final ref = FirebaseDatabase.instance.ref('androidTrialIds/$androidId');
      final snapshot = await ref.get();
      if (snapshot.exists) return;
      await ref.set({'startedAt': DateTime.now().toUtc().toIso8601String()});
      debugPrint('[Android] Recorded subscription for ANDROID_ID: $androidId');
    } catch (e) {
      debugPrint('[Android] Failed to record subscription: $e');
    }
  }

  Future<bool> _checkTrialEligibility() async {
    try {
      // Deliberately the legacy SKU rather than the assigned A/B variant: intro
      // -offer eligibility is per subscription *group*, and all four products
      // share one, so the answer is identical for any of them — and this one is
      // guaranteed to exist. If the variants ever move to their own groups,
      // this is the line that breaks (a lapsed user would get a fresh trial).
      final result = await _storeKitChannel.invokeMethod<bool>(
        'checkTrialEligibility',
        kAnnualProductId,
      );
      return result ?? true;
    } catch (e) {
      debugPrint(
        '[IAP] Trial eligibility check failed (defaulting to eligible): $e',
      );
      return true;
    }
  }

  /// Awaitable by splash / login screens. Resolves once the launch subscription
  /// check completes (restored event or timeout), with a 3 s safety cap.
  Future<void> awaitLaunchCheck() async {
    final completer = _launchCheckCompleter;
    if (completer == null || completer.isCompleted) return;
    await completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
  }

  void _startLaunchCheck() {
    _isLaunchCheck = true;
    _launchCheckCompleter = Completer<void>();

    // Fallback: if StoreKit delivers no restored event within 4 s, no active subscription.
    _launchCheckTimer = Timer(const Duration(milliseconds: 4000), () {
      _completeLaunchCheck(SubscriptionStatus.freeTrial);
    });

    InAppPurchase.instance.restorePurchases().catchError((e) {
      debugPrint('[Sub] Launch check restore error: $e');
      _completeLaunchCheck(SubscriptionStatus.freeTrial);
    });
  }

  void _completeLaunchCheck(SubscriptionStatus resolvedStatus) {
    if (!_isLaunchCheck) return;
    _isLaunchCheck = false;
    _launchCheckTimer?.cancel();
    _launchCheckTimer = null;
    if (!(_launchCheckCompleter?.isCompleted ?? true)) {
      _launchCheckCompleter!.complete();
    }
    _launchCheckCompleter = null;
    // A purchase is in flight — don't touch status or purchase flags.
    if (_purchaseInitiated) return;
    // If no active subscription and StoreKit says not eligible for intro offer,
    // treat as lapsed subscriber (previously subscribed, trial already used).
    if (resolvedStatus == SubscriptionStatus.freeTrial &&
        _isEligibleForTrial == false) {
      _status = SubscriptionStatus.cancelled;
    } else {
      _status = resolvedStatus;
    }
    _purchasePending = false;
    notifyListeners();
  }

  Future<void> _loadProducts() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      debugPrint('[IAP] Store not available');
      return;
    }

    // All A/B variants in one round trip, so whichever one RevenueCat assigns
    // is already priced by the time the offerings fetch comes back.
    final response = await InAppPurchase.instance.queryProductDetails(
      kAllAnnualProductIds,
    );
    if (response.notFoundIDs.isNotEmpty) {
      // Usually means a SKU isn't approved for sale yet — that variant would
      // silently fall back, so it's worth shouting about.
      debugPrint('[IAP] Products not found in store: ${response.notFoundIDs}');
    }
    if (response.productDetails.isNotEmpty) {
      for (final product in response.productDetails) {
        // Play returns one entry per subscription *offer*, all sharing an id.
        // First wins, matching the `.first` this used before it handled more
        // than one product — picking a different offer would change which base
        // plan (and whether the free trial) the user actually buys.
        if (_products.containsKey(product.id)) continue;
        _products[product.id] = product;
        debugPrint(
          '[IAP] Product loaded: ${product.id}, price: ${product.price}',
        );
      }
      notifyListeners();
    } else {
      debugPrint('[IAP] No products returned from store');
    }
  }

  Future<void> buyAnnual() async {
    if (annualProduct == null) {
      await _loadProducts();
    }
    final product = annualProduct;
    if (product == null) {
      _purchaseError =
          'Product not available. Check your App Store connection and try again.';
      notifyListeners();
      return;
    }
    _purchaseError = null;
    _purchaseCancelled = false;
    _purchasePending = true;
    _purchaseInitiated = true;
    notifyListeners();

    final param = PurchaseParam(productDetails: product);
    try {
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      _purchaseError = e.toString();
      _purchasePending = false;
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    _purchaseError = null;
    _purchasePending = true;
    notifyListeners();
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      _purchaseError = e.toString();
    } finally {
      // restorePurchases() only INITIATES the restore — results arrive via
      // purchaseStream. If there's nothing to restore the stream never fires,
      // so we must clear pending here.
      _purchasePending = false;
      notifyListeners();
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        _purchasePending = true;
        notifyListeners();
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        // Always complete the transaction unconditionally — Apple owns the
        // receipt and determines whether the subscription is valid.
        InAppPurchase.instance.completePurchase(purchase);

        if (_isLaunchCheck) {
          // During the silent launch check, only a 'restored' event means an
          // active subscription. 'purchased' events are stale unfinished
          // transactions from prior sessions — drain them and let the timer
          // resolve status if no restored event follows.
          if (purchase.status == PurchaseStatus.restored) {
            debugPrint('[IAP] Launch check: active subscription confirmed');
            if (Platform.isAndroid) _recordAndroidSubscription();
            _completeLaunchCheck(SubscriptionStatus.active);
          } else {
            debugPrint('[IAP] Launch check: draining stale transaction');
          }
        } else {
          // Purchase attempt or explicit restore — ask Apple to confirm the
          // current subscription status rather than trusting the event alone.
          _lastActivationWasRestore =
              purchase.status == PurchaseStatus.restored;
          _purchaseInitiated = false;
          _validateInBackground(purchase);
          _syncPurchaseToRevenueCat(purchase);
          if (Platform.isAndroid) _recordAndroidSubscription();
          _startLaunchCheck();
        }
      } else if (purchase.status == PurchaseStatus.error) {
        if (_isLaunchCheck) {
          _completeLaunchCheck(SubscriptionStatus.freeTrial);
          InAppPurchase.instance.completePurchase(purchase);
        } else {
          final wasPurchaseInitiated = _purchaseInitiated;
          _purchasePending = false;
          _purchaseInitiated = false;
          InAppPurchase.instance.completePurchase(purchase);
          final isCancellation = _isCancellationError(purchase.error);
          final isAlreadyOwned = _isAlreadyOwnedError(purchase.error);
          if (isAlreadyOwned ||
              (Platform.isAndroid && wasPurchaseInitiated && !isCancellation)) {
            debugPrint(
              '[IAP] Android purchase error — attempting restore to sync',
            );
            restorePurchases();
          } else if (isCancellation) {
            _purchaseCancelled = true;
            notifyListeners();
          } else {
            _purchaseError = purchase.error?.message ?? 'Purchase failed.';
            notifyListeners();
          }
        }
      } else if (purchase.status == PurchaseStatus.canceled) {
        _purchasePending = false;
        _purchaseInitiated = false;
        _purchaseCancelled = true;
        notifyListeners();
        InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  bool _isCancellationError(IAPError? error) {
    if (error == null) return false;
    final code = error.code.toLowerCase();
    final message = error.message.toLowerCase();
    return code.contains('cancel') || message.contains('cancel');
  }

  bool _isAlreadyOwnedError(IAPError? error) {
    if (error == null) return false;
    final code = error.code.toLowerCase();
    final message = error.message.toLowerCase();
    return code.contains('already_owned') ||
        code.contains('itemalreadyowned') ||
        message.contains('already own') ||
        message.contains('already purchased');
  }

  void _validateInBackground(PurchaseDetails purchase) {
    Future(() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return; // No Firebase user yet — skip server validation.
      }
      try {
        String? androidId;
        if (Platform.isAndroid) {
          androidId = await _getAndroidId();
        }
        final callable = FirebaseFunctions.instance.httpsCallable(
          'validatePurchase',
        );
        await callable.call({
          'platform': Platform.isIOS ? 'apple' : 'google',
          'productId': purchase.productID,
          'purchaseToken': Platform.isAndroid
              ? purchase.verificationData.serverVerificationData
              : null,
          'receiptData': Platform.isIOS
              ? purchase.verificationData.serverVerificationData
              : null,
          'transactionId': purchase.purchaseID,
          if (Platform.isAndroid && androidId != null) 'androidId': androidId,
        });
        debugPrint('[IAP] Background server validation successful');
      } catch (e) {
        debugPrint('[IAP] Background server validation failed (non-fatal): $e');
      }
    });
  }

  /// Nudges listeners after review access flips the entitlement getters —
  /// `_status` itself is untouched, so nothing else would signal the change.
  void refreshEntitlement() => notifyListeners();

  void clearError() {
    _purchaseError = null;
    notifyListeners();
  }

  void clearCancelled() {
    _purchaseCancelled = false;
    notifyListeners();
  }

  /// Clears a stuck pending state when StoreKit silently drops a cancellation
  /// event. Only clears if still pending — no-op for successful purchases.
  void forceCancelPending() {
    if (!_purchasePending) return;
    _purchasePending = false;
    _purchaseCancelled = true;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;

    final db = FirebaseDatabase.instance.ref();
    await Future.wait([
      db.child('users').child(uid).remove(),
      db.child('stockxTokens').child(uid).remove(),
      db.child('scans').child(uid).remove(),
    ]);

    reset();
  }

  void reset() {
    _initialized = false;
    _isLaunchCheck = false;
    _launchCheckTimer?.cancel();
    _launchCheckTimer = null;
    if (!(_launchCheckCompleter?.isCompleted ?? true)) {
      _launchCheckCompleter!.complete();
    }
    _launchCheckCompleter = null;
    _purchaseSubscription?.cancel();
    _status = SubscriptionStatus.loading;
    _products.clear();
    _assignedProductId = null;
    _assignedOfferingId = null;
    _offeringsResolved = false;
    _offeringsTimer?.cancel();
    _offeringsTimer = null;
    _purchasePending = false;
    _purchaseCancelled = false;
    _purchaseError = null;
    _purchaseInitiated = false;
    _isEligibleForTrial = null;
  }

  @override
  void dispose() {
    _launchCheckTimer?.cancel();
    _offeringsTimer?.cancel();
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
