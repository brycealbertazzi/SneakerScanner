import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/login_screen.dart';
import '../screens/main_screen.dart';
import '../services/subscription_service.dart';

class PaywallPage extends StatefulWidget {
  /// When false the close button is hidden and success/restore navigates to
  /// MainScreen instead of popping. Used for the hard launch paywall.
  final bool isCloseable;

  /// When true, successful subscription navigates to LoginScreen instead of
  /// MainScreen. Used when paywall appears before the user has signed in
  /// (i.e. the onboarding flow).
  final bool isPreLogin;

  const PaywallPage({
    super.key,
    this.isCloseable = true,
    this.isPreLogin = false,
  });

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> with WidgetsBindingObserver {
  final _sub = SubscriptionService.instance;

  bool _restorePressed = false;
  bool _privacyPressed = false;
  bool _termsPressed = false;
  bool _wasActiveOnInit = false;
  bool _restoredDialogShowing = false;
  bool _successDialogShowing = false;
  bool _isRestoring = false;
  Timer? _cancelFallbackTimer;

  @override
  void initState() {
    super.initState();
    _wasActiveOnInit = _sub.isSubscribed;
    _sub.addListener(_onSubChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _cancelFallbackTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _sub.removeListener(_onSubChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _sub.purchasePending &&
        !_isRestoring) {
      // Start a short fallback timer. If the purchase stream delivers any event
      // (cancel or confirm), _onSubChanged cancels this before it fires —
      // meaning cancels clear immediately via the stream, and confirmed purchases
      // keep the spinner until the success dialog. The timer only fires when
      // StoreKit silently drops the cancellation event (known iOS issue).
      _cancelFallbackTimer?.cancel();
      _cancelFallbackTimer = Timer(const Duration(milliseconds: 4000), () {
        if (mounted) _sub.forceCancelPending();
      });
    }
  }

  void _onSubChanged() {
    if (!mounted) return;
    _cancelFallbackTimer?.cancel();
    _cancelFallbackTimer = null;
    if (_sub.status == SubscriptionStatus.active) {
      if (_isRestoring) {
        // User explicitly tapped Restore Purchases — show confirmation (iOS only).
        _isRestoring = false;
        setState(() {});
        _showRestoredDialog();
      } else if (!_wasActiveOnInit) {
        // New subscription — show success modal, then dismiss paywall.
        setState(() {});
        _showSuccessDialog();
      } else {
        // Already subscribed when paywall opened (e.g. background recheck) — do nothing.
        setState(() {});
      }
      return;
    }
    if (_isRestoring && !_sub.purchasePending) {
      _isRestoring = false;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _sub.status != SubscriptionStatus.active) {
          _showNoRestoreFound();
        }
      });
    }
    setState(() {});
    if (_sub.purchaseCancelled) {
      _sub.clearCancelled();
    } else if (_sub.purchaseError != null) {
      _showError(_sub.purchaseError!);
      _sub.clearError();
    }
  }

  void _showNoRestoreFound() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        Future.delayed(const Duration(seconds: 2), () {
          if (ctx.mounted) Navigator.of(ctx).pop();
        });
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.blue,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No Previous Purchases Found',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
                'Purchase Restored',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You\'re already subscribed!',
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
                    if (mounted) _dismissPaywall();
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

  void _showSuccessDialog() {
    if (_successDialogShowing) return;
    _successDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
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
                'Thank you for subscribing to SneakScan!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _successDialogShowing = false;
                    Navigator.of(ctx).pop();
                    if (mounted) _dismissPaywall();
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
                    'Close',
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

  /// Dismisses the paywall correctly depending on context:
  /// - Pre-login hard paywall → LoginScreen (user subscribed before creating account)
  /// - Hard paywall (in-app) → MainScreen
  /// - Settings paywall (closeable) → pop
  void _dismissPaywall() {
    if (!widget.isCloseable) {
      if (widget.isPreLogin) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    } else {
      Navigator.of(context).pop();
    }
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

  String? _priceLabel() {
    final product = _sub.annualProduct;
    if (product != null && product.price.toLowerCase() != 'free') {
      return product.price;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isStatusLoading = _sub.status == SubscriptionStatus.loading;
    final pending = _sub.purchasePending || isStatusLoading;
    final buttonLabel = isStatusLoading
        ? null // still determining status — show spinner
        : _sub.isSubscribed
        ? null // subscribed — shows badge instead
        : _sub.isLapsedSubscriber
        ? 'Get Unlimited Scans'
        : 'Start Free Trial';
    final headline = _sub.isLapsedSubscriber
        ? 'Spot profits instantly with SneakScan'
        : 'Try SneakScan free for 7 days';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Top-center brand glow
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.0,
                    colors: [
                      const Color(0xFF646CFF).withValues(alpha: 0.18),
                      const Color(0xFF646CFF).withValues(alpha: 0.07),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        const SizedBox(height: 60),

                        // Headline
                        Text(
                          headline,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 24),

                        Text(
                          'We\'ll remind you 1 day before your free trial ends',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Feature list
                        _FeatureRow(
                          icon: Icons.all_inclusive_rounded,
                          iconColor: const Color(0xFF646CFF),
                          text: 'Unlimited scans',
                        ),
                        const SizedBox(height: 22),
                        _FeatureRow(
                          icon: Icons.show_chart_rounded,
                          iconColor: Colors.green,
                          text: 'Live StockX & GOAT market prices',
                        ),
                        const SizedBox(height: 22),
                        _FeatureRow(
                          icon: Icons.sell_rounded,
                          iconColor: Colors.orange,
                          text: 'eBay sold listings with fees',
                        ),
                        const SizedBox(height: 22),
                        _FeatureRow(
                          icon: Icons.camera_alt_rounded,
                          iconColor: Colors.blue,
                          text: 'OCR label & barcode scanning',
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),

                // Pinned bottom section
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    border: Border(
                      top: BorderSide(color: const Color(0xFF333333), width: 1),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // No payment hint — only for free trial eligible users
                      if (!_sub.isSubscribed && !_sub.isLapsedSubscriber) ...[
                        Text(
                          'No Payment Due Now. Cancel Anytime.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

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
                        Container(
                          width: double.infinity,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF646CFF), Color(0xFF8B5CF6)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF646CFF,
                                ).withValues(alpha: 0.45),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: (pending && !_isRestoring)
                                ? null
                                : _sub.buyAnnual,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(
                                0xFF646CFF,
                              ).withValues(alpha: 0.5),
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: (pending && !_isRestoring)
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    buttonLabel ?? 'Get Unlimited Scans',
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      const SizedBox(height: 12),

                      // Pricing note for lapsed subscribers
                      if (_sub.isLapsedSubscriber) ...[
                        if (_priceLabel() != null) ...[
                          Text(
                            '${_priceLabel()}/year - Cancel Anytime',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],

                      // Trial pricing note — only for free trial eligible users
                      if (!_sub.isSubscribed && !_sub.isLapsedSubscriber) ...[
                        if (_priceLabel() != null) ...[
                          Text(
                            '7 day free trial then ${_priceLabel()}/year',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ] else
                        const SizedBox(height: 4),

                      // Android-only required subscription notice
                      if (Platform.isAndroid) ...[
                        Text(
                          'A subscription is required to use the app',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Links row
                      if (Platform.isIOS)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _LinkText(
                              label: 'Terms',
                              pressed: _termsPressed,
                              onTap: () => launchUrl(
                                Uri.parse('https://terms.sneakscan.com'),
                                mode: LaunchMode.externalApplication,
                              ),
                              onTapDown: () =>
                                  setState(() => _termsPressed = true),
                              onTapUp: () =>
                                  setState(() => _termsPressed = false),
                            ),
                            _Dot(),
                            GestureDetector(
                              onTap: pending
                                  ? null
                                  : () {
                                      setState(() => _isRestoring = true);
                                      _sub.restorePurchases();
                                    },
                              onTapDown: (_) =>
                                  setState(() => _restorePressed = true),
                              onTapUp: (_) =>
                                  setState(() => _restorePressed = false),
                              onTapCancel: () =>
                                  setState(() => _restorePressed = false),
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
                            _Dot(),
                            _LinkText(
                              label: 'Privacy',
                              pressed: _privacyPressed,
                              onTap: () => launchUrl(
                                Uri.parse('https://privacy.sneakscan.com'),
                                mode: LaunchMode.externalApplication,
                              ),
                              onTapDown: () =>
                                  setState(() => _privacyPressed = true),
                              onTapUp: () =>
                                  setState(() => _privacyPressed = false),
                            ),
                          ],
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _LinkText(
                              label: 'Terms',
                              pressed: _termsPressed,
                              onTap: () => launchUrl(
                                Uri.parse('https://terms.sneakscan.com'),
                                mode: LaunchMode.externalApplication,
                              ),
                              onTapDown: () =>
                                  setState(() => _termsPressed = true),
                              onTapUp: () =>
                                  setState(() => _termsPressed = false),
                            ),
                            _Dot(),
                            _LinkText(
                              label: 'Privacy',
                              pressed: _privacyPressed,
                              onTap: () => launchUrl(
                                Uri.parse('https://privacy.sneakscan.com'),
                                mode: LaunchMode.externalApplication,
                              ),
                              onTapDown: () =>
                                  setState(() => _privacyPressed = true),
                              onTapUp: () =>
                                  setState(() => _privacyPressed = false),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // Close button — only shown when paywall is dismissible
            if (widget.isCloseable)
              Positioned(
                top: 12,
                right: 16,
                child: IconButton(
                  onPressed: pending
                      ? null
                      : () => Navigator.of(context).pop(false),
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.grey[600],
                    size: 28,
                  ),
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
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 16),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 17,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LinkText extends StatelessWidget {
  final String label;
  final bool pressed;
  final VoidCallback onTap;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;

  const _LinkText({
    required this.label,
    required this.pressed,
    required this.onTap,
    required this.onTapDown,
    required this.onTapUp,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp(),
      onTapCancel: onTapUp,
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 13,
          color: pressed ? Colors.white : Colors.grey[500],
          decoration: TextDecoration.underline,
          decorationColor: pressed ? Colors.white : Colors.grey[500],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        '·',
        style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
      ),
    );
  }
}
