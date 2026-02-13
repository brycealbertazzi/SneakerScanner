import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import '../api_keys.dart';

class StockXAuthService {
  StockXAuthService._();

  // Static token state shared across the app
  static String? accessToken;
  static DateTime? tokenExpiry;
  static String? refreshToken;
  static bool tokensLoaded = false;

  static Future<void> loadTokens() async {
    if (tokensLoaded) return;
    tokensLoaded = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('stockxTokens')
          .child(user.uid)
          .get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        accessToken = data['accessToken'] as String?;
        refreshToken = data['refreshToken'] as String?;
        final expiresAt = data['expiresAt'] as int?;
        if (expiresAt != null) {
          tokenExpiry = DateTime.fromMillisecondsSinceEpoch(expiresAt);
        }
        debugPrint('[StockX OAuth] Tokens loaded from Firebase');
      }
    } catch (e) {
      debugPrint('[StockX OAuth] Error loading tokens: $e');
    }
  }

  static Future<String?> getAccessToken() async {
    if (!tokensLoaded) {
      await loadTokens();
    }
    if (accessToken != null &&
        tokenExpiry != null &&
        DateTime.now().isBefore(tokenExpiry!)) {
      return accessToken;
    }
    if (refreshToken != null) {
      final refreshed = await refreshAccessToken();
      if (refreshed != null) return refreshed;
    }
    // Fallback: use client_credentials grant to get a token without user OAuth
    return await fetchClientCredentialsToken();
  }

  static Future<String?> fetchClientCredentialsToken() async {
    try {
      debugPrint('[StockX OAuth] Requesting client_credentials token...');
      final response = await http.post(
        Uri.parse('https://accounts.stockx.com/oauth/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'client_credentials',
          'client_id': ApiKeys.stockXClientId,
          'client_secret': ApiKeys.stockXClientSecret,
          'audience': 'gateway.stockx.com',
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('[StockX OAuth] Client credentials status: ${response.statusCode}');
      debugPrint('[StockX OAuth] Client credentials body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        accessToken = data['access_token'] as String;
        final expiresIn = data['expires_in'] as int;
        tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
        debugPrint('[StockX OAuth] Client credentials token acquired');
        return accessToken;
      } else {
        debugPrint('[StockX OAuth] Client credentials failed: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[StockX OAuth] Client credentials error: $e');
      return null;
    }
  }

  static Future<String?> refreshAccessToken() async {
    try {
      debugPrint('[StockX OAuth] Refreshing access token...');
      final response = await http.post(
        Uri.parse('https://accounts.stockx.com/oauth/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'client_id': ApiKeys.stockXClientId,
          'client_secret': ApiKeys.stockXClientSecret,
          'refresh_token': refreshToken!,
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('[StockX OAuth] Refresh status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        accessToken = data['access_token'] as String;
        final newRefresh = data['refresh_token'] as String?;
        if (newRefresh != null) refreshToken = newRefresh;
        final expiresIn = data['expires_in'] as int;
        tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));

        // Save to Firebase
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseDatabase.instance.ref().child('stockxTokens').child(user.uid).set({
            'accessToken': accessToken,
            'refreshToken': refreshToken,
            'expiresAt': DateTime.now()
                .add(Duration(seconds: expiresIn))
                .millisecondsSinceEpoch,
          });
        }
        debugPrint('[StockX OAuth] Token refreshed successfully');
        return accessToken;
      } else {
        debugPrint('[StockX OAuth] Refresh failed: ${response.body}');
        accessToken = null;
        tokenExpiry = null;
        refreshToken = null;
        return null;
      }
    } catch (e) {
      debugPrint('[StockX OAuth] Refresh error: $e');
      return null;
    }
  }

  /// Exchange an authorization code for tokens after OAuth callback.
  static Future<bool> exchangeCode(String code) async {
    try {
      debugPrint('[StockX OAuth] Exchanging authorization code for tokens...');
      final response = await http.post(
        Uri.parse('https://accounts.stockx.com/oauth/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'client_id': ApiKeys.stockXClientId,
          'client_secret': ApiKeys.stockXClientSecret,
          'redirect_uri': ApiKeys.stockXRedirectUri,
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('[StockX OAuth] Token exchange status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccessToken = data['access_token'] as String;
        final newRefreshToken = data['refresh_token'] as String?;
        final expiresIn = data['expires_in'] as int;

        // Save to static vars
        accessToken = newAccessToken;
        refreshToken = newRefreshToken;
        tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
        tokensLoaded = true;

        // Save to Firebase
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseDatabase.instance.ref()
              .child('stockxTokens')
              .child(user.uid)
              .set({
            'accessToken': newAccessToken,
            'refreshToken': newRefreshToken,
            'expiresAt': DateTime.now()
                .add(Duration(seconds: expiresIn))
                .millisecondsSinceEpoch,
          });
        }

        debugPrint('[StockX OAuth] Tokens saved successfully');
        return true;
      } else {
        debugPrint('[StockX OAuth] Token exchange failed: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[StockX OAuth] Token exchange error: $e');
      return false;
    }
  }

  static Future<void> launchOAuth() async {
    final uri = Uri.parse(
      'https://accounts.stockx.com/authorize'
      '?response_type=code'
      '&client_id=${ApiKeys.stockXClientId}'
      '&redirect_uri=${Uri.encodeComponent(ApiKeys.stockXRedirectUri)}'
      '&audience=gateway.stockx.com'
      '&scope=openid',
    );
    debugPrint('[StockX OAuth] Launching: $uri');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static void clearTokens() {
    accessToken = null;
    refreshToken = null;
    tokenExpiry = null;
    tokensLoaded = false;
  }
}
