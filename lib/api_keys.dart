import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ApiKeys {
  ApiKeys._();
  static bool _loaded = false;
  static bool get isLoaded => _loaded;

  // Populated from Firebase
  static String kicksDbApiKey = '';
  static String ebayClientId = '';
  static String ebayClientSecret = '';
  static String stockXApiKey = '';
  static String stockXClientId = '';
  static String stockXClientSecret = '';

  // NOT secrets — stay hardcoded
  static const String stockXRedirectUri = 'sneakerscanner://stockx-callback';
  static const bool ebayProduction = true;

  // RevenueCat public app-specific API keys (dashboard → Project settings →
  // API keys). Publishable, safe to hardcode. Empty = tracking disabled.
  static const String revenueCatAppleApiKey =
      'appl_hoLOIQDstFCgQivSqczmHTxgehb'; // appl_...
  static const String revenueCatGoogleApiKey =
      'goog_bdpchqxBSzmmnNJlObhGltPODlS'; // goog_...

  // GoMarketMe affiliate-attribution API key (dashboard → Profile > API Key).
  // Client-side SDK key like the RevenueCat ones above, so it stays hardcoded —
  // it has to be available at launch, long before the signed-in Cloud Function
  // fetch below can run. Empty = attribution disabled.
  static const String goMarketMeApiKey =
      'LDXonRaxvw16KocTslT0j104kUz2DqB18EWFijXx';

  static Future<bool> fetch() async {
    if (_loaded) return true;
    try {
      // Ensure the auth token is fresh before calling — avoids the race
      // condition where currentUser is set but the token hasn't been minted yet
      // after the app restores its session from persistence.
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[ApiKeys] No signed-in user, skipping fetch');
        return false;
      }
      debugPrint('[ApiKeys] Refreshing token for uid: ${user.uid}');
      final token = await user.getIdToken(true);
      debugPrint('[ApiKeys] Token refreshed, length=${token?.length ?? 0}');

      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('getApiKeys');
      final result = await callable.call();
      final data = result.data as Map<String, dynamic>;
      kicksDbApiKey = data['kicksDbApiKey'] as String? ?? '';
      ebayClientId = data['ebayClientId'] as String? ?? '';
      ebayClientSecret = data['ebayClientSecret'] as String? ?? '';
      stockXApiKey = data['stockXApiKey'] as String? ?? '';
      stockXClientId = data['stockXClientId'] as String? ?? '';
      stockXClientSecret = data['stockXClientSecret'] as String? ?? '';
      _loaded = true;
      debugPrint('[ApiKeys] Loaded successfully via Cloud Function');
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[ApiKeys] Cloud Function error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[ApiKeys] Failed to load: $e');
      return false;
    }
  }
}
