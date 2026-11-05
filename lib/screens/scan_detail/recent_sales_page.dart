import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/sales_service.dart';
import '../../theme/app_theme.dart';

String formatSaleAmount(SaleRecord sale) =>
    formatPrice(sale.amount, sale.currency);

String formatPrice(double amount, String currency) => currency == 'USD'
    ? '\$${amount.toStringAsFixed(2)}'
    : '${amount.toStringAsFixed(2)} $currency';

/// Full list of recent sales for one platform, opened from the profit
/// calculator. Back returns to the scan detail page.
class RecentSalesPage extends StatelessWidget {
  final String platformLabel;
  final IconData icon;
  final Color iconColor;
  final String? productTitle;

  /// Same shoe image as the scan detail page; hidden when null or broken.
  final String? productImage;
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
    this.productImage,
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (productImage != null && productImage!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppColors.cardShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  productImage!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.image_not_supported_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (productTitle != null && productTitle!.isNotEmpty)
            Text(
              productTitle!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${sales.length} recent sale${sales.length == 1 ? '' : 's'} on $platformLabel',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          if (sales.isNotEmpty) ...[const SizedBox(height: 14), _priceStats()],
          if (_dateRange() case final range?) ...[
            const SizedBox(height: 8),
            Text(
              range,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Average and max sale price across the listed sales. Max is green.
  Widget _priceStats() {
    final amounts = sales.map((s) => s.amount).toList();
    final currency = sales.first.currency;
    final max = amounts.reduce((a, b) => a > b ? a : b);
    final avg = amounts.reduce((a, b) => a + b) / amounts.length;

    Widget stat(String label, double value, {Color? color}) => Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatPrice(value, currency),
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          stat('Avg', avg),
          stat('Max', max, color: AppColors.profit),
        ],
      ),
    );
  }

  /// "Oct 2, 2026 – Nov 3, 2026" covering the listed sales, or null when
  /// no sale has a date.
  String? _dateRange() {
    final dates = sales.map((s) => s.date).whereType<DateTime>().toList();
    if (dates.isEmpty) return null;
    dates.sort();
    final first = formatSaleDate(dates.first);
    final last = formatSaleDate(dates.last);
    return first == last ? 'Sales from $first' : 'Sales from $first – $last';
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
      if (sale.isAuction) 'Auction',
    ];
    final url = sale.url;

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
                if (sale.title != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    sale.title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
                if (url != null) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.platformDefault,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View on eBay',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: iconColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.open_in_new, size: 14, color: iconColor),
                      ],
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
            ],
          ),
        ],
      ),
    );
  }
}
