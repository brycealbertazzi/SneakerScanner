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
  String? _purchaseError;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  StreamSubscription<DatabaseEvent>? _firebaseSubscription;

  SubscriptionStatus get status => _status;
  int get scansUsed => _scansUsed;
  int get scansLimit => _scansLimit;
  int get scansRemaining => (_scansLimit - _scansUsed).clamp(0, _scansLimit);
  bool get purchasePending => _purchasePending;
  String? get purchaseError => _purchaseError;
  ProductDetails? get annualProduct => _annualProduct;

  bool get canScan {
    if (_status == SubscriptionStatus.active) return true;
    if (_status == SubscriptionStatus.freeTrial) return _scansUsed < _scansLimit;
    return false;
  }

  bool get isSubscribed => _status == SubscriptionStatus.active;

  Future<void> initialize() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Ensure subscription doc exists (new/existing users get free trial)
    await _ensureSubscriptionExists(user.uid);

    // Listen to Firebase subscription node
    _firebaseSubscription?.cancel();
    _firebaseSubscription = FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(user.uid)
        .child('subscription')
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
    final ref = FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(uid)
        .child('subscription');
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      await ref.set({
        'status': 'free_trial',
        'scansUsed': 0,
        'scansLimit': kFreeScanLimit,
        'platform': null,
        'productId': null,
        'originalTransactionId': null,
        'purchaseToken': null,
        'expiresAt': null,
      });
    }
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
        _purchaseError = purchase.error?.message ?? 'Purchase failed.';
        notifyListeners();
        InAppPurchase.instance.completePurchase(purchase);
      } else if (purchase.status == PurchaseStatus.canceled) {
        _purchasePending = false;
        notifyListeners();
        InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  Future<void> _validateAndFinish(PurchaseDetails purchase) async {
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
      // Firebase listener will update status automatically
    } catch (e) {
      _purchaseError = 'Validation failed. Please contact support.';
    } finally {
      _purchasePending = false;
      notifyListeners();
      await InAppPurchase.instance.completePurchase(purchase);
    }
  }

  /// Increments scan count in Firebase. Returns false if user cannot scan.
  Future<bool> incrementScanCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !canScan) return false;
    try {
      final ref = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('subscription')
          .child('scansUsed');
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

  void reset() {
    _purchaseSubscription?.cancel();
    _firebaseSubscription?.cancel();
    _status = SubscriptionStatus.loading;
    _scansUsed = 0;
    _scansLimit = kFreeScanLimit;
    _annualProduct = null;
    _purchasePending = false;
    _purchaseError = null;
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _firebaseSubscription?.cancel();
    super.dispose();
  }
}
