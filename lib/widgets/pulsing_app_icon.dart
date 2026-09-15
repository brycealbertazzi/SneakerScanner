import 'package:flutter/material.dart';

/// The SneakScan sneaker app icon, breathing on a slow scale pulse.
///
/// Shared by the splash screen, the onboarding intro and the onboarding
/// analysis screen so the brand mark looks and moves the same everywhere.
class PulsingAppIcon extends StatefulWidget {
  const PulsingAppIcon({super.key, this.size = 120});

  final double size;

  @override
  State<PulsingAppIcon> createState() => _PulsingAppIconState();
}

class _PulsingAppIconState extends State<PulsingAppIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween<double>(
    begin: 0.92,
    end: 1.05,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // iOS-style squircle proportion: corner radius is ~20% of the side.
    final radius = widget.size * 0.2;
    return ScaleTransition(
      scale: _scale,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: widget.size * 0.15,
              offset: Offset(0, widget.size * 0.04),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.asset(
            'assets/app_icon.png',
            width: widget.size,
            height: widget.size,
          ),
        ),
      ),
    );
  }
}
