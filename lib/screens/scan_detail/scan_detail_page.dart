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
  String? _ebayItemUrl;
  String? _ebayImageUrl;
  String? _ebayTitle;

  /// Product title resolved from whichever API returns first.
  /// KicksDB is priority; eBay is the fallback.
  String? _resolvedTitle;

  /// Brand resolved from the first KicksDB call that returns one.
  /// OCR-extracted brand (widget.scanData.brand) is the fallback.
  String? _resolvedBrand;

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

  /// True until we confirm whether any platform returned a price.
  /// Keeps the detail UI hidden while checks run (new scans only).
  bool _checkingResults = true;

  /// Mutable scan ID — empty for new scans until results are confirmed and
  /// the record is persisted. Non-empty for historical scans reopened from history.
  String _resolvedScanId = '';

  /// The primary identifier used for DB keys and cache lookups.
  String get _primaryCode => widget.scanData.sku ?? '';

  @override
  void initState() {
    super.initState();
    _resolvedScanId = widget.scanId;
    // Historical scans already have confirmed results — skip the checking phase.
    if (_resolvedScanId.isNotEmpty) _checkingResults = false;
    _loadProductInfo();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Product lookup methods
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadProductInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (_resolvedScanId.isNotEmpty) {
          final scanSnapshot = await _database
              .child('scans')
              .child(user.uid)
              .child(_resolvedScanId)
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
            final savedEbayPrice = double.tryParse(
              (scanDataMap['ebayPrice'] as String?) ?? '',
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
              if (savedEbayPrice != null) {
                _ebayAveragePrice = savedEbayPrice;
                _isLoadingEbayPrices = false;
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

      // eBay title fallback — only applies when KicksDB didn't find a title.
      if (_resolvedTitle == null && _ebayTitle != null && _ebayTitle!.isNotEmpty) {
        setState(() => _resolvedTitle = _ebayTitle);
      }

      // If KicksDB returned no image but eBay did, use eBay's image as fallback.
      if (_ebayImageUrl != null &&
          _ebayImageUrl!.isNotEmpty &&
          (_productInfo?['images'] as List? ?? []).isEmpty) {
        setState(() {
          _productInfo = {
            ..._productInfo!,
            'images': [_ebayImageUrl!],
          };
        });
      }

      // For new scans: if no platform found any price, delete the scan and
      // navigate back rather than showing an empty detail page.
      final hasAnyPrice =
          _ebayAveragePrice != null ||
          _stockXPrice != null ||
          _goatPrice != null ||
          (_stockXColorways != null && _stockXColorways!.isNotEmpty) ||
          (_goatColorways != null && _goatColorways!.isNotEmpty);

      if (_checkingResults && !hasAnyPrice) {
        if (mounted) Navigator.of(context).pop('noResults');
        return;
      }

      // New scan — create the DB record now that we have at least one price.
      if (_resolvedScanId.isEmpty) {
        await _createScanInDb();
      }

      setState(() => _checkingResults = false);

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
      List<Map<String, dynamic>> unifiedItems = [];

      if (sku != null && sku.isNotEmpty) {
        final unifiedUri = Uri(
          scheme: 'https',
          host: 'api.kicks.dev',
          pathSegments: ['v3', 'unified', 'products', sku],
          queryParameters: {'similarity': '0.85'},
        );
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
      } else if (gtin != null && gtin.isNotEmpty) {
        debugPrint('═══ STEP 1: KicksDB Unified (GTIN) ═══');
        // GTINs from a UPC-A barcode arrive as 13 digits with a leading 0
        // (normalizeGtin pads 12-digit UPC-A). Try the stripped 12-digit form
        // first; fall back to the original 13-digit form on any failure.
        final hasLeadingZero = gtin.length == 13 && gtin.startsWith('0');
        final primaryGtin = hasLeadingZero ? gtin.substring(1) : gtin;

        unifiedItems = await _fetchUnifiedGtinItems(primaryGtin);

        if (unifiedItems.isEmpty && hasLeadingZero) {
          debugPrint(
            '[Unified] 12-digit GTIN yielded no results, retrying with 13-digit: $gtin',
          );
          unifiedItems = await _fetchUnifiedGtinItems(gtin);
        }
      }

      // The SKU to match against
      final matchSku = sku ?? '';
      final size = widget.scanData.size;

      // Pre-compute the best image across all unified items, preferring StockX
      // in both paths. StockX CDN (images.stockx.com) loads reliably in Flutter;
      // GOAT CDN (image.goat.com) can fail even for valid URLs.
      // SKU items use `shop_name`; GTIN items use `source`.
      final String? bestItemImage = unifiedItems.isNotEmpty
          ? (sku != null && sku.isNotEmpty
              ? _pickBestUnifiedImage(unifiedItems)
              : _pickBestGtinImage(unifiedItems))
          : null;

      // Extract identity from first matching result + StockX/GOAT prices
      for (final item in unifiedItems) {
        // SKU unified items use `shop_name`; GTIN items use `source`.
        final shopName =
            (item['shop_name'] ?? item['source'] ?? '').toString().toLowerCase();
        final apiSku = (item['sku'] ?? '').toString();

        // Identity: use the first result that has a title
        if (productInfo == null) {
          final title = (item['title'] ?? item['name'])?.toString();
          if (title != null && title.isNotEmpty) {
            if (_resolvedTitle == null) setState(() => _resolvedTitle = title);
            final apiBrand = item['brand']?.toString();
            if (_resolvedBrand == null && apiBrand != null && apiBrand.isNotEmpty) {
              setState(() => _resolvedBrand = apiBrand);
            }
            productInfo = {
              'title': title,
              'brand': item['brand'] ?? '',
              'sku': apiSku,
              'styleCode': apiSku,
              'retailPrice': () {
                final raw = item['retailPrice']?.toString() ??
                    item['retail_price']?.toString();
                if (raw == null) return null;
                final parsed = double.tryParse(raw);
                return (parsed != null && parsed > 0) ? raw : null;
              }(),
              'images': bestItemImage != null
                  ? [bestItemImage]
                  : item['images'] is List
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

        // SKU unified items have `prices` as a size→price map.
        // GTIN items have `price` as a direct number.
        final pricesRaw = item['prices'];
        final double? price;
        if (pricesRaw is Map<String, dynamic>) {
          price = _extractPriceFromMap(pricesRaw, size);
        } else {
          price = double.tryParse((item['price'] ?? '').toString());
        }
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

      // If identity was set but the first item had no images, scan all items
      // for a usable image URL (a later item — e.g. GOAT — may have one).
      if (productInfo != null &&
          (productInfo['images'] as List?)?.isEmpty != false) {
        for (final item in unifiedItems) {
          final imgs = item['images'];
          if (imgs is List && imgs.isNotEmpty) {
            productInfo['images'] = imgs;
            break;
          }
          final img = item['image'];
          if (img != null) {
            productInfo['images'] = [img];
            break;
          }
        }
      }

      // ── Step 2: Colorway fallback (Nike/Jordan, New Balance, Asics, Puma) ─
      final brand = _resolvedBrand ?? productInfo?['brand'] as String? ?? widget.scanData.brand ?? '';
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
      } else if (isNewBalance(brand) && sku != null && sku.isNotEmpty) {
        final parsed = parseNewBalanceSku(sku);
        if (parsed != null) {
          final (modelBlock, _) = parsed;

          if (_stockXPrice == null) {
            debugPrint('═══ STEP 2: StockX NB colorway fallback ═══');
            final variants = await _fetchColorwayVariants(
              'stockx', sku, modelBlock, stopwatch, brandKey: 'new_balance',
            );
            if (variants.isNotEmpty) {
              _stockXColorways = variants;
              _stockXPrice = variants.first.price;
              _stockXSlug = variants.first.slug;
            }
          }

          if (_goatPrice == null) {
            debugPrint('═══ STEP 2: GOAT NB colorway fallback ═══');
            final variants = await _fetchColorwayVariants(
              'goat', sku, modelBlock, stopwatch, brandKey: 'new_balance',
            );
            if (variants.isNotEmpty) {
              _goatColorways = variants;
              _goatPrice = variants.first.price;
              _goatSlug = variants.first.slug;
            }
          }
        }
      } else if (isAsics(brand) && sku != null && sku.isNotEmpty) {
        final parsed = parseAsicsSku(sku);
        if (parsed != null) {
          final (modelBlock, _) = parsed;

          if (_stockXPrice == null) {
            debugPrint('═══ STEP 2: StockX Asics colorway fallback ═══');
            final variants = await _fetchColorwayVariants(
              'stockx', sku, modelBlock, stopwatch, brandKey: 'asics',
            );
            if (variants.isNotEmpty) {
              _stockXColorways = variants;
              _stockXPrice = variants.first.price;
              _stockXSlug = variants.first.slug;
            }
          }

          if (_goatPrice == null) {
            debugPrint('═══ STEP 2: GOAT Asics colorway fallback ═══');
            final variants = await _fetchColorwayVariants(
              'goat', sku, modelBlock, stopwatch, brandKey: 'asics',
            );
            if (variants.isNotEmpty) {
              _goatColorways = variants;
              _goatPrice = variants.first.price;
              _goatSlug = variants.first.slug;
            }
          }
        }
      } else if (isPuma(brand) && sku != null && sku.isNotEmpty) {
        final parsed = parsePumaSku(sku);
        if (parsed != null) {
          final (modelBlock, _) = parsed;

          if (_stockXPrice == null) {
            debugPrint('═══ STEP 2: StockX Puma colorway fallback ═══');
            final variants = await _fetchColorwayVariants(
              'stockx', sku, modelBlock, stopwatch, brandKey: 'puma',
            );
            if (variants.isNotEmpty) {
              _stockXColorways = variants;
              _stockXPrice = variants.first.price;
              _stockXSlug = variants.first.slug;
            }
          }

          if (_goatPrice == null) {
            debugPrint('═══ STEP 2: GOAT Puma colorway fallback ═══');
            final variants = await _fetchColorwayVariants(
              'goat', sku, modelBlock, stopwatch, brandKey: 'puma',
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
      if (user != null && _resolvedScanId.isNotEmpty) {
        await _database
            .child('scans')
            .child(user.uid)
            .child(_resolvedScanId)
            .update({
              'productTitle': _resolvedTitle ?? title?.toString(),
              'productImage': image != null && image.toString().isNotEmpty
                  ? image.toString()
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
  // GTIN helpers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Normalize an image URL — protocol-relative URLs (//cdn.example.com/...)
  /// are valid in browsers but not in Flutter's Image.network, so prepend https:.
  String? _normalizeImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('//')) return 'https:$url';
    return url;
  }

  /// Pick the best image URL from KicksDB unified SKU items.
  /// Prefers shop_name == 'stockx' (reliable CDN); falls back to any item with an image.
  String? _pickBestUnifiedImage(List<Map<String, dynamic>> items) {
    for (final item in items) {
      final shopName = (item['shop_name'] ?? '').toString().toLowerCase();
      if (shopName == 'stockx') {
        final imgs = item['images'];
        if (imgs is List && imgs.isNotEmpty) {
          final url = _normalizeImageUrl(imgs[0]?.toString());
          if (url != null) return url;
        }
      }
    }
    for (final item in items) {
      final imgs = item['images'];
      if (imgs is List && imgs.isNotEmpty) {
        final url = _normalizeImageUrl(imgs[0]?.toString());
        if (url != null) return url;
      }
      final url = _normalizeImageUrl(item['image']?.toString());
      if (url != null) return url;
    }
    return null;
  }

  /// Pick the best image URL from KicksDB GTIN items.
  /// Prefers the StockX source; falls back to the first item that has any image.
  String? _pickBestGtinImage(List<Map<String, dynamic>> items) {
    for (final item in items) {
      final source = (item['source'] ?? '').toString().toLowerCase();
      if (source == 'stockx') {
        final url = _normalizeImageUrl(item['image']?.toString());
        if (url != null) return url;
      }
    }
    for (final item in items) {
      final url = _normalizeImageUrl(item['image']?.toString());
      if (url != null) return url;
    }
    return null;
  }

  /// Fetch KicksDB unified items for a single GTIN value.
  /// Returns an empty list on non-200 status or an empty/unparseable response.
  Future<List<Map<String, dynamic>>> _fetchUnifiedGtinItems(
    String gtinValue,
  ) async {
    final uri = Uri(
      scheme: 'https',
      host: 'api.kicks.dev',
      path: '/v3/unified/gtin',
      queryParameters: {'identifier': gtinValue},
    );
    debugPrint('[Unified] GTIN request: $uri');
    try {
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer ${ApiKeys.kicksDbApiKey}'})
          .timeout(const Duration(seconds: 15));
      debugPrint('[Unified] GTIN status: ${response.statusCode}');
      if (response.statusCode != 200) return [];
      debugPrint(
        '[Unified] GTIN body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
      );
      final body = jsonDecode(response.body);
      final items = <Map<String, dynamic>>[];
      if (body is Map<String, dynamic>) {
        if (body.containsKey('data') && body['data'] is List) {
          for (var item in body['data']) {
            items.add(item as Map<String, dynamic>);
          }
        } else if (body.containsKey('shop_name') || body.containsKey('title')) {
          items.add(body);
        }
      } else if (body is List) {
        for (var item in body) {
          items.add(item as Map<String, dynamic>);
        }
      }
      return items;
    } catch (e) {
      debugPrint('[Unified] GTIN error: $e');
      return [];
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
    if (_ebayItemUrl != null && _ebayItemUrl!.isNotEmpty) {
      await launchUrl(Uri.parse(_ebayItemUrl!), mode: LaunchMode.platformDefault);
      return;
    }
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

      double? price;

      if (sku != null && sku.isNotEmpty) {
        final ebayHost = baseUrl.replaceFirst('https://', '');
        final requestUri = Uri.https(
          ebayHost,
          '/buy/browse/v1/item_summary/search',
          {'q': sku},
        );
        debugPrint('[eBay] Request: $requestUri');

        final response = await http
            .get(
              requestUri,
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
          final item = _bestFootwearItem(items, ocrText: widget.scanData.ocrText);
          if (item != null) {
            final priceData = item['price'];
            if (priceData != null && priceData['value'] != null) {
              price = double.tryParse(priceData['value'].toString());
            }
            final webUrl = item['itemWebUrl'] as String?;
            if (webUrl != null && webUrl.isNotEmpty) _ebayItemUrl = webUrl;
            final imageObj = item['image'] as Map<String, dynamic>?;
            final imageUrl = imageObj?['imageUrl'] as String?;
            if (imageUrl != null && imageUrl.isNotEmpty) _ebayImageUrl = imageUrl;
            final titleStr = item['title'] as String?;
            if (titleStr != null && titleStr.isNotEmpty) _ebayTitle = titleStr;
          }
        }
      } else if (gtin != null && gtin.isNotEmpty) {
        // GTINs from UPC-A barcodes arrive as 13 digits with a leading 0.
        // Try the stripped 12-digit form first; retry with the original on failure.
        final hasLeadingZero = gtin.length == 13 && gtin.startsWith('0');
        final primaryGtin = hasLeadingZero ? gtin.substring(1) : gtin;

        final (p1, url1, img1, title1) = await _ebayGtinLookup(primaryGtin, baseUrl, token);
        price = p1;
        if (url1 != null) _ebayItemUrl = url1;
        if (img1 != null) _ebayImageUrl = img1;
        if (title1 != null) _ebayTitle = title1;

        if (price == null && hasLeadingZero) {
          debugPrint(
            '[eBay] 12-digit GTIN got no results, retrying with 13-digit: $gtin',
          );
          final (p2, url2, img2, title2) = await _ebayGtinLookup(gtin, baseUrl, token);
          price = p2;
          if (url2 != null) _ebayItemUrl = url2;
          if (img2 != null) _ebayImageUrl = img2;
          if (title2 != null) _ebayTitle = title2;
        }
      } else if (widget.scanData.titleSearch != null &&
          widget.scanData.titleSearch!.isNotEmpty) {
        // Title-search mode: user entered a free-text title from the manual dialog.
        final titleQuery = widget.scanData.titleSearch!;
        final ebayHost = baseUrl.replaceFirst('https://', '');
        final requestUri = Uri.https(
          ebayHost,
          '/buy/browse/v1/item_summary/search',
          {'q': titleQuery},
        );
        debugPrint('[eBay] Title search request: $requestUri');

        final response = await http
            .get(
              requestUri,
              headers: {
                'Authorization': 'Bearer $token',
                'X-EBAY-C-MARKETPLACE-ID': 'EBAY_US',
                'Content-Type': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 15));

        debugPrint('[eBay] Title search status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final items = data['itemSummaries'] as List? ?? [];
          // Score against the entered title so the closest match wins.
          final item = _bestFootwearItem(items, ocrText: titleQuery);
          if (item != null) {
            final priceData = item['price'];
            if (priceData != null && priceData['value'] != null) {
              price = double.tryParse(priceData['value'].toString());
            }
            final webUrl = item['itemWebUrl'] as String?;
            if (webUrl != null && webUrl.isNotEmpty) _ebayItemUrl = webUrl;
            final imageObj = item['image'] as Map<String, dynamic>?;
            final imageUrl = imageObj?['imageUrl'] as String?;
            if (imageUrl != null && imageUrl.isNotEmpty) _ebayImageUrl = imageUrl;
            final titleStr = item['title'] as String?;
            if (titleStr != null && titleStr.isNotEmpty) _ebayTitle = titleStr;
          }
        }
      } else {
        debugPrint('[eBay] No SKU, GTIN, or title available, skipping');
        setState(() => _isLoadingEbayPrices = false);
        return;
      }

      if (price != null && price > 0) {
        debugPrint(
          '[eBay] price=\$${price.toStringAsFixed(2)} '
          '(${stopwatch.elapsedMilliseconds}ms)',
        );
        setState(() {
          _ebayAveragePrice = price;
          _isLoadingEbayPrices = false;
        });
      } else {
        debugPrint(
          '[eBay] No listings found (${stopwatch.elapsedMilliseconds}ms)',
        );
        setState(() => _isLoadingEbayPrices = false);
      }
    } catch (e) {
      debugPrint('[eBay] Error: $e (${stopwatch.elapsedMilliseconds}ms)');
      setState(() => _isLoadingEbayPrices = false);
    }
  }

  /// Make a single eBay GTIN search.
  /// Returns (price, itemWebUrl, imageUrl, title) — any value may be null if not found.
  Future<(double?, String?, String?, String?)> _ebayGtinLookup(
    String gtinValue,
    String baseUrl,
    String token,
  ) async {
    final ebayHost = baseUrl.replaceFirst('https://', '');
    final requestUri = Uri.https(
      ebayHost,
      '/buy/browse/v1/item_summary/search',
      {'gtin': gtinValue},
    );
    debugPrint('[eBay] GTIN request: $requestUri');
    try {
      final response = await http
          .get(
            requestUri,
            headers: {
              'Authorization': 'Bearer $token',
              'X-EBAY-C-MARKETPLACE-ID': 'EBAY_US',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('[eBay] GTIN status: ${response.statusCode}');
      debugPrint(
        '[eBay] GTIN body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
      );
      if (response.statusCode != 200) return (null, null, null, null);
      final data = jsonDecode(response.body);
      final items = data['itemSummaries'] as List? ?? [];
      final item = _bestFootwearItem(items, ocrText: widget.scanData.ocrText);
      if (item == null) return (null, null, null, null);
      final priceData = item['price'];
      if (priceData == null || priceData['value'] == null) return (null, null, null, null);
      final price = double.tryParse(priceData['value'].toString());
      final url = item['itemWebUrl'] as String?;
      final imageObj = item['image'] as Map<String, dynamic>?;
      final imageUrl = imageObj?['imageUrl'] as String?;
      final titleStr = item['title'] as String?;
      return (
        price,
        url?.isNotEmpty == true ? url : null,
        imageUrl?.isNotEmpty == true ? imageUrl : null,
        titleStr?.isNotEmpty == true ? titleStr : null,
      );
    } catch (e) {
      debugPrint('[eBay] GTIN error: $e');
      return (null, null, null, null);
    }
  }

  static const _ocrStopwords = {
    'a', 'an', 'the', 'and', 'or', 'for', 'of', 'in', 'on', 'at', 'to',
    'is', 'it', 'as', 'by', 'be', 'we', 'us', 'my', 'no', 'so', 'do',
    'if', 'up', 'he', 'she', 'his', 'her', 'its', 'our', 'are', 'was',
    'with', 'from', 'this', 'that', 'have', 'has', 'had', 'not', 'but',
  };

  /// Returns the item from [items] whose title has the most word overlap with
  /// [ocrText]. Falls back to the first item on ties or when ocrText is null.
  /// Returns null if [items] is empty.
  static Map<String, dynamic>? _bestFootwearItem(List items, {String? ocrText}) {
    if (items.isEmpty) return null;
    if (items.length == 1 || ocrText == null || ocrText.isEmpty) {
      return items.first as Map<String, dynamic>;
    }

    // Build meaningful OCR word set (lowercase, no stopwords, 2+ chars).
    final ocrWords = ocrText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && !_ocrStopwords.contains(w))
        .toSet();

    if (ocrWords.isEmpty) return items.first as Map<String, dynamic>;

    // Score each item by word overlap with OCR text; first item wins ties.
    int bestScore = -1;
    Map<String, dynamic> bestItem = items.first as Map<String, dynamic>;
    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      final title = (item['title'] as String? ?? '').toLowerCase();
      final titleWords = title.split(RegExp(r'\s+')).toSet();
      final score = ocrWords.where((w) => titleWords.contains(w)).length;
      if (score > bestScore) {
        bestScore = score;
        bestItem = item;
      }
    }
    return bestItem;
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
  /// [brandKey] is either 'nike' (default) or 'new_balance'.
  Future<List<ColorwayVariant>> _fetchColorwayVariants(
    String platform,
    String sku,
    String modelBlock,
    Stopwatch stopwatch, {
    String brandKey = 'nike',
  }) async {
    final uri = Uri(
      scheme: 'https',
      host: 'api.kicks.dev',
      path: '/v3/$platform/products',
      queryParameters: {
        'query': sku,
        'limit': '5',
        'display[prices]': 'true',
        'display[variants]': 'true',
      },
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

        // Parse the API SKU using the appropriate brand parser.
        String apiModel;
        String apiColor;
        if (brandKey == 'new_balance') {
          final parsed = parseNewBalanceSku(apiSku);
          if (parsed == null) continue;
          (apiModel, apiColor) = parsed;
          // NB colorway must start with a letter.
          if (apiColor.isEmpty || !RegExp(r'^[A-Z]').hasMatch(apiColor.toUpperCase())) continue;
        } else if (brandKey == 'asics') {
          final parsed = parseAsicsSku(apiSku);
          if (parsed == null) continue;
          (apiModel, apiColor) = parsed;
        } else if (brandKey == 'puma') {
          final parsed = parsePumaSku(apiSku);
          if (parsed == null) continue;
          (apiModel, apiColor) = parsed;
        } else {
          final parsed = parseNikeSku(apiSku);
          if (parsed == null) continue;
          (apiModel, apiColor) = parsed;
        }

        // Model block must match; colorway can differ.
        if (apiModel.toUpperCase() != modelBlock.toUpperCase()) continue;

        // Extract price (old format: min_price → avg_price → variants lowest_ask)
        final price = _extractOldFormatPrice(product);
        if (price == null || price <= 0) continue;

        final (String family, Color color) = brandKey == 'new_balance'
            ? nbColorFamily(apiColor)
            : brandKey == 'asics'
                ? asicsColorFamily(apiColor)
                : brandKey == 'puma'
                    ? pumaColorFamily(apiColor)
                    : nikeColorFamily(apiColor);

        // Deduplicate: Nike/NB by color family; Asics/Puma by color code
        // (generic-family brands would collapse all variants into one otherwise).
        final dedupeKey =
            (brandKey == 'asics' || brandKey == 'puma') ? apiColor : family;
        if (seenFamilies.contains(dedupeKey)) continue;
        seenFamilies.add(dedupeKey);

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
    if (user == null || _resolvedScanId.isEmpty) return;

    try {
      final updateData = <String, dynamic>{};

      // Save the resolved product title from whichever API found it first.
      if (_resolvedTitle != null && _resolvedTitle!.isNotEmpty) {
        updateData['productTitle'] = _resolvedTitle;
      }

      // Save the resolved brand (KicksDB-verified, or OCR fallback).
      final resolvedBrand = _resolvedBrand ?? widget.scanData.brand;
      if (resolvedBrand != null && resolvedBrand.isNotEmpty) {
        updateData['brand'] = resolvedBrand;
      }

      // Save image regardless of which source found it (KicksDB or eBay fallback).
      // This ensures history always shows the image if one was found.
      final images = _productInfo?['images'] as List?;
      if (images != null && images.isNotEmpty) {
        final imageUrl = images[0]?.toString();
        if (imageUrl != null && imageUrl.isNotEmpty) {
          updateData['productImage'] = imageUrl;
        }
      }

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
            .child(_resolvedScanId)
            .update(updateData);
      }
    } catch (e) {
      debugPrint('Error saving prices: $e');
    }
  }

  void _setPricingStatus(String status) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _resolvedScanId.isEmpty) return;
    _database.child('scans').child(user.uid).child(_resolvedScanId).update({
      'pricingStatus': status,
    });
  }

  /// Creates the Firebase scan record for a new scan after prices are confirmed.
  /// Only called when [_resolvedScanId] is empty (i.e. a brand-new scan).
  Future<void> _createScanInDb() async {
    if (_resolvedScanId.isNotEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final scanData = widget.scanData;
      final scanRef = _database.child('scans').child(user.uid).push();
      final resolvedBrand = _resolvedBrand ?? scanData.brand;
      await scanRef.set({
        ...scanData.toFirebase(),
        if (resolvedBrand != null && resolvedBrand.isNotEmpty) 'brand': resolvedBrand,
        'code': scanData.sku ?? scanData.displayName,
        'format': 'STYLE_CODE',
        'timestamp': ServerValue.timestamp,
        'productTitle': (_resolvedTitle?.isNotEmpty == true) ? _resolvedTitle : null,
        'productImage': null,
        'retailPrice': null,
        'ebayPrice': null,
        'stockxPrice': null,
        'goatPrice': null,
        'pricingStatus': 'complete',
      });
      _resolvedScanId = scanRef.key ?? '';
      debugPrint('[createScan] Scan created: $_resolvedScanId');
    } catch (e) {
      debugPrint('[createScan] Error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // Show a spinner while we wait for the first price result on new scans.
    if (_checkingResults) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF646CFF)),
        ),
      );
    }

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
                      _resolvedTitle ??
                          (widget.scanData.displayName.isNotEmpty
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
                      final badgeBrand = _resolvedBrand ?? widget.scanData.brand;
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

    final brand = _resolvedBrand ?? widget.scanData.brand;
    if (brand != null && brand.isNotEmpty) {
      cards.add(InfoCard(label: 'Brand', value: brand, icon: Icons.business));
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
    } else if (widget.scanData.gtin != null) {
      cards.add(
        InfoCard(
          label: 'GTIN',
          value: widget.scanData.gtin!,
          icon: Icons.barcode_reader,
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
