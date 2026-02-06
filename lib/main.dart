import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const SneakerScannerApp());
}

class SneakerScannerApp extends StatelessWidget {
  const SneakerScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sneaker Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF646CFF),
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF646CFF),
          secondary: Color(0xFF535BF2),
          surface: Color(0xFF1E1E1E),
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        appBarTheme: AppBarTheme(
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        final user = FirebaseAuth.instance.currentUser;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                user != null ? const MainScreen() : const LoginScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF242424),
            ],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: const Color(0xFF646CFF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 64,
                              color: const Color(0xFF646CFF).withValues(alpha: 0.3),
                            ),
                            const Icon(
                              Icons.directions_run_rounded,
                              size: 48,
                              color: Color(0xFF646CFF),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Sneaker Scanner',
                        style: GoogleFonts.poppins(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Scan. Identify. Collect.',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Colors.grey[500],
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 48),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            const Color(0xFF646CFF).withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF242424),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF646CFF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Icon(
                      Icons.directions_run_rounded,
                      size: 48,
                      color: Color(0xFF646CFF),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Sneaker Scanner',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to sync your scans',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.network(
                                  'https://www.google.com/favicon.ico',
                                  width: 24,
                                  height: 24,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.g_mobiledata, size: 24),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    ScannerPage(),
    HistoryPage(),
  ];

  void switchToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
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
                  border: Border.all(
                    color: const Color(0xFF646CFF),
                    width: 2,
                  ),
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
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
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

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _isScanning = false;

  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_isScanning) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _controller?.stop();
        break;
      case AppLifecycleState.resumed:
        break;
      default:
        break;
    }
  }

  Future<void> _startScanning() async {
    _controller = MobileScannerController(
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
      autoStart: true,
    );
    setState(() {
      _isScanning = true;
    });
  }

  Future<void> _stopScanning() async {
    await _controller?.stop();
    await _controller?.dispose();
    _controller = null;
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<String?> _saveScan(String code, String format) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    // Save initial scan data
    final scanRef = _database.child('scans').child(user.uid).push();
    await scanRef.set({
      'code': code,
      'format': format,
      'timestamp': ServerValue.timestamp,
      'productTitle': null,
      'productImage': null,
      'retailPrice': null,
      'ebayPrice': null,
      'stockxPrice': null,
      'goatPrice': null,
    });

    // Try to fetch product info and update the scan
    _fetchAndUpdateProductInfo(code, scanRef);

    // Return the scan ID
    return scanRef.key;
  }

  Future<void> _fetchAndUpdateProductInfo(String code, DatabaseReference scanRef) async {
    try {
      // Check if product info is already cached
      final cachedSnapshot = await _database.child('products').child(code).get();
      if (cachedSnapshot.exists) {
        final productInfo = Map<String, dynamic>.from(cachedSnapshot.value as Map);
        if (productInfo['title'] != null && productInfo['title'] != 'Product Not Found') {
          final images = productInfo['images'] as List?;
          final imageUrl = (images != null && images.isNotEmpty) ? images[0] : null;
          final retailPrice = productInfo['retailPrice'] as String?;
          await scanRef.update({
            'productTitle': productInfo['title'],
            'productImage': imageUrl,
            'retailPrice': retailPrice,
          });
        }
        return;
      }

      // Fetch from API
      final response = await http.get(
        Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$code'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['items'] != null && (data['items'] as List).isNotEmpty) {
          final item = data['items'][0];
          final title = item['title'] ?? 'Unknown Product';
          final images = item['images'] as List? ?? [];
          final imageUrl = images.isNotEmpty ? images[0] : null;

          // Extract retail price
          double? lowestPrice;
          double? highestPrice;
          String? retailPrice;

          if (item['offers'] != null && (item['offers'] as List).isNotEmpty) {
            final offers = item['offers'] as List;
            for (var offer in offers) {
              final price = offer['price'];
              if (price != null) {
                final priceValue = double.tryParse(price.toString());
                if (priceValue != null && priceValue > 0) {
                  if (lowestPrice == null || priceValue < lowestPrice) {
                    lowestPrice = priceValue;
                  }
                  if (highestPrice == null || priceValue > highestPrice) {
                    highestPrice = priceValue;
                  }
                }
              }
            }
          }

          if (item['msrp'] != null) {
            final msrp = double.tryParse(item['msrp'].toString());
            if (msrp != null && msrp > 0) {
              retailPrice = msrp.toStringAsFixed(2);
            }
          } else if (item['lowest_recorded_price'] != null) {
            final lrp = double.tryParse(item['lowest_recorded_price'].toString());
            if (lrp != null && lrp > 0) {
              retailPrice = lrp.toStringAsFixed(2);
            }
          } else if (lowestPrice != null) {
            retailPrice = lowestPrice.toStringAsFixed(2);
          }

          // Cache product info
          await _database.child('products').child(code).set({
            'title': title,
            'brand': item['brand'] ?? '',
            'description': item['description'] ?? '',
            'category': item['category'] ?? '',
            'images': images,
            'retailPrice': retailPrice,
            'upc': code,
            'lastUpdated': ServerValue.timestamp,
          });

          // Update scan with product title, image, and retail price
          await scanRef.update({
            'productTitle': title,
            'productImage': imageUrl,
            'retailPrice': retailPrice,
          });
        }
      }
    } catch (e) {
      // Silently fail - product info will be fetched when viewing details
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final code = barcode.rawValue!;
        final format = barcode.format.name.toUpperCase();

        final scanId = await _saveScan(code, format);
        _stopScanning();

        // Navigate directly to the scan detail page
        if (mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ScanDetailPage(
                scanId: scanId ?? '',
                code: code,
                format: format,
                timestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            ),
          );
        }
        break;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Sneaker Scanner',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Scan barcodes from sneaker boxes',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 24),

            Container(
              height: 300,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: _isScanning
                    ? Border.all(color: const Color(0xFF646CFF), width: 2)
                    : null,
              ),
              clipBehavior: Clip.hardEdge,
              child: _isScanning && _controller != null
                  ? MobileScanner(
                      controller: _controller!,
                      onDetect: _onDetect,
                    )
                  : Center(
                      child: Icon(
                        Icons.qr_code_scanner,
                        size: 64,
                        color: Colors.grey[600],
                      ),
                    ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isScanning ? _stopScanning : _startScanning,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isScanning
                      ? const Color(0xFFFF4444)
                      : const Color(0xFF646CFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  _isScanning ? 'Stop Scanning' : 'Start Scanning',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

enum DateFilter { all, today, week, month, custom }

class _HistoryPageState extends State<HistoryPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  DateFilter _dateFilter = DateFilter.all;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  DatabaseReference get _scansRef {
    final user = FirebaseAuth.instance.currentUser;
    return FirebaseDatabase.instance.ref().child('scans').child(user?.uid ?? '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MapEntry<String, dynamic>> _filterScans(List<MapEntry<String, dynamic>> scans) {
    return scans.where((entry) {
      final scanData = Map<String, dynamic>.from(entry.value);
      final code = (scanData['code'] ?? '').toString().toLowerCase();
      final productTitle = (scanData['productTitle'] ?? '').toString().toLowerCase();
      final timestamp = scanData['timestamp'] as int?;

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!code.contains(query) && !productTitle.contains(query)) {
          return false;
        }
      }

      // Date filter
      if (timestamp != null && _dateFilter != DateFilter.all) {
        final scanDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        switch (_dateFilter) {
          case DateFilter.today:
            final scanDay = DateTime(scanDate.year, scanDate.month, scanDate.day);
            if (scanDay != today) return false;
            break;
          case DateFilter.week:
            final weekAgo = today.subtract(const Duration(days: 7));
            if (scanDate.isBefore(weekAgo)) return false;
            break;
          case DateFilter.month:
            final monthAgo = today.subtract(const Duration(days: 30));
            if (scanDate.isBefore(monthAgo)) return false;
            break;
          case DateFilter.custom:
            if (_customStartDate != null && scanDate.isBefore(_customStartDate!)) {
              return false;
            }
            if (_customEndDate != null) {
              final endOfDay = DateTime(
                _customEndDate!.year,
                _customEndDate!.month,
                _customEndDate!.day,
                23, 59, 59,
              );
              if (scanDate.isAfter(endOfDay)) return false;
            }
            break;
          case DateFilter.all:
            break;
        }
      }

      return true;
    }).toList();
  }

  Map<String, List<MapEntry<String, dynamic>>> _groupByDate(
      List<MapEntry<String, dynamic>> scans) {
    final Map<String, List<MapEntry<String, dynamic>>> grouped = {};

    for (final entry in scans) {
      final scanData = Map<String, dynamic>.from(entry.value);
      final timestamp = scanData['timestamp'] as int?;
      final dateKey = timestamp != null ? _getDateKey(timestamp) : 'Unknown';

      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(entry);
    }

    return grouped;
  }

  String _getDateKey(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final scanDay = DateTime(date.year, date.month, date.day);

    if (scanDay == today) {
      return 'Today';
    } else if (scanDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else if (scanDay.isAfter(today.subtract(const Duration(days: 7)))) {
      final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return weekdays[date.weekday - 1];
    } else {
      final months = ['January', 'February', 'March', 'April', 'May', 'June',
                      'July', 'August', 'September', 'October', 'November', 'December'];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }

  Future<void> _showDateRangePicker() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
            ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF646CFF),
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF1A1A1A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _dateFilter = DateFilter.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Scan History',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

            // Search Bar
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF2A2A2A),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by product name or barcode...',
                  hintStyle: GoogleFonts.inter(
                    color: Colors.grey[600],
                    fontSize: 15,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Colors.grey[600],
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.grey[600]),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Date Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', DateFilter.all),
                  const SizedBox(width: 8),
                  _buildFilterChip('Today', DateFilter.today),
                  const SizedBox(width: 8),
                  _buildFilterChip('This Week', DateFilter.week),
                  const SizedBox(width: 8),
                  _buildFilterChip('This Month', DateFilter.month),
                  const SizedBox(width: 8),
                  _buildCustomDateChip(),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: StreamBuilder<DatabaseEvent>(
                stream: _scansRef.orderByChild('timestamp').onValue,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error loading scans',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF646CFF),
                      ),
                    );
                  }

                  final data = snapshot.data?.snapshot.value;
                  if (data == null) {
                    return _buildEmptyState();
                  }

                  final scansMap = Map<String, dynamic>.from(data as Map);
                  var scansList = scansMap.entries.toList();
                  scansList.sort((a, b) {
                    final aTime = (a.value['timestamp'] ?? 0) as int;
                    final bTime = (b.value['timestamp'] ?? 0) as int;
                    return bTime.compareTo(aTime);
                  });

                  // Apply filters
                  final filteredScans = _filterScans(scansList);

                  if (filteredScans.isEmpty) {
                    return _buildNoResultsState();
                  }

                  // Group by date
                  final groupedScans = _groupByDate(filteredScans);
                  final dateKeys = groupedScans.keys.toList();

                  return ListView.builder(
                    itemCount: dateKeys.length,
                    itemBuilder: (context, sectionIndex) {
                      final dateKey = dateKeys[sectionIndex];
                      final scansInSection = groupedScans[dateKey]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (sectionIndex > 0) const SizedBox(height: 16),
                          // Date Header
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 10),
                            child: Text(
                              dateKey,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                          // Scans for this date
                          ...scansInSection.asMap().entries.map((entry) {
                            final index = entry.key;
                            final scanEntry = entry.value;
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index < scansInSection.length - 1 ? 8 : 0,
                              ),
                              child: _buildScanCard(scanEntry),
                            );
                          }),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildFilterChip(String label, DateFilter filter) {
    final isSelected = _dateFilter == filter;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _dateFilter = filter),
        borderRadius: BorderRadius.circular(20),
        splashColor: const Color(0xFF646CFF).withValues(alpha: 0.3),
        highlightColor: const Color(0xFF646CFF).withValues(alpha: 0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF646CFF)
                : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF646CFF)
                  : const Color(0xFF2A2A2A),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey[400],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomDateChip() {
    final isSelected = _dateFilter == DateFilter.custom;
    String label = 'Custom';
    if (isSelected && _customStartDate != null && _customEndDate != null) {
      final start = '${_customStartDate!.month}/${_customStartDate!.day}';
      final end = '${_customEndDate!.month}/${_customEndDate!.day}';
      label = '$start - $end';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showDateRangePicker,
        borderRadius: BorderRadius.circular(20),
        splashColor: const Color(0xFF646CFF).withValues(alpha: 0.3),
        highlightColor: const Color(0xFF646CFF).withValues(alpha: 0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF646CFF)
                : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF646CFF)
                  : const Color(0xFF2A2A2A),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today,
                size: 14,
                color: isSelected ? Colors.white : Colors.grey[400],
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF646CFF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.qr_code_scanner,
              size: 40,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No scans yet',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan a barcode to see it here',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF646CFF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.search_off,
              size: 40,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No results found',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _dateFilter = DateFilter.all;
                _customStartDate = null;
                _customEndDate = null;
              });
            },
            child: Text(
              'Clear all filters',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF646CFF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanCard(MapEntry<String, dynamic> entry) {
    final scanData = Map<String, dynamic>.from(entry.value);
    final code = scanData['code'] ?? '';
    final format = scanData['format'] ?? '';
    final productTitle = scanData['productTitle'] as String?;
    final productImage = scanData['productImage'] as String?;
    final timestamp = scanData['timestamp'] as int?;
    final timeStr = timestamp != null ? _formatTime(timestamp) : '';

    final displayTitle = productTitle != null && productTitle.isNotEmpty
        ? productTitle
        : 'Unknown Product';
    final hasProductInfo = productTitle != null && productTitle.isNotEmpty;
    final hasImage = productImage != null && productImage.isNotEmpty;

    return Dismissible(
      key: Key(entry.key),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        _scansRef.child(entry.key).remove();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      child: GestureDetector(
        onTap: () async {
          // Get state reference before async gap
          final mainScreenState = context.findAncestorStateOfType<_MainScreenState>();

          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ScanDetailPage(
                scanId: entry.key,
                code: code,
                format: format,
                timestamp: timestamp ?? 0,
              ),
            ),
          );

          // If user wants to scan another, switch to scan tab
          if (result == 'scanAnother') {
            mainScreenState?.switchToTab(0);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF2A2A2A),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: hasProductInfo
                      ? const Color(0xFF646CFF).withValues(alpha: 0.15)
                      : const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: hasImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          productImage,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.directions_run,
                            color: const Color(0xFF646CFF),
                            size: 26,
                          ),
                        ),
                      )
                    : Icon(
                        hasProductInfo
                            ? Icons.directions_run
                            : Icons.help_outline_rounded,
                        color: hasProductInfo
                            ? const Color(0xFF646CFF)
                            : Colors.grey[500],
                        size: 26,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: hasProductInfo
                            ? Colors.white
                            : Colors.grey[400],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.qr_code,
                          size: 12,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            code,
                            style: GoogleFonts.robotoMono(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeStr,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF646CFF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios,
                  color: Color(0xFF646CFF),
                  size: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }
}

class ScanDetailPage extends StatefulWidget {
  final String scanId;
  final String code;
  final String format;
  final int timestamp;

  const ScanDetailPage({
    super.key,
    required this.scanId,
    required this.code,
    required this.format,
    required this.timestamp,
  });

  @override
  State<ScanDetailPage> createState() => _ScanDetailPageState();
}

class _ScanDetailPageState extends State<ScanDetailPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _productInfo;
  String? _error;

  // Retail price manual entry
  final TextEditingController _retailPriceController = TextEditingController();
  double? _manualRetailPrice;
  bool _showRetailEntry = false;

  // eBay API state
  bool _isLoadingEbayPrices = false;
  double? _ebayLowestPrice;
  double? _ebayAveragePrice;
  int? _ebayListingCount;
  String? _ebayError;

  // StockX price state (via KicksDB)
  bool _isLoadingStockXPrice = false;
  double? _stockXPrice;
  String? _stockXSlug;

  // GOAT price state (via KicksDB)
  bool _isLoadingGoatPrice = false;
  double? _goatPrice;
  String? _goatSlug;

  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // KicksDB API key from kicks.dev
  static const String _kicksDbApiKey = 'KICKS-9C87-7171-ADAA-E89A98AF16B0';

  // eBay API credentials - Replace with your own from developer.ebay.com
  static const String _ebayClientId = 'YOUR_EBAY_CLIENT_ID';
  static const String _ebayClientSecret = 'YOUR_EBAY_CLIENT_SECRET';
  static const bool _ebayProduction = false; // Set to true for production

  @override
  void initState() {
    super.initState();
    _loadProductInfo();
  }

  @override
  void dispose() {
    _retailPriceController.dispose();
    super.dispose();
  }

  Future<void> _loadProductInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Load saved prices from scan record
        if (widget.scanId.isNotEmpty) {
          final scanSnapshot = await _database
              .child('scans')
              .child(user.uid)
              .child(widget.scanId)
              .get();

          if (scanSnapshot.exists) {
            final scanData = Map<String, dynamic>.from(scanSnapshot.value as Map);
            final savedRetailPrice = scanData['retailPrice'] as String?;
            if (savedRetailPrice != null) {
              _manualRetailPrice = double.tryParse(savedRetailPrice);
              if (_manualRetailPrice != null) {
                _retailPriceController.text = savedRetailPrice;
              }
            }
            // Load cached StockX price
            final savedStockXPrice = scanData['stockxPrice'] as String?;
            if (savedStockXPrice != null) {
              _stockXPrice = double.tryParse(savedStockXPrice);
            }
            // Load cached GOAT price
            final savedGoatPrice = scanData['goatPrice'] as String?;
            if (savedGoatPrice != null) {
              _goatPrice = double.tryParse(savedGoatPrice);
            }
          }
        }

        // Check if we have cached product info in Firebase
        final cachedSnapshot = await _database
            .child('products')
            .child(widget.code)
            .get();

        if (cachedSnapshot.exists) {
          setState(() {
            _productInfo = Map<String, dynamic>.from(cachedSnapshot.value as Map);
            _isLoading = false;
          });
          // Fetch marketplace prices in background
          _fetchEbayPrices();
          _fetchKicksDbPrices();
          return;
        }
      }

      // If not cached, try to look up the product
      await _lookupProduct();
      // Fetch marketplace prices after product lookup
      _fetchEbayPrices();
      _fetchKicksDbPrices();
    } catch (e) {
      setState(() {
        _error = 'Failed to load product info';
        _isLoading = false;
      });
    }
  }

  Future<void> _lookupProduct() async {
    Map<String, dynamic>? productInfo;
    String? retailPrice;

    try {
      // Try UPCitemdb API first (free tier)
      productInfo = await _tryUpcItemDb();
      retailPrice = productInfo?['retailPrice'] as String?;

      // If UPCitemdb didn't find price, try Open Food Facts
      if (retailPrice == null && productInfo != null) {
        final offPrice = await _tryOpenFoodFacts();
        if (offPrice != null) {
          productInfo['retailPrice'] = offPrice;
        }
      }

      // If still no product info, try Go-UPC
      if (productInfo == null || productInfo['notFound'] == true) {
        final goUpcInfo = await _tryGoUpc();
        if (goUpcInfo != null) {
          productInfo = goUpcInfo;
        }
      }

      if (productInfo != null && productInfo['notFound'] != true) {
        // Cache in Firebase
        productInfo['lastUpdated'] = ServerValue.timestamp;
        await _database.child('products').child(widget.code).set(productInfo);

        setState(() {
          _productInfo = productInfo;
          _isLoading = false;
        });
        return;
      }

      // If all API lookups fail, set as not found
      setState(() {
        _productInfo = {
          'title': 'Product Not Found',
          'brand': '',
          'description': 'We couldn\'t find information for this barcode. Try searching on eBay.',
          'upc': widget.code,
          'notFound': true,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _productInfo = {
          'title': 'Product Not Found',
          'brand': '',
          'description': 'We couldn\'t find information for this barcode. Try searching on eBay.',
          'upc': widget.code,
          'notFound': true,
        };
        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _tryUpcItemDb() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=${widget.code}'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['items'] != null && (data['items'] as List).isNotEmpty) {
          final item = data['items'][0];

          // Extract price from offers if available
          double? lowestPrice;
          double? highestPrice;
          String? retailPrice;

          if (item['offers'] != null && (item['offers'] as List).isNotEmpty) {
            final offers = item['offers'] as List;
            for (var offer in offers) {
              final price = offer['price'];
              if (price != null) {
                final priceValue = double.tryParse(price.toString());
                if (priceValue != null && priceValue > 0) {
                  if (lowestPrice == null || priceValue < lowestPrice) {
                    lowestPrice = priceValue;
                  }
                  if (highestPrice == null || priceValue > highestPrice) {
                    highestPrice = priceValue;
                  }
                }
              }
            }
          }

          // Also check for MSRP in the item data
          if (item['msrp'] != null) {
            final msrp = double.tryParse(item['msrp'].toString());
            if (msrp != null && msrp > 0) {
              retailPrice = msrp.toStringAsFixed(2);
            }
          } else if (item['lowest_recorded_price'] != null) {
            final lrp = double.tryParse(item['lowest_recorded_price'].toString());
            if (lrp != null && lrp > 0) {
              retailPrice = lrp.toStringAsFixed(2);
            }
          } else if (lowestPrice != null) {
            retailPrice = lowestPrice.toStringAsFixed(2);
          }

          return {
            'title': item['title'] ?? 'Unknown Product',
            'brand': item['brand'] ?? 'Unknown Brand',
            'description': item['description'] ?? '',
            'category': item['category'] ?? '',
            'images': item['images'] ?? [],
            'model': item['model'] ?? '',
            'retailPrice': retailPrice,
            'lowestPrice': lowestPrice?.toStringAsFixed(2),
            'highestPrice': highestPrice?.toStringAsFixed(2),
            'upc': widget.code,
          };
        }
      }
    } catch (e) {
      debugPrint('UPCitemdb error: $e');
    }
    return null;
  }

  Future<String?> _tryOpenFoodFacts() async {
    try {
      final response = await http.get(
        Uri.parse('https://world.openfoodfacts.org/api/v0/product/${widget.code}.json'),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 1 && data['product'] != null) {
          // Open Food Facts doesn't have price data for most products
          // but we can get additional product info
        }
      }
    } catch (e) {
      debugPrint('Open Food Facts error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _tryGoUpc() async {
    try {
      // Go-UPC requires an API key, but has a demo endpoint
      // For production, you would use: https://go-upc.com/api/v1/code/{barcode}
      final response = await http.get(
        Uri.parse('https://go-upc.com/api/v1/code/${widget.code}'),
        headers: {
          'Authorization': 'Bearer YOUR_GO_UPC_API_KEY', // Replace with your key
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['product'] != null) {
          final product = data['product'];
          String? retailPrice;

          // Extract price if available
          if (product['specs'] != null) {
            final specs = product['specs'];
            if (specs['msrp'] != null) {
              final msrp = double.tryParse(specs['msrp'].toString().replaceAll(RegExp(r'[^\d.]'), ''));
              if (msrp != null && msrp > 0) {
                retailPrice = msrp.toStringAsFixed(2);
              }
            }
          }

          return {
            'title': product['name'] ?? 'Unknown Product',
            'brand': product['brand'] ?? 'Unknown Brand',
            'description': product['description'] ?? '',
            'category': product['category'] ?? '',
            'images': product['imageUrl'] != null ? [product['imageUrl']] : [],
            'model': product['model'] ?? '',
            'retailPrice': retailPrice,
            'upc': widget.code,
          };
        }
      }
    } catch (e) {
      debugPrint('Go-UPC error: $e');
    }
    return null;
  }

  String _buildSearchQuery({bool forStockX = false}) {
    final title = _productInfo?['title'] as String?;
    final brand = _productInfo?['brand'] as String?;
    final model = _productInfo?['model'] as String?;

    if (title == null || title == 'Product Not Found') {
      return widget.code;
    }

    if (forStockX) {
      // For StockX, use a shorter query: brand + model or first few words of title
      if (brand != null && brand.isNotEmpty && model != null && model.isNotEmpty) {
        return '$brand $model';
      }

      // Otherwise, take first 5-6 words of title to avoid overly long queries
      final words = title.split(' ');
      if (words.length > 6) {
        return words.take(6).join(' ');
      }
    }

    return title;
  }

  Future<void> _openEbaySearch() async {
    final searchQuery = _buildSearchQuery();
    final url = Uri.parse(
        'https://www.ebay.com/sch/i.html?_nkw=${Uri.encodeComponent(searchQuery)}');
    await launchUrl(url, mode: LaunchMode.platformDefault);
  }

  Future<void> _openStockXSearch() async {
    if (_stockXSlug != null && _stockXSlug!.isNotEmpty) {
      final url = Uri.parse('https://stockx.com/$_stockXSlug');
      await launchUrl(url, mode: LaunchMode.platformDefault);
    } else {
      final searchQuery = _buildSearchQuery(forStockX: true);
      final url = Uri.parse(
          'https://stockx.com/search?s=${Uri.encodeComponent(searchQuery)}');
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
  }

  Future<void> _openGoatSearch() async {
    if (_goatSlug != null && _goatSlug!.isNotEmpty) {
      final url = Uri.parse('https://www.goat.com/sneakers/$_goatSlug');
      await launchUrl(url, mode: LaunchMode.platformDefault);
    } else {
      final searchQuery = _buildSearchQuery(forStockX: true);
      final url = Uri.parse(
          'https://www.goat.com/search?query=${Uri.encodeComponent(searchQuery)}');
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
  }

  // eBay OAuth token cache
  static String? _ebayAccessToken;
  static DateTime? _ebayTokenExpiry;

  Future<String?> _getEbayAccessToken() async {
    // Check if we have a valid cached token
    if (_ebayAccessToken != null &&
        _ebayTokenExpiry != null &&
        DateTime.now().isBefore(_ebayTokenExpiry!)) {
      return _ebayAccessToken;
    }

    // Skip if credentials not configured
    if (_ebayClientId == 'YOUR_EBAY_CLIENT_ID') {
      return null;
    }

    try {
      final baseUrl = _ebayProduction
          ? 'https://api.ebay.com'
          : 'https://api.sandbox.ebay.com';

      final credentials = base64Encode(utf8.encode('$_ebayClientId:$_ebayClientSecret'));

      final response = await http.post(
        Uri.parse('$baseUrl/identity/v1/oauth2/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Basic $credentials',
        },
        body: 'grant_type=client_credentials&scope=https://api.ebay.com/oauth/api_scope',
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _ebayAccessToken = data['access_token'];
        final expiresIn = data['expires_in'] as int;
        _ebayTokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60)); // Buffer
        return _ebayAccessToken;
      }
    } catch (e) {
      debugPrint('eBay OAuth error: $e');
    }
    return null;
  }

  Future<void> _fetchEbayPrices() async {
    if (_productInfo == null) return;

    setState(() {
      _isLoadingEbayPrices = true;
      _ebayError = null;
    });

    try {
      final token = await _getEbayAccessToken();

      if (token == null) {
        // Fallback: Use eBay's public search page scraping isn't possible,
        // so we'll just indicate eBay integration isn't configured
        setState(() {
          _isLoadingEbayPrices = false;
          _ebayError = 'eBay API not configured';
        });
        return;
      }

      final searchQuery = _buildSearchQuery();
      final baseUrl = _ebayProduction
          ? 'https://api.ebay.com'
          : 'https://api.sandbox.ebay.com';

      final response = await http.get(
        Uri.parse(
          '$baseUrl/buy/browse/v1/item_summary/search?'
          'q=${Uri.encodeComponent(searchQuery)}'
          '&category_ids=93427' // Athletic shoes category
          '&limit=50'
          '&sort=price'
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'X-EBAY-C-MARKETPLACE-ID': 'EBAY_US',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['itemSummaries'] as List? ?? [];

        if (items.isNotEmpty) {
          double totalPrice = 0;
          double? lowestPrice;
          int validPrices = 0;

          for (var item in items) {
            final priceData = item['price'];
            if (priceData != null && priceData['value'] != null) {
              final price = double.tryParse(priceData['value'].toString());
              if (price != null && price > 0) {
                totalPrice += price;
                validPrices++;
                if (lowestPrice == null || price < lowestPrice) {
                  lowestPrice = price;
                }
              }
            }
          }

          if (validPrices > 0) {
            setState(() {
              _ebayLowestPrice = lowestPrice;
              _ebayAveragePrice = totalPrice / validPrices;
              _ebayListingCount = validPrices;
              _isLoadingEbayPrices = false;
            });
            _savePricesToDatabase();
            return;
          }
        }
      }

      setState(() {
        _isLoadingEbayPrices = false;
        _ebayError = 'No listings found';
      });
    } catch (e) {
      setState(() {
        _isLoadingEbayPrices = false;
        _ebayError = 'Failed to fetch prices';
      });
    }
  }

  // Shared price cache TTL: 24 hours (matches KicksDB data refresh rate)
  static const int _priceCacheTtlMs = 24 * 60 * 60 * 1000;

  Future<void> _fetchKicksDbPrices() async {
    if (_productInfo == null) return;

    setState(() {
      _isLoadingStockXPrice = true;
      _isLoadingGoatPrice = true;
    });

    // Check shared price cache first
    try {
      final cacheSnapshot = await _database
          .child('priceCache')
          .child(widget.code)
          .get();

      if (cacheSnapshot.exists) {
        final cacheData = Map<String, dynamic>.from(cacheSnapshot.value as Map);
        final cachedAt = cacheData['cachedAt'] as int?;
        final now = DateTime.now().millisecondsSinceEpoch;

        if (cachedAt != null && (now - cachedAt) < _priceCacheTtlMs) {
          // Cache is fresh, use it
          setState(() {
            _stockXPrice = double.tryParse((cacheData['stockxPrice'] ?? '').toString());
            _stockXSlug = cacheData['stockxSlug'] as String?;
            _goatPrice = double.tryParse((cacheData['goatPrice'] ?? '').toString());
            _goatSlug = cacheData['goatSlug'] as String?;
            _isLoadingStockXPrice = false;
            _isLoadingGoatPrice = false;
          });
          _savePricesToDatabase();
          return;
        }
      }
    } catch (e) {
      debugPrint('Price cache read error: $e');
    }

    // Cache miss or stale — fetch fresh prices
    await Future.wait([
      _fetchStockXPrice(),
      _fetchGoatPrice(),
    ]);

    // Write to shared price cache
    try {
      final cacheData = <String, dynamic>{
        'cachedAt': ServerValue.timestamp,
      };
      if (_stockXPrice != null) {
        cacheData['stockxPrice'] = _stockXPrice!.toStringAsFixed(2);
        cacheData['stockxSlug'] = _stockXSlug;
      }
      if (_goatPrice != null) {
        cacheData['goatPrice'] = _goatPrice!.toStringAsFixed(2);
        cacheData['goatSlug'] = _goatSlug;
      }
      await _database.child('priceCache').child(widget.code).set(cacheData);
    } catch (e) {
      debugPrint('Price cache write error: $e');
    }

    _savePricesToDatabase();
  }

  Future<void> _fetchStockXPrice() async {
    try {
      final query = _buildSearchQuery(forStockX: true);
      final response = await http.get(
        Uri.parse(
          'https://api.kicks.dev/v3/stockx/products'
          '?query=${Uri.encodeComponent(query)}&limit=1'
          '&display[prices]=true&display[variants]=true'
        ),
        headers: {'Authorization': 'Bearer $_kicksDbApiKey'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> products = body is List ? body : (body['data'] ?? []);

        if (products.isNotEmpty) {
          final product = products[0] as Map<String, dynamic>;

          double? lowestAsk;
          final variants = product['variants'] as List?;
          if (variants != null) {
            for (var variant in variants) {
              final ask = variant['lowest_ask'];
              if (ask != null) {
                final askPrice = double.tryParse(ask.toString());
                if (askPrice != null && askPrice > 0) {
                  if (lowestAsk == null || askPrice < lowestAsk) {
                    lowestAsk = askPrice;
                  }
                }
              }
            }
          }

          // Fallback to product-level min_price
          lowestAsk ??= double.tryParse((product['min_price'] ?? '').toString());

          setState(() {
            _stockXPrice = lowestAsk;
            _stockXSlug = product['slug'] as String?;
            _isLoadingStockXPrice = false;

          });
          return;
        }
      }

      setState(() {
        _isLoadingStockXPrice = false;
      });
    } catch (e) {
      debugPrint('StockX fetch error: $e');
      setState(() {
        _isLoadingStockXPrice = false;
      });
    }
  }

  Future<void> _fetchGoatPrice() async {
    try {
      final query = _buildSearchQuery(forStockX: true);
      final response = await http.get(
        Uri.parse(
          'https://api.kicks.dev/v3/goat/products'
          '?query=${Uri.encodeComponent(query)}&limit=1'
          '&display[variants]=true'
        ),
        headers: {'Authorization': 'Bearer $_kicksDbApiKey'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> products = body is List ? body : (body['data'] ?? []);

        if (products.isNotEmpty) {
          final product = products[0] as Map<String, dynamic>;

          double? lowestAsk;
          final variants = product['variants'] as List?;
          if (variants != null) {
            for (var variant in variants) {
              final ask = variant['lowest_ask'];
              if (ask != null) {
                final askPrice = double.tryParse(ask.toString());
                if (askPrice != null && askPrice > 0) {
                  if (lowestAsk == null || askPrice < lowestAsk) {
                    lowestAsk = askPrice;
                  }
                }
              }
            }
          }

          setState(() {
            _goatPrice = lowestAsk;
            _goatSlug = product['slug'] as String?;
            _isLoadingGoatPrice = false;

          });
          return;
        }
      }

      setState(() {
        _isLoadingGoatPrice = false;
      });
    } catch (e) {
      debugPrint('GOAT fetch error: $e');
      setState(() {
        _isLoadingGoatPrice = false;
      });
    }
  }

  Future<void> _savePricesToDatabase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.scanId.isEmpty) return;

    try {
      final updateData = <String, dynamic>{};

      // Add retail price if available
      final retailPriceStr = _productInfo?['retailPrice'] as String?;
      final retailPrice = retailPriceStr ?? (_manualRetailPrice?.toStringAsFixed(2));
      if (retailPrice != null) {
        updateData['retailPrice'] = retailPrice;
      }

      // Add eBay price if available
      if (_ebayAveragePrice != null) {
        updateData['ebayPrice'] = _ebayAveragePrice!.toStringAsFixed(2);
      }

      // Add StockX price if available
      if (_stockXPrice != null) {
        updateData['stockxPrice'] = _stockXPrice!.toStringAsFixed(2);
      }

      // Add GOAT price if available
      if (_goatPrice != null) {
        updateData['goatPrice'] = _goatPrice!.toStringAsFixed(2);
      }

      // Only update if we have prices to save
      if (updateData.isNotEmpty) {
        await _database.child('scans').child(user.uid).child(widget.scanId).update(updateData);
      }
    } catch (e) {
      debugPrint('Error saving prices: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Scan Details'),
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            border: Border(
              top: BorderSide(
                color: const Color(0xFF2A2A2A),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Pop with result to indicate we want to scan another
                  Navigator.of(context).pop('scanAnother');
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Another'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF646CFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF646CFF)),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[600]),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: Colors.grey[500])),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadProductInfo,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product Image or Placeholder
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _productInfo?['images'] != null &&
                                (_productInfo!['images'] as List).isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  _productInfo!['images'][0],
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _buildPlaceholderImage(),
                                ),
                              )
                            : _buildPlaceholderImage(),
                      ),
                      const SizedBox(height: 24),

                      // Product Title
                      Text(
                        _productInfo?['title'] ?? 'Unknown Product',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Brand
                      if (_productInfo?['brand'] != null &&
                          _productInfo!['brand'].toString().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF646CFF).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _productInfo!['brand'],
                            style: GoogleFonts.inter(
                              color: const Color(0xFF646CFF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),

                      // Price Section
                      if (_productInfo?['retailPrice'] != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF1E3A1E),
                                const Color(0xFF1A2A1A),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.sell,
                                    color: Colors.green[400],
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Retail Price',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.green[400],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '\$${_productInfo!['retailPrice']}',
                                style: GoogleFonts.poppins(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              if (_productInfo?['lowestPrice'] != null &&
                                  _productInfo?['highestPrice'] != null &&
                                  _productInfo!['lowestPrice'] != _productInfo!['highestPrice']) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Market range: \$${_productInfo!['lowestPrice']} - \$${_productInfo!['highestPrice']}',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // eBay Market Prices Section
                      _buildEbayPricesSection(),

                      // Info Cards
                      _buildInfoCard(
                        'Barcode',
                        widget.code,
                        Icons.qr_code,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoCard(
                        'Format',
                        widget.format,
                        Icons.category,
                      ),
                      if (_productInfo?['category'] != null &&
                          _productInfo!['category'].toString().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildInfoCard(
                          'Category',
                          _productInfo!['category'],
                          Icons.label,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildInfoCard(
                        'Scanned',
                        _formatDate(widget.timestamp),
                        Icons.access_time,
                      ),
                      const SizedBox(height: 24),

                      // Description
                      if (_productInfo?['description'] != null &&
                          _productInfo!['description'].toString().isNotEmpty) ...[
                        Text(
                          'Description',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _productInfo!['description'],
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey[400],
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Profit Calculator Section
                      _buildProfitCalculator(),
                      const SizedBox(height: 24),

                      // eBay Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openEbaySearch,
                          icon: const Icon(Icons.shopping_bag),
                          label: const Text('Open on eBay'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0064D2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // StockX Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openStockXSearch,
                          icon: const Icon(Icons.store),
                          label: const Text('Open on StockX'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF006340),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // GOAT Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openGoatSearch,
                          icon: const Icon(Icons.storefront),
                          label: const Text('Open on GOAT'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7B61FF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildProfitCalculator() {
    final retailPriceStr = _productInfo?['retailPrice'] as String?;
    final fetchedRetailPrice = retailPriceStr != null ? double.tryParse(retailPriceStr) : null;

    // Use fetched price if available, otherwise use manually entered price
    final retailPrice = fetchedRetailPrice ?? _manualRetailPrice;
    final hasAutoRetailPrice = fetchedRetailPrice != null;

    // Get eBay price (auto-fetched only)
    final ebayPrice = _ebayAveragePrice;

    // Calculate separate profits for eBay, StockX, and GOAT
    double? ebayProfit;
    double? ebayProfitPercent;
    if (retailPrice != null && ebayPrice != null) {
      ebayProfit = ebayPrice - retailPrice;
      ebayProfitPercent = (ebayProfit / retailPrice) * 100;
    }

    double? stockXProfit;
    double? stockXProfitPercent;
    if (retailPrice != null && _stockXPrice != null) {
      stockXProfit = _stockXPrice! - retailPrice;
      stockXProfitPercent = (stockXProfit / retailPrice) * 100;
    }

    double? goatProfit;
    double? goatProfitPercent;
    if (retailPrice != null && _goatPrice != null) {
      goatProfit = _goatPrice! - retailPrice;
      goatProfitPercent = (goatProfit / retailPrice) * 100;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calculate_rounded,
                color: const Color(0xFF646CFF),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Profit Calculator',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Retail Price Row
          Row(
            children: [
              Icon(Icons.sell, size: 16, color: Colors.green[400]),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Retail Price',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    ),
                    if (hasAutoRetailPrice)
                      Text(
                        '\$${fetchedRetailPrice.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      )
                    else if (_showRetailEntry)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 100,
                            height: 36,
                            child: TextField(
                              controller: _retailPriceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textInputAction: TextInputAction.done,
                              autofocus: true,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.right,
                              decoration: InputDecoration(
                                hintText: '0.00',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                                prefixText: '\$ ',
                                prefixStyle: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                filled: true,
                                fillColor: const Color(0xFF252525),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.green[400]!, width: 1),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _manualRetailPrice = double.tryParse(value);
                                });
                              },
                              onSubmitted: (value) {
                                setState(() {
                                  _manualRetailPrice = double.tryParse(value);
                                  if (_manualRetailPrice != null) {
                                    _showRetailEntry = false;
                                    _savePricesToDatabase();
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _manualRetailPrice = double.tryParse(_retailPriceController.text);
                                if (_manualRetailPrice != null) {
                                  _showRetailEntry = false;
                                  _savePricesToDatabase();
                                }
                              });
                            },
                            child: Container(
                              width: 40,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.green[400]!.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.check,
                                color: Colors.green[400],
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      )
                    else if (_manualRetailPrice != null)
                      GestureDetector(
                        onTap: () => setState(() => _showRetailEntry = true),
                        child: Text(
                          '\$${_manualRetailPrice!.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[400],
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Text(
                            'Not Found',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() => _showRetailEntry = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Enter',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green[400],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: Colors.grey[800], height: 1),
          ),

          // eBay Section
          _buildMarketPriceSection(
            label: 'eBay',
            icon: Icons.shopping_bag,
            iconColor: const Color(0xFF0064D2),
            price: ebayPrice,
            profit: ebayProfit,
            profitPercent: ebayProfitPercent,
            isLoading: _isLoadingEbayPrices,
            retailPrice: retailPrice,
            onOpenMarketplace: _openEbaySearch,
          ),
          const SizedBox(height: 12),

          // StockX Section
          _buildMarketPriceSection(
            label: 'StockX',
            icon: Icons.store,
            iconColor: const Color(0xFF006340),
            price: _stockXPrice,
            profit: stockXProfit,
            profitPercent: stockXProfitPercent,
            isLoading: _isLoadingStockXPrice,
            retailPrice: retailPrice,
            onOpenMarketplace: _openStockXSearch,
          ),
          const SizedBox(height: 12),

          // GOAT Section
          _buildMarketPriceSection(
            label: 'GOAT',
            icon: Icons.storefront,
            iconColor: const Color(0xFF7B61FF),
            price: _goatPrice,
            profit: goatProfit,
            profitPercent: goatProfitPercent,
            isLoading: _isLoadingGoatPrice,
            retailPrice: retailPrice,
            onOpenMarketplace: _openGoatSearch,
          ),
        ],
      ),
    );
  }

  Widget _buildMarketPriceSection({
    required String label,
    required IconData icon,
    required Color iconColor,
    required double? price,
    required double? profit,
    required double? profitPercent,
    required bool isLoading,
    required double? retailPrice,
    required VoidCallback onOpenMarketplace,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // Price Row
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                '$label Price',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (isLoading)
                Text(
                  'Loading...',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                )
              else if (price != null)
                Text(
                  '\$${price.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                )
              else
                GestureDetector(
                  onTap: onOpenMarketplace,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open on $label',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: iconColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.open_in_new, size: 12, color: iconColor),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // Profit Row (only show if we have a price)
          if (price != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Profit',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey[400],
                    ),
                  ),
                  if (profit != null)
                    Row(
                      children: [
                        Text(
                          '${profit >= 0 ? '+' : ''}\$${profit.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: profit >= 0 ? Colors.green[400] : Colors.red[400],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (profit >= 0 ? Colors.green : Colors.red).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${profitPercent! >= 0 ? '+' : ''}${profitPercent.toStringAsFixed(1)}%',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: profit >= 0 ? Colors.green[400] : Colors.red[400],
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Retail price not found',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.directions_run,
            size: 64,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 8),
          Text(
            'No image available',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEbayPricesSection() {
    // Show loading state
    if (_isLoadingEbayPrices) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E2A3A),
              const Color(0xFF1A2230),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF0064D2).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF0064D2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Fetching eBay prices...',
              style: GoogleFonts.inter(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Show eBay prices if available
    if (_ebayLowestPrice != null || _ebayAveragePrice != null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E2A3A),
              const Color(0xFF1A2230),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF0064D2).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shopping_bag,
                  color: const Color(0xFF0064D2),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'eBay Market Prices',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF0064D2),
                  ),
                ),
                const Spacer(),
                if (_ebayListingCount != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0064D2).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_ebayListingCount listings',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF0064D2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lowest',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _ebayLowestPrice != null
                            ? '\$${_ebayLowestPrice!.toStringAsFixed(2)}'
                            : '--',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey[700],
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Average',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _ebayAveragePrice != null
                            ? '\$${_ebayAveragePrice!.toStringAsFixed(2)}'
                            : '--',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[400],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Show setup prompt if eBay not configured
    if (_ebayError == 'eBay API not configured') {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[800]!,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.grey[500],
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'eBay Prices Available',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Set up eBay API credentials to automatically fetch market prices.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    // Don't show anything if there was another error
    return const SizedBox.shrink();
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF646CFF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF646CFF),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: label == 'Barcode'
                      ? GoogleFonts.robotoMono(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        )
                      : GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(int timestamp) {
    if (timestamp == 0) return 'Just now';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.month}/${date.day}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _signOut(BuildContext context) async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _showSignOutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF333333),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.red,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Sign Out',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to sign out of your account?',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey[400],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[400],
                        side: BorderSide(color: Colors.grey[600]!),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _signOut(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Sign Out',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL;
    final displayName = user?.displayName ?? 'User';
    final email = user?.email ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Settings',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF2A2A2A),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF646CFF),
                        width: 3,
                      ),
                    ),
                    child: ClipOval(
                      child: photoUrl != null
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildLargeDefaultAvatar(displayName),
                            )
                          : _buildLargeDefaultAvatar(displayName),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Subscription Section
            Text(
              'SUBSCRIPTION',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF2A2A2A),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  _buildSettingsTile(
                    icon: Icons.workspace_premium_rounded,
                    iconColor: Colors.amber,
                    title: 'Current Plan',
                    subtitle: 'Free',
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF646CFF).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Upgrade',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF646CFF),
                        ),
                      ),
                    ),
                    onTap: () {
                      // TODO: Navigate to subscription page
                    },
                  ),
                  _buildDivider(),
                  _buildSettingsTile(
                    icon: Icons.qr_code_scanner,
                    iconColor: const Color(0xFF646CFF),
                    title: 'Scans This Month',
                    subtitle: 'Unlimited on Free plan',
                    onTap: null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // App Section
            Text(
              'APP',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF2A2A2A),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  _buildSettingsTile(
                    icon: Icons.notifications_outlined,
                    iconColor: Colors.orange,
                    title: 'Notifications',
                    subtitle: 'Manage notification preferences',
                    onTap: () {
                      // TODO: Navigate to notifications settings
                    },
                  ),
                  _buildDivider(),
                  _buildSettingsTile(
                    icon: Icons.help_outline_rounded,
                    iconColor: Colors.blue,
                    title: 'Help & Support',
                    subtitle: 'Get help or send feedback',
                    onTap: () {
                      // TODO: Navigate to help page
                    },
                  ),
                  _buildDivider(),
                  _buildSettingsTile(
                    icon: Icons.info_outline_rounded,
                    iconColor: Colors.teal,
                    title: 'About',
                    subtitle: 'Version 1.0.0',
                    onTap: () {
                      // TODO: Show about dialog
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Account Section
            Text(
              'ACCOUNT',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF2A2A2A),
                  width: 1,
                ),
              ),
              child: _buildSettingsTile(
                icon: Icons.logout_rounded,
                iconColor: Colors.red,
                title: 'Sign Out',
                subtitle: 'Sign out of your account',
                onTap: () => _showSignOutConfirmation(context),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLargeDefaultAvatar(String displayName) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return Container(
      color: const Color(0xFF646CFF),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 28,
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
            if (onTap != null && trailing == null)
              Icon(
                Icons.chevron_right,
                color: Colors.grey[600],
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        height: 1,
        color: Colors.grey[800],
      ),
    );
  }
}
