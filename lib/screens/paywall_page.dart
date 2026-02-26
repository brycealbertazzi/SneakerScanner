import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/subscription_service.dart';

class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key});

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage>
    with WidgetsBindingObserver {
  final _sub = SubscriptionService.instance;

  bool _restorePressed = false;
  bool _privacyPressed = false;
  bool _termsPressed = false;
  bool _wasActiveOnInit = false;
  bool _restoredDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _wasActiveOnInit = _sub.isSubscribed;
    _sub.addListener(_onSubChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub.removeListener(_onSubChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _sub.purchasePending) {
      // Give StoreKit 1 second to deliver its event after the app resumes.
      // For a successful purchase, _purchasePending will be cleared by the
      // Firebase write well within that window, making this a no-op.
      // For a silent cancellation (no stream event), this resets the button.
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _sub.forceCancelPending();
      });
    }
  }

  void _onSubChanged() {
    if (!mounted) return;
    if (_sub.status == SubscriptionStatus.active) {
      if (_wasActiveOnInit) {
        // User was already subscribed — this is a restore confirmation.
        // Show dialog instead of popping so camera/nav stack is undisturbed.
        setState(() {});
        _showRestoredDialog();
      } else {
        // New subscription (or restore on a new device) — pop with success.
        Navigator.of(context).pop(true);
      }
      return;
    }
    setState(() {});
    if (_sub.purchaseCancelled) {
      _sub.clearCancelled();
      _showCancelledDialog();
    } else if (_sub.purchaseError != null) {
      _showError(_sub.purchaseError!);
      _sub.clearError();
    }
  }

  void _showRestoredDialog() {
    if (_restoredDialogShowing) return;
    _restoredDialogShowing = true;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF333333), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.green,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Purchases Restored',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your subscription has been restored successfully.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey[400],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _restoredDialogShowing = false;
                    Navigator.of(ctx).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'OK',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCancelledDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF333333), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Purchase Not Completed',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your purchase was not completed. You can try again whenever you\'re ready.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey[400],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF646CFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'OK',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _priceLabel() {
    final product = _sub.annualProduct;
    if (product != null) return product.price;
    return '\$49.99';
  }

  @override
  Widget build(BuildContext context) {
    final status = _sub.status;
    final isFreeTrial = status == SubscriptionStatus.freeTrial;
    final scansRemaining = _sub.scansRemaining;
    final pending = _sub.purchasePending;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Dismiss button
            Positioned(
              top: 12,
              right: 16,
              child: IconButton(
                onPressed: pending ? null : () => Navigator.of(context).pop(false),
                icon: Icon(
                  Icons.close_rounded,
                  color: Colors.grey[600],
                  size: 28,
                ),
              ),
            ),

            // Main content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 60),

                  // Icon
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF646CFF), Color(0xFF9B59B6)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF646CFF).withValues(alpha: 0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_enhance_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Headline
                  Text(
                    'Sneaker Scanner\nPremium',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Trial warning or subtitle
                  if (isFreeTrial && scansRemaining == 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        "You've used all 30 free scans",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.red[300],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else if (isFreeTrial)
                    Text(
                      '$scansRemaining of ${_sub.scansLimit} free scans remaining',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    )
                  else
                    Text(
                      'Unlock unlimited scans and real-time market prices',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    ),

                  const SizedBox(height: 32),

                  // Feature list
                  _FeatureRow(
                    icon: Icons.all_inclusive_rounded,
                    iconColor: const Color(0xFF646CFF),
                    text: 'Unlimited scans',
                  ),
                  const SizedBox(height: 14),
                  _FeatureRow(
                    icon: Icons.trending_up_rounded,
                    iconColor: Colors.green,
                    text: 'Live StockX & GOAT market prices',
                  ),
                  const SizedBox(height: 14),
                  _FeatureRow(
                    icon: Icons.sell_rounded,
                    iconColor: Colors.orange,
                    text: 'eBay sold listings with fees',
                  ),
                  const SizedBox(height: 14),
                  _FeatureRow(
                    icon: Icons.camera_alt_rounded,
                    iconColor: Colors.blue,
                    text: 'OCR label & barcode scanning',
                  ),

                  const Spacer(),

                  // Price card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF1E1B4B),
                          const Color(0xFF1A1A2E),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF646CFF).withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _priceLabel(),
                              style: GoogleFonts.poppins(
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'per year — less than \$4.17/month',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // CTA button or subscribed badge
                  if (_sub.isSubscribed)
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.green,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'You\'re subscribed',
                            style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: pending ? null : _sub.buyAnnual,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF646CFF),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              const Color(0xFF646CFF).withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: pending
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Start Annual Plan',
                                style: GoogleFonts.poppins(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  const SizedBox(height: 22),

                  // Cancel subscription hint
                  Text(
                    Platform.isIOS
                        ? 'Cancel subscription anytime in Settings'
                        : 'Cancel subscription anytime in your Google Settings',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Restore purchases (iOS only)
                  if (Platform.isIOS) ...[
                    GestureDetector(
                      onTap: pending ? null : _sub.restorePurchases,
                      onTapDown: (_) => setState(() => _restorePressed = true),
                      onTapUp: (_) => setState(() => _restorePressed = false),
                      onTapCancel: () => setState(() => _restorePressed = false),
                      child: Text(
                        'Restore Purchases',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: _restorePressed
                              ? Colors.white
                              : Colors.grey[500],
                          decoration: TextDecoration.underline,
                          decorationColor: _restorePressed
                              ? Colors.white
                              : Colors.grey[500],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Privacy & Terms links
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse('https://privacy.sneakscan.com'),
                          mode: LaunchMode.externalApplication,
                        ),
                        onTapDown: (_) =>
                            setState(() => _privacyPressed = true),
                        onTapUp: (_) =>
                            setState(() => _privacyPressed = false),
                        onTapCancel: () =>
                            setState(() => _privacyPressed = false),
                        child: Text(
                          'Privacy',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _privacyPressed
                                ? Colors.white
                                : Colors.grey[500],
                            decoration: TextDecoration.underline,
                            decorationColor: _privacyPressed
                                ? Colors.white
                                : Colors.grey[500],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '·',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse('https://terms.sneakscan.com'),
                          mode: LaunchMode.externalApplication,
                        ),
                        onTapDown: (_) =>
                            setState(() => _termsPressed = true),
                        onTapUp: (_) =>
                            setState(() => _termsPressed = false),
                        onTapCancel: () =>
                            setState(() => _termsPressed = false),
                        child: Text(
                          'Terms',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _termsPressed
                                ? Colors.white
                                : Colors.grey[500],
                            decoration: TextDecoration.underline,
                            decorationColor: _termsPressed
                                ? Colors.white
                                : Colors.grey[500],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;

  const _FeatureRow({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 14),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 15,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
