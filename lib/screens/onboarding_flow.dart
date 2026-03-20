import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/subscription_service.dart';
import 'login_screen.dart';
import 'main_screen.dart';
import 'paywall_page.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _showAnalysis = false;

  @override
  void initState() {
    super.initState();
    // Start the subscription check as early as possible — well before the
    // analysis screen opens — so the status (freeTrial vs cancelled) is
    // resolved by the time we route to the paywall. Without this, if product
    // loading takes longer than the analysis animation (~3 s), awaitLaunchCheck
    // could return prematurely with status = loading, causing a lapsed
    // subscriber to incorrectly see "Start Free Trial".
    SubscriptionService.instance.initialize();
  }

  void _next() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      setState(() => _showAnalysis = true);
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    final Widget destination;
    if (SubscriptionService.instance.canScan) {
      // Already subscribed — skip paywall, ensure signed in before app.
      destination = user != null ? const MainScreen() : const LoginScreen();
    } else {
      // Not subscribed — paywall first, then sign in if needed.
      destination = PaywallPage(isCloseable: false, isPreLogin: user == null);
    }
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showAnalysis) {
      return _AnalysisScreen(onComplete: _completeOnboarding);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Page indicator dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF646CFF)
                        : const Color(0xFF646CFF).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _Page1(onNext: _next),
                  _Page2(onNext: _next),
                  _Page3(onNext: _next),
                  _Page4(onNext: _next),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared page layout ────────────────────────────────────────────────────────

class _OnboardingPageLayout extends StatelessWidget {
  final Widget visual;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onNext;
  final double visualHeight;

  const _OnboardingPageLayout({
    required this.visual,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onNext,
    this.visualHeight = 210,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const Spacer(flex: 2),
          SizedBox(height: visualHeight, child: Center(child: visual)),
          const Spacer(flex: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: Colors.grey[400],
              height: 1.6,
            ),
          ),
          const Spacer(flex: 3),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF646CFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Text(
                buttonLabel,
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }
}

// ── Page 1: Camera viewfinder ─────────────────────────────────────────────────

class _Page1 extends StatefulWidget {
  final VoidCallback onNext;
  const _Page1({required this.onNext});

  @override
  State<_Page1> createState() => _Page1State();
}

class _Page1State extends State<_Page1> with TickerProviderStateMixin {
  late final AnimationController _bracketCtrl;
  late final AnimationController _scanCtrl;
  late final Animation<double> _bracketProgress;
  late final Animation<double> _labelFade;
  late final Animation<double> _scanPos;

  @override
  void initState() {
    super.initState();
    _bracketCtrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _scanCtrl = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );

    _bracketProgress = CurvedAnimation(
      parent: _bracketCtrl,
      curve: Curves.easeOut,
    );
    _labelFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _bracketCtrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _scanPos = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _scanCtrl, curve: Curves.easeInOut));

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _bracketCtrl.forward().then((_) {
        if (mounted) _scanCtrl.repeat(reverse: true);
      });
    });
  }

  @override
  void dispose() {
    _bracketCtrl.dispose();
    _scanCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageLayout(
      visual: AnimatedBuilder(
        animation: Listenable.merge([_bracketCtrl, _scanCtrl]),
        builder: (context, _) => _ViewfinderWidget(
          bracketProgress: _bracketProgress.value,
          labelFade: _labelFade.value,
          scanPos: _scanPos.value,
        ),
      ),
      title: 'Scan any sneaker\ninstantly',
      description:
          'Point your camera at a sneaker box label. '
          'The app instantly identifies the shoe and retrieves current resale data.',
      buttonLabel: 'Continue',
      onNext: widget.onNext,
    );
  }
}

class _ViewfinderWidget extends StatelessWidget {
  final double bracketProgress;
  final double labelFade;
  final double scanPos;

  const _ViewfinderWidget({
    required this.bracketProgress,
    required this.labelFade,
    required this.scanPos,
  });

  @override
  Widget build(BuildContext context) {
    const w = 230.0;
    const h = 155.0;
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          // Sneaker label card
          Opacity(
            opacity: labelFade,
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.directions_run_rounded,
                        color: Color(0xFF646CFF),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'NIKE AIR JORDAN 1',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'STYLE: 553558-174',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 10,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'COLOR: WHITE/BLACK-RED',
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 9,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  // Barcode
                  SizedBox(
                    height: 28,
                    child: Row(
                      children: List.generate(
                        24,
                        (i) => Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 0.4),
                            color: i % 3 == 0
                                ? Colors.white.withValues(alpha: 0.55)
                                : i % 2 == 0
                                ? Colors.white.withValues(alpha: 0.25)
                                : Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Center(
                    child: Text(
                      '036204133593',
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 8,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Corner brackets
          Positioned.fill(
            child: CustomPaint(
              painter: _BracketPainter(
                progress: bracketProgress,
                color: const Color(0xFF646CFF),
              ),
            ),
          ),
          // Scan line (only after brackets have appeared)
          if (bracketProgress > 0.8)
            Positioned(
              left: 10,
              right: 10,
              top: 10 + scanPos * (h - 20),
              child: Opacity(
                opacity: 0.75,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0xFF646CFF),
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF646CFF).withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _BracketPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: progress.clamp(0.0, 1.0))
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const pad = 5.0;
    const len = 18.0;
    final l = pad;
    final r = size.width - pad;
    final t = pad;
    final b = size.height - pad;

    // Scale from 130% → 100% as progress goes 0 → 1
    final s = 1.0 + (1 - progress) * 0.3;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    canvas.translate(-size.width / 2, -size.height / 2);

    // Top-left
    canvas.drawLine(Offset(l, t + len), Offset(l, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l + len, t), paint);
    // Top-right
    canvas.drawLine(Offset(r - len, t), Offset(r, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + len), paint);
    // Bottom-left
    canvas.drawLine(Offset(l, b - len), Offset(l, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l + len, b), paint);
    // Bottom-right
    canvas.drawLine(Offset(r - len, b), Offset(r, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - len), paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BracketPainter old) => old.progress != progress;
}

// ── Page 2: Resale prices ─────────────────────────────────────────────────────

class _PlatformData {
  final String name;
  final int price;
  final Color color;
  final IconData icon;
  const _PlatformData(this.name, this.price, this.color, this.icon);
}

const _kPlatforms = [
  _PlatformData('StockX', 247, Color(0xFF22C55E), Icons.trending_up_rounded),
  _PlatformData('GOAT', 215, Color(0xFFE63946), Icons.directions_run_rounded),
  _PlatformData('eBay', 189, Color(0xFFE6AC00), Icons.local_offer_rounded),
];

class _Page2 extends StatefulWidget {
  final VoidCallback onNext;
  const _Page2({required this.onNext});

  @override
  State<_Page2> createState() => _Page2State();
}

class _Page2State extends State<_Page2> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    );
    Future.delayed(const Duration(milliseconds: 300), () {
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
    return _OnboardingPageLayout(
      visual: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_kPlatforms.length, (i) {
                final slideStart = 0.05 + i * 0.22;
                final slideEnd = slideStart + 0.25;
                final t = _ctrl.value;
                final slideP = ((t - slideStart) / (slideEnd - slideStart))
                    .clamp(0.0, 1.0);
                // Ease the slide progress
                final easedSlide = Curves.easeOut.transform(slideP);

                final priceStart = 0.35 + i * 0.18;
                final priceEnd = priceStart + 0.25;
                final priceP = ((t - priceStart) / (priceEnd - priceStart))
                    .clamp(0.0, 1.0);
                final displayPrice = (_kPlatforms[i].price * priceP).round();

                return Opacity(
                  opacity: easedSlide,
                  child: Transform.translate(
                    offset: Offset(-28 * (1 - easedSlide), 0),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _kPlatforms[i].color.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              _kPlatforms[i].icon,
                              color: _kPlatforms[i].color,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _kPlatforms[i].name,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Text(
                            '\$$displayPrice',
                            style: GoogleFonts.poppins(
                              color: _kPlatforms[i].color,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
      title: 'See resale prices\nacross platforms',
      description:
          'Compare what sneakers are selling for across StockX, GOAT, '
          'and eBay in seconds. All in one place.',
      buttonLabel: 'Next',
      onNext: widget.onNext,
    );
  }
}

// ── Page 3: Profit pop ────────────────────────────────────────────────────────

class _Page3 extends StatefulWidget {
  final VoidCallback onNext;
  const _Page3({required this.onNext});

  @override
  State<_Page3> createState() => _Page3State();
}

class _Page3State extends State<_Page3> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _profitFade;
  late final Animation<double> _chipsFade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _scale = TweenSequence(
      [
        TweenSequenceItem(tween: Tween(begin: 0.3, end: 1.15), weight: 60),
        TweenSequenceItem(tween: Tween(begin: 1.15, end: 0.95), weight: 20),
        TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 20),
      ],
    ).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.85)));
    _profitFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
      ),
    );
    _chipsFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.55, 0.9, curve: Curves.easeOut),
      ),
    );

    Future.delayed(const Duration(milliseconds: 400), () {
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
    return _OnboardingPageLayout(
      visual: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Retail price chip
              Opacity(
                opacity: _chipsFade.value,
                child: _PriceChip(label: 'Retail', value: '\$120'),
              ),
              const SizedBox(height: 20),
              // Profit amount with bounce
              Opacity(
                opacity: _profitFade.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '+\$127',
                        style: GoogleFonts.poppins(
                          fontSize: 64,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF22C55E),
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'EST. PROFIT',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF22C55E).withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // StockX price chip
              Opacity(
                opacity: _chipsFade.value,
                child: _PriceChip(label: 'StockX', value: '\$247'),
              ),
            ],
          );
        },
      ),
      title: 'Know the profit\nbefore you buy',
      description:
          'See the potential profit instantly based on current resale prices. '
          'Know if a flip is worth it before you spend a dollar.',
      buttonLabel: 'Get Started',
      onNext: widget.onNext,
    );
  }
}

class _PriceChip extends StatelessWidget {
  final String label;
  final String value;
  const _PriceChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(fontSize: 14, color: Colors.white54),
          children: [
            TextSpan(text: '$label  →  '),
            TextSpan(
              text: value,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 4: Flip profit stats ─────────────────────────────────────────────────

class _FlipCardData {
  final String name;
  final String profit;
  const _FlipCardData(this.name, this.profit);
}

const _kFlipCards = [
  _FlipCardData('Jordan 1 Retro', '+\$85'),
  _FlipCardData('Yeezy Boost 350', '+\$110'),
  _FlipCardData('Nike Dunk Low', '+\$47'),
];

class _Page4 extends StatefulWidget {
  final VoidCallback onNext;
  const _Page4({required this.onNext});

  @override
  State<_Page4> createState() => _Page4State();
}

class _Page4State extends State<_Page4> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    Future.delayed(const Duration(milliseconds: 300), () {
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
    return _OnboardingPageLayout(
      visual: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;

          // Stat ($40 – $120) fade-in
          final statP = ((t - 0.62) / 0.25).clamp(0.0, 1.0);
          final statEased = Curves.easeOut.transform(statP);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Profit range stat with glow
              Opacity(
                opacity: statEased,
                child: Text(
                  '\$40 – \$120',
                  style: GoogleFonts.poppins(
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF22C55E),
                    height: 1,
                    shadows: [
                      Shadow(
                        color: const Color(
                          0xFF22C55E,
                        ).withValues(alpha: 0.55 * statEased),
                        blurRadius: 24,
                      ),
                      Shadow(
                        color: const Color(
                          0xFF22C55E,
                        ).withValues(alpha: 0.25 * statEased),
                        blurRadius: 48,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Flip cards stacking up
              ...List.generate(_kFlipCards.length, (i) {
                final start = 0.05 + i * 0.19;
                final end = start + 0.22;
                final p = ((t - start) / (end - start)).clamp(0.0, 1.0);
                final eased = Curves.easeOut.transform(p);
                return Opacity(
                  opacity: eased,
                  child: Transform.translate(
                    offset: Offset(0, 18 * (1 - eased)),
                    child: Container(
                      width: 280,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF22C55E,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.directions_run_rounded,
                              color: Color(0xFF22C55E),
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _kFlipCards[i].name,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            _kFlipCards[i].profit,
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF22C55E),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
      visualHeight: 270,
      title: 'Average sneaker\nflip profit',
      description: '',
      buttonLabel: 'Next',
      onNext: widget.onNext,
    );
  }
}

// ── Analysis screen ───────────────────────────────────────────────────────────

class _AnalysisScreen extends StatefulWidget {
  final Future<void> Function() onComplete;
  const _AnalysisScreen({required this.onComplete});

  @override
  State<_AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<_AnalysisScreen>
    with SingleTickerProviderStateMixin {
  static const _steps = [
    'Detecting sneaker label',
    'Extracting SKU',
    'Matching sneaker database',
    'Checking StockX sales',
    'Checking GOAT listings',
    'Checking eBay sold prices',
    'Calculating profit',
  ];

  // 200ms initial delay + 350ms per step = ~2500ms for all steps
  // 700ms pause after last step → ~3200ms total before navigating
  static const _stepDelay = 350;
  static const _initialDelay = 200;
  static const _pauseAfterLastStep = 700;

  int _visibleSteps = 0;
  late final AnimationController _progressCtrl;

  @override
  void initState() {
    super.initState();

    final totalAnimMs =
        _initialDelay + (_steps.length - 1) * _stepDelay + _pauseAfterLastStep;

    _progressCtrl = AnimationController(
      duration: Duration(milliseconds: totalAnimMs),
      vsync: this,
    );

    // Show steps one by one
    for (int i = 0; i < _steps.length; i++) {
      Future.delayed(
        Duration(milliseconds: _initialDelay + i * _stepDelay),
        () {
          if (mounted) setState(() => _visibleSteps = i + 1);
        },
      );
    }

    _progressCtrl.forward();

    // Navigate after all steps appear + pause
    Future.delayed(Duration(milliseconds: totalAnimMs), () async {
      if (!mounted) return;
      await SubscriptionService.instance.awaitLaunchCheck();
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sneaker icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF646CFF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.directions_run_rounded,
                    color: Color(0xFF646CFF),
                    size: 36,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Scanning sneaker\ndatabase…',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 32),
                // Progress bar
                AnimatedBuilder(
                  animation: _progressCtrl,
                  builder: (context, _) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progressCtrl.value,
                        backgroundColor: const Color(0xFF1A1A2E),
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFF646CFF),
                        ),
                        minHeight: 6,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                // Steps
                ...List.generate(
                  _steps.length,
                  (i) => _AnalysisStep(
                    label: _steps[i],
                    visible: i < _visibleSteps,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalysisStep extends StatelessWidget {
  final String label;
  final bool visible;
  const _AnalysisStep({required this.label, required this.visible});

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(-0.4, 0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 280),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF22C55E),
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
