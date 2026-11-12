import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_keys.dart';
import '../services/annual_nudge_service.dart';
import '../services/mixpanel_service.dart';
import '../services/plan_pricing.dart';
import '../services/play_offers.dart';
import '../services/stockx_auth_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import 'demo/demo_controller.dart';
import 'paywall_page.dart';
import 'scanner_page.dart';
import 'history_page.dart';
import 'settings_page.dart';
import 'tutorial_sheet.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  /// The home screen that's currently mounted, if any. Lets a screen pushed on
  /// top (e.g. the paywall) return to it instead of building a second one —
  /// two home screens means two scanners fighting over the one camera, which
  /// is what left the preview broken after switching plans.
  static MainScreenState? _current;
  static MainScreenState? get current {
    final home = _current;
    return home != null && home.mounted ? home : null;
  }

  int _currentIndex = 0;
  late AppLinks _appLinks;
  final ValueNotifier<bool> _scannerActive = ValueNotifier(true);
  bool _wasSubscribed = false;

  /// Annual-switch prompt: one check at a time. Which prompt (if any) is due
  /// is decided by [AnnualNudgeService]; each shows at most once ever.
  bool _nudgeCheckRunning = false;

  /// Debug bypass only: once per launch, so testing isn't a popup on every
  /// return to the app.
  static bool _debugNudgedThisLaunch = false;

  @override
  void initState() {
    super.initState();
    _current = this;
    _wasSubscribed = SubscriptionService.instance.canScan;
    SubscriptionService.instance.addListener(_onSubChanged);
    WidgetsBinding.instance.addObserver(this);
    _loadApiKeys();
    SubscriptionService.instance.initialize();
    _maybeShowTutorial();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeNudgeAnnual());
    _appLinks = AppLinks();
    _appLinks.uriLinkStream.listen((Uri uri) {
      debugPrint('[StockX OAuth] Deep link received: $uri');
      if (uri.scheme == 'sneakerscanner' && uri.host == 'stockx-callback') {
        final code = uri.queryParameters['code'];
        if (code != null) {
          debugPrint('[StockX OAuth] Authorization code received');
          _exchangeStockXCode(code);
        }
      }
    });
  }

  static const _tutorialSeenKey = 'has_seen_tutorial';
  static const _demoSeenKey = 'has_seen_demo';

  /// First open after install: Quick Tips, then the guided demo. Both are
  /// one-shot and neither is offered to installs that predate them.
  Future<void> _maybeShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_tutorialSeenKey) ?? false) {
      // Already knows the app — don't drop a 2-minute demo on them at update.
      await prefs.setBool(_demoSeenKey, true);
      return;
    }
    if (!mounted) return;
    await prefs.setBool(_tutorialSeenKey, true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    await showTutorialSheet(context);

    if (!mounted || (prefs.getBool(_demoSeenKey) ?? false)) return;
    // Written up front so a force-quit mid-demo can't re-trap them next launch.
    await prefs.setBool(_demoSeenKey, true);
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    await DemoController.instance.start(context, switchTab: switchToTab);
  }

  Future<void> _loadApiKeys() async {
    final success = await ApiKeys.fetch();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load API keys. Some features may not work.'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _exchangeStockXCode(String code) async {
    final success = await StockXAuthService.exchangeCode(code);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'StockX connected successfully!'
                : 'Failed to connect StockX. Please try again.',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SubscriptionService.instance.recheckSubscription();
      // A milestone can pass while the app sits in the background.
      _maybeNudgeAnnual();
    }
  }

  /// Monthly subscribers: at a week into their first paid month and two
  /// weeks into their second, offer the switch to annual. Checked when the
  /// home screen loads and whenever the app comes back to the foreground; the
  /// milestone rules live in [AnnualNudgeService].
  Future<void> _maybeNudgeAnnual() async {
    final bypass = AnnualNudgeService.debugBypass;
    if (_nudgeCheckRunning || (bypass && _debugNudgedThisLaunch)) return;
    _nudgeCheckRunning = true;
    try {
      final sub = SubscriptionService.instance;
      await sub.awaitLaunchCheck();
      await sub.awaitOfferings();
      await sub.awaitUpgradeReady();
      if (!mounted || !sub.canUpgradeToAnnual) return;
      // Never in the session they bought in — they just chose monthly.
      if (sub.lastPurchasedProductId != null && !bypass) return;

      AnnualNudgeMilestone? milestone;
      DateTime? firstPayment;
      if (bypass) {
        debugPrint('[AnnualNudge] Debug bypass on — skipping milestone rules');
      } else {
        firstPayment = await sub.monthlyFirstPaymentDate();
        if (AnnualNudgeService.timing.isSandbox) {
          debugPrint(
            '[AnnualNudge] Sandbox timing — first payment: $firstPayment',
          );
        }
        if (firstPayment == null) return;
        milestone = await AnnualNudgeService.dueNow(firstPayment);
        if (AnnualNudgeService.timing.isSandbox) {
          debugPrint('[AnnualNudge] Sandbox timing — due: ${milestone?.name}');
        }
        if (milestone == null) return;
      }

      // Only over the home screen itself — never on top of a scan result,
      // Settings, the paywall or another dialog.
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;

      final monthly = sub.activeMonthlyProduct;
      final annual = sub.upgradeAnnualProduct;
      if (monthly == null || annual == null) return;
      final savings = annualSavingsAmount(
        annual: recurringPriceAmount(annual),
        monthly: recurringPriceAmount(monthly),
      );
      if (savings == null) return;

      if (milestone != null && firstPayment != null) {
        await AnnualNudgeService.recordShown(milestone, firstPayment);
      }
      if (bypass) _debugNudgedThisLaunch = true;
      MixpanelService.instance.track(
        'Annual Nudge Shown',
        properties: {
          'milestone': milestone?.name ?? 'debug',
          'from_product_id': monthly.id,
        },
      );
      if (!mounted) return;
      _showAnnualNudge(
        monthlyPrice: recurringPriceLabel(monthly) ?? monthly.price,
        savings: priceLabelFor(annual, savings) ?? '',
      );
    } catch (e) {
      debugPrint('[AnnualNudge] Check failed: $e');
    } finally {
      _nudgeCheckRunning = false;
    }
  }

  void _showAnnualNudge({
    required String monthlyPrice,
    required String savings,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Save $savings a year',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  letterSpacing: -0.6,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You\'re paying $monthlyPrice a month. Switch to Annual and '
                'get the same unlimited access for less.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    MixpanelService.instance.track(
                      'Annual Nudge Switch Tapped',
                    );
                    Navigator.of(dialogContext).pop();
                    // The soft paywall opens straight on the upgrade view for
                    // a monthly subscriber.
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => const PaywallPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    side: BorderSide.none,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    overlayColor: Colors.white.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Switch to Annual',
                    style: GoogleFonts.inter(
                      letterSpacing: -0.4,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () {
                  MixpanelService.instance.track('Annual Nudge Dismissed');
                  Navigator.of(dialogContext).pop();
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
                child: Text(
                  'Dismiss',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onSubChanged() {
    if (!mounted) return;
    final canScan = SubscriptionService.instance.canScan;
    if (_wasSubscribed && !canScan) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const PaywallPage(isCloseable: false),
        ),
        (route) => false,
      );
    }
    _wasSubscribed = canScan;
  }

  @override
  void dispose() {
    if (_current == this) _current = null;
    WidgetsBinding.instance.removeObserver(this);
    SubscriptionService.instance.removeListener(_onSubChanged);
    _scannerActive.dispose();
    super.dispose();
  }

  /// Pops every route above this home screen and shows the scanner tab.
  /// The scanner restarts its own camera when it's uncovered (didPopNext).
  void returnHome() {
    final route = ModalRoute.of(context);
    if (route != null) {
      Navigator.of(context).popUntil((r) => r == route);
    }
    switchToTab(0);
  }

  void switchToTab(int index) {
    _scannerActive.value = index == 0;
    setState(() {
      _currentIndex = index;
    });
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SettingsPage()));
  }

  @override
  Widget build(BuildContext context) {
    // The demo is non-skippable, so the Android back button can't be allowed to
    // pop out of MainScreen while it's running.
    return ListenableBuilder(
      listenable: DemoController.instance,
      builder: (context, child) =>
          PopScope(canPop: !DemoController.instance.isActive, child: child!),
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: GestureDetector(
              onTap: _openSettings,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.buttonBorder),
                  boxShadow: AppColors.buttonShadow(),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      // Pages scroll behind the floating tab bar.
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ScannerPage(activeNotifier: _scannerActive),
          const HistoryPage(),
        ],
      ),
      bottomNavigationBar: _FloatingNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          _scannerActive.value = index == 0;
          setState(() => _currentIndex = index);
          if (index == 1) {
            // Small beat so the tab transition lands before the spotlight moves.
            Future.delayed(const Duration(milliseconds: 250), () {
              DemoController.instance.handleEvent(DemoEvent.historyTabOpened);
            });
          }
        },
        items: [
          const _NavItem(icon: Icons.qr_code_scanner, label: 'Scan'),
          _NavItem(
            icon: Icons.history,
            label: 'History',
            demoKey: DemoKeys.key(DemoTarget.historyTab),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label, this.demoKey});

  final IconData icon;
  final String label;

  /// Marks the whole tab (not just its icon) so the demo spotlight matches
  /// the tab's pill shape.
  final Key? demoKey;
}

/// Nike-style floating white pill with a gray pill behind the selected tab.
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;

  static const _duration = Duration(milliseconds: 280);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final count = items.length;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // One shared pill that slides to the selected tab, so only the
              // tapped tab changes instead of one fading out as another fades in.
              Positioned.fill(
                child: AnimatedAlign(
                  duration: _duration,
                  curve: _curve,
                  alignment: Alignment(
                    count > 1 ? -1 + 2 * currentIndex / (count - 1) : 0,
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / count,
                    heightFactor: 1,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.selectedPill,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: _NavButton(
                        item: items[i],
                        selected: i == currentIndex,
                        onTap: () => onTap(i),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: item.demoKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, color: AppColors.textPrimary, size: 26),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: _FloatingNavBar._duration,
                curve: _FloatingNavBar._curve,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                child: Text(item.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
