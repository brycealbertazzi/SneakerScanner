import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'paywall_page.dart';
import '../theme/app_theme.dart';

/// Full-value pitch shown at the end of onboarding, immediately before the
/// analysis animation that leads into [PaywallPage].
///
/// Deliberately styled as the paywall's twin — same black ground, same brand
/// glow, same [PaywallFeatureRow]s, same pinned bottom bar — so the two screens
/// read as one continuous moment rather than two separate asks. It carries no
/// trial or pricing language and no lapsed-subscriber branch; the paywall two
/// screens later already handles all of that.
///
/// Only shown to users who are about to see the paywall — see the gating in
/// `_OnboardingFlowState._onContinue`.
class PaywallPrimingScreen extends StatelessWidget {
  final VoidCallback onContinue;

  const PaywallPrimingScreen({super.key, required this.onContinue});

  static const _brand = Color(0xFFBA6A37);

  @override
  Widget build(BuildContext context) => DarkThemeScope(builder: _buildDark);

  Widget _buildDark(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Top-center brand glow — matches PaywallPage.
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
                      _brand.withValues(alpha: 0.18),
                      _brand.withValues(alpha: 0.07),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                // Scrollable content — six rows plus the band overflow on
                // smaller phones, so the CTA lives outside this and stays put.
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        const SizedBox(height: 44),

                        const _MarketplaceBand(),

                        const SizedBox(height: 28),

                        Text(
                          'Everything you need to find the most profitable sneaker flips',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 36),

                        const PaywallFeatureRow(
                          icon: Icons.all_inclusive_rounded,
                          iconColor: _brand,
                          text: 'Unlimited scans',
                        ),
                        const SizedBox(height: 22),
                        const PaywallFeatureRow(
                          icon: Icons.show_chart_rounded,
                          iconColor: Colors.green,
                          text: 'Live StockX & GOAT market prices',
                        ),
                        const SizedBox(height: 22),
                        const PaywallFeatureRow(
                          icon: Icons.sell_rounded,
                          iconColor: Colors.orange,
                          text: 'eBay sold comps with fees included',
                        ),
                        const SizedBox(height: 22),
                        const PaywallFeatureRow(
                          icon: Icons.camera_alt_rounded,
                          iconColor: Colors.blue,
                          text: 'Label OCR & barcode scanning',
                        ),
                        const SizedBox(height: 22),
                        const PaywallFeatureRow(
                          icon: Icons.payments_rounded,
                          iconColor: Color(0xFF22C55E),
                          text: 'Instant profit estimate per size',
                        ),
                        const SizedBox(height: 22),
                        const PaywallFeatureRow(
                          icon: Icons.history_rounded,
                          iconColor: Color(0xFF8B7CF6),
                          text: 'Full history of every scan',
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),

                // Pinned bottom bar — matches PaywallPage's.
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A1A),
                    border: Border(
                      top: BorderSide(color: Color(0xFF333333), width: 1),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
                  child: _PrimingCta(onPressed: onContinue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The marketplaces the app actually prices against. Deliberately factual
/// rather than a star rating or testimonial — there is no real review data to
/// draw on, and invented social proof isn't worth shipping.
///
/// Breathes: a slow scale-and-glow pulse in the brand orange, so the first
/// thing on the screen draws the eye without shouting.
class _MarketplaceBand extends StatefulWidget {
  const _MarketplaceBand();

  @override
  State<_MarketplaceBand> createState() => _MarketplaceBandState();
}

class _MarketplaceBandState extends State<_MarketplaceBand>
    with SingleTickerProviderStateMixin {
  static const _brand = PaywallPrimingScreen._brand;

  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        return Transform.scale(
          // Deliberately small — enough to read as a heartbeat, not enough to
          // shift the headline below it.
          scale: 1.0 + 0.035 * t,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.06 + 0.04 * t),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _brand.withValues(alpha: 0.28 + 0.22 * t),
              ),
              boxShadow: [
                BoxShadow(
                  color: _brand.withValues(alpha: 0.16 + 0.22 * t),
                  blurRadius: 16 + 14 * t,
                  spreadRadius: 1 + 2 * t,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      // Static subtree — built once, not on every animation frame.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'StockX · GOAT · eBay',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Live market data',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

/// Same geometry and glow as the paywall's subscribe button, with the press
/// scale of the onboarding footer button.
class _PrimingCta extends StatefulWidget {
  final VoidCallback onPressed;

  const _PrimingCta({required this.onPressed});

  @override
  State<_PrimingCta> createState() => _PrimingCtaState();
}

class _PrimingCtaState extends State<_PrimingCta> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.heavyImpact();
        widget.onPressed();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeInOut,
        child: Container(
          width: double.infinity,
          height: 64,
          decoration: BoxDecoration(
            color: PaywallPrimingScreen._brand,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: PaywallPrimingScreen._brand.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            'Start Finding Flips',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
