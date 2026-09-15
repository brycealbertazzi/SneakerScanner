import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'paywall_page.dart';
import '../theme/app_theme.dart';

/// Full-value pitch shown at the end of onboarding, immediately before the
/// analysis animation that leads into [PaywallPage].
///
/// Deliberately styled as the paywall's twin — same light ground, same
/// outlined card of [PaywallFeatureRow]s, same bottom CTA — so the two screens
/// read as one continuous moment rather than two separate asks. It carries no
/// trial or pricing language and no lapsed-subscriber branch; the paywall two
/// screens later already handles all of that.
///
/// Only shown to users who are about to see the paywall — see the gating in
/// `_OnboardingFlowState._onContinue`.
class PaywallPrimingScreen extends StatelessWidget {
  final VoidCallback onContinue;

  const PaywallPrimingScreen({super.key, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
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

                        Text(
                          'Everything you need to find the most profitable sneaker flips',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            letterSpacing: -0.5,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 36),

                        AppCard(
                          outlined: true,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              for (final (i, point)
                                  in kSellingPoints.indexed) ...[
                                if (i > 0) const SizedBox(height: 22),
                                PaywallFeatureRow(
                                  icon: point.icon,
                                  text: point.text,
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),

                // Pinned bottom CTA — matches PaywallPage's.
                Padding(
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

/// Same white pill as the paywall's subscribe button, with the press scale of
/// the onboarding footer button.
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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.buttonBorder),
            boxShadow: AppColors.buttonShadow(pressed: _pressed),
          ),
          alignment: Alignment.center,
          child: Text(
            'Start Finding Flips',
            style: GoogleFonts.inter(
              letterSpacing: -0.5,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
