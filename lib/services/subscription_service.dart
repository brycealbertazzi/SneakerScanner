import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_functions/cloud_functions.dart';

const String kAnnualProductId = 'sneaker_scanner_annual';

enum SubscriptionStatus { loading, freeTrial, active, expired, cancelled }

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  static const _storeKitChannel = MethodChannel('com.sneakerscanner/storekit');

  SubscriptionStatus _status = SubscriptionStatus.loading;
  ProductDetails? _annualProduct;
  bool _purchasePending = false;
  bool _purchaseCancelled = false;
  String? _purchaseError;
  bool _purchaseInitiated = false;
  bool _sawPendingEvent = false;
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
  ProductDetails? get annualProduct => _annualProduct;

  /// True only when the subscription is currently active (including trial period).
  bool get canScan => _status == SubscriptionStatus.active;

  bool get isSubscribed => _status == SubscriptionStatus.active;
  bool get lastActivationWasRestore => _lastActivationWasRestore;

  bool get isLapsedSubscriber =>
      _status == SubscriptionStatus.expired ||
      _status == SubscriptionStatus.cancelled;

  /// Re-queries StoreKit/Play Billing for current status.
  /// Called when the app returns to the foreground.
  void recheckSubscription() {
    if (_isLaunchCheck) return; // Already checking
    if (_purchasePending || _purchaseInitiated)
      return; // Purchase in flight — let it resolve naturally
    _startLaunchCheck();
  }

  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Query StoreKit for intro offer eligibility (iOS only). Fire this off
    // concurrently — result is available before the 1.5 s launch check timeout.
    if (Platform.isIOS) {
      _checkTrialEligibility().then((eligible) {
        _isEligibleForTrial = eligible;
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

    // Load IAP products.
    await _loadProducts();

    // Silently query StoreKit/Play Billing for current subscription status.
    // Results arrive via the purchase stream. _startLaunchCheck is non-blocking;
    // call awaitLaunchCheck() to wait for resolution.
    _startLaunchCheck();
  }

  Future<bool> _checkTrialEligibility() async {
    try {
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
  /// check completes (restored event or 1.5 s timeout), with a 3 s safety cap.
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

    // Fallback: if StoreKit delivers no events within 1.5 s, no active subscription.
    _launchCheckTimer = Timer(const Duration(milliseconds: 1500), () {
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
    // If no active subscription and StoreKit says not eligible for intro offer,
    // treat as lapsed subscriber (previously subscribed, trial already used).
    if (resolvedStatus == SubscriptionStatus.freeTrial &&
        _isEligibleForTrial == false) {
      _status = SubscriptionStatus.cancelled;
    } else {
      _status = resolvedStatus;
    }
    _purchasePending = false;
    _purchaseInitiated = false;
    notifyListeners();
    if (!(_launchCheckCompleter?.isCompleted ?? true)) {
      _launchCheckCompleter!.complete();
    }
    _launchCheckCompleter = null;
  }

  Future<void> _loadProducts() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      debugPrint('[IAP] Store not available');
      return;
    }

    final response = await InAppPurchase.instance.queryProductDetails({
      kAnnualProductId,
    });
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('[IAP] Products not found in store: ${response.notFoundIDs}');
    }
    if (response.productDetails.isNotEmpty) {
      _annualProduct = response.productDetails.first;
      debugPrint(
        '[IAP] Product loaded: ${_annualProduct!.id}, price: ${_annualProduct!.price}',
      );
      notifyListeners();
    } else {
      debugPrint('[IAP] No products returned from store');
    }
  }

  Future<void> buyAnnual() async {
    if (_annualProduct == null) {
      await _loadProducts();
    }
    if (_annualProduct == null) {
      _purchaseError =
          'Product not available. Check your App Store connection and try again.';
      notifyListeners();
      return;
    }
    _purchaseError = null;
    _purchaseCancelled = false;
    _purchasePending = true;
    _purchaseInitiated = true;
    _sawPendingEvent = false;
    notifyListeners();

    final param = PurchaseParam(productDetails: _annualProduct!);
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
        if (_purchaseInitiated) _sawPendingEvent = true;
        _purchasePending = true;
        notifyListeners();
      } else if (purchase.status == PurchaseStatus.purchased) {
        if (_purchaseInitiated && _sawPendingEvent) {
          // Real new purchase — pending always precedes purchased for genuine transactions.
          _validateAndFinish(purchase);
        } else if (_purchaseInitiated && !_sawPendingEvent) {
          // Received 'purchased' without a preceding 'pending'. Two possible causes:
          // (a) Stale unfinished transaction from a prior expired subscription,
          //     delivered immediately when buyNonConsumable() is called.
          // (b) Free trial subscription — Apple skips the pending phase when there
          //     is no payment to process.
          // We can't tell them apart here, so complete the transaction to clear it
          // from StoreKit's queue, then run a fresh status recheck. If the sub is
          // genuinely active (case b), the recheck will confirm it and navigate the
          // user forward. If it was stale (case a), the recheck timer will fire and
          // the user stays on the paywall.
          debugPrint(
            '[IAP] Purchased event without pending — completing and rechecking status',
          );
          _purchaseInitiated = false;
          InAppPurchase.instance.completePurchase(purchase);
          _startLaunchCheck();
        } else {
          // Stale unfinished transaction from a previous session — complete it
          // to clean up StoreKit's queue without activating the subscription.
          debugPrint('[IAP] Completing stale transaction without activating');
          InAppPurchase.instance.completePurchase(purchase);
        }
      } else if (purchase.status == PurchaseStatus.restored) {
        if (_isLaunchCheck) {
          // Silent launch check — active subscription confirmed. No dialog.
          _completeLaunchCheck(SubscriptionStatus.active);
          InAppPurchase.instance.completePurchase(purchase);
        } else if (_purchaseInitiated) {
          // StoreKit returned 'restored' during a buy attempt instead of
          // 'purchased'. This happens when there is a stale unfinished
          // transaction in the queue — most commonly with expired sandbox
          // subscriptions. Do NOT optimistically activate: complete the
          // stale transaction to clear it, then do a fresh status recheck.
          // If the sub is genuinely active the recheck will confirm it;
          // if it is expired the recheck timer will fire and leave the
          // status as cancelled/freeTrial.
          debugPrint(
            '[IAP] Restored event during purchase attempt — rechecking status',
          );
          _purchaseInitiated = false;
          InAppPurchase.instance.completePurchase(purchase);
          _startLaunchCheck();
        } else {
          // User-initiated restore from the Restore Purchases button.
          _validateAndFinish(purchase);
        }
      } else if (purchase.status == PurchaseStatus.error) {
        if (_isLaunchCheck) {
          // Error during silent check — treat as no active subscription.
          _completeLaunchCheck(SubscriptionStatus.freeTrial);
          InAppPurchase.instance.completePurchase(purchase);
        } else {
          final wasPurchaseInitiated = _purchaseInitiated;
          _purchasePending = false;
          _purchaseInitiated = false;
          _sawPendingEvent = false;
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
        _sawPendingEvent = false;
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

  Future<void> _validateAndFinish(PurchaseDetails purchase) async {
    _lastActivationWasRestore = purchase.status == PurchaseStatus.restored;
    _status = SubscriptionStatus.active;
    _purchaseCancelled = false;
    _purchasePending = false;
    _purchaseInitiated = false;
    _sawPendingEvent = false;
    notifyListeners();
    await InAppPurchase.instance.completePurchase(purchase);
    _validateInBackground(purchase);
  }

  void _validateInBackground(PurchaseDetails purchase) {
    Future(() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null)
        return; // No Firebase user yet — skip server validation.
      try {
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
        });
        debugPrint('[IAP] Background server validation successful');
      } catch (e) {
        debugPrint('[IAP] Background server validation failed (non-fatal): $e');
      }
    });
  }

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
    _annualProduct = null;
    _purchasePending = false;
    _purchaseCancelled = false;
    _purchaseError = null;
    _sawPendingEvent = false;
    _isEligibleForTrial = null;
  }

  @override
  void dispose() {
    _launchCheckTimer?.cancel();
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
