import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/nike_colorway_utils.dart';
import '../../../theme/app_theme.dart';
import 'recent_sales_row.dart';

class MarketPriceSection extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final double? price;
  final double? profit;
  final double? profitPercent;
  final bool isLoading;
  final double? retailPrice;
  final VoidCallback? onOpenMarketplace;
  final bool productFound;
  final List<ColorwayVariant>? colorways;

  /// eBay: "Seller Fee" row. Rate is a decimal (e.g. 0.08 for 8%).
  final double? sellerFeeRate;

  /// StockX: "Transaction Fee" row. Rate is a decimal (e.g. 0.08 for 8%).
  final double? transactionFeeRate;

  /// StockX: "Payment Processing" row. Rate is a decimal (e.g. 0.03 for 3%).
  final double? paymentProcessingFeeRate;

  /// GOAT: flat dollar "Seller Fee" row (e.g. 5.0 for $5).
  final double? sellerFlatFee;

  /// GOAT: "Commission" row. Rate is a decimal (e.g. 0.095 for 9.5%).
  final double? commissionFeeRate;

  /// Scanned shoe size (US, e.g. "10", "10.5") — appended to GOAT URLs.
  final String? scannedSize;

  /// True when the displayed price is the lowest available ask (size not found),
  /// rather than the exact price for the scanned size.
  final bool isLowestAsk;

  /// Full size→price map from the unified API. When provided, a size dropdown
  /// is shown (StockX/GOAT only, not for colorway variants or GTIN results).
  final Map<String, double>? sizeMap;

  /// The currently selected size (managed by parent). Null means "Select Size".
  final String? selectedSize;

  /// Called when the user picks a size from the dropdown.
  final ValueChanged<String?>? onSizeSelected;

  /// 'stockx', 'goat' or 'ebay' to show recent sales; null hides them.
  final String? salesPlatform;

  /// KicksDB product id for the exact-SKU match (eBay: the CompsAPI search
  /// text). Colorway variants use their own id instead. When neither exists,
  /// no sales call is made.
  final String? salesProductId;

  /// Shown at the top of the Recent Sales page.
  final String? productTitle;
  final String? productImage;

  const MarketPriceSection({
    super.key,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.price,
    required this.profit,
    required this.profitPercent,
    required this.isLoading,
    required this.retailPrice,
    this.onOpenMarketplace,
    this.productFound = true,
    this.colorways,
    this.sellerFeeRate,
    this.transactionFeeRate,
    this.paymentProcessingFeeRate,
    this.sellerFlatFee,
    this.commissionFeeRate,
    this.scannedSize,
    this.isLowestAsk = false,
    this.sizeMap,
    this.selectedSize,
    this.onSizeSelected,
    this.salesPlatform,
    this.salesProductId,
    this.productTitle,
    this.productImage,
  });

  @override
  State<MarketPriceSection> createState() => _MarketPriceSectionState();
}

class _MarketPriceSectionState extends State<MarketPriceSection> {
  int _selectedColorwayIndex = 0;
  String? _selectedSize;

  @override
  void initState() {
    super.initState();
    _selectedSize = widget.selectedSize;
  }

  @override
  void didUpdateWidget(covariant MarketPriceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedSize != oldWidget.selectedSize) {
      _selectedSize = widget.selectedSize;
    }
  }

  bool get _hasColorways =>
      widget.colorways != null && widget.colorways!.isNotEmpty;

  bool get _hasSizeMap =>
      widget.sizeMap != null && widget.sizeMap!.isNotEmpty && !_hasColorways;

  List<String> get _sortedSizes {
    if (widget.sizeMap == null) return [];
    final sizes = widget.sizeMap!.keys.toList();
    sizes.sort((a, b) {
      final da = double.tryParse(a.replaceAll(RegExp(r'[yY]$'), '')) ?? 999;
      final db = double.tryParse(b.replaceAll(RegExp(r'[yY]$'), '')) ?? 999;
      return da.compareTo(db);
    });
    return sizes;
  }

  double? get _displayPrice {
    if (_hasColorways) return widget.colorways![_selectedColorwayIndex].price;
    if (_hasSizeMap) {
      if (_selectedSize != null && widget.sizeMap!.containsKey(_selectedSize)) {
        return widget.sizeMap![_selectedSize!];
      }
      // No size selected — show lowest ask
      final sorted = widget.sizeMap!.values.where((p) => p > 0).toList()
        ..sort();
      return sorted.isEmpty ? null : sorted.first;
    }
    return widget.price;
  }

  bool get _showLowestAskLabel {
    if (_hasColorways) return false;
    if (_hasSizeMap) return _selectedSize == null;
    return widget.isLowestAsk;
  }

  /// Product id to pull sales for: the selected colorway's, or the exact match.
  String? get _salesId {
    if (widget.salesPlatform == null) return null;
    // No slug fallback: StockX sales need the UUID and GOAT the numeric id.
    final id = _hasColorways
        ? widget.colorways![_selectedColorwayIndex].productId
        : widget.salesProductId;
    return (id != null && id.isNotEmpty) ? id : null;
  }

  double? get _sellerFeeAmount {
    final price = _displayPrice;
    if (widget.sellerFeeRate == null || price == null) return null;
    return price * widget.sellerFeeRate!;
  }

  double? get _transactionFeeAmount {
    final price = _displayPrice;
    if (widget.transactionFeeRate == null || price == null) return null;
    return price * widget.transactionFeeRate!;
  }

  double? get _paymentProcessingFeeAmount {
    final price = _displayPrice;
    if (widget.paymentProcessingFeeRate == null || price == null) return null;
    return price * widget.paymentProcessingFeeRate!;
  }

  double? get _commissionFeeAmount {
    final price = _displayPrice;
    if (widget.commissionFeeRate == null || price == null) return null;
    return price * widget.commissionFeeRate!;
  }

  double get _totalFeeAmount =>
      (_sellerFeeAmount ?? 0) +
      (_transactionFeeAmount ?? 0) +
      (_paymentProcessingFeeAmount ?? 0) +
      (widget.sellerFlatFee ?? 0) +
      (_commissionFeeAmount ?? 0);

  bool get _hasFees =>
      widget.sellerFeeRate != null ||
      widget.transactionFeeRate != null ||
      widget.paymentProcessingFeeRate != null ||
      widget.sellerFlatFee != null ||
      widget.commissionFeeRate != null;

  double? get _displayProfit {
    final price = _displayPrice;
    if (widget.retailPrice != null && price != null) {
      return price - _totalFeeAmount - widget.retailPrice!;
    }
    return _hasColorways ? null : widget.profit;
  }

  double? get _displayProfitPercent {
    final price = _displayPrice;
    if (widget.retailPrice != null && price != null) {
      final afterFees = price - _totalFeeAmount;
      return ((afterFees - widget.retailPrice!) / widget.retailPrice!) * 100;
    }
    return _hasColorways ? null : widget.profitPercent;
  }

  Widget _feeRow(String label, double rate, double amount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label (${(rate * 100).toStringAsFixed(1)}%)',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            '-\$${amount.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.orange[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _flatFeeRow(String label, double amount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            '-\$${amount.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.orange[800],
            ),
          ),
        ],
      ),
    );
  }

  /// Small size badge shown next to the marketplace open button.
  /// Rendered for StockX and GOAT when a scanned size is available and
  /// no sizeMap dropdown is present.
  Widget? _sizeBadge() {
    if (_hasSizeMap) return null; // dropdown replaces the badge
    final platform = widget.label;
    if ((platform != 'GOAT' && platform != 'StockX') ||
        widget.scannedSize == null)
      return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: widget.iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: widget.iconColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Text(
        'Size ${widget.scannedSize}',
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: widget.iconColor,
        ),
      ),
    );
  }

  void _openColorwayLink() {
    if (!_hasColorways) return;
    final variant = widget.colorways![_selectedColorwayIndex];
    final slug = variant.slug;
    if (slug == null || slug.isEmpty) return;

    final platform = widget.label.toLowerCase();
    String url;
    if (platform == 'stockx') {
      final raw = widget.scannedSize;
      final numStr = raw?.replaceAll(RegExp(r'[yY]$'), '');
      final parsed = numStr != null ? double.tryParse(numStr) : null;
      final sizeQuery = (parsed != null && parsed >= 4 && parsed <= 18)
          ? '?size=${parsed % 1 == 0 ? parsed.toInt().toString() : parsed.toString()}'
          : '';
      url = 'https://stockx.com/$slug$sizeQuery';
    } else if (platform == 'goat') {
      url = 'https://www.goat.com/sneakers/$slug';
    } else {
      return;
    }
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final price = _displayPrice;
    final profit = _displayProfit;
    final profitPercent = _displayProfitPercent;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Price Row
          Row(
            children: [
              Icon(widget.icon, size: 18, color: widget.iconColor),
              const SizedBox(width: 8),
              Text(
                '${widget.label} Price',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (widget.isLoading)
                Text(
                  'Loading ${widget.label} prices...',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else if (price != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '\$${price.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (_showLowestAskLabel)
                      Text(
                        'lowest ask',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                )
              else if (!widget.productFound)
                Text(
                  'Not found on ${widget.label}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                )
              else if (widget.onOpenMarketplace != null)
                GestureDetector(
                  onTap: widget.onOpenMarketplace,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: widget.iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open on ${widget.label}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.iconColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.open_in_new,
                          size: 12,
                          color: widget.iconColor,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // Size dropdown (StockX / GOAT only, not for colorway variants or GTIN)
          if (_hasSizeMap) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedSize,
                  isExpanded: true,
                  dropdownColor: AppColors.surface,
                  icon: Icon(
                    Icons.expand_more,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'Select Size',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    ..._sortedSizes.map(
                      (size) => DropdownMenuItem<String?>(
                        value: size,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'US $size',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '\$${widget.sizeMap![size]!.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  onChanged: (size) {
                    setState(() => _selectedSize = size);
                    widget.onSizeSelected?.call(size);
                  },
                ),
              ),
            ),
          ],

          // Open on... button for non-colorway sections with a price
          if (!_hasColorways &&
              price != null &&
              widget.onOpenMarketplace != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (_sizeBadge() != null) _sizeBadge()!,
                const Spacer(),
                GestureDetector(
                  onTap: widget.onOpenMarketplace,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: widget.iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open on ${widget.label}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.iconColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.open_in_new,
                          size: 12,
                          color: widget.iconColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Colorway dropdown
          if (_hasColorways && widget.colorways!.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              'Exact color not found — available in other colors',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedColorwayIndex,
                  isExpanded: true,
                  dropdownColor: AppColors.surface,
                  icon: Icon(
                    Icons.expand_more,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  items: List.generate(widget.colorways!.length, (i) {
                    final variant = widget.colorways![i];
                    return DropdownMenuItem<int>(
                      value: i,
                      child: Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: variant.displayColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.outline,
                                width: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            variant.colorFamily,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            variant.sku,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  onChanged: (index) {
                    if (index == null) return;
                    setState(() => _selectedColorwayIndex = index);
                  },
                ),
              ),
            ),
          ],

          // Open on... button for colorway variants
          if (_hasColorways && price != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (_sizeBadge() != null) _sizeBadge()!,
                const Spacer(),
                GestureDetector(
                  onTap: _openColorwayLink,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: widget.iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open on ${widget.label}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.iconColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.open_in_new,
                          size: 12,
                          color: widget.iconColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Fee Rows
          if (price != null && _sellerFeeAmount != null) ...[
            const SizedBox(height: 8),
            _feeRow('Seller Fee', widget.sellerFeeRate!, _sellerFeeAmount!),
          ],
          if (price != null && _transactionFeeAmount != null) ...[
            const SizedBox(height: 8),
            _feeRow(
              'Transaction Fee',
              widget.transactionFeeRate!,
              _transactionFeeAmount!,
            ),
          ],
          if (price != null && _paymentProcessingFeeAmount != null) ...[
            const SizedBox(height: 8),
            _feeRow(
              'Payment Processing',
              widget.paymentProcessingFeeRate!,
              _paymentProcessingFeeAmount!,
            ),
          ],
          if (price != null && widget.sellerFlatFee != null) ...[
            const SizedBox(height: 8),
            _flatFeeRow('Seller Fee', widget.sellerFlatFee!),
          ],
          if (price != null && _commissionFeeAmount != null) ...[
            const SizedBox(height: 8),
            _feeRow(
              'Commission',
              widget.commissionFeeRate!,
              _commissionFeeAmount!,
            ),
          ],

          // Profit Row
          if (price != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _hasFees ? 'Profit after fees' : 'Profit',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (profit != null)
                    Row(
                      children: [
                        Text(
                          '${profit >= 0 ? '+' : ''}\$${profit.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            letterSpacing: -0.5,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: profit >= 0
                                ? AppColors.profit
                                : Colors.red[700],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: (profit >= 0 ? Colors.green : Colors.red)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${profitPercent! >= 0 ? '+' : ''}${profitPercent.toStringAsFixed(1)}%',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: profit >= 0
                                  ? AppColors.profit
                                  : Colors.red[700],
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Please Enter Retail Price',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ],

          // Recent sales (StockX / GOAT / eBay)
          if (price != null && !widget.isLoading && _salesId != null) ...[
            const SizedBox(height: 8),
            RecentSalesRow(
              platform: widget.salesPlatform!,
              label: widget.label,
              icon: widget.icon,
              iconColor: widget.iconColor,
              productId: _salesId!,
              productTitle: _hasColorways
                  ? widget.colorways![_selectedColorwayIndex].sku
                  : widget.productTitle,
              productImage: widget.productImage,
              highlightSize: _hasColorways
                  ? widget.scannedSize
                  : (_selectedSize ?? widget.scannedSize),
            ),
          ],
        ],
      ),
    );
  }
}
