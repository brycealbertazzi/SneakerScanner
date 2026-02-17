import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

  static Future<bool> fetch() async {
    if (_loaded) return true;
    try {
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
