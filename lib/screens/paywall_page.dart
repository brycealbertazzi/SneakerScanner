import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/login_screen.dart';
import '../screens/main_screen.dart';
import '../services/mixpanel_service.dart';
import '../services/paywall_impression.dart';
import '../services/review_access.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

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
      builder: _darkDialog((ctx) {
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
      }),
    );
  }

  void _showRestoredDialog() {
    if (_restoredDialogShowing) return;
    _restoredDialogShowing = true;
    showDialog(
      context: context,
      builder: _darkDialog(
        (ctx) => Dialog(
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
      builder: _darkDialog(
        (ctx) => Dialog(
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
      builder: _darkDialog(
        (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Access Code',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF252525),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFBA6A37)),
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey[400],
                            side: BorderSide(color: Colors.grey[600]!),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFBA6A37),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
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

  /// The renewal price. Reads past any trial phase on Play, so a trial-eligible
  /// Android user gets "$59.99/year" here rather than "Free" — which used to
  /// fall through to null and leave the line on its skeleton forever.
  String? _priceLabel() => _sub.annualPriceLabel;

  /// Placeholder held at the price line's own height so the real text lands
  /// without shifting the layout under the subscribe button.
  Widget _priceSkeleton() {
    return Container(
      width: 180,
      height: 15,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DarkThemeScope(builder: _buildDark);

  /// Dialogs are shown from this State's context, which sits above the
  /// [DarkThemeScope] in [build], so they need the dark theme applied again.
  WidgetBuilder _darkDialog(WidgetBuilder builder) =>
      (_) => Theme(
        data: AppTheme.dark,
        child: Builder(builder: builder),
      );

  Widget _buildDark(BuildContext context) {
    final isStatusLoading = _sub.status == SubscriptionStatus.loading;
    final pending = _sub.purchasePending || isStatusLoading;
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
    final headline = (_sub.isLapsedSubscriber || _sub.isSubscribed)
        ? 'Spot profits instantly with SneakScan'
        : 'How Your Free Trial Works';

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
                      const Color(0xFFBA6A37).withValues(alpha: 0.18),
                      const Color(0xFFBA6A37).withValues(alpha: 0.07),
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
                        const SizedBox(height: 36),

                        // Outside the trial/lapsed branch below — both variants
                        // get the same trust anchor before the pitch.
                        const PaywallSocialProof(),

                        const SizedBox(height: 28),

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

                        const SizedBox(height: 32),

                        // Trial-eligible users get the billing timeline instead
                        // of the feature list: the onboarding priming screen
                        // just pitched the features, and what's actually unclear
                        // at this point is when they get charged.
                        if (_sub.isLapsedSubscriber || _sub.isSubscribed) ...[
                          PaywallFeatureRow(
                            icon: Icons.all_inclusive_rounded,
                            iconColor: const Color(0xFFBA6A37),
                            text: 'Unlimited scans',
                          ),
                          const SizedBox(height: 22),
                          PaywallFeatureRow(
                            icon: Icons.show_chart_rounded,
                            iconColor: Colors.green,
                            text: 'Live StockX & GOAT market prices',
                          ),
                          const SizedBox(height: 22),
                          PaywallFeatureRow(
                            icon: Icons.sell_rounded,
                            iconColor: Colors.orange,
                            text: 'eBay sold listings with fees',
                          ),
                          const SizedBox(height: 22),
                          PaywallFeatureRow(
                            icon: Icons.camera_alt_rounded,
                            iconColor: Colors.blue,
                            text: 'OCR label & barcode scanning',
                          ),
                        ] else
                          const TrialTimeline(),

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
                        Listener(
                          onPointerDown: _onSubscribePointerDown,
                          onPointerMove: _onSubscribePointerMove,
                          onPointerUp: (_) => _cancelHold(),
                          onPointerCancel: (_) => _cancelHold(),
                          child: Container(
                            width: double.infinity,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: const Color(0xFFBA6A37),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFBA6A37,
                                  ).withValues(alpha: 0.45),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
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
                                      MixpanelService.instance.track(
                                        'Subscribe Button Tapped',
                                      );
                                      _sub.buyAnnual();
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(
                                  0xFFBA6A37,
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
                        ),
                      const SizedBox(height: 12),

                      // Pricing note for lapsed subscribers
                      if (_sub.isLapsedSubscriber) ...[
                        if (priceLoading) ...[
                          _priceSkeleton(),
                          const SizedBox(height: 12),
                        ] else if (_priceLabel() != null) ...[
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
                        if (priceLoading) ...[
                          _priceSkeleton(),
                          const SizedBox(height: 12),
                        ] else if (_priceLabel() != null) ...[
                          Text(
                            '$kTrialDays day free trial then ${_priceLabel()}/year',
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

/// A single icon-tile + label row. Public so the onboarding paywall priming
/// screen can pitch the app in an identical visual language.
class PaywallFeatureRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;

  const PaywallFeatureRow({
    super.key,
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
        // Expanded so a long label wraps instead of overflowing the row. The
        // paywall's own four labels happen to fit on common widths, but only
        // just — a narrow device or bumped text scale overflowed them.
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 17,
              color: Colors.white,
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
  const TrialTimeline({super.key});

  static const _brand = Color(0xFFBA6A37);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _TimelineNode(
          icon: Icons.lock_open_rounded,
          color: _brand,
          title: 'Today',
          body: 'Your free trial starts',
        ),
        // Explicit connector segments rather than a Stack/IntrinsicHeight rail:
        // heights stay predictable inside the paywall's SingleChildScrollView,
        // and each segment carries its own slice of the fade.
        const _TimelineConnector(fromAlpha: 1.0, toAlpha: 0.6),
        _TimelineNode(
          icon: Icons.notifications_active_rounded,
          color: _brand,
          title: 'In ${kTrialDays - 1} days',
          body: 'We\'ll remind you 1 day before your free trial ends',
        ),
        const _TimelineConnector(fromAlpha: 0.6, toAlpha: 0.25),
        _TimelineNode(
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

  const _TimelineNode({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

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
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: accent == null
                ? Colors.white.withValues(alpha: 0.06)
                : accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: accent ?? Colors.grey[500], size: 30),
        ),
        const SizedBox(width: 18),
        // Expanded so the long middle line wraps instead of overflowing.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.65),
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

  const _TimelineConnector({required this.fromAlpha, required this.toAlpha});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          // Centred under the 58pt tile above it.
          margin: const EdgeInsets.only(left: 27),
          width: 4,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                TrialTimeline._brand.withValues(alpha: fromAlpha),
                TrialTimeline._brand.withValues(alpha: toAlpha),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Five-star trust anchor above the paywall headline, shown on both the
/// trial-timeline and the lapsed/subscribed variants.
///
/// Public so it can be widget-tested on its own, without standing up
/// [SubscriptionService] and Firebase — same reason [PaywallFeatureRow] and
/// [TrialTimeline] are.
class PaywallSocialProof extends StatelessWidget {
  const PaywallSocialProof({super.key});

  /// Amber rather than the brand orange: the top glow and the CTA are both
  /// #BA6A37, so orange stars would blend into them and stop reading as a
  /// rating at all.
  static const _star = Color(0xFFFFC107);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (_) => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 1),
              child: Icon(Icons.star_rounded, color: _star, size: 18),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '\u201CIt paid for itself after just one flip\u201D',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ),
      ],
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
              color: Colors.grey[400],
            ),
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
