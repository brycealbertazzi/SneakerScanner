import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Nike-app-inspired palette for the main app: light gray canvas, white
/// rounded surfaces, black type and controls.
class AppColors {
  AppColors._();

  static const background = Color(0xFFF5F5F5);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF111111);
  static const textSecondary = Color(0xFF707072);
  static const divider = Color(0xFFE5E5E5);
  static const selectedPill = Color(0xFFEDEDED);
  static const outline = Color(0xFFCACACB);
  static const accent = textPrimary;

  /// Profit green that stays legible on white.
  static const profit = Color(0xFF1E8E3E);

  /// Hairline around white buttons so their edge reads on every side, not
  /// just where the drop shadow falls.
  static const buttonBorder = Color(0xFFDADADA);

  /// Soft, nearly centred shadow for white buttons, visible all the way around.
  static List<BoxShadow> buttonShadow({bool pressed = false}) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: pressed ? 0.06 : 0.10),
      blurRadius: pressed ? 6 : 12,
      offset: Offset(0, pressed ? 1 : 2),
    ),
  ];

  static final cardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  /// SneakScan brand orange. Used sparingly: card outlines on the paywall and
  /// onboarding, and selected onboarding answers.
  static const brand = Color(0xFFE66B25);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData.light();
    final text = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );
    TextStyle? heading(TextStyle? s, FontWeight w) =>
        s?.copyWith(fontWeight: w, letterSpacing: -0.5);

    return base.copyWith(
      primaryColor: AppColors.accent,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.accent,
        onPrimary: Colors.white,
        secondary: AppColors.accent,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        outline: AppColors.outline,
        outlineVariant: AppColors.divider,
      ),
      textTheme: text.copyWith(
        displayLarge: heading(text.displayLarge, FontWeight.w800),
        displayMedium: heading(text.displayMedium, FontWeight.w800),
        displaySmall: heading(text.displaySmall, FontWeight.w800),
        headlineLarge: heading(text.headlineLarge, FontWeight.w800),
        headlineMedium: heading(text.headlineMedium, FontWeight.w700),
        headlineSmall: heading(text.headlineSmall, FontWeight.w700),
        titleLarge: heading(text.titleLarge, FontWeight.w700),
        titleMedium: heading(text.titleMedium, FontWeight.w700),
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: AppColors.textPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.surface.withValues(alpha: 0.6)
                : AppColors.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.textSecondary
                : AppColors.textPrimary,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.textSecondary
                : AppColors.textPrimary,
          ),
          overlayColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: 0.05),
          ),
          elevation: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? 0 : 1,
          ),
          // White-on-gray needs an edge on every side; elevation alone only
          // shades the bottom. Colored buttons opt out with BorderSide.none.
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? AppColors.buttonBorder.withValues(alpha: 0.5)
                  : AppColors.buttonBorder,
            ),
          ),
          shadowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: 0.35),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          disabledForegroundColor: AppColors.textSecondary,
          side: const BorderSide(color: AppColors.outline),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.textSecondary,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: GoogleFonts.inter(color: AppColors.textSecondary),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondary),
        // Only `border` is themed: an enabled/focused border here would win
        // over fields that set just `border` locally (e.g. InputBorder.none).
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider),
      dividerColor: AppColors.divider,
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.textPrimary
              : AppColors.outline,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.textPrimary,
        selectionHandleColor: AppColors.textPrimary,
      ),
    );
  }
}

/// White rounded card with a soft shadow — the main-app content block.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = 16,
    this.onTap,
    this.outlined = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final VoidCallback? onTap;

  /// Adds the brand-orange outline used on paywall and onboarding cards.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    Widget content = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: content,
        ),
      );
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: borderRadius,
        boxShadow: AppColors.cardShadow,
        border: outlined
            ? Border.all(color: AppColors.brand, width: 1.5)
            : null,
      ),
      child: content,
    );
  }
}
