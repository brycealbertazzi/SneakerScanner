import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api_keys.dart';

class EbayAuthService {
  EbayAuthService._();

  // eBay OAuth token cache
  static String? accessToken;
  static DateTime? tokenExpiry;

  static Future<String?> getAccessToken() async {
    // Check if we have a valid cached token
    if (accessToken != null &&
        tokenExpiry != null &&
        DateTime.now().isBefore(tokenExpiry!)) {
      return accessToken;
    }

    // Skip if credentials not configured
    if (ApiKeys.ebayClientId.isEmpty || ApiKeys.ebayClientSecret.isEmpty) {
      debugPrint('eBay OAuth: credentials empty, skipping');
      return null;
    }

    try {
      final baseUrl = ApiKeys.ebayProduction
          ? 'https://api.ebay.com'
          : 'https://api.sandbox.ebay.com';

      final credentials = base64Encode(
        utf8.encode('${ApiKeys.ebayClientId}:${ApiKeys.ebayClientSecret}'),
      );

      final response = await http
          .post(
            Uri.parse('$baseUrl/identity/v1/oauth2/token'),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Authorization': 'Basic $credentials',
            },
            body:
                'grant_type=client_credentials&scope=https://api.ebay.com/oauth/api_scope',
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        accessToken = data['access_token'];
        final expiresIn = data['expires_in'] as int;
        tokenExpiry = DateTime.now().add(
          Duration(seconds: expiresIn - 60),
        ); // Buffer
        return accessToken;
      }
    } catch (e) {
      debugPrint('eBay OAuth error: $e');
    }
    return null;
  }
}
