import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_functions/cloud_functions.dart';

const String kAnnualProductId = 'sneakerscanner_annual_4999';
const int kFreeScanLimit = 30;

enum SubscriptionStatus { loading, freeTrial, active, expired, cancelled }

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  SubscriptionStatus _status = SubscriptionStatus.loading;
  int _scansUsed = 0;
  int _scansLimit = kFreeScanLimit;
  ProductDetails? _annualProduct;
  bool _purchasePending = false;
  bool _purchaseCancelled = false;
  String? _purchaseError;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  StreamSubscription<DatabaseEvent>? _firebaseSubscription;

  SubscriptionStatus get status => _status;
  int get scansUsed => _scansUsed;
  int get scansLimit => _scansLimit;
  int get scansRemaining => (_scansLimit - _scansUsed).clamp(0, _scansLimit);
  bool get purchasePending => _purchasePending;
  bool get purchaseCancelled => _purchaseCancelled;
  String? get purchaseError => _purchaseError;
  ProductDetails? get annualProduct => _annualProduct;

  bool get canScan {
    if (_status == SubscriptionStatus.active) return true;
    if (_status == SubscriptionStatus.freeTrial) return _scansUsed < _scansLimit;
    return false;
  }

  bool get isSubscribed => _status == SubscriptionStatus.active;

  /// Returns the platform-specific subscription node reference.
  DatabaseReference _subRef(String uid) {
    final platform = Platform.isIOS ? 'apple' : 'google';
    return FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(uid)
        .child('subscriptions')
        .child(platform);
  }

  Future<void> initialize() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Ensure subscription doc exists (new/existing users get free trial)
    await _ensureSubscriptionExists(user.uid);

    // Listen to platform-specific Firebase subscription node
    _firebaseSubscription?.cancel();
    _firebaseSubscription = _subRef(user.uid)
        .onValue
        .listen(_onFirebaseUpdate);

    // Load IAP products
    await _loadProducts();

    // Listen to purchase updates
    _purchaseSubscription?.cancel();
    _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (error) {
        _purchaseError = error.toString();
        notifyListeners();
      },
    );
  }

  Future<void> _ensureSubscriptionExists(String uid) async {
    final ref = _subRef(uid);
    final snapshot = await ref.get();
    if (snapshot.exists) return;

    // Migrate existing users from the old single-node path (iOS only).
    if (Platform.isIOS) {
      final oldRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(uid)
          .child('subscription');
      final oldSnapshot = await oldRef.get();
      if (oldSnapshot.exists) {
        await ref.set(oldSnapshot.value);
        return;
      }
    }

    await ref.set({
      'status': 'free_trial',
      'scansUsed': 0,
      'scansLimit': kFreeScanLimit,
      'platform': Platform.isIOS ? 'apple' : 'google',
      'productId': null,
      'originalTransactionId': null,
      'purchaseToken': null,
      'expiresAt': null,
    });
  }

  void _onFirebaseUpdate(DatabaseEvent event) {
    final data = event.snapshot.value as Map<dynamic, dynamic>?;
    if (data == null) return;

    final statusStr = data['status'] as String? ?? 'free_trial';
    _scansUsed = (data['scansUsed'] as int?) ?? 0;
    _scansLimit = (data['scansLimit'] as int?) ?? kFreeScanLimit;

    switch (statusStr) {
      case 'active':
        _status = SubscriptionStatus.active;
        break;
      case 'expired':
        _status = SubscriptionStatus.expired;
        break;
      case 'cancelled':
        _status = SubscriptionStatus.cancelled;
        break;
      default:
        _status = SubscriptionStatus.freeTrial;
    }

    notifyListeners();
  }

  Future<void> _loadProducts() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      debugPrint('[IAP] Store not available');
      return;
    }

    final response =
        await InAppPurchase.instance.queryProductDetails({kAnnualProductId});
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('[IAP] Products not found in store: ${response.notFoundIDs}');
    }
    if (response.productDetails.isNotEmpty) {
      _annualProduct = response.productDetails.first;
      debugPrint(
          '[IAP] Product loaded: ${_annualProduct!.id}, price: ${_annualProduct!.price}');
      notifyListeners();
    } else {
      debugPrint('[IAP] No products returned from store');
    }
  }

  Future<void> buyAnnual() async {
    // Retry product load if it wasn't available at startup
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
      // so we must clear pending here. If purchases do come through, the stream
      // handler (_validateAndFinish) will manage pending state for each one.
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
        _validateAndFinish(purchase);
      } else if (purchase.status == PurchaseStatus.error) {
        _purchasePending = false;
        // iOS fires SKErrorPaymentCancelled (code 2 / "paymentCancelled") when
        // the user dismisses the payment or sign-in sheet — treat as cancellation,
        // not as a hard error.
        final isCancellation = _isCancellationError(purchase.error);
        if (isCancellation) {
          _purchaseCancelled = true;
        } else {
          _purchaseError = purchase.error?.message ?? 'Purchase failed.';
        }
        notifyListeners();
        InAppPurchase.instance.completePurchase(purchase);
      } else if (purchase.status == PurchaseStatus.canceled) {
        _purchasePending = false;
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

  Future<void> _validateAndFinish(PurchaseDetails purchase) async {
    final user = FirebaseAuth.instance.currentUser;
    try {
      // Optimistically activate — trust the platform confirmation immediately.
      // Server-side validation runs in the background and can update/revoke
      // the subscription later if needed.
      if (user != null) {
        await _subRef(user.uid).update({
          'status': 'active',
          'platform': Platform.isIOS ? 'apple' : 'google',
          'productId': purchase.productID,
          'originalTransactionId': purchase.purchaseID,
        });
      }
    } catch (e) {
      debugPrint('[IAP] Failed to activate subscription: $e');
      _purchaseError = 'Failed to activate. Please try again.';
    } finally {
      _purchasePending = false;
      notifyListeners();
      await InAppPurchase.instance.completePurchase(purchase);
    }

    // Background server validation — non-blocking, no error shown to user.
    _validateInBackground(purchase);
  }

  void _validateInBackground(PurchaseDetails purchase) {
    Future(() async {
      try {
        final callable =
            FirebaseFunctions.instance.httpsCallable('validatePurchase');
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

  /// Increments scan count in Firebase. Returns false if user cannot scan.
  Future<bool> incrementScanCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !canScan) return false;
    try {
      final ref = _subRef(user.uid).child('scansUsed');
      await ref.set(ServerValue.increment(1));
      return true;
    } catch (e) {
      return false;
    }
  }

  void clearError() {
    _purchaseError = null;
    notifyListeners();
  }

  void clearCancelled() {
    _purchaseCancelled = false;
    notifyListeners();
  }

  /// Called when the app returns to the foreground while a purchase is still
  /// pending. Treats the pending purchase as cancelled immediately.
  void forceCancelPending() {
    if (!_purchasePending) return;
    _purchasePending = false;
    _purchaseCancelled = true;
    notifyListeners();
  }

  void reset() {
    _purchaseSubscription?.cancel();
    _firebaseSubscription?.cancel();
    _status = SubscriptionStatus.loading;
    _scansUsed = 0;
    _scansLimit = kFreeScanLimit;
    _annualProduct = null;
    _purchasePending = false;
    _purchaseCancelled = false;
    _purchaseError = null;
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _firebaseSubscription?.cancel();
    super.dispose();
  }
}
