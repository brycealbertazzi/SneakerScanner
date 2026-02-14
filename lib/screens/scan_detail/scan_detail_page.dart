import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import '../../api_keys.dart';
import '../../constants.dart';
import '../../models/scan_data.dart';
import '../../services/ebay_auth_service.dart';
import 'widgets/info_card.dart';
import 'widgets/ebay_prices_section.dart';
import 'widgets/similar_results_section.dart';
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
  bool _isLoading = true;
  Map<String, dynamic>? _productInfo;
  String? _error;

  // Retail price manual entry
  double? _manualRetailPrice;

  // eBay API state
  bool _isLoadingEbayPrices = false;
  double? _ebayLowestPrice;
  double? _ebayAveragePrice;
  int? _ebayListingCount;
  String? _ebayError;

  // StockX price state (via KicksDB)
  bool _isLoadingStockXPrice = false;
  double? _stockXPrice;
  String? _stockXSlug;

  // GOAT price state (via KicksDB)
  bool _isLoadingGoatPrice = false;
  double? _goatPrice;
  String? _goatSlug;

  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  bool _identityConfirmed = false;

  List<Map<String, dynamic>> _similarCandidates = [];
  bool _isLoadingCandidates = false;
  bool _candidatesSearchDone = false;
  bool _fuzzySearchInitiated = false;

  bool _pricingInterrupted = false;

  // Shared price cache TTL: 24 hours
  static const int _priceCacheTtlMs = 24 * 60 * 60 * 1000;
  static const bool _priceCacheEnabled = false;

  /// The primary identifier used for DB keys and cache lookups.
  String get _primaryCode => widget.scanData.sku ?? '';

  /// SKU-only query for KicksDB pricing — returns null if no SKU available.
  String? get _skuQuery {
    final sku = widget.scanData.sku;
    if (sku != null && sku.isNotEmpty) return sku;
    final productSku = _productInfo?['sku'] as String?;
    if (productSku != null && productSku.isNotEmpty) return productSku;
    final styleCode = _productInfo?['styleCode'] as String?;
    if (styleCode != null && styleCode.isNotEmpty) return styleCode;
    return null;
  }

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
            final scanData = Map<String, dynamic>.from(
              scanSnapshot.value as Map,
            );
            final savedRetailPrice = scanData['retailPrice'] as String?;
            if (savedRetailPrice != null) {
              _manualRetailPrice = double.tryParse(savedRetailPrice);
            }
            final savedStockXPrice = scanData['stockxPrice'] as String?;
            if (savedStockXPrice != null) {
              _stockXPrice = double.tryParse(savedStockXPrice);
            }
            final savedGoatPrice = scanData['goatPrice'] as String?;
            if (savedGoatPrice != null) {
              _goatPrice = double.tryParse(savedGoatPrice);
            }
            final savedCandidates = scanData['sneakerDbCandidates'];
            if (savedCandidates is List && savedCandidates.isNotEmpty) {
              _similarCandidates = savedCandidates
                  .map((c) => Map<String, dynamic>.from(c as Map))
                  .toList();
              _candidatesSearchDone = true;
              _fuzzySearchInitiated = true;
            }
            if (scanData['pricingStatus'] == 'loading') {
              _pricingInterrupted = true;
            }
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
            final confirmed = cached['notFound'] != true;

            setState(() {
              _productInfo = cached;
              _identityConfirmed = confirmed;
              _isLoading = false;
            });
            _fetchAllPrices();
            if (!confirmed && !_candidatesSearchDone) {
              _fetchKicksDbFuzzyCandidates().then(
                (_) => _saveCandidatesToDatabase(),
              );
            }
            return;
          }
        }
      }

      await _lookupProduct();
      _fetchAllPrices();
    } catch (e) {
      setState(() {
        _error = 'Failed to load product info';
        _isLoading = false;
      });
    }
  }

  /// Unified product lookup flow:
  /// 1. SKU → KicksDB exact search (identity confirmed)
  /// 2. Brand/model/colorway → KicksDB fuzzy search (identity NOT confirmed)
  Future<void> _lookupProduct() async {
    try {
      Map<String, dynamic>? productInfo;
      bool confirmed = false;
      final sku = widget.scanData.sku;

      // Step 1: SKU → KicksDB exact (identity confirmed)
      if (sku != null && sku.isNotEmpty) {
        debugPrint('═══ LOOKUP STEP 1 ═══');
        debugPrint('KicksDB exact search for SKU "$sku"');
        productInfo = await _searchKicksDb(sku, isStyleCodeSearch: true);
        if (productInfo != null) confirmed = true;
      }

      // Step 2: Brand/model/colorway → KicksDB fuzzy (identity NOT confirmed)
      if (productInfo == null) {
        debugPrint('═══ LOOKUP STEP 2 ═══');
        debugPrint('KicksDB fuzzy search — identity not confirmed');
        _fetchKicksDbFuzzyCandidates().then((_) => _saveCandidatesToDatabase());

        setState(() {
          _productInfo = {
            'title': widget.scanData.displayName.isNotEmpty
                ? widget.scanData.displayName
                : 'Product Not Found',
            'brand': widget.scanData.brand ?? '',
            'description':
                'No product found. Similar results may appear below.',
            'notFound': true,
          };
          _identityConfirmed = false;
          _isLoading = false;
        });
        return;
      }

      // Steps 1 or 2 succeeded — save and update state
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

      setState(() {
        _productInfo = productInfo;
        _identityConfirmed = confirmed;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Lookup error: $e');
      setState(() {
        _productInfo = {
          'title': widget.scanData.displayName.isNotEmpty
              ? widget.scanData.displayName
              : 'Product Not Found',
          'brand': widget.scanData.brand ?? '',
          'description': 'No product found. Similar results may appear below.',
          'notFound': true,
        };
        _identityConfirmed = false;
        _isLoading = false;
      });
      _fetchKicksDbFuzzyCandidates().then((_) => _saveCandidatesToDatabase());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Validation helpers
  // ═══════════════════════════════════════════════════════════════════════════

  bool _looksLikeFootwear(Map<String, dynamic> product) {
    final brand = (product['brand'] ?? '').toString().toLowerCase().trim();

    if (brand.length >= 2 &&
        knownFootwearBrands.any(
          (b) => brand.contains(b) || b.contains(brand),
        )) {
      return true;
    }

    final category = (product['category'] ?? '').toString().toLowerCase();
    final title = (product['title'] ?? product['name'] ?? '')
        .toString()
        .toLowerCase();
    final slug = (product['slug'] ?? '').toString().toLowerCase();
    final combined = '$category $title $slug';
    return footwearKeywords.any((kw) => combined.contains(kw));
  }

  static bool _isRetailerLabel(String text) {
    final lower = text.toLowerCase();
    return retailerLabels.any((label) => lower.contains(label));
  }

  bool _resultMatchesLabel(Map<String, dynamic> product, String query) {
    final apiTitle = (product['title'] ?? product['name'] ?? '')
        .toString()
        .toLowerCase();
    final apiBrand = (product['brand'] ?? '').toString().toLowerCase();
    final queryLower = query.toLowerCase();

    final queryWords = queryLower
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();
    final apiWords = '$apiBrand $apiTitle'
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();

    if (queryWords.isEmpty) return false;

    final overlap = queryWords.intersection(apiWords);
    return overlap.length >= 2 || overlap.length > queryWords.length * 0.5;
  }

  bool _isProductMatch(Map<String, dynamic> apiProduct) {
    if (!_looksLikeFootwear(apiProduct)) return false;

    final scannedBrand =
        (_productInfo?['brand'] as String?)?.toLowerCase().trim() ?? '';
    final scannedTitle =
        (_productInfo?['title'] as String?)?.toLowerCase().trim() ?? '';
    final scannedModel =
        (_productInfo?['model'] as String?)?.toLowerCase().trim() ?? '';

    final apiTitle =
        ((apiProduct['title'] ?? apiProduct['name'] ?? '') as String)
            .toLowerCase()
            .trim();
    final apiBrand = ((apiProduct['brand'] ?? '') as String)
        .toLowerCase()
        .trim();

    if (scannedBrand.isEmpty && scannedTitle.isEmpty) return true;

    if (scannedBrand.isNotEmpty && apiBrand.isNotEmpty) {
      if (!apiBrand.contains(scannedBrand) &&
          !scannedBrand.contains(apiBrand)) {
        return false;
      }
    }

    if (scannedModel.isNotEmpty && apiTitle.contains(scannedModel)) return true;

    final scannedWords = scannedTitle
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();
    final apiWords = apiTitle
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();
    final overlap = scannedWords.intersection(apiWords);

    if (scannedWords.isNotEmpty && apiWords.isNotEmpty && overlap.length < 2) {
      return false;
    }

    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // API search methods (KicksDB)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> _searchKicksDb(
    String query, {
    bool isStyleCodeSearch = false,
  }) async {
    if (!isStyleCodeSearch && _isRetailerLabel(query)) {
      debugPrint('KicksDB skip: query "$query" is a retailer/private label');
      return null;
    }

    final kicksDbUrl = 'https://api.kicks.dev/v3/stockx/products'
        '?query=${Uri.encodeComponent(query)}&limit=5'
        '&display[prices]=true&display[variants]=false';
    debugPrint('[KicksDB Lookup] Request: $kicksDbUrl');
    final response = await http
        .get(
          Uri.parse(kicksDbUrl),
          headers: {'Authorization': 'Bearer ${ApiKeys.kicksDbApiKey}'},
        )
        .timeout(const Duration(seconds: 10));

    debugPrint('[KicksDB Lookup] Status ($query): ${response.statusCode}');
    debugPrint(
      'KicksDB lookup body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
    );

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body);
    List<dynamic> items = [];
    if (body is Map<String, dynamic> &&
        body.containsKey('data') &&
        body['data'] is List) {
      items = body['data'];
    } else if (body is List) {
      items = body;
    }

    if (items.isEmpty) return null;

    for (final item in items) {
      final product = item as Map<String, dynamic>;
      final title = product['title'] ?? product['name'] ?? 'Unknown Product';
      final brand = product['brand'] ?? '';
      final image = product['image'] ?? product['thumbnail'] ?? '';
      final retailPrice = product['retail_price']?.toString();
      final styleId = (product['style_id'] ?? '')
          .toString()
          .replaceAll(' ', '-')
          .toUpperCase();

      if (_isRetailerLabel(brand.toString())) {
        debugPrint('KicksDB skip (retailer label): "$title" brand="$brand"');
        continue;
      }

      if (!_looksLikeFootwear(product)) {
        debugPrint('KicksDB skip (not footwear): "$title"');
        continue;
      }

      if (isStyleCodeSearch) {
        final queryNorm = query.replaceAll(' ', '-').toUpperCase();
        if (styleId.isNotEmpty && styleId == queryNorm) {
          // exact match
        } else {
          final titleUpper = title.toString().toUpperCase();
          final slugUpper = (product['slug'] ?? '')
              .toString()
              .replaceAll('-', ' ')
              .toUpperCase();
          if (!titleUpper.contains(queryNorm) &&
              !titleUpper.contains(queryNorm.replaceAll('-', ' ')) &&
              !slugUpper.contains(queryNorm.replaceAll('-', ' '))) {
            debugPrint(
              'KicksDB skip (style code "$queryNorm" not found in product): "$title" style_id="$styleId"',
            );
            continue;
          }
        }
      }

      if (!isStyleCodeSearch && !_resultMatchesLabel(product, query)) {
        debugPrint(
          'KicksDB skip (label mismatch): "$title" for query "$query"',
        );
        continue;
      }

      return <String, dynamic>{
        'title': title,
        'brand': brand,
        'description': '',
        'category': (product['category'] ?? 'Sneakers').toString(),
        'images': image is String && image.isNotEmpty ? [image] : [],
        'retailPrice': retailPrice,
        'styleCode': _primaryCode,
        'gtinVerified': isStyleCodeSearch,
        'lastUpdated': ServerValue.timestamp,
      };
    }

    debugPrint(
      'KicksDB: no valid match for "$query" out of ${items.length} candidates',
    );
    return null;
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
    if (_productInfo == null) return;
    final stopwatch = Stopwatch()..start();

    setState(() {
      _isLoadingEbayPrices = true;
      _ebayError = null;
    });

    try {
      final token = await EbayAuthService.getAccessToken();

      if (token == null) {
        debugPrint('[eBay] API not configured, skipping');
        setState(() {
          _isLoadingEbayPrices = false;
          _ebayError = 'eBay API not configured';
        });
        return;
      }

      final searchQuery = _buildSearchQuery();
      final baseUrl = ApiKeys.ebayProduction
          ? 'https://api.ebay.com'
          : 'https://api.sandbox.ebay.com';

      final requestUrl =
          '$baseUrl/buy/browse/v1/item_summary/search?'
          'q=${Uri.encodeComponent(searchQuery)}'
          '&category_ids=93427'
          '&limit=50'
          '&sort=price';
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
          double totalPrice = 0;
          double? lowestPrice;
          int validPrices = 0;

          for (var item in items) {
            final priceData = item['price'];
            if (priceData != null && priceData['value'] != null) {
              final price = double.tryParse(priceData['value'].toString());
              if (price != null && price > 0) {
                totalPrice += price;
                validPrices++;
                if (lowestPrice == null || price < lowestPrice) {
                  lowestPrice = price;
                }
              }
            }
          }

          if (validPrices > 0) {
            debugPrint(
              '[eBay] avg=\$${(totalPrice / validPrices).toStringAsFixed(2)} '
              'lowest=\$${lowestPrice?.toStringAsFixed(2)} '
              'listings=$validPrices (${stopwatch.elapsedMilliseconds}ms)',
            );
            setState(() {
              _ebayLowestPrice = lowestPrice;
              _ebayAveragePrice = totalPrice / validPrices;
              _ebayListingCount = validPrices;
              _isLoadingEbayPrices = false;
            });
            return;
          }
        }
      }

      debugPrint(
        '[eBay] No listings found (${stopwatch.elapsedMilliseconds}ms)',
      );
      setState(() {
        _isLoadingEbayPrices = false;
        _ebayError = 'No listings found';
      });
    } catch (e) {
      debugPrint('[eBay] Error: $e (${stopwatch.elapsedMilliseconds}ms)');
      setState(() {
        _isLoadingEbayPrices = false;
        _ebayError = 'Failed to fetch prices';
      });
    }
  }

  Future<void> _fetchAllPrices() async {
    if (_productInfo == null) return;

    // eBay always runs immediately, separate from StockX/GOAT flow
    _fetchEbayPrices();

    if (!_identityConfirmed) {
      debugPrint('');
      debugPrint(
        '╔══════════════════════════════════════════════════════════════╗',
      );
      debugPrint(
        '║  PRICING SKIPPED: identity not confirmed for $_primaryCode',
      );
      debugPrint(
        '╚══════════════════════════════════════════════════════════════╝',
      );
      debugPrint('');
      setState(() {
        _isLoadingStockXPrice = false;
        _isLoadingGoatPrice = false;
      });
      return;
    }

    setState(() {
      _isLoadingStockXPrice = true;
      _isLoadingGoatPrice = true;
    });

    if (_priceCacheEnabled && _primaryCode.isNotEmpty) {
      try {
        final cacheSnapshot = await _database
            .child('priceCache')
            .child(_primaryCode)
            .get();

        if (cacheSnapshot.exists) {
          final cacheData = Map<String, dynamic>.from(
            cacheSnapshot.value as Map,
          );
          final cachedAt = cacheData['cachedAt'] as int?;
          final now = DateTime.now().millisecondsSinceEpoch;

          if (cachedAt != null && (now - cachedAt) < _priceCacheTtlMs) {
            final cachedStockX = double.tryParse(
              (cacheData['stockxPrice'] ?? '').toString(),
            );
            final cachedGoat = double.tryParse(
              (cacheData['goatPrice'] ?? '').toString(),
            );
            setState(() {
              _stockXPrice = (cachedStockX != null && cachedStockX > 0)
                  ? cachedStockX
                  : null;
              _stockXSlug = (cachedStockX != null && cachedStockX > 0)
                  ? cacheData['stockxSlug'] as String?
                  : null;
              _goatPrice = (cachedGoat != null && cachedGoat > 0)
                  ? cachedGoat
                  : null;
              _goatSlug = (cachedGoat != null && cachedGoat > 0)
                  ? cacheData['goatSlug'] as String?
                  : null;
              _isLoadingStockXPrice = false;
              _isLoadingGoatPrice = false;
            });
            _savePricesToDatabase();
            return;
          }
        }
      } catch (e) {
        debugPrint('Price cache read error: $e');
      }
    }

    final totalStopwatch = Stopwatch()..start();

    _pricingInterrupted = false;
    _setPricingStatus('loading');

    debugPrint('');
    debugPrint(
      '╔══════════════════════════════════════════════════════════════╗',
    );
    debugPrint('║  PRICING WATERFALL START: $_primaryCode');
    debugPrint(
      '╚══════════════════════════════════════════════════════════════╝',
    );

    // Step 1: KicksDB by SKU — if StockX or GOAT found, stop
    debugPrint('');
    debugPrint('═══ STEP 1: KicksDB by SKU ═══');
    await _fetchKicksDbStockXPrice();
    await _fetchKicksDbGoatPrice();
    debugPrint(
      '[KicksDB] Result: stockx=\$${_stockXPrice?.toStringAsFixed(2) ?? "N/A"} '
      'goat=\$${_goatPrice?.toStringAsFixed(2) ?? "N/A"}',
    );

    if (_stockXPrice != null || _goatPrice != null) {
      debugPrint('Step 1 found resell prices — stopping waterfall');
      _finalizePricing(totalStopwatch);
      return;
    }

    // Step 2: KicksDB fuzzy by name (no confirmed matches from step 1)
    debugPrint('');
    debugPrint('═══ STEP 2: KicksDB fuzzy (no confirmed matches) ═══');
    _fetchKicksDbFuzzyCandidates().then((_) => _saveCandidatesToDatabase());

    _finalizePricing(totalStopwatch);
  }

  void _finalizePricing(Stopwatch totalStopwatch) {
    setState(() {
      _isLoadingStockXPrice = false;
      _isLoadingGoatPrice = false;
    });

    if (_priceCacheEnabled &&
        _primaryCode.isNotEmpty &&
        (_stockXPrice != null || _goatPrice != null)) {
      try {
        final cacheData = <String, dynamic>{'cachedAt': ServerValue.timestamp};
        if (_stockXPrice != null) {
          cacheData['stockxPrice'] = _stockXPrice!.toStringAsFixed(2);
          cacheData['stockxSlug'] = _stockXSlug;
        }
        if (_goatPrice != null) {
          cacheData['goatPrice'] = _goatPrice!.toStringAsFixed(2);
          cacheData['goatSlug'] = _goatSlug;
        }
        _database.child('priceCache').child(_primaryCode).set(cacheData);
      } catch (e) {
        debugPrint('Price cache write error: $e');
      }
    }

    _savePricesToDatabase();
    _setPricingStatus('complete');

    debugPrint('');
    debugPrint(
      '╔══════════════════════════════════════════════════════════════╗',
    );
    debugPrint(
      '║  PRICING WATERFALL COMPLETE (${totalStopwatch.elapsedMilliseconds}ms)',
    );
    debugPrint(
      '║  eBay: avg=\$${_ebayAveragePrice?.toStringAsFixed(2) ?? "N/A"} lowest=\$${_ebayLowestPrice?.toStringAsFixed(2) ?? "N/A"}',
    );
    debugPrint('║  StockX: \$${_stockXPrice?.toStringAsFixed(2) ?? "N/A"}');
    debugPrint('║  GOAT: \$${_goatPrice?.toStringAsFixed(2) ?? "N/A"}');
    debugPrint(
      '╚══════════════════════════════════════════════════════════════╝',
    );
    debugPrint('');
  }

  Future<void> _fetchKicksDbStockXPrice() async {
    if (_stockXPrice != null) return;
    // KicksDB pricing only queries by SKU — never by title
    final query = _skuQuery;
    if (query == null) {
      debugPrint('[KicksDB StockX] Skipped — no SKU available');
      return;
    }
    final stopwatch = Stopwatch()..start();
    debugPrint('[KicksDB StockX] Starting lookup for SKU "$query"');
    try {
      final uri = Uri.parse(
        'https://api.kicks.dev/v3/stockx/products'
        '?query=${Uri.encodeComponent(query)}&limit=5'
        '&display[prices]=true&display[variants]=true',
      );
      debugPrint('[KicksDB StockX] Request: $uri');

      final response = await http
          .get(
            uri,
            headers: {'Authorization': 'Bearer ${ApiKeys.kicksDbApiKey}'},
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[KicksDB StockX] Status: ${response.statusCode}');

      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body);
      final List<Map<String, dynamic>> candidates = [];
      if (body is Map<String, dynamic>) {
        if (body.containsKey('data') && body['data'] is List) {
          for (var item in body['data']) {
            candidates.add(item as Map<String, dynamic>);
          }
        } else if (body.containsKey('title') || body.containsKey('slug')) {
          candidates.add(body);
        }
      } else if (body is List) {
        for (var item in body) {
          candidates.add(item as Map<String, dynamic>);
        }
      }

      for (final product in candidates) {
        if (!_isProductMatch(product)) {
          debugPrint('[KicksDB StockX] Skip mismatch: "${product['title']}"');
          continue;
        }

        double? lowestAsk;
        final minPrice = double.tryParse(
          (product['min_price'] ?? '').toString(),
        );
        if (minPrice != null && minPrice > 0) lowestAsk = minPrice;

        if (lowestAsk == null) {
          final avgPrice = double.tryParse(
            (product['avg_price'] ?? '').toString(),
          );
          if (avgPrice != null && avgPrice > 0) lowestAsk = avgPrice;
        }

        if (lowestAsk == null) {
          final variants = product['variants'] as List?;
          if (variants != null) {
            for (var variant in variants) {
              final ask = variant['lowest_ask'];
              if (ask != null) {
                final askPrice = double.tryParse(ask.toString());
                if (askPrice != null && askPrice > 0) {
                  if (lowestAsk == null || askPrice < lowestAsk)
                    lowestAsk = askPrice;
                }
              }
            }
          }
        }

        if (lowestAsk != null && lowestAsk > 0) {
          debugPrint(
            '[KicksDB StockX] Price: \$$lowestAsk (${stopwatch.elapsedMilliseconds}ms)',
          );
          setState(() {
            _stockXPrice = lowestAsk;
            _stockXSlug = product['slug'] as String?;
            _isLoadingStockXPrice = false;
          });
          return;
        }
      }
      debugPrint(
        '[KicksDB StockX] No price found (${stopwatch.elapsedMilliseconds}ms)',
      );
    } catch (e) {
      debugPrint(
        '[KicksDB StockX] Error: $e (${stopwatch.elapsedMilliseconds}ms)',
      );
    }
  }

  Future<void> _fetchKicksDbGoatPrice() async {
    if (_goatPrice != null) return;
    // KicksDB pricing only queries by SKU — never by title
    final query = _skuQuery;
    if (query == null) {
      debugPrint('[KicksDB GOAT] Skipped — no SKU available');
      return;
    }
    final stopwatch = Stopwatch()..start();
    debugPrint('[KicksDB GOAT] Starting lookup for SKU "$query"');
    try {
      final uri = Uri.parse(
        'https://api.kicks.dev/v3/goat/products'
        '?query=${Uri.encodeComponent(query)}&limit=5'
        '&display[prices]=true&display[variants]=true',
      );
      debugPrint('[KicksDB GOAT] Request: $uri');

      final response = await http
          .get(
            uri,
            headers: {'Authorization': 'Bearer ${ApiKeys.kicksDbApiKey}'},
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[KicksDB GOAT] Status: ${response.statusCode}');

      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body);
      final List<Map<String, dynamic>> candidates = [];
      if (body is Map<String, dynamic>) {
        if (body.containsKey('data') && body['data'] is List) {
          for (var item in body['data']) {
            candidates.add(item as Map<String, dynamic>);
          }
        } else if (body.containsKey('name') || body.containsKey('slug')) {
          candidates.add(body);
        }
      } else if (body is List) {
        for (var item in body) {
          candidates.add(item as Map<String, dynamic>);
        }
      }

      for (final product in candidates) {
        if (!_isProductMatch(product)) {
          debugPrint(
            '[KicksDB GOAT] Skip mismatch: "${product['name'] ?? product['title']}"',
          );
          continue;
        }

        double? lowestAsk;
        final minPrice = double.tryParse(
          (product['min_price'] ?? '').toString(),
        );
        if (minPrice != null && minPrice > 0) lowestAsk = minPrice;

        if (lowestAsk == null) {
          final avgPrice = double.tryParse(
            (product['avg_price'] ?? '').toString(),
          );
          if (avgPrice != null && avgPrice > 0) lowestAsk = avgPrice;
        }

        if (lowestAsk == null) {
          final variants = product['variants'] as List?;
          if (variants != null) {
            for (var variant in variants) {
              final ask = variant['lowest_ask'];
              if (ask != null) {
                final askPrice = double.tryParse(ask.toString());
                if (askPrice != null && askPrice > 0) {
                  if (lowestAsk == null || askPrice < lowestAsk)
                    lowestAsk = askPrice;
                }
              }
            }
          }
        }

        if (lowestAsk != null && lowestAsk > 0) {
          debugPrint(
            '[KicksDB GOAT] Price: \$$lowestAsk (${stopwatch.elapsedMilliseconds}ms)',
          );
          setState(() {
            _goatPrice = lowestAsk;
            _goatSlug = (product['slug'] ?? product['id'] ?? product['name'])
                ?.toString();
            _isLoadingGoatPrice = false;
          });
          return;
        }
      }
      debugPrint(
        '[KicksDB GOAT] No price found (${stopwatch.elapsedMilliseconds}ms)',
      );
    } catch (e) {
      debugPrint(
        '[KicksDB GOAT] Error: $e (${stopwatch.elapsedMilliseconds}ms)',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Similar results & data persistence
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _fetchKicksDbFuzzyCandidates() async {
    final title = _productInfo?['title'] as String?;
    final query =
        (title != null && title != 'Product Not Found' && title.isNotEmpty)
        ? title
        : widget.scanData.displayName;
    if (query.isEmpty) return;

    debugPrint('[KicksDB Fuzzy] Starting fuzzy search for: "$query"');
    if (!mounted) return;
    setState(() {
      _fuzzySearchInitiated = true;
      _isLoadingCandidates = true;
    });

    try {
      final fuzzyUri = Uri.parse(
        'https://api.kicks.dev/v3/stockx/products'
        '?query=${Uri.encodeComponent(query)}&limit=10'
        '&display[prices]=true&display[variants]=false',
      );
      debugPrint('[KicksDB Fuzzy] Request: $fuzzyUri');
      final response = await http
          .get(
            fuzzyUri,
            headers: {'Authorization': 'Bearer ${ApiKeys.kicksDbApiKey}'},
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('[KicksDB Fuzzy] Status: ${response.statusCode}');
      debugPrint(
        '[KicksDB Fuzzy] Body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        debugPrint('[KicksDB Fuzzy] Failed with ${response.statusCode}');
        setState(() {
          _isLoadingCandidates = false;
          _candidatesSearchDone = true;
        });
        return;
      }

      final body = jsonDecode(response.body);
      List<dynamic> items = [];
      if (body is Map<String, dynamic> &&
          body.containsKey('data') &&
          body['data'] is List) {
        items = body['data'];
      } else if (body is List) {
        items = body;
      }

      debugPrint('[KicksDB Fuzzy] Got ${items.length} raw results');

      final candidates = <Map<String, dynamic>>[];
      for (final item in items) {
        final product = item as Map<String, dynamic>;
        final name = (product['title'] ?? product['name'] ?? '').toString();
        final brand = (product['brand'] ?? '').toString();

        if (_isRetailerLabel(brand)) continue;
        if (!_looksLikeFootwear(product)) {
          debugPrint('[KicksDB Fuzzy] Skip non-footwear: "$name"');
          continue;
        }

        final image = (product['image'] ?? product['thumbnail'] ?? '')
            .toString();
        final retailPrice = product['retail_price'];
        final retailPriceNum = retailPrice != null
            ? double.tryParse(retailPrice.toString())
            : null;

        final sku = (product['style_id'] ?? '').toString();
        final slug = (product['slug'] ?? '').toString();

        candidates.add({
          'title': name,
          'brand': brand,
          'image': image,
          'retailPrice': retailPriceNum,
          'estimatedMarketValue': null,
          'sku': sku,
          'stockXSlug': slug.isNotEmpty ? slug : null,
          'goatSlug': null,
        });
        debugPrint(
          '[KicksDB Fuzzy] Candidate: "$name" sku="$sku" retail=\$${retailPriceNum ?? "N/A"}',
        );
      }

      debugPrint(
        '[KicksDB Fuzzy] ${candidates.length} footwear candidates after filtering',
      );
      if (!mounted) return;
      setState(() {
        _similarCandidates = candidates;
        _isLoadingCandidates = false;
        _candidatesSearchDone = true;
      });
    } catch (e) {
      debugPrint('[KicksDB Fuzzy] Error: $e');
      if (mounted)
        setState(() {
          _isLoadingCandidates = false;
          _candidatesSearchDone = true;
        });
    }
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

  Future<void> _saveCandidatesToDatabase() async {
    if (_similarCandidates.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.scanId.isEmpty) return;

    try {
      final candidateList = _similarCandidates
          .map(
            (c) => {
              'title': c['title'],
              'brand': c['brand'],
              'image': c['image'],
              'retailPrice': c['retailPrice']?.toString(),
              'estimatedMarketValue': c['estimatedMarketValue']?.toString(),
              'sku': c['sku'],
              'stockXSlug': c['stockXSlug'],
              'goatSlug': c['goatSlug'],
            },
          )
          .toList();

      await _database
          .child('scans')
          .child(user.uid)
          .child(widget.scanId)
          .update({'sneakerDbCandidates': candidateList});
      debugPrint(
        '[KicksDB Fuzzy] Saved ${candidateList.length} candidates to DB',
      );
    } catch (e) {
      debugPrint('[KicksDB Fuzzy] Error saving candidates: $e');
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
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF646CFF)),
              )
            : _error != null
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
                    if (_productInfo?['brand'] != null &&
                        _productInfo!['brand'].toString().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF646CFF).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _productInfo!['brand'],
                          style: GoogleFonts.inter(
                            color: const Color(0xFF646CFF),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // 4. eBay Prices Section
                    EbayPricesSection(
                      isLoading: _isLoadingEbayPrices,
                      lowestPrice: _ebayLowestPrice,
                      averagePrice: _ebayAveragePrice,
                      listingCount: _ebayListingCount,
                      error: _ebayError,
                    ),

                    // 5. Info Cards
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

                    // 9. Marketplace buttons — MOVED UP
                    if (_ebayAveragePrice != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openEbaySearch,
                          icon: const Icon(Icons.shopping_bag),
                          label: const Text('Open on eBay'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0064D2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_stockXPrice != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openStockXSearch,
                          icon: const Icon(Icons.store),
                          label: const Text('Open on StockX'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF006340),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_goatPrice != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openGoatSearch,
                          icon: const Icon(Icons.storefront),
                          label: const Text('Open on GOAT'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7B61FF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_ebayAveragePrice != null ||
                        _stockXPrice != null ||
                        _goatPrice != null)
                      const SizedBox(height: 12),

                    // 10. Similar Results — only shown when fuzzy search initiated
                    if (_fuzzySearchInitiated)
                      SimilarResultsSection(
                        candidates: _similarCandidates,
                        isLoading: _isLoadingCandidates,
                        searchDone: _candidatesSearchDone,
                      ),
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
