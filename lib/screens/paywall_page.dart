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

    return Scaffold(
      backgroundColor: const Color(0xFF0D0A1E),
      body: SafeArea(
        child: Stack(
          children: [
            // Radial gradient: dark indigo center fading to black at edges
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [
                      Color(0xFF0D0A1E),
                      Colors.black,
                    ],
                    stops: [0.0, 1.0],
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
                          'Get SneakScan and never miss a flip',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
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
                          icon: Icons.show_chart_rounded,
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
                        const SizedBox(height: 40),

                        // Value prop card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D0D0D),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF1E1E1E),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.attach_money_rounded,
                                    color: Colors.green,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '\$40–\$120 avg. profit per flip',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.access_time_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Stop wasting time looking up resale prices. Remember time is money',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.explore_rounded,
                                    color: Color(0xFF646CFF),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Discover 2x-3x flips other sellers miss',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _PaywallAnimationCarousel(),
                        const SizedBox(height: 16),
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

// ── Paywall animation carousel ────────────────────────────────────────────────

class _PaywallAnimationCarousel extends StatefulWidget {
  const _PaywallAnimationCarousel();

  @override
  State<_PaywallAnimationCarousel> createState() =>
      _PaywallAnimationCarouselState();
}

class _PaywallAnimationCarouselState extends State<_PaywallAnimationCarousel>
    with SingleTickerProviderStateMixin {
  int _current = 0;
  final _visitCounts = [0, 0, 0];
  late final AnimationController _fadeCtrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    // 400ms fade-in · 3000ms hold · 400ms fade-out = 3800ms per scene
    _fadeCtrl = AnimationController(
      duration: const Duration(milliseconds: 3800),
      vsync: this,
    );
    _opacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 400),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 3000),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 400),
    ]).animate(_fadeCtrl);
    _startCycle();
  }

  void _startCycle() {
    _fadeCtrl.forward(from: 0).then((_) {
      if (!mounted) return;
      final next = (_current + 1) % 3;
      setState(() {
        _current = next;
        _visitCounts[next]++;
      });
      _startCycle();
    });
  }

  Widget _buildScene(int idx) {
    final key = ValueKey((idx, _visitCounts[idx]));
    switch (idx) {
      case 0:
        return _ScanScene(key: key);
      case 1:
        return _PricesScene(key: key);
      default:
        return _ProfitScene(key: key);
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: AnimatedBuilder(
        animation: _opacity,
        builder: (context, child) =>
            Opacity(opacity: _opacity.value, child: child),
        child: _buildScene(_current),
      ),
    );
  }
}

// ── Scene 1: OCR label scan with photo snap ───────────────────────────────────

class _ScanScene extends StatefulWidget {
  const _ScanScene({super.key});

  @override
  State<_ScanScene> createState() => _ScanSceneState();
}

class _ScanSceneState extends State<_ScanScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  // brackets: 0.0 → 0.28
  late final Animation<double> _bracketProgress;
  // photo flash: 0.26 → 0.42 (spike up then back down)
  late final Animation<double> _flash;
  // label lines fade in sequentially after snap
  late final Animation<double> _line1;
  late final Animation<double> _line2;
  late final Animation<double> _line3;
  late final Animation<double> _line4;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    _bracketProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.28, curve: Curves.easeOut),
      ),
    );
    _flash = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.55), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.55, end: 0.0), weight: 60),
    ]).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.26, 0.44),
      ),
    );
    _line1 = _lineFade(0.40, 0.56);
    _line2 = _lineFade(0.50, 0.65);
    _line3 = _lineFade(0.59, 0.74);
    _line4 = _lineFade(0.68, 0.82);

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _ctrl.forward();
    });
  }

  Animation<double> _lineFade(double start, double end) =>
      Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(start, end, curve: Curves.easeOut),
        ),
      );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const w = 190.0;
    const h = 116.0;
    return Center(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              // Label card — revealed after snap
              Opacity(
                opacity: _line1.value,
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand + model
                      Opacity(
                        opacity: _line1.value,
                        child: Text(
                          'NIKE  ·  AIR JORDAN 1 RETRO HIGH OG',
                          style: GoogleFonts.inter(
                            fontSize: 8,
                            color: Colors.white.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // SKU line
                      Opacity(
                        opacity: _line2.value,
                        child: Row(
                          children: [
                            Text(
                              'STYLE',
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                color: Colors.white.withValues(alpha: 0.25),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '553558-174',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                color: Colors.white.withValues(alpha: 0.55),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      // Color line
                      Opacity(
                        opacity: _line3.value,
                        child: Row(
                          children: [
                            Text(
                              'COLOR',
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                color: Colors.white.withValues(alpha: 0.25),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'WHITE / BLACK-VARSITY RED',
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                color: Colors.white.withValues(alpha: 0.4),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      // Size line
                      Opacity(
                        opacity: _line4.value,
                        child: Row(
                          children: [
                            Text(
                              'SIZE',
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                color: Colors.white.withValues(alpha: 0.25),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '10.5 US  /  44.5 EUR',
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                color: Colors.white.withValues(alpha: 0.4),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Corner brackets
              Positioned.fill(
                child: CustomPaint(
                  painter: _PaywallBracketPainter(
                    progress: _bracketProgress.value,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ),
              // Photo flash overlay
              if (_flash.value > 0)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          Colors.white.withValues(alpha: _flash.value),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaywallBracketPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _PaywallBracketPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const pad = 4.0;
    const len = 16.0;
    final l = pad, r = size.width - pad;
    final t = pad, b = size.height - pad;

    final s = 1.0 + (1 - progress) * 0.25;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    canvas.translate(-size.width / 2, -size.height / 2);

    canvas.drawLine(Offset(l, t + len), Offset(l, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l + len, t), paint);
    canvas.drawLine(Offset(r - len, t), Offset(r, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + len), paint);
    canvas.drawLine(Offset(l, b - len), Offset(l, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l + len, b), paint);
    canvas.drawLine(Offset(r - len, b), Offset(r, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - len), paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PaywallBracketPainter old) =>
      old.progress != progress || old.color != color;
}

// ── Scene 2: Resale prices (minimal text rows, no filled chips) ───────────────

class _PricesScene extends StatefulWidget {
  const _PricesScene({super.key});

  @override
  State<_PricesScene> createState() => _PricesSceneState();
}

class _PricesSceneState extends State<_PricesScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // name · price · subtle accent (only StockX gets a hint of green)
  static const _rows = [
    ('StockX', '\$247', Color(0xFF4D9A6A)),
    ('GOAT', '\$215', Color(0xFFAAAAAA)),
    ('eBay', '\$189', Color(0xFFAAAAAA)),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 210,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Shoe name header
            AnimatedBuilder(
              animation: _ctrl,
              builder: (ctx, child) => Opacity(
                opacity: (_ctrl.value / 0.2).clamp(0.0, 1.0),
                child: Text(
                  'Air Jordan 1 Retro High OG',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.35),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Price rows
            ...List.generate(_rows.length, (i) {
              final startFrac = 0.2 + i * 0.22;
              final endFrac = startFrac + 0.28;
              return AnimatedBuilder(
                animation: _ctrl,
                builder: (ctx, child) {
                  final p = ((_ctrl.value - startFrac) /
                          (endFrac - startFrac))
                      .clamp(0.0, 1.0);
                  final eased = Curves.easeOut.transform(p);
                  return Opacity(
                    opacity: eased,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            children: [
                              Text(
                                _rows[i].$1,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color:
                                      Colors.white.withValues(alpha: 0.45),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _rows[i].$2,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: _rows[i].$3,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── Scene 3: Profit summary (outline card, muted) ─────────────────────────────

class _ProfitScene extends StatefulWidget {
  const _ProfitScene({super.key});

  @override
  State<_ProfitScene> createState() => _ProfitSceneState();
}

class _ProfitSceneState extends State<_ProfitScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _cardFade;
  late final Animation<double> _badgeFade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _cardFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );
    _badgeFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.5, 0.9, curve: Curves.easeOut),
      ),
    );
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Outline card with retail / resale rows
            Opacity(
              opacity: _cardFade.value,
              child: Container(
                width: 200,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Text(
                            'Retail',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '\$120',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.45),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Text(
                            'Resale',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '\$247',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.65),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Profit badge — outline, subtle green
            Opacity(
              opacity: _badgeFade.value,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF4D9A6A).withValues(alpha: 0.35),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '+\$127 est. profit',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: const Color(0xFF4D9A6A).withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
