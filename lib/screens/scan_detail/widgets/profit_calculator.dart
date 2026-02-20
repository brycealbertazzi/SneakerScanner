import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/nike_colorway_utils.dart';
import 'market_price_section.dart';

class ProfitCalculator extends StatefulWidget {
  final Map<String, dynamic>? productInfo;
  final double? manualRetailPrice;
  final double? ebayAveragePrice;
  final double? stockXPrice;
  final double? goatPrice;
  final bool isLoadingEbayPrices;
  final bool isLoadingStockXPrice;
  final bool isLoadingGoatPrice;
  final List<ColorwayVariant>? stockXColorways;
  final List<ColorwayVariant>? goatColorways;
  final VoidCallback? onOpenEbay;
  final VoidCallback? onOpenStockX;
  final VoidCallback? onOpenGoat;
  final ValueChanged<double?> onRetailPriceChanged;
  final VoidCallback onSavePrices;

  const ProfitCalculator({
    super.key,
    required this.productInfo,
    required this.manualRetailPrice,
    required this.ebayAveragePrice,
    required this.stockXPrice,
    required this.goatPrice,
    required this.isLoadingEbayPrices,
    required this.isLoadingStockXPrice,
    required this.isLoadingGoatPrice,
    this.stockXColorways,
    this.goatColorways,
    this.onOpenEbay,
    this.onOpenStockX,
    this.onOpenGoat,
    required this.onRetailPriceChanged,
    required this.onSavePrices,
  });

  @override
  State<ProfitCalculator> createState() => _ProfitCalculatorState();
}

class _ProfitCalculatorState extends State<ProfitCalculator> {
  late TextEditingController _retailPriceController;
  bool _showRetailEntry = false;

  @override
  void initState() {
    super.initState();
    final initialPrice = _fetchedRetailPrice ?? widget.manualRetailPrice;
    _retailPriceController = TextEditingController(
      text: initialPrice?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant ProfitCalculator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pre-populate controller when auto-fetched price arrives for the first time
    final oldFetched = _parseRetailPrice(oldWidget.productInfo);
    final newFetched = _fetchedRetailPrice;
    if (oldFetched == null && newFetched != null && !_showRetailEntry) {
      _retailPriceController.text = newFetched.toStringAsFixed(2);
    }
  }

  double? get _fetchedRetailPrice {
    return _parseRetailPrice(widget.productInfo);
  }

  static double? _parseRetailPrice(Map<String, dynamic>? productInfo) {
    final retailPriceStr = productInfo?['retailPrice'] as String?;
    return retailPriceStr != null ? double.tryParse(retailPriceStr) : null;
  }

  @override
  void dispose() {
    _retailPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fetchedRetailPrice = _fetchedRetailPrice;
    final retailPrice = fetchedRetailPrice ?? widget.manualRetailPrice;

    final ebayPrice = widget.ebayAveragePrice;
    final ebayFeeRate = ebayPrice != null ? (ebayPrice >= 150 ? 0.08 : 0.136) : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calculate_rounded,
                color: const Color(0xFF646CFF),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Profit Calculator',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Retail Price Row — always editable
          Row(
            children: [
              Icon(Icons.sell, size: 16, color: Colors.green[400]),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Retail Price',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    ),
                    if (_showRetailEntry)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 100,
                            height: 36,
                            child: TextField(
                              controller: _retailPriceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textInputAction: TextInputAction.done,
                              autofocus: true,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.right,
                              decoration: InputDecoration(
                                hintText: '0.00',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                                prefixText: '\$ ',
                                prefixStyle: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF252525),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.green[400]!,
                                    width: 1,
                                  ),
                                ),
                              ),
                              onChanged: (value) {
                                widget.onRetailPriceChanged(double.tryParse(value));
                              },
                              onSubmitted: (value) {
                                final parsed = double.tryParse(value);
                                widget.onRetailPriceChanged(parsed);
                                if (parsed != null) {
                                  setState(() => _showRetailEntry = false);
                                  widget.onSavePrices();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              final parsed = double.tryParse(
                                _retailPriceController.text,
                              );
                              widget.onRetailPriceChanged(parsed);
                              if (parsed != null) {
                                setState(() => _showRetailEntry = false);
                                widget.onSavePrices();
                              }
                            },
                            child: Container(
                              width: 40,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.green[400]!.withValues(
                                  alpha: 0.2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.check,
                                color: Colors.green[400],
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      )
                    else if (retailPrice != null)
                      GestureDetector(
                        onTap: () {
                          _retailPriceController.text = retailPrice.toStringAsFixed(2);
                          setState(() => _showRetailEntry = true);
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '\$${retailPrice.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.edit,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        children: [
                          Text(
                            'Not Found',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _showRetailEntry = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Enter',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green[400],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: Colors.grey[800], height: 1),
          ),

          // eBay Section
          MarketPriceSection(
            label: 'eBay',
            icon: Icons.shopping_bag,
            iconColor: const Color(0xFF0064D2),
            price: ebayPrice,
            profit: null,
            profitPercent: null,
            isLoading: widget.isLoadingEbayPrices,
            retailPrice: retailPrice,
            productFound: ebayPrice != null,
            onOpenMarketplace: ebayPrice != null ? widget.onOpenEbay : null,
            sellerFeeRate: ebayFeeRate,
          ),
          const SizedBox(height: 12),

          // StockX Section
          MarketPriceSection(
            label: 'StockX',
            icon: Icons.store,
            iconColor: const Color(0xFF006340),
            price: widget.stockXPrice,
            profit: null,
            profitPercent: null,
            isLoading: widget.isLoadingStockXPrice,
            retailPrice: retailPrice,
            productFound: widget.stockXPrice != null,
            colorways: widget.stockXColorways,
            onOpenMarketplace: widget.stockXPrice != null ? widget.onOpenStockX : null,
            transactionFeeRate: widget.stockXPrice != null ? 0.08 : null,
            paymentProcessingFeeRate: widget.stockXPrice != null ? 0.03 : null,
          ),
          const SizedBox(height: 12),

          // GOAT Section
          MarketPriceSection(
            label: 'GOAT',
            icon: Icons.storefront,
            iconColor: const Color(0xFF7B61FF),
            price: widget.goatPrice,
            profit: null,
            profitPercent: null,
            isLoading: widget.isLoadingGoatPrice,
            retailPrice: retailPrice,
            productFound: widget.goatPrice != null,
            colorways: widget.goatColorways,
            onOpenMarketplace: widget.goatPrice != null ? widget.onOpenGoat : null,
            sellerFlatFee: widget.goatPrice != null ? 5.0 : null,
            commissionFeeRate: widget.goatPrice != null ? 0.095 : null,
          ),
        ],
      ),
    );
  }
}
