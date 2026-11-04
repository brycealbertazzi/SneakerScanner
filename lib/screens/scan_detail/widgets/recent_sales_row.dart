import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/sales_service.dart';
import '../../../theme/app_theme.dart';
import '../recent_sales_page.dart';

/// Recent-sales summary inside a StockX/GOAT profit section: either
/// "No recent sales on X", or the last sale plus a link to the full list.
/// Fetches (via the cached [SalesService]) whenever [productId] changes, so
/// switching colorways loads that colorway's sales.
class RecentSalesRow extends StatefulWidget {
  /// 'stockx' or 'goat'.
  final String platform;
  final String label;
  final IconData icon;
  final Color iconColor;
  final String productId;
  final String? productTitle;
  final String? highlightSize;

  const RecentSalesRow({
    super.key,
    required this.platform,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.productId,
    this.productTitle,
    this.highlightSize,
  });

  @override
  State<RecentSalesRow> createState() => _RecentSalesRowState();
}

class _RecentSalesRowState extends State<RecentSalesRow> {
  late Future<List<SaleRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = SalesService.fetch(widget.platform, widget.productId);
  }

  @override
  void didUpdateWidget(covariant RecentSalesRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId ||
        oldWidget.platform != widget.platform) {
      _future = SalesService.fetch(widget.platform, widget.productId);
    }
  }

  void _openList(List<SaleRecord> sales) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecentSalesPage(
          platformLabel: widget.label,
          icon: widget.icon,
          iconColor: widget.iconColor,
          productTitle: widget.productTitle,
          sales: sales,
          highlightSize: widget.highlightSize,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SaleRecord>>(
      future: _future,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.connectionState != ConnectionState.done) {
          child = _text('Loading recent sales...', italic: true);
        } else {
          final sales = snapshot.data ?? const <SaleRecord>[];
          child = sales.isEmpty
              ? _text('No recent sales on ${widget.label}')
              : _salesLink(sales);
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: child,
        );
      },
    );
  }

  Widget _text(String value, {bool italic = false}) => Text(
    value,
    style: GoogleFonts.inter(
      fontSize: 12,
      color: AppColors.textSecondary,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    ),
  );

  Widget _salesLink(List<SaleRecord> sales) {
    final last = sales.first;
    final when = last.date != null ? ' · ${relativeSaleTime(last.date!)}' : '';
    final sizeText = last.size != null ? ' · US ${last.size}' : '';
    return InkWell(
      onTap: () => _openList(sales),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last sale ${formatSaleAmount(last)}$sizeText$when',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'View ${sales.length} recent sale${sales.length == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: widget.iconColor,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: widget.iconColor),
        ],
      ),
    );
  }
}
