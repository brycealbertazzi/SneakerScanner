import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Tutorial tip data ─────────────────────────────────────────────────────────

class _TipData {
  final String title;
  final String body;
  const _TipData({required this.title, required this.body});
}

const _kTips = [
  _TipData(
    title: 'Scan Nike & Jordan first',
    body:
        'Nike and Jordan shoes have the richest resale data. Look for the swoosh or Jumpman logo on the box — these are your best flips.',
  ),
  _TipData(
    title: 'Find the SKU on the box',
    body:
        'Find it on the side label of the box. Nike/Jordan: DZ5485-612 · Adidas: HQ4234 · Asics: 1011B548-001 · New Balance: M990GL6 · Vans: VN0A4U39 · Puma: 384857-01',
  ),
  _TipData(
    title: 'Watch out for OCR mix-ups',
    body:
        'The camera can confuse I with 1, O with 0, and B with 8. If your result looks off, tap "Enter Code" to type the SKU manually.',
  ),
  _TipData(
    title: 'SKU not found? Try the barcode',
    body:
        'If the label scan comes up empty, try scanning the barcode on the label with the live camera.',
  ),
  _TipData(
    title: 'Good lighting = better scans',
    body:
        'Lay the box flat, hold your phone steady, and find good light. Avoid glare on shiny box surfaces for the most accurate reads.',
  ),
];

// ── Public entry point ────────────────────────────────────────────────────────

Future<void> showTutorialSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.70),
    builder: (_) => const _TutorialSheet(),
  );
}

// ── Sheet widget ──────────────────────────────────────────────────────────────

class _TutorialSheet extends StatefulWidget {
  const _TutorialSheet();

  @override
  State<_TutorialSheet> createState() => _TutorialSheetState();
}

class _TutorialSheetState extends State<_TutorialSheet> {
  final _pageCtrl = PageController();
  int _current = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.heavyImpact();
    if (_current < _kTips.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _current == _kTips.length - 1;

    return PopScope(
      canPop: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Header row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Quick Tips',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${_current + 1} / ${_kTips.length}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Dot indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_kTips.length, (i) {
                final active = i == _current;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF646CFF)
                        : Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),

            const SizedBox(height: 8),

            // Tip cards
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _current = i),
                itemCount: _kTips.length,
                itemBuilder: (_, i) => _TipCard(tip: _kTips[i], index: i),
              ),
            ),

            // Footer button
            Container(
              padding: EdgeInsets.fromLTRB(24, 14, 24, 32 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
              ),
              child: _PressableButton(
                label: isLast ? 'Got it' : 'Next',
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tip card ──────────────────────────────────────────────────────────────────

class _TipCard extends StatefulWidget {
  final _TipData tip;
  final int index;
  const _TipCard({required this.tip, required this.index});

  @override
  State<_TipCard> createState() => _TipCardState();
}

class _TipCardState extends State<_TipCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    switch (widget.index) {
      case 0:
        _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 1400))
          ..repeat(reverse: true);
      case 1:
        _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 2800))
          ..repeat();
      case 2:
        _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 1800))
          ..repeat(reverse: true);
      case 3:
        _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 2000))
          ..repeat();
      default:
        _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 2000))
          ..repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 130,
            width: double.infinity,
            child: _buildVisual(),
          ),
          const SizedBox(height: 28),
          Text(
            widget.tip.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.tip.body,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.65),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisual() {
    switch (widget.index) {
      case 0:
        return _TrophyVisual(ctrl: _ctrl);
      case 1:
        return _LabelVisual(ctrl: _ctrl);
      case 2:
        return _OcrVisual(ctrl: _ctrl);
      case 3:
        return _BarcodeVisual(ctrl: _ctrl);
      default:
        return _SunVisual(ctrl: _ctrl);
    }
  }
}

// ── Tip 0: Trophy pulse ───────────────────────────────────────────────────────

class _TrophyVisual extends StatelessWidget {
  final AnimationController ctrl;
  const _TrophyVisual({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 0.90, end: 1.10)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    final glow = Tween<double>(begin: 0.0, end: 0.22)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));

    return Center(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (_, child) => Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: scale.value * 1.9,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF646CFF).withValues(alpha: glow.value),
                ),
              ),
            ),
            Transform.scale(
              scale: scale.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF646CFF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFF646CFF),
                  size: 40,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tip 1: SKU typing ─────────────────────────────────────────────────────────

class _LabelVisual extends StatelessWidget {
  final AnimationController ctrl;
  const _LabelVisual({required this.ctrl});

  static const _sku = 'DZ5485-612';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (_, child) {
          // type in for first 70% of cycle, hold for 20%, blank for 10%
          final t = ctrl.value;
          int charCount;
          if (t < 0.70) {
            charCount = (t / 0.70 * _sku.length).floor().clamp(0, _sku.length);
          } else if (t < 0.90) {
            charCount = _sku.length;
          } else {
            charCount = 0;
          }
          final displayed = _sku.substring(0, charCount);
          final showCursor = charCount < _sku.length;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF151520),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF4D9A6A).withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STYLE CODE',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    letterSpacing: 1.6,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayed,
                      style: GoogleFonts.robotoMono(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF4D9A6A),
                      ),
                    ),
                    if (showCursor)
                      Container(
                        width: 2,
                        height: 28,
                        color: const Color(0xFF4D9A6A),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Tip 2: OCR swap ───────────────────────────────────────────────────────────

class _OcrVisual extends StatelessWidget {
  final AnimationController ctrl;
  const _OcrVisual({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (_, child) {
          final t = ctrl.value; // 0→1→0 (reverse repeat)
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _OcrPair(from: 'I', to: '1', t: t),
              const SizedBox(width: 14),
              _OcrPair(from: 'O', to: '0', t: t),
              const SizedBox(width: 14),
              _OcrPair(from: 'B', to: '8', t: t),
            ],
          );
        },
      ),
    );
  }
}

class _OcrPair extends StatelessWidget {
  final String from;
  final String to;
  final double t;
  const _OcrPair({required this.from, required this.to, required this.t});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFE6AC00);
    final showingTo = t > 0.5;
    final fadeT = showingTo ? (t - 0.5) * 2 : 1.0 - t * 2;
    final char = showingTo ? to : from;
    final label = showingTo ? 'read as' : 'actual';

    return Container(
      width: 66,
      height: 90,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Opacity(
            opacity: fadeT.clamp(0.0, 1.0),
            child: Text(
              char,
              style: GoogleFonts.robotoMono(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: showingTo ? Colors.redAccent : color,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9,
              color: color.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tip 3: Barcode scan line ──────────────────────────────────────────────────

class _BarcodeVisual extends StatelessWidget {
  final AnimationController ctrl;
  const _BarcodeVisual({required this.ctrl});

  static const _bars = [
    3.0, 1.0, 2.0, 1.0, 4.0, 1.0, 2.0, 3.0, 1.0, 2.0,
    1.0, 3.0, 2.0, 1.0, 4.0, 1.0, 2.0, 1.0, 3.0, 2.0,
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (_, child) {
          return SizedBox(
            width: 200,
            height: 110,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  // Barcode bars
                  CustomPaint(
                    size: const Size(200, 110),
                    painter: _BarcodePainter(_bars),
                  ),
                  // Scan line
                  Positioned(
                    top: ctrl.value * 90,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 2.5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            const Color(0xFF64B5F6).withValues(alpha: 0.9),
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF64B5F6).withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  final List<double> bars;
  const _BarcodePainter(this.bars);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.18);
    final scale = (size.width - 16) / bars.fold(0.0, (s, w) => s + w * 6 + 2);
    double x = 8;
    bool dark = true;
    for (final w in bars) {
      final barW = w * 6 * scale;
      if (dark) {
        canvas.drawRect(Rect.fromLTWH(x, 10, barW, size.height - 20), paint);
      }
      x += barW + 2 * scale;
      dark = !dark;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Tip 4: Sun expanding rings ────────────────────────────────────────────────

class _SunVisual extends StatelessWidget {
  final AnimationController ctrl;
  const _SunVisual({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (_, child) {
          final t = ctrl.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring — expands and fades
              Opacity(
                opacity: (math.sin(t * math.pi) * 0.30).clamp(0.0, 1.0),
                child: Container(
                  width: 80 + t * 40,
                  height: 80 + t * 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.6), width: 1.5),
                  ),
                ),
              ),
              // Middle ring
              Opacity(
                opacity: (math.sin((t + 0.3) * math.pi) * 0.45).clamp(0.0, 1.0),
                child: Container(
                  width: 60 + t * 25,
                  height: 60 + t * 25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orange.withValues(alpha: 0.06),
                    border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.4), width: 1),
                  ),
                ),
              ),
              // Sun icon (static centre)
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orange.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.wb_sunny_rounded,
                    color: Colors.orange, size: 34),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Pressable button ──────────────────────────────────────────────────────────

class _PressableButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  const _PressableButton({required this.label, required this.onPressed});

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeInOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF646CFF),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
