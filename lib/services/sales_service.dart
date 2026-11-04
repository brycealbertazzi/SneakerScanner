import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api_keys.dart';

/// One completed sale from the KicksDB StockX or GOAT /sales endpoint.
class SaleRecord {
  final double amount;
  final String currency;
  final DateTime? date;

  /// US size. GOAT only — StockX sales only carry a variant id.
  final String? size;

  /// GOAT only, e.g. "Athens, US".
  final String? location;

  /// GOAT only: true when the sale was an accepted offer rather than Buy Now.
  final bool isOffer;

  const SaleRecord({
    required this.amount,
    required this.currency,
    this.date,
    this.size,
    this.location,
    this.isOffer = false,
  });

  static SaleRecord? fromJson(Map<String, dynamic> json) {
    final amount = double.tryParse((json['amount'] ?? '').toString());
    if (amount == null || amount <= 0) return null;
    final rawDate = (json['purchased_at'] ?? json['created_at'])?.toString();
    final size = (json['size_us'] ?? json['size'])?.toString();
    final location = json['location']?.toString();
    return SaleRecord(
      amount: amount,
      currency: (json['currency'] ?? 'USD').toString(),
      date: rawDate != null ? DateTime.tryParse(rawDate)?.toLocal() : null,
      size: (size != null && size.isNotEmpty) ? size : null,
      location: (location != null && location.isNotEmpty) ? location : null,
      isOffer: json['type']?.toString() == 'PURCHASE_TYPE_OFFER_CLOSED',
    );
  }
}

/// Fetches recent sales from KicksDB. Requests are cached per product for the
/// life of the app session, so switching colorways back and forth (or the
/// page prefetching before the UI asks) never repeats a call.
class SalesService {
  SalesService._();

  static final Map<String, Future<List<SaleRecord>>> _cache = {};

  /// [platform] is 'stockx' or 'goat'. Returns sales newest first, or an
  /// empty list when there are none or the request fails.
  static Future<List<SaleRecord>> fetch(String platform, String productId) {
    final key = '$platform:$productId';
    return _cache.putIfAbsent(key, () async {
      final result = await _request(platform, productId);
      // Don't keep failures around, so a later open can retry.
      if (result == null) _cache.remove(key);
      return result ?? const [];
    });
  }

  static Future<List<SaleRecord>?> _request(
    String platform,
    String productId,
  ) async {
    final uri = Uri(
      scheme: 'https',
      host: 'api.kicks.dev',
      pathSegments: ['v3', platform, 'products', productId, 'sales'],
    );
    debugPrint('[Sales $platform] Request: $uri');
    try {
      final response = await http
          .get(
            uri,
            headers: {'Authorization': 'Bearer ${ApiKeys.kicksDbApiKey}'},
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('[Sales $platform] Status: ${response.statusCode}');
      if (response.statusCode != 200) return null;
      debugPrint(
        '[Sales $platform] Body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
      );
      final body = jsonDecode(response.body);
      final data = body is Map<String, dynamic> ? body['data'] : null;
      if (data is! List) return const [];
      final sales = data
          .whereType<Map>()
          .map((e) => SaleRecord.fromJson(Map<String, dynamic>.from(e)))
          .whereType<SaleRecord>()
          .toList();
      sales.sort((a, b) {
        if (a.date == null || b.date == null) return 0;
        return b.date!.compareTo(a.date!);
      });
      return sales;
    } catch (e) {
      debugPrint('[Sales $platform] Error: $e');
      return null;
    }
  }
}

/// "just now", "5 min ago", "3 hours ago", "2 days ago", or a date.
String relativeSaleTime(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  if (diff.inDays < 30) {
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }
  return formatSaleDate(date);
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Apr 20, 2025".
String formatSaleDate(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

/// "5:31 PM".
String formatSaleTime(DateTime date) {
  final h = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final m = date.minute.toString().padLeft(2, '0');
  return '$h:$m ${date.hour < 12 ? 'AM' : 'PM'}';
}
