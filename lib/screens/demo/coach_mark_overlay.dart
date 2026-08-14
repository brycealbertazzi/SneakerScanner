import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'demo_controller.dart';

const _accent = Color(0xFFBA6A37);
const _cardColor = Color(0xFF1A1A1A);
const _borderColor = Color(0xFF333333);

/// Full-screen scrim with a spotlight cut out over the current demo target.
///
/// Every tap outside the spotlight is swallowed. On action steps the spotlight
/// itself falls through to the real widget underneath so the user presses the
/// actual button.
class CoachMarkOverlay extends StatefulWidget {
  const CoachMarkOverlay({super.key});

  @override
  State<CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<CoachMarkOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _intro;

  /// Rect the spotlight is currently drawn at, eased toward the live target so
  /// it glides between steps and follows dialogs as they animate in.
  Rect? _displayRect;
  DateTime? _unresolvedSince;

  DemoController get _demo => DemoController.instance;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    _pulse.addListener(_syncRect);
    _demo.addListener(_onStepChanged);
  }

  @override
  void dispose() {
    _demo.removeListener(_onStepChanged);
    _pulse.removeListener(_syncRect);
    _pulse.dispose();
    _intro.dispose();
    super.dispose();
  }

  void _onStepChanged() {
    if (!mounted) return;
    HapticFeedback.selectionClick();
    setState(() {
      _unresolvedSince = null;
      _displayRect = null;
    });
  }

  /// Re-measures the target every frame. Cheap, and it means the spotlight
  /// tracks dialogs, tab switches and scrolls without any extra plumbing.
  void _syncRect() {
    if (!_demo.isActive) return;
    final target = _demo.step.target;
    final live = target == null ? null : DemoKeys.rectOf(target);

    if (live == null) {
      _displayRect = null;
      _unresolvedSince ??= DateTime.now();
      return;
    }

    _unresolvedSince = null;
    final padded = _demo.step.holePadding.inflateRect(live);
    _displayRect = _displayRect == null
        ? padded
        : Rect.lerp(_displayRect!, padded, 0.28);
  }

  /// A spotlit action step whose target never appeared would trap the user, so
  /// after a grace period it falls back to a Next button.
  bool get _actionStalled {
    final step = _demo.step;
    if (!step.isAction || step.target == null) return false;
    final since = _unresolvedSince;
    return since != null &&
        DateTime.now().difference(since) > const Duration(seconds: 4);
  }

  @override
  Widget build(BuildContext context) {
    if (!_demo.isActive) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final step = _demo.step;
        final hole = _displayRect;
        final intro = Curves.easeOut.transform(_intro.value);
        // The spotlight on an action step is the only thing in the whole app
        // that can be pressed while the demo runs.
        final passThrough = (step.isAction && !_actionStalled) ? hole : null;

        return Stack(
          children: [
            Positioned.fill(
              child: _HoleAbsorber(
                passThrough: passThrough,
                child: CustomPaint(
                  painter: _SpotlightPainter(
                    hole: hole,
                    radius: step.holeRadius,
                    pulse: _pulse.value,
                    scrimOpacity: 0.58 * intro,
                    ringOpacity: intro,
                  ),
                ),
              ),
            ),
            _positionCard(
              context,
              step,
              hole,
              Opacity(opacity: intro, child: _card(step)),
            ),
          ],
        );
      },
    );
  }

  /// Places the card clear of the spotlight — below it when there's room,
  /// otherwise above, falling back to the step's own alignment.
  Widget _positionCard(
    BuildContext context,
    DemoStep step,
    Rect? hole,
    Widget card,
  ) {
    const margin = 16.0;
    const gap = 14.0;
    const estimatedHeight = 210.0;

    final media = MediaQuery.of(context);

    if (hole == null) {
      return Align(
        alignment: step.cardAlignment,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            margin,
            media.padding.top + margin,
            margin,
            media.padding.bottom + margin,
          ),
          child: card,
        ),
      );
    }

    final spaceBelow = media.size.height - hole.bottom - media.padding.bottom;
    final spaceAbove = hole.top - media.padding.top;

    if (spaceBelow >= estimatedHeight) {
      return Positioned(
        left: margin,
        right: margin,
        top: hole.bottom + gap,
        child: card,
      );
    }
    if (spaceAbove >= estimatedHeight) {
      return Positioned(
        left: margin,
        right: margin,
        bottom: media.size.height - hole.top + gap,
        child: card,
      );
    }
    return Align(
      alignment: step.cardAlignment,
      child: Padding(padding: const EdgeInsets.all(margin), child: card),
    );
  }

  Widget _card(DemoStep step) {
    final showNext = !step.isAction || _actionStalled;

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              step.title,
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              step.body,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                height: 1.5,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 18),
            if (showNext) _nextButton() else _actionHint(step),
          ],
        ),
      ),
    );
  }

  Widget _nextButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          HapticFeedback.mediumImpact();
          _demo.next();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _demo.isLastStep ? 'Start Scanning' : 'Next',
              style: GoogleFonts.poppins(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _actionHint(DemoStep step) {
    // Breathes in time with the spotlight ring so the two read as one cue.
    final glow =
        0.55 + 0.45 * (0.5 + 0.5 * math.cos(_pulse.value * 2 * math.pi));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accent.withValues(alpha: 0.35 * glow)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.touch_app_rounded,
            size: 18,
            color: _accent.withValues(alpha: glow),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step.actionHint!,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scrim ─────────────────────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  final double radius;
  final double pulse;
  final double scrimOpacity;
  final double ringOpacity;

  const _SpotlightPainter({
    required this.hole,
    required this.radius,
    required this.pulse,
    required this.scrimOpacity,
    required this.ringOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: scrimOpacity);
    final full = Offset.zero & size;
    final cutout = hole;

    if (cutout == null) {
      canvas.drawRect(full, scrim);
      return;
    }

    final rrect = RRect.fromRectAndRadius(cutout, Radius.circular(radius));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(full),
        Path()..addRRect(rrect),
      ),
      scrim,
    );

    // Expanding ring that fades as it grows.
    final t = Curves.easeOut.transform(pulse);
    final spread = 10 * t;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        cutout.inflate(2 + spread),
        Radius.circular(radius + 2 + spread),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _accent.withValues(alpha: (1 - t) * 0.8 * ringOpacity),
    );

    // Steady outline so the target stays legible between pulses.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _accent.withValues(alpha: 0.9 * ringOpacity),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => true;
}

// ── Hit testing ───────────────────────────────────────────────────────────────

/// Absorbs every pointer event except those inside [passThrough], which fall
/// through to whatever is rendered beneath the overlay.
class _HoleAbsorber extends SingleChildRenderObjectWidget {
  final Rect? passThrough;

  const _HoleAbsorber({required this.passThrough, required Widget super.child});

  @override
  _RenderHoleAbsorber createRenderObject(BuildContext context) =>
      _RenderHoleAbsorber(passThrough);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHoleAbsorber renderObject,
  ) {
    renderObject.passThrough = passThrough;
  }
}

class _RenderHoleAbsorber extends RenderProxyBox {
  _RenderHoleAbsorber(this._passThrough);

  Rect? _passThrough;
  set passThrough(Rect? value) => _passThrough = value;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final hole = _passThrough;
    if (hole != null && hole.contains(position)) return false;
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  bool hitTestSelf(Offset position) => true;
}
