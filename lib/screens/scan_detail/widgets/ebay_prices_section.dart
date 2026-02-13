import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EbayPricesSection extends StatelessWidget {
  final bool isLoading;
  final double? lowestPrice;
  final double? averagePrice;
  final int? listingCount;
  final String? error;

  const EbayPricesSection({
    super.key,
    required this.isLoading,
    required this.lowestPrice,
    required this.averagePrice,
    required this.listingCount,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    // Show loading state
    if (isLoading) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF1E2A3A), const Color(0xFF1A2230)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF0064D2).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF0064D2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Fetching eBay prices...',
              style: GoogleFonts.inter(color: Colors.grey[400], fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Show eBay prices if available
    if (lowestPrice != null || averagePrice != null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF1E2A3A), const Color(0xFF1A2230)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF0064D2).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shopping_bag,
                  color: const Color(0xFF0064D2),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'eBay Market Prices',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF0064D2),
                  ),
                ),
                const Spacer(),
                if (listingCount != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0064D2).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$listingCount listings',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF0064D2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lowest',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        lowestPrice != null
                            ? '\$${lowestPrice!.toStringAsFixed(2)}'
                            : '--',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: Colors.grey[700]),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Average',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        averagePrice != null
                            ? '\$${averagePrice!.toStringAsFixed(2)}'
                            : '--',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[400],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Show setup prompt if eBay not configured
    if (error == 'eBay API not configured') {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[800]!, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey[500], size: 18),
                const SizedBox(width: 8),
                Text(
                  'eBay Prices Available',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Set up eBay API credentials to automatically fetch market prices.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
