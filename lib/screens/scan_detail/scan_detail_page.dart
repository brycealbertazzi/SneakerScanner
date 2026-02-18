import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import '../../api_keys.dart';
import '../../models/scan_data.dart';
import '../../services/ebay_auth_service.dart';
import '../../services/nike_colorway_utils.dart';
import 'widgets/info_card.dart';
import 'widgets/profit_calculator.dart';

class ScanDetailPage extends StatefulWidget {
  final String scanId;
  final ScanData scanData;
  final int timestamp;

  const ScanDetailPage({
    super.key,
    required this.scanId,
    required this.scanData,
    required this.timestamp,
  });

  @override
  State<ScanDetailPage> createState() => _ScanDetailPageState();
}

class _ScanDetailPageState extends State<ScanDetailPage> {
  Map<String, dynamic>? _productInfo;
  String? _error;

  // Retail price manual entry
  double? _manualRetailPrice;

  // eBay API state
  bool _isLoadingEbayPrices = true;
  double? _ebayAveragePrice;

  // StockX price state (via KicksDB)
  bool _isLoadingStockXPrice = true;
  double? _stockXPrice;
  String? _stockXSlug;

  // GOAT price state (via KicksDB)
  bool _isLoadingGoatPrice = true;
  double? _goatPrice;
  String? _goatSlug;

  // Colorway variants (Nike/Jordan fallback)
  List<ColorwayVariant>? _stockXColorways;
  List<ColorwayVariant>? _goatColorways;

  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  bool _identityConfirmed = false;

  bool _pricingInterrupted = false;

  /// The primary identifier used for DB keys and cache lookups.
  String get _primaryCode => widget.scanData.sku ?? '';

  @override
  void initState() {
    super.initState();
    _loadProductInfo();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Product lookup methods
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadProductInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (widget.scanId.isNotEmpty) {
          final scanSnapshot = await _database
              .child('scans')
              .child(user.uid)
              .child(widget.scanId)
              .get();

          if (scanSnapshot.exists) {
            final scanDataMap = Map<String, dynamic>.from(
              scanSnapshot.value as Map,
            );
            final savedRetailPrice = double.tryParse(
              (scanDataMap['retailPrice'] as String?) ?? '',
            );
            final savedStockXPrice = double.tryParse(
              (scanDataMap['stockxPrice'] as String?) ?? '',
            );
            final savedGoatPrice = double.tryParse(
              (scanDataMap['goatPrice'] as String?) ?? '',
            );
            final savedStockXColorways = scanDataMap['stockxColorways'];
            final savedGoatColorways = scanDataMap['goatColorways'];
            final pricingStatus = scanDataMap['pricingStatus'] as String?;

            setState(() {
              if (savedRetailPrice != null) _manualRetailPrice = savedRetailPrice;
              if (savedStockXPrice != null) {
                _stockXPrice = savedStockXPrice;
                _isLoadingStockXPrice = false;
              }
              if (savedGoatPrice != null) {
                _goatPrice = savedGoatPrice;
                _isLoadingGoatPrice = false;
              }
              if (savedStockXColorways is List && savedStockXColorways.isNotEmpty) {
                _stockXColorways = _parseColorwaysFromDb(savedStockXColorways);
              }
              if (savedGoatColorways is List && savedGoatColorways.isNotEmpty) {
                _goatColorways = _parseColorwaysFromDb(savedGoatColorways);
              }
              if (pricingStatus == 'loading') _pricingInterrupted = true;
            });
          }
        }

        if (_primaryCode.isNotEmpty) {
          final cachedSnapshot = await _database
              .child('products')
              .child(_primaryCode)
              .get();

          if (cachedSnapshot.exists) {
            final cached = Map<String, dynamic>.from(
              cachedSnapshot.value as Map,
            );
            setState(() {
              _productInfo = cached;
              _identityConfirmed = cached['notFound'] != true;
            });
            // Don't return — still need to run _lookupProduct for
            // StockX/GOAT pricing + colorway fallback
          }
        }
      }

      _setPricingStatus('loading');

      // Run eBay in parallel with the identity/pricing waterfall.
      // eBay only needs widget.scanData.sku/gtin, not _productInfo.
      final ebayFuture = _fetchEbayPrices();
      await _lookupProduct();
      await ebayFuture;

      _savePricesToDatabase();
      _setPricingStatus('complete');
    } catch (e) {
      setState(() {
        _error = 'Failed to load product info';
      });
    }
  }

  /// Unified product lookup + pricing flow:
  /// 1. Call /unified/products/`<sku>` or /unified/gtin — identifies shoe + extracts StockX/GOAT prices
  /// 2. If StockX/GOAT missing & Nike/Jordan — colorway fallback via platform-specific endpoints
  /// 3. Not found fallback
  Future<void> _lookupProduct() async {
    final stopwatch = Stopwatch()..start();

    try {
      // Preserve any cached identity so we don't overwrite with worse data
      Map<String, dynamic>? productInfo = _productInfo;
      bool confirmed = _identityConfirmed;
      final sku = widget.scanData.sku;
      final gtin = widget.scanData.gtin;

      // ── Step 1: Call unified endpoint ──────────────────────────────
      Uri? unifiedUri;
      if (sku != null && sku.isNotEmpty) {
        unifiedUri = Uri.parse(
          'https://api.kicks.dev/v3/unified/products'
          '/${Uri.encodeComponent(sku)}?similarity=0.85',
        );
      } else if (gtin != null && gtin.isNotEmpty) {
        unifiedUri = Uri.parse(
          'https://api.kicks.dev/v3/unified/gtin'
          '?identifier=${Uri.encodeComponent(gtin)}',
        );
      }

      List<Map<String, dynamic>> unifiedItems = [];

      if (unifiedUri != null) {
        debugPrint('═══ STEP 1: KicksDB Unified ═══');
        debugPrint('[Unified] Request: $unifiedUri');

        final response = await http
            .get(
              unifiedUri,
              headers: {'Authorization': 'Bearer ${ApiKeys.kicksDbApiKey}'},
            )
            .timeout(const Duration(seconds: 15));

        debugPrint('[Unified] Status: ${response.statusCode}');
        debugPrint(
          '[Unified] Body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
        );

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          if (body is Map<String, dynamic>) {
            if (body.containsKey('data') && body['data'] is List) {
              for (var item in body['data']) {
                unifiedItems.add(item as Map<String, dynamic>);
              }
            } else if (body.containsKey('shop_name') || body.containsKey('title')) {
              unifiedItems.add(body);
            }
          } else if (body is List) {
            for (var item in body) {
              unifiedItems.add(item as Map<String, dynamic>);
            }
          }
        }
      }

      // The SKU to match against
      final matchSku = sku ?? '';
      final size = widget.scanData.size;

      // Extract identity from first matching result + StockX/GOAT prices
      for (final item in unifiedItems) {
        final shopName = (item['shop_name'] ?? '').toString().toLowerCase();
        final apiSku = (item['sku'] ?? '').toString();

        // Identity: use the first result that has a title
        if (productInfo == null) {
          final title = item['title'] ?? item['name'];
          if (title != null) {
            productInfo = {
              'title': title,
              'brand': item['brand'] ?? '',
              'sku': apiSku,
              'styleCode': apiSku,
              'retailPrice': item['retailPrice']?.toString() ??
                  item['retail_price']?.toString(),
              'images': item['images'] is List
                  ? item['images']
                  : item['image'] != null
                      ? [item['image']]
                      : [],
              'model': item['model'] ?? '',
              'slug': item['slug'] ?? '',
              'category': item['category'] ?? '',
            };
            confirmed = true;
            debugPrint('[Unified] Identity found: "$title" (${stopwatch.elapsedMilliseconds}ms)');
          }
        }

        // Prices: only from stockx/goat with SKU match
        if (shopName != 'stockx' && shopName != 'goat') continue;
        if (matchSku.isNotEmpty && !_skuSubsequenceMatch(matchSku, apiSku)) {
          debugPrint('[Unified] Skip $shopName — SKU mismatch: "$apiSku" vs "$matchSku"');
          continue;
        }

        final pricesRaw = item['prices'];
        if (pricesRaw is! Map<String, dynamic>) continue;
        final price = _extractPriceFromMap(pricesRaw, size);
        if (price == null || price <= 0) continue;

        final slug = (item['slug'] ?? item['id'] ?? item['name'])?.toString();

        if (shopName == 'stockx' && _stockXPrice == null) {
          debugPrint('[Unified] StockX price: \$${price.toStringAsFixed(2)} (${stopwatch.elapsedMilliseconds}ms)');
          _stockXPrice = price;
          _stockXSlug = slug;
        } else if (shopName == 'goat' && _goatPrice == null) {
          debugPrint('[Unified] GOAT price: \$${price.toStringAsFixed(2)} (${stopwatch.elapsedMilliseconds}ms)');
          _goatPrice = price;
          _goatSlug = slug;
        }
      }

      // ── Step 2: Colorway fallback (Nike/Jordan only) ───────────────
      final brand = productInfo?['brand'] as String? ?? widget.scanData.brand ?? '';
      if (isNikeOrJordan(brand) && sku != null && sku.isNotEmpty) {
        final parsed = parseNikeSku(sku);
        if (parsed != null) {
          final (modelBlock, _) = parsed;

          if (_stockXPrice == null) {
            debugPrint('═══ STEP 2: StockX colorway fallback ═══');
            final variants = await _fetchColorwayVariants(
              'stockx', sku, modelBlock, stopwatch,
            );
            if (variants.isNotEmpty) {
              _stockXColorways = variants;
              _stockXPrice = variants.first.price;
              _stockXSlug = variants.first.slug;
            }
          }

          if (_goatPrice == null) {
            debugPrint('═══ STEP 2: GOAT colorway fallback ═══');
            final variants = await _fetchColorwayVariants(
              'goat', sku, modelBlock, stopwatch,
            );
            if (variants.isNotEmpty) {
              _goatColorways = variants;
              _goatPrice = variants.first.price;
              _goatSlug = variants.first.slug;
            }
          }
        }
      }

      // If unified didn't find identity but colorway fallback did find results,
      // use the scan data for identity
      if (productInfo == null && (_stockXPrice != null || _goatPrice != null)) {
        productInfo = {
          'title': widget.scanData.displayName.isNotEmpty
              ? widget.scanData.displayName
              : 'Unknown Product',
          'brand': widget.scanData.brand ?? '',
          'sku': sku ?? '',
          'styleCode': sku ?? '',
        };
        confirmed = true;
      }

      // ── Step 3: Not found ──────────────────────────────────────────
      if (productInfo == null) {
        debugPrint('═══ NOT FOUND ═══');
        debugPrint('No product found (${stopwatch.elapsedMilliseconds}ms)');

        setState(() {
          _productInfo = {
            'title': widget.scanData.displayName.isNotEmpty
                ? widget.scanData.displayName
                : 'Product Not Found',
            'brand': widget.scanData.brand ?? '',
            'description': 'No product found.',
            'notFound': true,
          };
          _identityConfirmed = false;
          _isLoadingStockXPrice = false;
          _isLoadingGoatPrice = false;
        });
        return;
      }

      // ── Save and update state ──────────────────────────────────────
      final title = productInfo['title'];
      final image = (productInfo['images'] as List?)?.isNotEmpty == true
          ? productInfo['images'][0]
          : null;
      final retailPrice = productInfo['retailPrice'];

      if (_primaryCode.isNotEmpty) {
        await _database.child('products').child(_primaryCode).set(productInfo);
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null && widget.scanId.isNotEmpty) {
        await _database
            .child('scans')
            .child(user.uid)
            .child(widget.scanId)
            .update({
              'productTitle': title,
              'productImage': image is String && image.isNotEmpty
                  ? image
                  : null,
              'retailPrice': retailPrice,
            });
      }

      debugPrint('');
      debugPrint('╔══════════════════════════════════════════════════════════════╗');
      debugPrint('║  LOOKUP COMPLETE (${stopwatch.elapsedMilliseconds}ms)');
      debugPrint('║  Product: $title');
      debugPrint('║  StockX: \$${_stockXPrice?.toStringAsFixed(2) ?? "N/A"}');
      debugPrint('║  GOAT: \$${_goatPrice?.toStringAsFixed(2) ?? "N/A"}');
      debugPrint('╚══════════════════════════════════════════════════════════════╝');
      debugPrint('');

      setState(() {
        _productInfo = productInfo;
        _identityConfirmed = confirmed;
        _isLoadingStockXPrice = false;
        _isLoadingGoatPrice = false;
        // Colorway variants set during step 2 fallback
        // (already assigned above, but setState triggers rebuild)
      });
    } catch (e) {
      debugPrint('Lookup error: $e');
      setState(() {
        _productInfo = {
          'title': widget.scanData.displayName.isNotEmpty
              ? widget.scanData.displayName
              : 'Product Not Found',
          'brand': widget.scanData.brand ?? '',
          'description': 'No product found.',
          'notFound': true,
        };
        _identityConfirmed = false;
        _isLoadingStockXPrice = false;
        _isLoadingGoatPrice = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Search query helpers
  // ═══════════════════════════════════════════════════════════════════════════

  String _buildSearchQuery({bool forStockX = false}) {
    // Check SKU from scan data first, then from productInfo
    final sku =
        widget.scanData.sku ??
        (_productInfo?['sku'] as String?) ??
        (_productInfo?['styleCode'] as String?);
    if (sku != null && sku.isNotEmpty) {
      return sku;
    }

    final brand = widget.scanData.brand ?? _productInfo?['brand'] as String?;
    final modelName = widget.scanData.modelName;
    final colorway = widget.scanData.colorway;

    if (brand != null &&
        brand.isNotEmpty &&
        modelName != null &&
        modelName.isNotEmpty) {
      final parts = [brand, modelName];
      if (colorway != null && colorway.isNotEmpty) parts.add(colorway);
      final query = parts.join(' ');
      if (forStockX) {
        final words = query.split(' ');
        if (words.length > 6) return words.take(6).join(' ');
      }
      return query;
    }

    final title = _productInfo?['title'] as String?;
    if (title != null && title != 'Product Not Found') {
      if (forStockX) {
        final words = title.split(' ');
        if (words.length > 6) return words.take(6).join(' ');
      }
      return title;
    }

    return widget.scanData.displayName;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Marketplace links
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _openEbaySearch() async {
    final searchQuery = _buildSearchQuery();
    final url = Uri.parse(
      'https://www.ebay.com/sch/i.html?_nkw=${Uri.encodeComponent(searchQuery)}',
    );
    await launchUrl(url, mode: LaunchMode.platformDefault);
  }

  Future<void> _openStockXSearch() async {
    if (_stockXSlug != null && _stockXSlug!.isNotEmpty) {
      final url = Uri.parse('https://stockx.com/$_stockXSlug');
      await launchUrl(url, mode: LaunchMode.platformDefault);
    } else {
      final title = _productInfo?['title'] as String?;
      if (title != null) {
        final url = Uri.parse(
          'https://stockx.com/search?s=${Uri.encodeComponent(title)}',
        );
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    }
  }

  Future<void> _openGoatSearch() async {
    if (_goatSlug != null && _goatSlug!.isNotEmpty) {
      final url = Uri.parse('https://www.goat.com/sneakers/$_goatSlug');
      await launchUrl(url, mode: LaunchMode.platformDefault);
    } else {
      final title = _productInfo?['title'] as String?;
      if (title != null) {
        final url = Uri.parse(
          'https://www.goat.com/search?query=${Uri.encodeComponent(title)}',
        );
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Pricing waterfall
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _fetchEbayPrices() async {
    final stopwatch = Stopwatch()..start();

    setState(() => _isLoadingEbayPrices = true);

    try {
      final token = await EbayAuthService.getAccessToken();

      if (token == null) {
        debugPrint('[eBay] API not configured, skipping');
        setState(() => _isLoadingEbayPrices = false);
        return;
      }

      final baseUrl = ApiKeys.ebayProduction
          ? 'https://api.ebay.com'
          : 'https://api.sandbox.ebay.com';

      final sku = widget.scanData.sku;
      final gtin = widget.scanData.gtin;

      String requestUrl;
      if (sku != null && sku.isNotEmpty) {
        requestUrl =
            '$baseUrl/buy/browse/v1/item_summary/search?'
            'q=${Uri.encodeComponent(sku)}'
            '&limit=1';
      } else if (gtin != null && gtin.isNotEmpty) {
        requestUrl =
            '$baseUrl/buy/browse/v1/item_summary/search?'
            'gtin=$gtin'
            '&limit=1';
      } else {
        debugPrint('[eBay] No SKU or GTIN available, skipping');
        setState(() => _isLoadingEbayPrices = false);
        return;
      }
      debugPrint('[eBay] Request: $requestUrl');

      final response = await http
          .get(
            Uri.parse(requestUrl),
            headers: {
              'Authorization': 'Bearer $token',
              'X-EBAY-C-MARKETPLACE-ID': 'EBAY_US',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('[eBay] Status: ${response.statusCode}');
      debugPrint(
        '[eBay] Body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['itemSummaries'] as List? ?? [];

        if (items.isNotEmpty) {
          final item = items[0];
          final priceData = item['price'];
          if (priceData != null && priceData['value'] != null) {
            final price = double.tryParse(priceData['value'].toString());
            if (price != null && price > 0) {
              debugPrint(
                '[eBay] price=\$${price.toStringAsFixed(2)} '
                '(${stopwatch.elapsedMilliseconds}ms)',
              );
              setState(() {
                _ebayAveragePrice = price;
                _isLoadingEbayPrices = false;
              });
              return;
            }
          }
        }
      }

      debugPrint(
        '[eBay] No listings found (${stopwatch.elapsedMilliseconds}ms)',
      );
      setState(() => _isLoadingEbayPrices = false);
    } catch (e) {
      debugPrint('[eBay] Error: $e (${stopwatch.elapsedMilliseconds}ms)');
      setState(() => _isLoadingEbayPrices = false);
    }
  }

  /// Check if [scannedSku]'s alphanumeric characters (in order) are a
  /// subsequence of [apiSku]'s alphanumeric characters.
  bool _skuSubsequenceMatch(String scannedSku, String apiSku) {
    final scanned = scannedSku.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final api = apiSku.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (scanned.isEmpty) return false;
    int j = 0;
    for (int i = 0; i < api.length && j < scanned.length; i++) {
      if (api[i] == scanned[j]) j++;
    }
    return j == scanned.length;
  }

  /// Extract a price from the `prices` size-map.
  /// If [size] matches a key, use that; otherwise pick the highest price.
  double? _extractPriceFromMap(Map<String, dynamic> prices, String? size) {
    if (prices.isEmpty) return null;

    // Try exact size match
    if (size != null && prices.containsKey(size)) {
      final p = double.tryParse(prices[size].toString());
      if (p != null && p > 0) return p;
    }

    // Fallback: highest price
    double? highest;
    for (final entry in prices.entries) {
      final p = double.tryParse(entry.value.toString());
      if (p != null && p > 0 && (highest == null || p > highest)) {
        highest = p;
      }
    }
    return highest;
  }


  List<ColorwayVariant> _parseColorwaysFromDb(List<dynamic> list) {
    return list.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final colorCode = map['colorCode']?.toString() ?? '';
      final (family, color) = nikeColorFamily(colorCode);
      return ColorwayVariant(
        sku: map['sku']?.toString() ?? '',
        colorCode: colorCode,
        colorFamily: map['colorFamily']?.toString() ?? family,
        displayColor: color,
        price: double.tryParse(map['price']?.toString() ?? '') ?? 0,
        slug: map['slug']?.toString(),
      );
    }).toList();
  }

  /// Fetch colorway variants from a platform-specific KicksDB endpoint.
  Future<List<ColorwayVariant>> _fetchColorwayVariants(
    String platform,
    String sku,
    String modelBlock,
    Stopwatch stopwatch,
  ) async {
    final uri = Uri.parse(
      'https://api.kicks.dev/v3/$platform/products'
      '?query=${Uri.encodeComponent(sku)}&limit=5'
      '&display[prices]=true&display[variants]=true',
    );
    debugPrint('[KicksDB $platform colorway] Request: $uri');

    try {
      final response = await http
          .get(
            uri,
            headers: {'Authorization': 'Bearer ${ApiKeys.kicksDbApiKey}'},
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[KicksDB $platform colorway] Status: ${response.statusCode}');
      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body);
      final List<Map<String, dynamic>> candidates = [];
      if (body is Map<String, dynamic>) {
        if (body.containsKey('data') && body['data'] is List) {
          for (var item in body['data']) {
            candidates.add(item as Map<String, dynamic>);
          }
        } else if (body.containsKey('title') || body.containsKey('name') || body.containsKey('slug')) {
          candidates.add(body);
        }
      } else if (body is List) {
        for (var item in body) {
          candidates.add(item as Map<String, dynamic>);
        }
      }

      final variants = <ColorwayVariant>[];
      final seenFamilies = <String>{};
      for (final product in candidates) {
        final apiSku = (product['style_id'] ?? product['sku'] ?? '').toString();
        final parsed = parseNikeSku(apiSku);
        if (parsed == null) continue;

        final (apiModel, apiColor) = parsed;
        // Model block must match; colorway can differ
        if (apiModel.toUpperCase() != modelBlock.toUpperCase()) continue;

        // Extract price (old format: min_price → avg_price → variants lowest_ask)
        final price = _extractOldFormatPrice(product);
        if (price == null || price <= 0) continue;

        final (family, color) = nikeColorFamily(apiColor);

        // Skip duplicate color families (e.g. 001 and 003 are both Black)
        if (seenFamilies.contains(family)) continue;
        seenFamilies.add(family);

        final slug = (product['slug'] ?? product['id'] ?? product['name'])?.toString();

        variants.add(ColorwayVariant(
          sku: apiSku,
          colorCode: apiColor,
          colorFamily: family,
          displayColor: color,
          price: price,
          slug: slug,
        ));
      }

      debugPrint(
        '[KicksDB $platform colorway] Found ${variants.length} variants '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
      return variants;
    } catch (e) {
      debugPrint('[KicksDB $platform colorway] Error: $e');
      return [];
    }
  }

  /// Extract price from old KicksDB format (min_price → avg_price → variants lowest_ask).
  double? _extractOldFormatPrice(Map<String, dynamic> product) {
    final minPrice = double.tryParse((product['min_price'] ?? '').toString());
    if (minPrice != null && minPrice > 0) return minPrice;

    final avgPrice = double.tryParse((product['avg_price'] ?? '').toString());
    if (avgPrice != null && avgPrice > 0) return avgPrice;

    final variants = product['variants'] as List?;
    if (variants != null) {
      double? lowest;
      for (var variant in variants) {
        final ask = variant['lowest_ask'];
        if (ask != null) {
          final askPrice = double.tryParse(ask.toString());
          if (askPrice != null && askPrice > 0) {
            if (lowest == null || askPrice < lowest) {
              lowest = askPrice;
            }
          }
        }
      }
      return lowest;
    }
    return null;
  }

  Future<void> _savePricesToDatabase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.scanId.isEmpty) return;

    try {
      final updateData = <String, dynamic>{};

      final retailPriceStr = _productInfo?['retailPrice'] as String?;
      final retailPrice =
          retailPriceStr ?? (_manualRetailPrice?.toStringAsFixed(2));
      if (retailPrice != null) {
        updateData['retailPrice'] = retailPrice;
      }

      if (_ebayAveragePrice != null) {
        updateData['ebayPrice'] = _ebayAveragePrice!.toStringAsFixed(2);
      }

      if (_stockXPrice != null) {
        updateData['stockxPrice'] = _stockXPrice!.toStringAsFixed(2);
      }

      if (_goatPrice != null) {
        updateData['goatPrice'] = _goatPrice!.toStringAsFixed(2);
      }

      if (_stockXColorways != null && _stockXColorways!.isNotEmpty) {
        updateData['stockxColorways'] = _stockXColorways!
            .map((v) => {
                  'sku': v.sku,
                  'colorCode': v.colorCode,
                  'colorFamily': v.colorFamily,
                  'price': v.price,
                  'slug': v.slug,
                })
            .toList();
      }

      if (_goatColorways != null && _goatColorways!.isNotEmpty) {
        updateData['goatColorways'] = _goatColorways!
            .map((v) => {
                  'sku': v.sku,
                  'colorCode': v.colorCode,
                  'colorFamily': v.colorFamily,
                  'price': v.price,
                  'slug': v.slug,
                })
            .toList();
      }

      if (updateData.isNotEmpty) {
        await _database
            .child('scans')
            .child(user.uid)
            .child(widget.scanId)
            .update(updateData);
      }
    } catch (e) {
      debugPrint('Error saving prices: $e');
    }
  }

  void _setPricingStatus(String status) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.scanId.isEmpty) return;
    _database.child('scans').child(user.uid).child(widget.scanId).update({
      'pricingStatus': status,
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final hasPrices =
        _ebayAveragePrice != null ||
        _stockXPrice != null ||
        _goatPrice != null ||
        _isLoadingEbayPrices ||
        _isLoadingStockXPrice ||
        _isLoadingGoatPrice;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Scan Details'),
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            border: Border(
              top: BorderSide(color: const Color(0xFF2A2A2A), width: 1),
            ),
          ),
          child: SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop('scanAnother');
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Another'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF646CFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: Colors.grey[500])),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadProductInfo,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Product Image
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child:
                          _productInfo?['images'] != null &&
                              (_productInfo!['images'] as List).isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                _productInfo!['images'][0],
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildPlaceholderImage(),
                              ),
                            )
                          : _buildPlaceholderImage(),
                    ),
                    const SizedBox(height: 24),

                    // 2. Product Title
                    Text(
                      _identityConfirmed
                          ? (_productInfo?['title'] ?? 'Unknown Product')
                          : (widget.scanData.displayName.isNotEmpty
                                ? widget.scanData.displayName
                                : 'Scanned Product'),
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 3. Brand Badge
                    Builder(builder: (context) {
                      final badgeBrand = widget.scanData.brand ??
                          _productInfo?['brand']?.toString();
                      if (badgeBrand == null || badgeBrand.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF646CFF).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          badgeBrand,
                          style: GoogleFonts.inter(
                            color: const Color(0xFF646CFF),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),

                    // 4. Info Cards
                    ..._buildInfoCards(),
                    const SizedBox(height: 24),

                    // 6. Description
                    if (_productInfo?['description'] != null &&
                        _productInfo!['description'].toString().isNotEmpty) ...[
                      Text(
                        'Description',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _productInfo!['description'],
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.grey[400],
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // 7. Profit Calculator (show whenever prices exist)
                    if (hasPrices) ...[
                      ProfitCalculator(
                        productInfo: _productInfo,
                        manualRetailPrice: _manualRetailPrice,
                        ebayAveragePrice: _ebayAveragePrice,
                        stockXPrice: _stockXPrice,
                        goatPrice: _goatPrice,
                        isLoadingEbayPrices: _isLoadingEbayPrices,
                        isLoadingStockXPrice: _isLoadingStockXPrice,
                        isLoadingGoatPrice: _isLoadingGoatPrice,
                        stockXColorways: _stockXColorways,
                        goatColorways: _goatColorways,
                        onOpenEbay: _openEbaySearch,
                        onOpenStockX: _openStockXSearch,
                        onOpenGoat: _openGoatSearch,
                        onRetailPriceChanged: (value) {
                          setState(() => _manualRetailPrice = value);
                        },
                        onSavePrices: _savePricesToDatabase,
                      ),
                      const SizedBox(height: 24),
                    ],

                    // 8. Pricing interrupted
                    if (_pricingInterrupted &&
                        _identityConfirmed &&
                        _stockXPrice == null &&
                        _goatPrice == null &&
                        !_isLoadingStockXPrice &&
                        !_isLoadingGoatPrice) ...[
                      _buildPricingInterruptedMessage(),
                      const SizedBox(height: 16),
                    ],


                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _buildInfoCards() {
    final cards = <Widget>[];

    final brand = widget.scanData.brand ?? _productInfo?['brand'] as String?;
    if (brand != null && brand.isNotEmpty) {
      cards.add(InfoCard(label: 'Brand', value: brand, icon: Icons.business));
      cards.add(const SizedBox(height: 12));
    }

    final modelName =
        widget.scanData.modelName ?? _productInfo?['title'] as String?;
    if (modelName != null &&
        modelName.isNotEmpty &&
        modelName != 'Product Not Found') {
      cards.add(
        InfoCard(label: 'Model Name', value: modelName, icon: Icons.label),
      );
      cards.add(const SizedBox(height: 12));
    }

    final colorway =
        widget.scanData.colorway ?? _productInfo?['colorway'] as String?;
    if (colorway != null && colorway.isNotEmpty) {
      cards.add(
        InfoCard(label: 'Colorway', value: colorway, icon: Icons.palette),
      );
      cards.add(const SizedBox(height: 12));
    }

    if (widget.scanData.sku != null) {
      cards.add(
        InfoCard(
          label: 'SKU',
          value: widget.scanData.sku!,
          icon: Icons.qr_code,
        ),
      );
      cards.add(const SizedBox(height: 12));
    }

    if (widget.scanData.size != null && widget.scanData.size!.isNotEmpty) {
      cards.add(
        InfoCard(
          label: 'Size',
          value: widget.scanData.size!,
          icon: Icons.straighten,
        ),
      );
      cards.add(const SizedBox(height: 12));
    }

    cards.add(
      InfoCard(
        label: 'Scanned',
        value: _formatDate(widget.timestamp),
        icon: Icons.access_time,
      ),
    );

    return cards;
  }

  Widget _buildPlaceholderImage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_run, size: 64, color: Colors.grey[700]),
          const SizedBox(height: 8),
          Text(
            'No image available',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingInterruptedMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3A3A2A), width: 1),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange[400],
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'The app was closed while prices were loading. Re-scan to fetch pricing.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.orange[300]),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(int timestamp) {
    if (timestamp == 0) return 'Just now';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.month}/${date.day}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
