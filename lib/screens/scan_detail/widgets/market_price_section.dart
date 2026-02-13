import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MarketPriceSection extends StatelessWidget {
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
  });

  @override
  Widget build(BuildContext context) {
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
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                '$label Price',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (isLoading)
                Text(
                  'Loading...',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                )
              else if (price != null)
                Text(
                  '\$${price!.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                )
              else if (!productFound)
                Text(
                  'Not found on $label',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                )
              else if (onOpenMarketplace != null)
                GestureDetector(
                  onTap: onOpenMarketplace,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open on $label',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: iconColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.open_in_new, size: 12, color: iconColor),
                      ],
                    ),
                  ),
                ),
            ],
          ),

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
                    'Profit',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey[400],
                    ),
                  ),
                  if (profit != null)
                    Row(
                      children: [
                        Text(
                          '${profit! >= 0 ? '+' : ''}\$${profit!.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: profit! >= 0
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
                            color: (profit! >= 0 ? Colors.green : Colors.red)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${profitPercent! >= 0 ? '+' : ''}${profitPercent!.toStringAsFixed(1)}%',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: profit! >= 0
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
