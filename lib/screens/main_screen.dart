import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_links/app_links.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api_keys.dart';
import '../services/stockx_auth_service.dart';
import '../services/subscription_service.dart';
import 'scanner_page.dart';
import 'history_page.dart';
import 'settings_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late AppLinks _appLinks;

  final List<Widget> _pages = const [ScannerPage(), HistoryPage()];

  @override
  void initState() {
    super.initState();
    _loadApiKeys();
    SubscriptionService.instance.initialize();
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

  void switchToTab(int index) {
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
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _openSettings,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF646CFF), width: 2),
                ),
                child: ClipOval(
                  child: photoUrl != null
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildDefaultAvatar(user?.displayName),
                        )
                      : _buildDefaultAvatar(user?.displayName),
                ),
              ),
            ),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: const Color(0xFF646CFF),
        unselectedItemColor: Colors.grey[600],
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar(String? displayName) {
    final initial = displayName?.isNotEmpty == true
        ? displayName![0].toUpperCase()
        : '?';
    return Container(
      color: const Color(0xFF646CFF),
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
