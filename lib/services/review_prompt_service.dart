import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mixpanel_service.dart';

/// Asks for an in-app rating (StoreKit on iOS, Play In-App Review on Android)
/// after the 3rd and 20th successful scan.
///
/// Neither platform reports whether the sheet was shown or whether the user
/// rated, so we don't track that — the OS throttles the sheet itself and
/// suppresses it for users who have already reviewed.
class ReviewPromptService {
  ReviewPromptService._();

  static const _countKey = 'sneakscan_successful_scan_count';

  /// Legacy counter from the old iOS-only prompt, which fired on the 3rd scan
  /// of any kind.
  static const _legacyCountKey = 'sneakscan_scan_count';

  static const _promptAt = {3, 20};

  static bool _pending = false;
  static int _pendingCount = 0;

  /// Call once a new scan has produced a result. Marks a prompt as pending
  /// when the count hits a threshold; [promptIfPending] shows it later.
  static Future<void> recordSuccessfulScan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var count = prefs.getInt(_countKey);
      if (count == null) {
        // iOS users past the old 3-scan prompt were already asked once.
        final legacy = prefs.getInt(_legacyCountKey) ?? 0;
        count = Platform.isIOS && legacy >= 3 ? 3 : 0;
      }
      count++;
      await prefs.setInt(_countKey, count);
      if (_promptAt.contains(count)) {
        _pending = true;
        _pendingCount = count;
      }
    } catch (e) {
      debugPrint('ReviewPromptService.recordSuccessfulScan error: $e');
    }
  }

  /// Call after the user leaves the result page. No-op unless a threshold
  /// was just reached.
  static Future<void> promptIfPending() async {
    if (!_pending) return;
    _pending = false;
    try {
      // Let the pop transition finish before the system sheet slides up.
      await Future.delayed(const Duration(milliseconds: 600));
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
        MixpanelService.instance.track(
          'Review Prompt Requested',
          properties: {'scan_count': _pendingCount},
        );
      }
    } catch (e) {
      debugPrint('ReviewPromptService.promptIfPending error: $e');
    }
  }
}
