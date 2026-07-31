import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Store-review bypass: unlocks entitlement without a purchase.
///
/// Reached only by holding the paywall's subscribe button for three seconds and
/// entering the access code. There is no visible affordance and no way to
/// revoke it on-device short of reinstalling.
///
/// Auth is deliberately untouched — this bypasses the paywall only, so the
/// normal Google/Apple sign-in still happens afterwards.
class ReviewAccess {
  ReviewAccess._();

  static final ReviewAccess instance = ReviewAccess._();

  static const _prefsKey = 'review_access_granted';

  /// SHA-256 of the access code. Stored as a digest so the code itself can't be
  /// recovered by running `strings` over the shipped binary.
  ///
  /// To rotate: hash the new code (`printf '%s' 'NEW-CODE' | shasum -a 256`)
  /// and replace this constant.
  static const _codeDigest =
      '689c6af9258c9a76b26cb76e2c3c04293a444e3988808351aac6f03d996ac339';

  bool _granted = false;

  /// Read synchronously by [SubscriptionService]'s entitlement getters, so it
  /// must be loaded before the first routing decision — see `main()`.
  bool get isGranted => _granted;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _granted = prefs.getBool(_prefsKey) ?? false;
  }

  bool matches(String input) =>
      sha256.convert(utf8.encode(input.trim().toUpperCase())).toString() ==
      _codeDigest;

  Future<void> grant() async {
    _granted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }
}
