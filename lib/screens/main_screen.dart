import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_links/app_links.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_keys.dart';
import '../services/stockx_auth_service.dart';
import '../services/subscription_service.dart';
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
  int _currentIndex = 0;
  late AppLinks _appLinks;
  final ValueNotifier<bool> _scannerActive = ValueNotifier(true);
  late final StreamSubscription<User?> _userSub;
  bool _wasSubscribed = false;

  @override
  void initState() {
    super.initState();
    // Rebuild avatar whenever user profile changes (displayName, photoURL, etc.)
    _userSub = FirebaseAuth.instance.userChanges().listen((_) {
      if (mounted) setState(() {});
    });
    _wasSubscribed = SubscriptionService.instance.canScan;
    SubscriptionService.instance.addListener(_onSubChanged);
    WidgetsBinding.instance.addObserver(this);
    _loadApiKeys();
    SubscriptionService.instance.initialize();
    _maybeShowTutorial();
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
          content: Text(success
              ? 'StockX connected successfully!'
              : 'Failed to connect StockX. Please try again.'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SubscriptionService.instance.recheckSubscription();
    }
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
    WidgetsBinding.instance.removeObserver(this);
    SubscriptionService.instance.removeListener(_onSubChanged);
    _userSub.cancel();
    _scannerActive.dispose();
    super.dispose();
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
      builder: (context, child) => PopScope(
        canPop: !DemoController.instance.isActive,
        child: child!,
      ),
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
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _openSettings,
              child: Builder(builder: (context) {
                final user = FirebaseAuth.instance.currentUser;
                final photoUrl = user?.photoURL;
                final displayName = user?.displayName ??
                    user?.email?.split('@').first;
                return Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: photoUrl != null
                        ? Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildDefaultAvatar(displayName),
                          )
                        : _buildDefaultAvatar(displayName),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ScannerPage(activeNotifier: _scannerActive),
          const HistoryPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
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
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: const Color(0xFFBA6A37),
        unselectedItemColor: Colors.grey[600],
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            // Keyed on the inactive icon only: BottomNavigationBar can build
            // icon and activeIcon at once, and a GlobalKey can't be mounted
            // twice. History is unselected when the demo spotlights it.
            icon: KeyedSubtree(
              key: DemoKeys.key(DemoTarget.historyTab),
              child: const Icon(Icons.history),
            ),
            activeIcon: const Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar(String? displayName) {
    final initial = displayName?.isNotEmpty == true
        ? displayName![0].toUpperCase()
        : '?';
    return Container(
      color: const Color(0xFFBA6A37),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
