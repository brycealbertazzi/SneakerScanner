import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/nike_colorway_utils.dart';

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
  });

  @override
  State<MarketPriceSection> createState() => _MarketPriceSectionState();
}

class _MarketPriceSectionState extends State<MarketPriceSection> {
  int _selectedColorwayIndex = 0;

  bool get _hasColorways =>
      widget.colorways != null && widget.colorways!.isNotEmpty;

  double? get _displayPrice {
    if (_hasColorways) return widget.colorways![_selectedColorwayIndex].price;
    return widget.price;
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
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label (${(rate * 100).toStringAsFixed(1)}%)',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          Text(
            '-\$${amount.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.orange[300],
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
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          Text(
            '-\$${amount.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.orange[300],
            ),
          ),
        ],
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
      url = 'https://stockx.com/$slug';
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
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(10),
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
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (widget.isLoading)
                Text(
                  'Loading ${widget.label} prices...',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                )
              else if (price != null)
                Text(
                  '\$${price.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                )
              else if (!widget.productFound)
                Text(
                  'Not found on ${widget.label}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey[600],
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
                        Icon(Icons.open_in_new, size: 12, color: widget.iconColor),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // Open on... button for non-colorway sections with a price
          if (!_hasColorways && price != null && widget.onOpenMarketplace != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
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
                      Icon(Icons.open_in_new, size: 12, color: widget.iconColor),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Colorway dropdown
          if (_hasColorways && widget.colorways!.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              'Exact color not found — available in other colors',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedColorwayIndex,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A1A1A),
                  icon: Icon(Icons.expand_more, color: Colors.grey[500], size: 20),
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
                                color: Colors.grey[600]!,
                                width: variant.displayColor == Colors.black ? 1 : 0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            variant.colorFamily,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            variant.sku,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.grey[500],
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
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
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
                      Icon(Icons.open_in_new, size: 12, color: widget.iconColor),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Fee Rows
          if (price != null && _sellerFeeAmount != null) ...[
            const SizedBox(height: 8),
            _feeRow('Seller Fee', widget.sellerFeeRate!, _sellerFeeAmount!),
          ],
          if (price != null && _transactionFeeAmount != null) ...[
            const SizedBox(height: 8),
            _feeRow('Transaction Fee', widget.transactionFeeRate!, _transactionFeeAmount!),
          ],
          if (price != null && _paymentProcessingFeeAmount != null) ...[
            const SizedBox(height: 8),
            _feeRow('Payment Processing', widget.paymentProcessingFeeRate!, _paymentProcessingFeeAmount!),
          ],
          if (price != null && widget.sellerFlatFee != null) ...[
            const SizedBox(height: 8),
            _flatFeeRow('Seller Fee', widget.sellerFlatFee!),
          ],
          if (price != null && _commissionFeeAmount != null) ...[
            const SizedBox(height: 8),
            _feeRow('Commission', widget.commissionFeeRate!, _commissionFeeAmount!),
          ],

          // Profit Row
          if (price != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _hasFees ? 'Profit after fees' : 'Profit',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey[400],
                    ),
                  ),
                  if (profit != null)
                    Row(
                      children: [
                        Text(
                          '${profit >= 0 ? '+' : ''}\$${profit.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: profit >= 0
                                ? Colors.green[400]
                                : Colors.red[400],
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
                                  ? Colors.green[400]
                                  : Colors.red[400],
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Retail price not found',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
