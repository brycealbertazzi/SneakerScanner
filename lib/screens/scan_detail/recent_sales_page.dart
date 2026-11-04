import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/sales_service.dart';
import '../../theme/app_theme.dart';

String formatSaleAmount(SaleRecord sale) => sale.currency == 'USD'
    ? '\$${sale.amount.toStringAsFixed(2)}'
    : '${sale.amount.toStringAsFixed(2)} ${sale.currency}';

/// Full list of recent sales for one platform, opened from the profit
/// calculator. Back returns to the scan detail page.
class RecentSalesPage extends StatelessWidget {
  final String platformLabel;
  final IconData icon;
  final Color iconColor;
  final String? productTitle;
  final List<SaleRecord> sales;

  /// Sales in this size get highlighted (GOAT only — StockX has no sizes).
  final String? highlightSize;

  const RecentSalesPage({
    super.key,
    required this.platformLabel,
    required this.icon,
    required this.iconColor,
    required this.sales,
    this.productTitle,
    this.highlightSize,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '$platformLabel Recent Sales',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: sales.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) return _header();
          return _SaleCard(
            sale: sales[index - 1],
            iconColor: iconColor,
            highlight:
                highlightSize != null && sales[index - 1].size == highlightSize,
          );
        },
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (productTitle != null && productTitle!.isNotEmpty)
            Text(
              productTitle!,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Text(
                '${sales.length} recent sale${sales.length == 1 ? '' : 's'} on $platformLabel',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final SaleRecord sale;
  final Color iconColor;
  final bool highlight;

  const _SaleCard({
    required this.sale,
    required this.iconColor,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final date = sale.date;
    final details = <String>[
      if (sale.location != null) sale.location!,
      if (sale.isOffer) 'Accepted offer',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
        border: Border.all(
          color: highlight
              ? iconColor.withValues(alpha: 0.6)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatSaleAmount(sale),
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  date != null
                      ? '${formatSaleDate(date)} · ${formatSaleTime(date)}'
                      : 'Date unavailable',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    details.join(' · '),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (sale.size != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'US ${sale.size}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: iconColor,
                    ),
                  ),
                ),
              if (date != null) ...[
                const SizedBox(height: 6),
                Text(
                  relativeSaleTime(date),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
