import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/login_screen.dart';
import '../screens/main_screen.dart';
import '../services/mixpanel_service.dart';
import '../services/paywall_impression.dart';
import '../services/plan_pricing.dart';
import '../services/play_offers.dart';
import '../services/review_access.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

/// The paywall's one accent color: subscribe button, selected plan card,
/// radio, savings badge, checkmarks and footer links. Brand orange in place of
/// the reference design's purple, so the paywall stays on-brand.
const _accent = AppColors.brand;

/// Artwork above the headline. The app icon is a placeholder until the final
/// header image is added to assets/ (and pubspec.yaml).
const _kHeaderImage = 'assets/app_icon.png';

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

  /// Which plan card is selected. Annual by default: it's the better value
  /// and the one the savings badge points at. Only meaningful while
  /// [SubscriptionService.hasMonthlyPlan] is true — see [_effectivePlan].
  SubscriptionPlan _selectedPlan = SubscriptionPlan.annual;

  /// A monthly → annual switch started from the upgrade view. Needed because
  /// the user is already subscribed, so status never changes to tell us the
  /// purchase landed, was cancelled or failed.
  bool _upgradeInFlight = false;

  /// One `Upgrade Paywall Viewed` per display.
  bool _upgradeViewTracked = false;

  /// One RevenueCat impression per display, however many rebuilds happen.
  bool _impressionTracked = false;

  // Hidden store-review unlock: hold the subscribe button for three seconds.
  static const _holdDuration = Duration(seconds: 3);
  // Matches Flutter's kTouchSlop: enough for finger jitter across a 3s hold,
  // and the same threshold at which a scroll would take over anyway.
  static const _holdSlop = 18.0;
  Timer? _holdTimer;
  Offset? _holdOrigin;
  bool _holdFired = false;

  @override
  void initState() {
    super.initState();
    _wasActiveOnInit = _sub.isSubscribed;
    _sub.addListener(_onSubChanged);
    // Freezes the displayed price for as long as this paywall is up, so a
    // late-arriving A/B variant can't change the number under a live button.
    _sub.paywallShown();
    WidgetsBinding.instance.addObserver(this);
    MixpanelService.instance.track(
      'Paywall Viewed',
      properties: {'is_closeable': widget.isCloseable},
    );
    // Fire-and-forget: RevenueCat needs to hear about the view, but nothing on
    // this screen should wait on it.
    unawaited(_trackRevenueCatImpression());
  }

  /// Reports this display to RevenueCat, which is the only way a *custom*
  /// paywall ever counts as viewed. Without it every customer stays under
  /// "Not viewed" and filtering the price experiment by Viewed returns nobody.
  Future<void> _trackRevenueCatImpression() async {
    if (_impressionTracked) return;
    _impressionTracked = true;
    if (!_sub.revenueCatConfigured) return;

    // Both waits are already capped internally. They matter because at mount
    // `status` can still be `loading`: until the launch check settles we don't
    // know whether this user is seeing the trial timeline or the lapsed
    // feature rows, and that's exactly what the paywall id records.
    await _sub.awaitOfferings();
    await _sub.awaitLaunchCheck();

    // An active subscriber opening this from Settings was never a conversion
    // opportunity — counting them would pad the experiment's denominator.
    if (_sub.isSubscribed) return;

    // Deliberately not gated on `mounted`: the view already happened, so a fast
    // dismissal should still count.
    await trackPaywallImpression(
      paywallId: paywallIdFor(trialEligible: !_sub.isLapsedSubscriber),
      offering: _sub.assignedOffering,
    );
  }

  @override
  void dispose() {
    _cancelFallbackTimer?.cancel();
    _holdTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _sub.removeListener(_onSubChanged);
    _sub.paywallDismissed();
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
      _cancelFallbackTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) _sub.forceCancelPending();
      });
    }
  }

  void _onSubChanged() {
    if (!mounted) return;
    _cancelFallbackTimer?.cancel();
    _cancelFallbackTimer = null;
    if (_upgradeInFlight && _handleUpgradeUpdate()) return;
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

  /// Settles an in-flight monthly → annual switch. Returns true when it did,
  /// so the regular purchase handling (which ignores already-subscribed users)
  /// doesn't run too.
  bool _handleUpgradeUpdate() {
    final bought = _sub.lastPurchasedProductId;
    if (bought != null &&
        isAnnualVariantProductId(bought) &&
        !_sub.purchasePending) {
      _upgradeInFlight = false;
      MixpanelService.instance.track('Upgrade To Annual Completed');
      _finishUpgrade();
      return true;
    }
    if (_sub.purchaseCancelled) {
      _upgradeInFlight = false;
      _sub.clearCancelled();
      setState(() {});
      return true;
    }
    final error = _sub.purchaseError;
    if (error != null) {
      _upgradeInFlight = false;
      _showError(error);
      _sub.clearError();
      setState(() {});
      return true;
    }
    return false;
  }

  void _startUpgrade() {
    MixpanelService.instance.track(
      'Upgrade To Annual Tapped',
      properties: {'from_product_id': ?_sub.activeProductId},
    );
    setState(() => _upgradeInFlight = true);
    _sub.upgradeToAnnual();
  }

  /// After a successful switch: straight back to the home screen, with a
  /// brief confirmation. The snackbar lives on the app-level messenger, so it
  /// survives the route change and shows over home.
  void _finishUpgrade() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'You\'re switching to Annual. You won\'t be charged for both plans.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    _goHome();
  }

  /// Back to the home screen. Returns to the one already underneath when there
  /// is one — building a second would leave two scanners competing for the
  /// camera — and only builds a fresh one when the paywall is the app's root
  /// (launch, or after the lapse kick-out cleared the stack).
  void _goHome() {
    final home = MainScreenState.current;
    if (home != null) {
      home.returnHome();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()),
      (route) => false,
    );
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
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
                  style: GoogleFonts.inter(
                    letterSpacing: -0.5,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
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
                style: GoogleFonts.inter(
                  letterSpacing: -0.5,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You\'re already subscribed!',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.textSecondary,
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
    MixpanelService.instance.track('Purchase Completed');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
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
                style: GoogleFonts.inter(
                  letterSpacing: -0.5,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
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

  // ── Hidden store-review unlock ──────────────────────────────────────────────

  void _onSubscribePointerDown(PointerDownEvent event) {
    // Mirrors the button's own disabled condition — no unlocking mid-purchase.
    if (_sub.purchasePending && !_isRestoring) return;
    _holdFired = false;
    _holdOrigin = event.position;
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdDuration, () {
      _holdFired = true;
      HapticFeedback.heavyImpact();
      _showAccessCodeDialog();
    });
  }

  void _onSubscribePointerMove(PointerMoveEvent event) {
    final origin = _holdOrigin;
    if (origin == null) return;
    // A scroll that happens to start on the button isn't a hold.
    if ((event.position - origin).distance > _holdSlop) _cancelHold();
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdOrigin = null;
  }

  void _showAccessCodeDialog() {
    final controller = TextEditingController();
    String? error;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Access Code',
                  style: GoogleFonts.inter(
                    letterSpacing: -0.5,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: GoogleFonts.robotoMono(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: Colors.red[700],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _submitAccessCode(
                          dialogContext,
                          controller.text,
                          (message) => setDialogState(() => error = message),
                        ),
                        child: const Text('Unlock'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitAccessCode(
    BuildContext dialogContext,
    String input,
    void Function(String) onError,
  ) async {
    if (!ReviewAccess.instance.matches(input)) {
      MixpanelService.instance.track('Review Access Denied');
      onError('Invalid code');
      return;
    }

    await ReviewAccess.instance.grant();
    MixpanelService.instance.track('Review Access Granted');

    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    if (!mounted) return;
    // Entitlement getters flip on the flag, so listeners need a nudge.
    _sub.refreshEntitlement();
    // Same exit path as a real purchase — pre-login still routes to sign-in.
    _dismissPaywall();
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
        _goHome();
      }
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Opens a legal page inside the app — SFSafariViewController on iOS, a
  /// Custom Tab on Android — so the user closes it and lands back on the
  /// paywall instead of being sent off to the browser app.
  Future<void> _openInApp(String url) async {
    final uri = Uri.parse(url);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (opened) return;
    } catch (e) {
      debugPrint('[Paywall] In-app browser failed for $url: $e');
    }
    // No in-app browser available (rare on Android) — the external browser
    // still beats a dead link.
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  /// The plan the button will buy. Falls back to annual whenever the offering
  /// has no buyable monthly product, so a stale monthly selection can't
  /// leave the button pointing at nothing.
  SubscriptionPlan get _effectivePlan =>
      _sub.hasMonthlyPlan ? _selectedPlan : SubscriptionPlan.annual;

  /// The renewal price of the selected plan. Reads past any trial phase on
  /// Play, so a trial-eligible Android user gets "$59.99/year" here rather than
  /// "Free" — which used to fall through to null and leave the line on its
  /// skeleton forever.
  String? _priceLabel() => _effectivePlan == SubscriptionPlan.monthly
      ? _sub.monthlyPriceLabel
      : _sub.annualPriceLabel;

  /// "/year" or "/month", matching [_priceLabel].
  String get _pricePeriod =>
      _effectivePlan == SubscriptionPlan.monthly ? 'month' : 'year';

  /// Placeholder held at the price line's own height so the real text lands
  /// without shifting the layout under the subscribe button.
  Widget _priceSkeleton() {
    return Container(
      width: 180,
      height: 15,
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  /// The monthly → annual upgrade view.
  ///
  /// Deliberately sparse: no feature list (they already have every feature),
  /// one number to care about (the yearly saving), a side-by-side cost
  /// comparison to make it concrete, one primary action and an easy way out.
  Widget _buildUpgrade({required bool pending}) {
    final monthly = _sub.activeMonthlyProduct!;
    final annual = _sub.upgradeAnnualProduct!;
    final monthlyAmount = recurringPriceAmount(monthly);
    final annualAmount = recurringPriceAmount(annual);
    final savings = annualSavingsAmount(
      annual: annualAmount,
      monthly: monthlyAmount,
    );
    final savingsPercent = annualSavingsPercent(
      annual: annualAmount,
      monthly: monthlyAmount,
    );
    final savingsLabel = savings != null
        ? priceLabelFor(annual, savings)
        : null;
    final annualLabel = recurringPriceLabel(annual) ?? annual.price;
    final busy = pending || _upgradeInFlight;

    if (!_upgradeViewTracked) {
      _upgradeViewTracked = true;
      MixpanelService.instance.track(
        'Upgrade Paywall Viewed',
        properties: {
          'from_product_id': ?_sub.activeProductId,
          'to_product_id': annual.id,
          'savings_percent': ?savingsPercent,
        },
      );
    }

    final headlineStyle = GoogleFonts.inter(
      letterSpacing: -0.8,
      fontSize: 30,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      height: 1.15,
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        const _PaywallHeaderImage(size: 64),
                        const SizedBox(height: 20),
                        // The saving is the whole pitch, so it's in the
                        // headline itself, in the accent color.
                        Text.rich(
                          TextSpan(
                            style: headlineStyle,
                            children: [
                              const TextSpan(text: 'Switch to Annual'),
                              if (savingsLabel != null) ...[
                                const TextSpan(text: ' and save '),
                                TextSpan(
                                  text: savingsLabel,
                                  style: const TextStyle(color: _accent),
                                ),
                                const TextSpan(text: ' a year'),
                              ],
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Same unlimited access, billed once a year.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _UpgradeComparison(
                          monthlyPrice:
                              recurringPriceLabel(monthly) ?? monthly.price,
                          monthlyYearly: monthlyAmount != null
                              ? priceLabelFor(monthly, monthlyAmount * 12)
                              : null,
                          annualPrice: annualLabel,
                          annualPerMonth: perMonthPriceLabel(annual),
                          savingsPercent: savingsPercent,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // Same pinned white bar as the main paywall.
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: AppColors.divider)),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    12 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: busy ? null : _startUpgrade,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _accent.withValues(
                              alpha: 0.5,
                            ),
                            disabledForegroundColor: Colors.white.withValues(
                              alpha: 0.85,
                            ),
                            side: BorderSide.none,
                            elevation: 0,
                            // The fixed height does the vertical spacing; the
                            // theme's own padding would crowd the larger label.
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            overlayColor: Colors.white.withValues(alpha: 0.12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: busy
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Switch to Annual',
                                  style: GoogleFonts.inter(
                                    letterSpacing: -0.5,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // A plain, equally easy way out — best practice for an
                      // upsell to someone who's already paying.
                      TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                MixpanelService.instance.track(
                                  'Upgrade Paywall Dismissed',
                                );
                                Navigator.of(context).pop(false);
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                        ),
                        child: Text(
                          'Keep Monthly',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Billing disclosure: what's charged and that the plans
                      // don't stack.
                      Text(
                        '$annualLabel billed yearly. Your annual plan replaces '
                        'your monthly one, so you\'re never charged for both. '
                        'Cancel anytime.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildLinks(pending: busy),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 16,
              child: _CloseButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Restore (iOS) · Terms · Privacy — accent text, no separators.
  Widget _buildLinks({required bool pending}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (Platform.isIOS) ...[
          _LinkText(
            label: 'Restore Purchases',
            pressed: _restorePressed,
            onTap: pending
                ? null
                : () {
                    setState(() => _isRestoring = true);
                    _sub.restorePurchases();
                  },
            onPressedChanged: (v) => setState(() => _restorePressed = v),
          ),
          const SizedBox(width: 28),
        ],
        _LinkText(
          label: 'Terms',
          pressed: _termsPressed,
          onTap: () => _openInApp('https://sneakscan.com/terms'),
          onPressedChanged: (v) => setState(() => _termsPressed = v),
        ),
        const SizedBox(width: 28),
        _LinkText(
          label: 'Privacy',
          pressed: _privacyPressed,
          onTap: () => _openInApp('https://sneakscan.com/privacy'),
          onPressedChanged: (v) => setState(() => _privacyPressed = v),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isStatusLoading = _sub.status == SubscriptionStatus.loading;
    final pending = _sub.purchasePending || isStatusLoading;
    // A monthly subscriber opening the soft paywall gets a focused pitch to
    // switch to annual instead of the feature list they've already bought.
    if (widget.isCloseable && _sub.canUpgradeToAnnual) {
      return _buildUpgrade(pending: pending);
    }
    // The RevenueCat price experiment decides which product this user buys, so
    // the price isn't final until both the store query and the offerings fetch
    // land. Both are time-capped, so this can't stick on forever.
    final priceLoading = isStatusLoading || !_sub.offeringsResolved;
    final buttonLabel = isStatusLoading
        ? null // still determining status — show spinner
        : _sub.isSubscribed
        ? null // subscribed — shows badge instead
        : _sub.isLapsedSubscriber
        ? 'Get Unlimited Scans'
        : 'Start Free Trial';
    // Lapsed and active subscribers see the full feature list instead of the
    // free-trial timeline.
    final showFeatureList = _sub.isLapsedSubscriber || _sub.isSubscribed;
    final headline = showFeatureList
        ? 'Spot profits instantly with SneakScan'
        : 'Try SneakScan for FREE';
    // The plan cards make the pinned bar taller, so the scrolling content is
    // condensed to keep the pitch in view. The single-plan paywall keeps its
    // original spacing — it's the experiment's baseline.
    final showPlanPicker =
        !_sub.isSubscribed && !priceLoading && _sub.hasMonthlyPlan;
    final compact = showPlanPicker;

    return Scaffold(
      backgroundColor: AppColors.surface,
      // Bottom inset is handled by the white CTA bar so it runs to the screen edge.
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        SizedBox(height: compact ? 20 : 32),

                        _PaywallHeaderImage(size: compact ? 60 : 72),

                        SizedBox(height: compact ? 14 : 18),

                        // Headline
                        Text(
                          headline,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            letterSpacing: -0.8,
                            fontSize: compact ? 28 : 32,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.15,
                          ),
                        ),

                        SizedBox(height: compact ? 18 : 28),

                        // Trial-eligible users get the billing timeline above
                        // the checklist: the onboarding priming screen just
                        // pitched the features, and what's actually unclear at
                        // this point is when they get charged.
                        if (!showFeatureList) ...[
                          _GreyPanel(
                            padding: EdgeInsets.all(compact ? 16 : 20),
                            child: TrialTimeline(compact: compact),
                          ),
                          SizedBox(height: compact ? 12 : 16),
                        ],

                        _GreyPanel(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: compact ? 14 : 18,
                          ),
                          child: _SellingPointChecklist(compact: compact),
                        ),

                        SizedBox(height: compact ? 16 : 28),
                      ],
                    ),
                  ),
                ),

                // Pinned bottom section — solid white so the CTA sits on its
                // own surface, clear of the scrolling content above.
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: AppColors.divider)),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    16 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Plan picker — only when the assigned offering has a
                      // buyable monthly product. Otherwise this is the
                      // single-plan annual paywall, unchanged. The bar's top
                      // padding leaves room for the badge that overhangs the
                      // yearly card.
                      if (showPlanPicker) ...[
                        // Room for the badge centred on the yearly card's top
                        // edge.
                        const SizedBox(height: 6),
                        _PlanPicker(
                          annual: _sub.annualProduct!,
                          monthly: _sub.monthlyProduct!,
                          selected: _effectivePlan,
                          enabled: !(pending && !_isRestoring),
                          onSelected: (plan) {
                            if (plan == _selectedPlan) return;
                            HapticFeedback.selectionClick();
                            MixpanelService.instance.track(
                              'Paywall Plan Selected',
                              properties: {'plan': plan.name},
                            );
                            setState(() => _selectedPlan = plan);
                          },
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Reassurance line — both variants get it, with the
                      // wording that fits what they're actually agreeing to.
                      // Active subscribers are excluded: they've already
                      // subscribed, so there's nothing to reassure them about.
                      if (!_sub.isSubscribed) ...[
                        _ReassuranceLine(
                          text: _sub.isLapsedSubscriber
                              ? 'No Commitment. Cancel Anytime.'
                              : 'No Payment Due Now. Cancel Anytime.',
                        ),
                        const SizedBox(height: 12),
                      ],

                      // CTA button or subscribed badge
                      if (_sub.isSubscribed)
                        Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                color: Colors.green[700],
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'You\'re subscribed',
                                style: GoogleFonts.inter(
                                  letterSpacing: -0.5,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green[800],
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Listener(
                          onPointerDown: _onSubscribePointerDown,
                          onPointerMove: _onSubscribePointerMove,
                          onPointerUp: (_) => _cancelHold(),
                          onPointerCancel: (_) => _cancelHold(),
                          child: SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              // priceLoading also disables: buying before the
                              // A/B variant resolves would charge a price the
                              // paywall never showed. It only greys the button
                              // — the spinner stays reserved for a real pending
                              // purchase, since one on every open reads broken.
                              onPressed:
                                  ((pending && !_isRestoring) || priceLoading)
                                  ? null
                                  : () {
                                      // Releasing after a three-second hold must
                                      // not also open the real purchase sheet.
                                      if (_holdFired) return;
                                      final plan = _effectivePlan;
                                      MixpanelService.instance.track(
                                        'Subscribe Button Tapped',
                                        properties: {
                                          'plan': plan.name,
                                          'monthly_shown': _sub.hasMonthlyPlan,
                                        },
                                      );
                                      _sub.buy(plan);
                                    },
                              // The accent fill: the one solid block of color
                              // on the paywall, so the purchase is unmistakable.
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: _accent.withValues(
                                  alpha: 0.5,
                                ),
                                disabledForegroundColor: Colors.white
                                    .withValues(alpha: 0.85),
                                side: BorderSide.none,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
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
                                      style: GoogleFonts.inter(
                                        letterSpacing: -0.4,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),

                      // Pricing note for lapsed subscribers
                      if (_sub.isLapsedSubscriber) ...[
                        if (priceLoading) ...[
                          _priceSkeleton(),
                          const SizedBox(height: 12),
                        ] else if (_priceLabel() != null) ...[
                          Text(
                            '${_priceLabel()}/$_pricePeriod - Cancel Anytime',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],

                      // Trial pricing note — only for free trial eligible users
                      if (!_sub.isSubscribed && !_sub.isLapsedSubscriber) ...[
                        if (priceLoading) ...[
                          _priceSkeleton(),
                          const SizedBox(height: 12),
                        ] else if (_priceLabel() != null) ...[
                          Text(
                            '$kTrialDays day free trial then ${_priceLabel()}/$_pricePeriod',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textSecondary,
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
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      _buildLinks(pending: pending),
                    ],
                  ),
                ),
              ],
            ),

            // Close button — only shown when paywall is dismissible
            if (widget.isCloseable)
              Positioned(
                top: 8,
                right: 16,
                child: _CloseButton(
                  onPressed: pending
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// SneakScan's selling points. The priming screen's feature rows and the
/// paywall's checklist both read from this list so the two never drift apart.
const kSellingPoints = <({IconData icon, String text})>[
  (icon: Icons.all_inclusive_rounded, text: 'Unlimited scans'),
  (icon: Icons.show_chart_rounded, text: 'Live StockX & GOAT market prices'),
  (icon: Icons.sell_rounded, text: 'Sold listings on StockX, eBay and GOAT'),
  (icon: Icons.camera_alt_rounded, text: 'Label OCR & barcode scanning'),
  (icon: Icons.payments_rounded, text: 'Instant profit estimate per size'),
  (icon: Icons.history_rounded, text: 'Full history of every scan'),
];

/// Accent-checkmark list of [kSellingPoints] in the paywall's grey panel.
/// Shown on every variant — under the free-trial timeline, or on its own for
/// lapsed and active subscribers.
class _SellingPointChecklist extends StatelessWidget {
  /// Tighter rows for when the plan cards take room from the scroll area.
  final bool compact;

  const _SellingPointChecklist({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (i, point) in kSellingPoints.indexed) ...[
          if (i > 0) SizedBox(height: compact ? 10 : 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.check_rounded, color: _accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  point.text,
                  style: GoogleFonts.inter(
                    letterSpacing: -0.3,
                    fontSize: compact ? 16 : 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The rounded light-grey panel the paywall's content sits in.
class _GreyPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GreyPanel({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

/// Rounded artwork above the headline.
class _PaywallHeaderImage extends StatelessWidget {
  final double size;

  const _PaywallHeaderImage({required this.size});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.24);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(_kHeaderImage, fit: BoxFit.cover),
      ),
    );
  }
}

/// White circular close button with a soft shadow, top-right.
class _CloseButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _CloseButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: 'Close',
        onPressed: onPressed,
        icon: const Icon(
          Icons.close_rounded,
          color: AppColors.textPrimary,
          size: 24,
        ),
      ),
    );
  }
}

/// A single icon-tile + label row. Public so the onboarding paywall priming
/// screen can pitch the app in an identical visual language.
class PaywallFeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const PaywallFeatureRow({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: 22),
        ),
        const SizedBox(width: 16),
        // Expanded so a long label wraps instead of overflowing the row. The
        // paywall's own four labels happen to fit on common widths, but only
        // just — a narrow device or bumped text scale overflowed them.
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 17,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// The three-beat free-trial timeline shown to trial-eligible users in place of
/// the feature list.
///
/// Public so it can be widget-tested on its own, without standing up
/// [SubscriptionService] and Firebase — same reason [PaywallFeatureRow] is.
class TrialTimeline extends StatelessWidget {
  /// Smaller tiles and shorter rails for when the plan cards take room from
  /// the scroll area.
  final bool compact;

  const TrialTimeline({super.key, this.compact = false});

  static const _ink = AppColors.textPrimary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TimelineNode(
          compact: compact,
          icon: Icons.lock_open_rounded,
          color: _ink,
          title: 'Today',
          body: 'Your free trial starts',
        ),
        // Explicit connector segments rather than a Stack/IntrinsicHeight rail:
        // heights stay predictable inside the paywall's SingleChildScrollView,
        // and each segment carries its own slice of the fade.
        _TimelineConnector(fromAlpha: 1.0, toAlpha: 0.6, compact: compact),
        _TimelineNode(
          compact: compact,
          icon: Icons.notifications_active_rounded,
          color: _ink,
          title: 'In ${kTrialDays - 1} days',
          body: 'We\'ll remind you 1 day before your free trial ends',
        ),
        _TimelineConnector(fromAlpha: 0.6, toAlpha: 0.25, compact: compact),
        _TimelineNode(
          compact: compact,
          // Muted: the charge hasn't happened, and saying so plainly is the
          // whole reassurance this timeline exists to deliver.
          icon: Icons.workspace_premium_rounded,
          color: null,
          title: 'In $kTrialDays days',
          body: 'Your subscription starts unless you cancelled beforehand',
        ),
      ],
    );
  }
}

class _TimelineNode extends StatelessWidget {
  final IconData icon;

  /// Null renders the muted state used for the not-yet-reached final beat.
  final Color? color;
  final String title;
  final String body;
  final bool compact;

  const _TimelineNode({
    this.compact = false,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  /// The icon tile's side; the connector centres its rail under it.
  static double tileSize(bool compact) => compact ? 50 : 58;

  @override
  Widget build(BuildContext context) {
    final accent = color;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Deliberately larger than PaywallFeatureRow's 44pt tile: the timeline
        // is the only content on the trial variant, so it carries the screen
        // rather than sitting in a list.
        Container(
          width: _TimelineNode.tileSize(compact),
          height: _TimelineNode.tileSize(compact),
          decoration: BoxDecoration(
            // White for the muted beat, so it still reads as a tile on the
            // grey panel.
            color: accent ?? AppColors.surface,
            borderRadius: BorderRadius.circular(compact ? 13 : 15),
          ),
          child: Icon(
            icon,
            color: accent == null ? AppColors.outline : Colors.white,
            size: compact ? 26 : 30,
          ),
        ),
        SizedBox(width: compact ? 16 : 18),
        // Expanded so the long middle line wraps instead of overflowing.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  letterSpacing: -0.5,
                  fontSize: compact ? 18 : 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(
                body,
                style: GoogleFonts.inter(
                  fontSize: compact ? 15 : 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary.withValues(alpha: 0.65),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The rail between two nodes, fading as it runs down the timeline.
class _TimelineConnector extends StatelessWidget {
  final double fromAlpha;
  final double toAlpha;
  final bool compact;

  const _TimelineConnector({
    required this.fromAlpha,
    required this.toAlpha,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          // Centred under the icon tile above it.
          margin: EdgeInsets.only(
            left: _TimelineNode.tileSize(compact) / 2 - 2,
          ),
          width: 4,
          height: compact ? 22 : 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                TrialTimeline._ink.withValues(alpha: fromAlpha),
                TrialTimeline._ink.withValues(alpha: toAlpha),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Annual and monthly plan cards, side by side, in the pinned bottom bar.
class _PlanPicker extends StatelessWidget {
  final ProductDetails annual;
  final ProductDetails monthly;
  final SubscriptionPlan selected;
  final bool enabled;
  final ValueChanged<SubscriptionPlan> onSelected;

  const _PlanPicker({
    required this.annual,
    required this.monthly,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final annualAmount = recurringPriceAmount(annual);
    final monthlyAmount = recurringPriceAmount(monthly);
    final annualLabel = recurringPriceLabel(annual) ?? annual.price;
    final monthlyLabel = recurringPriceLabel(monthly) ?? monthly.price;
    final savings = annualSavingsPercent(
      annual: annualAmount,
      monthly: monthlyAmount,
    );

    final annualCaption = annualAmount != null
        ? '$annualLabel billed annually'
        : null;

    // Re-measures when a font finishes loading: Inter arrives at runtime, and
    // a size measured against the fallback font could overflow once it lands.
    return ListenableBuilder(
      listenable: PaintingBinding.instance.systemFonts,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          // The billed line must stay on one line so the cards stay the same
          // height. Measure the yearly one (the longer of the two) at the card's
          // real width and, only if it doesn't fit, shrink both captions by the
          // same amount so they keep matching.
          final cardWidth = (constraints.maxWidth - _gap) / 2;
          final captionSize = _PlanCard.fittedCaptionSize(
            annualCaption ?? 'billed monthly',
            maxWidth: cardWidth - _PlanCard.horizontalInset,
            textScaler: MediaQuery.textScalerOf(context),
          );
          return _buildRow(
            annualAmount: annualAmount,
            annualLabel: annualLabel,
            annualCaption: annualCaption,
            monthlyLabel: monthlyLabel,
            savings: savings,
            captionSize: captionSize,
          );
        },
      ),
    );
  }

  static const _gap = 12.0;

  Widget _buildRow({
    required double? annualAmount,
    required String annualLabel,
    required String? annualCaption,
    required String monthlyLabel,
    required int? savings,
    required double captionSize,
  }) {
    // IntrinsicHeight so both cards match the taller one; it's two short
    // cards, so the extra layout pass is cheap.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PlanCard(
              title: 'Yearly',
              // Per-month rate, so the two cards compare like for like, with
              // the billed amount on the line below. Falls back to the billed
              // price when the store gave no number to divide.
              price: switch (perMonthPriceLabel(annual)) {
                final perMonth? => '$perMonth/mo',
                null => '$annualLabel/yr',
              },
              caption: annualCaption,
              captionSize: captionSize,
              badge: savings != null ? 'SAVE $savings%' : null,
              selected: selected == SubscriptionPlan.annual,
              onTap: enabled ? () => onSelected(SubscriptionPlan.annual) : null,
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: _PlanCard(
              title: 'Monthly',
              price: '$monthlyLabel/mo',
              caption: 'billed monthly',
              captionSize: captionSize,
              selected: selected == SubscriptionPlan.monthly,
              onTap: enabled
                  ? () => onSelected(SubscriptionPlan.monthly)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;

  /// Small secondary line under [price], e.g. what's actually billed.
  final String? caption;

  /// Shared by both cards — see [fittedCaptionSize].
  final double captionSize;
  final String? badge;
  final bool selected;
  final VoidCallback? onTap;

  const _PlanCard({
    required this.title,
    required this.price,
    this.caption,
    this.captionSize = _captionBaseSize,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  static const _captionBaseSize = 13.0;
  static const _minCaptionSize = 10.0;
  static const _border = 2.0;
  static const _padLeft = 12.0;
  static const _padRight = 8.0;

  /// Horizontal space a card takes away from its caption: borders + padding.
  static const horizontalInset = _border * 2 + _padLeft + _padRight;

  static TextStyle _captionStyle(double size) => GoogleFonts.inter(
    fontSize: size,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.25,
  );

  /// The largest caption size, up to 13, at which [text] fits on one line in
  /// [maxWidth]. Never below 10 — past that it ellipsizes rather than
  /// becoming unreadable.
  static double fittedCaptionSize(
    String text, {
    required double maxWidth,
    required TextScaler textScaler,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _captionStyle(_captionBaseSize)),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    if (width <= maxWidth || width == 0) return _captionBaseSize;
    // A hair under the exact ratio, so rounding can't push it back over.
    final fitted = (_captionBaseSize * maxWidth / width) - 0.1;
    return fitted.clamp(_minCaptionSize, _captionBaseSize);
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(12);
    return Semantics(
      button: true,
      selected: selected,
      label: [title, price, ?caption, ?badge].join(', '),
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: borderRadius,
              border: Border.all(
                color: selected ? _accent : AppColors.outline,
                width: _border,
              ),
              // A soft accent glow lifts the selected card off the bar.
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: borderRadius,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _padLeft,
                    14,
                    _padRight,
                    12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Fixed sizes, no scale-to-fit: both cards' text
                          // must render at the same size.
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    letterSpacing: -0.3,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  price,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    letterSpacing: -0.3,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          _PlanRadio(selected: selected),
                        ],
                      ),
                      if (caption != null) ...[
                        const SizedBox(height: 10),
                        // One line, always: the picker sizes this so the
                        // yearly line fits, keeping both cards the same height.
                        Text(
                          caption!,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: _captionStyle(captionSize),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              top: -12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanRadio extends StatelessWidget {
  final bool selected;

  const _PlanRadio({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? _accent : Colors.transparent,
        // Selected: accent disc with a white ring and a soft shadow.
        // Unselected: a plain grey ring.
        border: Border.all(
          color: selected ? Colors.white : AppColors.outline,
          width: selected ? 2.5 : 2,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}

/// Current monthly cost vs annual, stacked, for the upgrade view. The monthly
/// row shows what they pay over a year, struck through, so the gap to the
/// annual price is visible at a glance.
class _UpgradeComparison extends StatelessWidget {
  final String monthlyPrice;
  final String? monthlyYearly;
  final String annualPrice;
  final String? annualPerMonth;
  final int? savingsPercent;

  const _UpgradeComparison({
    required this.monthlyPrice,
    required this.monthlyYearly,
    required this.annualPrice,
    required this.annualPerMonth,
    required this.savingsPercent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row(
          label: 'Monthly',
          tag: 'Your plan',
          price: monthlyYearly != null ? '$monthlyYearly/yr' : monthlyPrice,
          detail: monthlyYearly != null ? '$monthlyPrice/mo' : null,
          highlighted: false,
        ),
        const SizedBox(height: 14),
        Stack(
          clipBehavior: Clip.none,
          children: [
            _row(
              label: 'Annual',
              price: '$annualPrice/yr',
              detail: annualPerMonth != null ? '$annualPerMonth/mo' : null,
              highlighted: true,
            ),
            if (savingsPercent != null)
              Positioned(
                top: -12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'SAVE $savingsPercent%',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _row({
    required String label,
    String? tag,
    required String price,
    String? detail,
    required bool highlighted,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? _accent : AppColors.outline,
          width: 2,
        ),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    letterSpacing: -0.3,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (tag != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    tag,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: GoogleFonts.inter(
                  letterSpacing: -0.3,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  // The current plan's yearly cost, struck through: the
                  // number the annual plan beats.
                  color: highlighted
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  decoration: highlighted ? null : TextDecoration.lineThrough,
                  decorationColor: AppColors.textSecondary,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The green-badge reassurance line above the subscribe button.
class _ReassuranceLine extends StatelessWidget {
  final String text;

  const _ReassuranceLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.verified_rounded, color: Color(0xFF22C55E), size: 16),
        const SizedBox(width: 6),
        // Flexible rather than fixed: the line is centred, and at large text
        // scales it needs to wrap instead of overflowing the bottom bar.
        Flexible(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Footer link: accent text, dimmed while pressed.
class _LinkText extends StatelessWidget {
  final String label;
  final bool pressed;

  /// Null disables the link (e.g. Restore while a purchase is pending).
  final VoidCallback? onTap;
  final ValueChanged<bool> onPressedChanged;

  const _LinkText({
    required this.label,
    required this.pressed,
    required this.onTap,
    required this.onPressedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      onTapDown: enabled ? (_) => onPressedChanged(true) : null,
      onTapUp: enabled ? (_) => onPressedChanged(false) : null,
      onTapCancel: enabled ? () => onPressedChanged(false) : null,
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _accent.withValues(alpha: pressed ? 0.55 : 1),
        ),
      ),
    );
  }
}
