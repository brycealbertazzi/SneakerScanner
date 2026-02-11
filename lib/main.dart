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
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:app_links/app_links.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
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
            colors: [Color(0xFF1A1A2E), Color(0xFF242424)],
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
                          color: const Color(
                            0xFF646CFF,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 64,
                              color: const Color(
                                0xFF646CFF,
                              ).withValues(alpha: 0.3),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sign in failed: $e')));
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
            colors: [Color(0xFF1A1A2E), Color(0xFF242424)],
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
  late AppLinks _appLinks;

  final List<Widget> _pages = const [ScannerPage(), HistoryPage()];

  @override
  void initState() {
    super.initState();
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

  Future<void> _exchangeStockXCode(String code) async {
    try {
      debugPrint('[StockX OAuth] Exchanging authorization code for tokens...');
      final response = await http.post(
        Uri.parse('https://accounts.stockx.com/oauth/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'client_id': _ScanDetailPageState._stockXClientId,
          'client_secret': _ScanDetailPageState._stockXClientSecret,
          'redirect_uri': _ScanDetailPageState._stockXRedirectUri,
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('[StockX OAuth] Token exchange status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['access_token'] as String;
        final refreshToken = data['refresh_token'] as String?;
        final expiresIn = data['expires_in'] as int;

        // Save to static vars
        _ScanDetailPageState._stockXAccessToken = accessToken;
        _ScanDetailPageState._stockXRefreshToken = refreshToken;
        _ScanDetailPageState._stockXTokenExpiry =
            DateTime.now().add(Duration(seconds: expiresIn - 60));
        _ScanDetailPageState._stockXTokensLoaded = true;

        // Save to Firebase
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseDatabase.instance.ref()
              .child('stockxTokens')
              .child(user.uid)
              .set({
            'accessToken': accessToken,
            'refreshToken': refreshToken,
            'expiresAt': DateTime.now()
                .add(Duration(seconds: expiresIn))
                .millisecondsSinceEpoch,
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('StockX connected successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        debugPrint('[StockX OAuth] Tokens saved successfully');
      } else {
        debugPrint('[StockX OAuth] Token exchange failed: ${response.body}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect StockX. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[StockX OAuth] Token exchange error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect StockX. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _isScanning = false;
  bool _isLabelMode = false;
  bool _isProcessingOcr = false;

  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final ImagePicker _imagePicker = ImagePicker();

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

  /// Extract a sneaker style code from OCR text using brand-specific patterns.
  /// Extract a sneaker style code from OCR text.
  /// Handles variations in separators (dash, space, slash, dot, or missing)
  /// and normalizes the result to the canonical format with dashes.
  ({String? code, String? labelName}) _parseLabelInfo(String text) {
    // Normalize: collapse whitespace, uppercase
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

    // sep = flexible separator: dash, space, slash, dot, or nothing
    const sep = r'[-\s/.]*';

    // --- Code extraction (same logic as former _extractStyleCode) ---
    String? code;

    // --- Pass 1: Look for labeled codes (high confidence, avoids false positives) ---
    // Style/Style# label first — this is the actual product identifier that
    // KicksDB/StockX can look up. Must come before DPCI/SKU/ITEM which are
    // retailer-internal numbers useless for product search.
    // "STYLE# DD1391-100" or "STYLE: DD1391 100"
    final styleLabeled = RegExp(
      'STYLE[#:\\s]+([A-Z0-9][A-Z0-9\\-\\s/.]+[A-Z0-9])',
    ).firstMatch(normalized);
    if (styleLabeled != null) {
      final raw = styleLabeled.group(1)!.trim();
      code = raw.replaceAll(RegExp(r'[\s/.]+'), '-');
    }
    if (code == null) {
      // SKU label: "SKU: ..." or "SKU# ..."
      final skuLabeled = RegExp(
        'SKU[#:\\s]+([A-Z0-9][A-Z0-9\\-\\s/.]+[A-Z0-9])',
      ).firstMatch(normalized);
      if (skuLabeled != null) {
        final raw = skuLabeled.group(1)!.trim();
        code = raw.replaceAll(RegExp(r'[\s/.]+'), '-');
      }
    }
    if (code == null) {
      // Item# label: "ITEM# ..." or "ITEM: ..."
      final itemLabeled = RegExp(
        'ITEM[#:\\s]+([A-Z0-9][A-Z0-9\\-\\s/.]+[A-Z0-9])',
      ).firstMatch(normalized);
      if (itemLabeled != null) {
        final raw = itemLabeled.group(1)!.trim();
        code = raw.replaceAll(RegExp(r'[\s/.]+'), '-');
      }
    }
    // DPCI (Target) last — retailer inventory number, not a product identifier.
    // Only used as fallback if no style code, SKU, or item# was found.
    if (code == null) {
      final dpciLabeled = RegExp(
        'DPCI[:\\s]+(\\d{3})$sep(\\d{2})$sep(\\d{4})',
      ).firstMatch(normalized);
      if (dpciLabeled != null) {
        code =
            '${dpciLabeled.group(1)}-${dpciLabeled.group(2)}-${dpciLabeled.group(3)}';
      }
    }

    // --- Pass 2: Pattern-match common style code formats ---
    if (code == null) {
      final patterns = <(RegExp, String Function(String))>[
        // Nike/Jordan: DD1391-100, CT8012 170, FB8896/100, CW1590.100, DH9765002
        (
          RegExp('\\b([A-Z]{2,3}\\d{4})$sep(\\d{3})\\b'),
          (m) {
            final match = RegExp(
              '\\b([A-Z]{2,3}\\d{4})$sep(\\d{3})\\b',
            ).firstMatch(m)!;
            return '${match.group(1)}-${match.group(2)}';
          },
        ),
        // Jordan/UA 6-digit: 555088-134, 555088 134, 3026175-001
        (
          RegExp('\\b(\\d{6,7})$sep(\\d{3})\\b'),
          (m) {
            final match = RegExp('\\b(\\d{6,7})$sep(\\d{3})\\b').firstMatch(m)!;
            return '${match.group(1)}-${match.group(2)}';
          },
        ),
        // Puma: 374915-01, 374915 01
        (
          RegExp('\\b(\\d{6})$sep(\\d{2})\\b'),
          (m) {
            final match = RegExp('\\b(\\d{6})$sep(\\d{2})\\b').firstMatch(m)!;
            return '${match.group(1)}-${match.group(2)}';
          },
        ),
        // Adidas: GW2871, HP5582, IF1477 (2 letters + 4 digits)
        (RegExp(r'\b[A-Z]{2}\d{4}\b'), (m) => m),
        // New Balance: M990GL6, ML574EVG, M1080B12
        (RegExp(r'\bM[A-Z]?\d{3,4}[A-Z]{1,3}\d{0,2}\b'), (m) => m),
        // Converse: 162050C
        (RegExp(r'\b\d{6}C\b'), (m) => m),
      ];

      for (final (pattern, normalize) in patterns) {
        final match = pattern.firstMatch(normalized);
        if (match != null) {
          code = normalize(match.group(0)!);
          break;
        }
      }
    }

    // --- Label name extraction ---
    String? labelName;

    // Known retail brand names to look for in OCR text
    const knownBrands = [
      'GOODFELLOW',
      'CAT & JACK',
      'ALL IN MOTION',
      'A NEW DAY',
      'UNIVERSAL THREAD',
      'WILD FABLE',
      'ART CLASS',
      'SHADE & SHORE',
      'NIKE',
      'ADIDAS',
      'JORDAN',
      'NEW BALANCE',
      'PUMA',
      'REEBOK',
      'CONVERSE',
      'VANS',
      'ASICS',
      'SAUCONY',
      'UNDER ARMOUR',
      'HOKA',
      'ON RUNNING',
      'BROOKS',
      'FILA',
      'SKETCHERS',
      'SKECHERS',
      'CROCS',
      'BIRKENSTOCK',
      'DR. MARTENS',
      'TIMBERLAND',
      'CHAMPION',
      'LEVI\'S',
      'WRANGLER',
      'DICKIES',
    ];

    // 1. Try to find a brand from labeled fields: "BRAND: Goodfellow"
    String? foundBrand;
    final brandLabelMatch = RegExp(
      r'BRAND[:\s]+([A-Z][A-Z&\s]+)',
    ).firstMatch(normalized);
    if (brandLabelMatch != null) {
      foundBrand = brandLabelMatch.group(1)!.trim();
    }

    // 2. If no labeled brand, scan for known brand names in text
    if (foundBrand == null) {
      for (final brand in knownBrands) {
        if (normalized.contains(brand)) {
          foundBrand = brand;
          break;
        }
      }
    }

    // 3. Find product name: multi-word mostly-alphabetic lines that aren't codes/labels
    final lines = text.split(RegExp(r'[\n\r]+'));
    String? productName;
    final labelFieldPattern = RegExp(
      r'^(DPCI|STYLE|SKU|ITEM|BRAND|COLOR|SIZE|UPC|TCIN|BARCODE)[#:\s]',
      caseSensitive: false,
    );
    final codePattern = RegExp(
      r'^\d{3}-\d{2}-\d{4}$|^[A-Z]{2,3}\d{4}-\d{3}$|^\d{6,}$|^\d{12,13}$',
    );

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.length < 3) continue;
      // Skip lines that are label fields
      if (labelFieldPattern.hasMatch(trimmed)) continue;
      // Skip lines that look like codes/numbers
      if (codePattern.hasMatch(trimmed.toUpperCase())) continue;
      // Skip lines that are mostly digits/special chars
      final alphaCount = trimmed.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
      if (alphaCount < trimmed.length * 0.5) continue;
      // Skip single-word lines (likely labels like "SIZE", "COLOR")
      final words = trimmed.split(RegExp(r'\s+'));
      if (words.length < 2) continue;
      // Skip if it's a known brand line by itself
      if (foundBrand != null && trimmed.toUpperCase().trim() == foundBrand) {
        continue;
      }
      // This looks like a product name
      productName = trimmed;
      break;
    }

    // 4. Assemble label name: "Brand ProductName"
    if (foundBrand != null || productName != null) {
      // Title-case the brand
      String titleCase(String s) => s
          .split(' ')
          .map(
            (w) => w.isEmpty
                ? w
                : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
          )
          .join(' ');

      final parts = <String>[];
      if (foundBrand != null) {
        // Don't duplicate brand if product name already starts with it
        final brandTitle = titleCase(foundBrand);
        parts.add(brandTitle);
        if (productName != null &&
            !productName.toUpperCase().startsWith(foundBrand)) {
          parts.add(productName);
        } else if (productName != null) {
          parts.add(productName);
          parts.clear();
          parts.add(productName); // product name already contains brand
        }
      } else if (productName != null) {
        parts.add(productName);
      }
      labelName = parts.join(' ').trim();
      if (labelName.isEmpty) labelName = null;
    }

    return (code: code, labelName: labelName);
  }

  /// Opens camera via ImagePicker, runs OCR, extracts style code.
  Future<void> _captureAndProcessLabel() async {
    setState(() => _isProcessingOcr = true);

    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) {
        setState(() => _isProcessingOcr = false);
        return;
      }

      final inputImage = InputImage.fromFilePath(photo.path);
      final textRecognizer = TextRecognizer();

      try {
        final RecognizedText recognizedText = await textRecognizer.processImage(
          inputImage,
        );

        final fullText = recognizedText.text;
        debugPrint('OCR text: $fullText');

        final (:code, :labelName) = _parseLabelInfo(fullText);
        debugPrint('Parsed code: $code, labelName: $labelName');

        if (code != null || labelName != null) {
          // Found useful info — save and navigate
          final displayCode = code ?? labelName!;
          final scanId = await _saveScan(
            displayCode,
            'STYLE_CODE',
            labelName: labelName,
          );
          if (mounted) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ScanDetailPage(
                  scanId: scanId ?? '',
                  code: displayCode,
                  format: 'STYLE_CODE',
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                  labelName: labelName,
                ),
              ),
            );
          }
        } else {
          // No style code or label name found — show dialog with OCR text + manual entry
          if (mounted) {
            _showManualStyleCodeDialog(fullText);
          }
        }
      } finally {
        textRecognizer.close();
      }
    } catch (e) {
      debugPrint('OCR error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to process image: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingOcr = false);
      }
    }
  }

  void _showManualStyleCodeDialog(String ocrText) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ocrText.isEmpty ? 'Enter Style Code' : 'No Style Code Found',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ocrText.isEmpty
                    ? 'Type the style code from the shoe label or box.'
                    : 'We couldn\'t automatically detect a style code. You can enter it manually.',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: GoogleFonts.robotoMono(
                  fontSize: 16,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. DD1391-100',
                  hintStyle: GoogleFonts.robotoMono(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  filled: true,
                  fillColor: const Color(0xFF252525),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF646CFF),
                      width: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
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
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final code = controller.text.trim().toUpperCase();
                        if (code.isEmpty) return;
                        Navigator.of(context).pop();
                        final scanId = await _saveScan(code, 'STYLE_CODE');
                        if (mounted) {
                          await Navigator.of(this.context).push(
                            MaterialPageRoute(
                              builder: (context) => ScanDetailPage(
                                scanId: scanId ?? '',
                                code: code,
                                format: 'STYLE_CODE',
                                timestamp:
                                    DateTime.now().millisecondsSinceEpoch,
                              ),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF646CFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Look Up'),
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

  Future<String?> _saveScan(
    String code,
    String format, {
    String? labelName,
  }) async {
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
      'labelName': labelName,
    });

    // Try to fetch product info and update the scan (skip UPC lookups for style codes)
    if (format != 'STYLE_CODE') {
      _fetchAndUpdateProductInfo(code, scanRef);
    }

    // Return the scan ID
    return scanRef.key;
  }

  Future<void> _fetchAndUpdateProductInfo(
    String code,
    DatabaseReference scanRef,
  ) async {
    try {
      // Check if product info is already cached
      final cachedSnapshot = await _database
          .child('products')
          .child(code)
          .get();
      if (cachedSnapshot.exists) {
        final productInfo = Map<String, dynamic>.from(
          cachedSnapshot.value as Map,
        );
        if (productInfo['title'] != null &&
            productInfo['title'] != 'Product Not Found') {
          final isVerified = productInfo['gtinVerified'] == true;
          final images = productInfo['images'] as List?;
          final imageUrl = isVerified && images != null && images.isNotEmpty
              ? images[0]
              : null;
          final retailPrice = productInfo['retailPrice'] as String?;
          await scanRef.update({
            'productTitle': isVerified ? productInfo['title'] : null,
            'productImage': imageUrl,
            'retailPrice': isVerified ? retailPrice : null,
          });
        }
        return;
      }

      // Fetch from API
      final response = await http
          .get(
            Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$code'),
          )
          .timeout(const Duration(seconds: 10));

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
            final lrp = double.tryParse(
              item['lowest_recorded_price'].toString(),
            );
            if (lrp != null && lrp > 0) {
              retailPrice = lrp.toStringAsFixed(2);
            }
          } else if (lowestPrice != null) {
            retailPrice = lowestPrice.toStringAsFixed(2);
          }

          // Verify GTIN: compare normalized scanned barcode against product UPC/EAN
          final normalizedScanned = _ScanDetailPageState._normalizeGtin(code);
          final productUpc = (item['upc'] ?? item['ean'] ?? '').toString();
          final gtinMatch = productUpc.isNotEmpty &&
              _ScanDetailPageState._normalizeGtin(productUpc) == normalizedScanned;

          // Cache product info
          await _database.child('products').child(code).set({
            'title': title,
            'brand': item['brand'] ?? '',
            'description': item['description'] ?? '',
            'category': item['category'] ?? '',
            'images': images,
            'retailPrice': retailPrice,
            'upc': code,
            'gtinVerified': gtinMatch,
            'lastUpdated': ServerValue.timestamp,
          });

          // Update scan — only include title/image/price if GTIN verified
          await scanRef.update({
            'productTitle': gtinMatch ? title : null,
            'productImage': gtinMatch ? imageUrl : null,
            'retailPrice': gtinMatch ? retailPrice : null,
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
              _isLabelMode
                  ? 'Take a photo of a shoe label'
                  : 'Scan barcodes from sneaker boxes',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),

            // Barcode / Label mode toggle
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_isLabelMode) {
                          setState(() => _isLabelMode = false);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_isLabelMode
                              ? const Color(0xFF646CFF)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.qr_code_scanner,
                              size: 18,
                              color: !_isLabelMode
                                  ? Colors.white
                                  : Colors.grey[500],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Barcode',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: !_isLabelMode
                                    ? Colors.white
                                    : Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (!_isLabelMode) {
                          if (_isScanning) _stopScanning();
                          setState(() => _isLabelMode = true);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _isLabelMode
                              ? const Color(0xFF646CFF)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.label,
                              size: 18,
                              color: _isLabelMode
                                  ? Colors.white
                                  : Colors.grey[500],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Label',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _isLabelMode
                                    ? Colors.white
                                    : Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (!_isLabelMode) ...[
              // Barcode mode: camera preview
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
            ] else ...[
              // Label mode: photo capture for OCR
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: _isProcessingOcr
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(
                              color: Color(0xFF646CFF),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Reading label...',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt_rounded,
                              size: 64,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Take a photo of the shoe label\nor box with the style code',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isProcessingOcr
                      ? null
                      : () => _showManualStyleCodeDialog(''),
                  icon: const Icon(Icons.keyboard, size: 18),
                  label: const Text('Enter Style Code'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF646CFF),
                    side: const BorderSide(color: Color(0xFF646CFF)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessingOcr ? null : _captureAndProcessLabel,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Scan Label'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF646CFF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(
                      0xFF646CFF,
                    ).withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
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
    return FirebaseDatabase.instance
        .ref()
        .child('scans')
        .child(user?.uid ?? '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MapEntry<String, dynamic>> _filterScans(
    List<MapEntry<String, dynamic>> scans,
  ) {
    return scans.where((entry) {
      final scanData = Map<String, dynamic>.from(entry.value);
      final code = (scanData['code'] ?? '').toString().toLowerCase();
      final productTitle = (scanData['productTitle'] ?? '')
          .toString()
          .toLowerCase();
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
            final scanDay = DateTime(
              scanDate.year,
              scanDate.month,
              scanDate.day,
            );
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
            if (_customStartDate != null &&
                scanDate.isBefore(_customStartDate!)) {
              return false;
            }
            if (_customEndDate != null) {
              final endOfDay = DateTime(
                _customEndDate!.year,
                _customEndDate!.month,
                _customEndDate!.day,
                23,
                59,
                59,
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
    List<MapEntry<String, dynamic>> scans,
  ) {
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
      final weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      return weekdays[date.weekday - 1];
    } else {
      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
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
                  border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search by product name or barcode...',
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey[600],
                      fontSize: 15,
                    ),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
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
                              padding: const EdgeInsets.only(
                                left: 4,
                                bottom: 10,
                              ),
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
                                  bottom: index < scansInSection.length - 1
                                      ? 8
                                      : 0,
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
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
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
            child: Icon(Icons.search_off, size: 40, color: Colors.grey[600]),
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
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
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
    final isStyleCode = format == 'STYLE_CODE';
    final productTitle = scanData['productTitle'] as String?;
    final productImage = scanData['productImage'] as String?;
    final timestamp = scanData['timestamp'] as int?;
    final labelName = scanData['labelName'] as String?;
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
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () async {
          // Get state reference before async gap
          final mainScreenState = context
              .findAncestorStateOfType<_MainScreenState>();

          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ScanDetailPage(
                scanId: entry.key,
                code: code,
                format: format,
                timestamp: timestamp ?? 0,
                labelName: labelName,
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
            border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
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
                        color: hasProductInfo ? Colors.white : Colors.grey[400],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          isStyleCode ? Icons.label : Icons.qr_code,
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

enum MatchConfidence { verified, likely, unverified }

class ScanDetailPage extends StatefulWidget {
  final String scanId;
  final String code;
  final String format;
  final int timestamp;
  final String? labelName;

  const ScanDetailPage({
    super.key,
    required this.scanId,
    required this.code,
    required this.format,
    required this.timestamp,
    this.labelName,
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

  bool get _isStyleCode => widget.format == 'STYLE_CODE';

  MatchConfidence _matchConfidence = MatchConfidence.verified;
  bool _matchConfirmed = false;

  /// True when we have a verified GTIN/SKU match — only then show the product image.
  bool _gtinVerified = false;

  /// True when product identity is confirmed (exact GTIN/SKU match).
  /// Pricing is only fetched when this is true.
  bool _identityConfirmed = false;

  /// Fuzzy SneakerDB candidates shown when identity is NOT confirmed.
  List<Map<String, dynamic>> _sneakerDbCandidates = [];
  bool _isLoadingCandidates = false;

  /// Normalize a GTIN/UPC/EAN to a canonical 13-digit EAN-13 string for comparison.
  /// Strips leading/trailing whitespace, pads UPC-A (12 digits) to EAN-13,
  /// and strips leading zeros down to 13 digits for longer codes.
  static String _normalizeGtin(String raw) {
    final stripped = raw.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (stripped.isEmpty) return '';
    // UPC-A (12 digits) → EAN-13 by prepending '0'
    if (stripped.length == 12) return '0$stripped';
    // UPC-E (8 digits) or EAN-8 — keep as-is (too short to pad reliably)
    if (stripped.length <= 8) return stripped;
    // EAN-13 or longer — take rightmost 13 digits (strip leading zeros)
    if (stripped.length > 13) return stripped.substring(stripped.length - 13);
    return stripped;
  }

  void _computeMatchConfidence() {
    if (!_isStyleCode) {
      _matchConfidence = MatchConfidence.verified;
      return;
    }
    if (widget.labelName == null) {
      _matchConfidence = MatchConfidence.verified;
      return;
    }
    if (widget.code != widget.labelName) {
      _matchConfidence = MatchConfidence.verified;
      return;
    }
    // code == labelName means only labelName was found (no real style code)
    if (_productInfo != null && _productInfo!['notFound'] != true) {
      _matchConfidence = MatchConfidence.likely;
    } else {
      _matchConfidence = MatchConfidence.unverified;
    }
  }

  // KicksDB API key from kicks.dev
  static const String _kicksDbApiKey = 'KICKS-9C87-7171-ADAA-E89A98AF16B0';

  // Retailed.io API key
  static const String _retailedApiKey = '9f1dd4d2-44ea-406e-a702-8aae58796cba';

  // SneakerDB (RapidAPI) key
  static const String _sneakerDbApiKey = '462b41c4bcmshef496140a2f7292p1a09dcjsna243ae0d12fb';

  // eBay API credentials
  static const String _ebayClientId = 'BryceAlb-SneakerS-SBX-42fb30cc2-4d516ca4';
  static const String _ebayClientSecret = 'SBX-2fb30cc2aa64-5bdc-4bbf-a927-88b9';
  static const bool _ebayProduction = false; // Set to true for production

  // StockX Official API credentials
  static const String _stockXApiKey = 'u9jS7v0Ijs4fZBiOzial8hsa2cmFVmJ9SlchL1Ta';
  static const String _stockXClientId = 'b8EmWHz5tMJ2tZ3YC9b7SqKBDmcswG9p';
  static const String _stockXClientSecret = 'wx_nKf-U4kObQrbuovIvSbRJCA5Eq3My6iDNOuKwsDI3bBHDnUxNBmU6LzEtP7Gn';
  static const String _stockXRedirectUri = 'sneakerscanner://stockx-callback';

  // StockX OAuth token management (static so shared across instances)
  static String? _stockXAccessToken;
  static DateTime? _stockXTokenExpiry;
  static String? _stockXRefreshToken;
  static bool _stockXTokensLoaded = false;

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

  Future<void> _loadStockXTokens() async {
    if (_stockXTokensLoaded) return;
    _stockXTokensLoaded = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snapshot = await _database
          .child('stockxTokens')
          .child(user.uid)
          .get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        _stockXAccessToken = data['accessToken'] as String?;
        _stockXRefreshToken = data['refreshToken'] as String?;
        final expiresAt = data['expiresAt'] as int?;
        if (expiresAt != null) {
          _stockXTokenExpiry =
              DateTime.fromMillisecondsSinceEpoch(expiresAt);
        }
        debugPrint('[StockX OAuth] Tokens loaded from Firebase');
      }
    } catch (e) {
      debugPrint('[StockX OAuth] Error loading tokens: $e');
    }
  }

  Future<String?> _getStockXAccessToken() async {
    if (!_stockXTokensLoaded) {
      await _loadStockXTokens();
    }
    if (_stockXAccessToken != null &&
        _stockXTokenExpiry != null &&
        DateTime.now().isBefore(_stockXTokenExpiry!)) {
      return _stockXAccessToken;
    }
    if (_stockXRefreshToken != null) {
      final refreshed = await _refreshStockXToken();
      if (refreshed != null) return refreshed;
    }
    // Fallback: use client_credentials grant to get a token without user OAuth
    return await _fetchStockXClientCredentialsToken();
  }

  Future<String?> _fetchStockXClientCredentialsToken() async {
    try {
      debugPrint('[StockX OAuth] Requesting client_credentials token...');
      final response = await http.post(
        Uri.parse('https://accounts.stockx.com/oauth/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'client_credentials',
          'client_id': _stockXClientId,
          'client_secret': _stockXClientSecret,
          'audience': 'gateway.stockx.com',
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('[StockX OAuth] Client credentials status: ${response.statusCode}');
      debugPrint('[StockX OAuth] Client credentials body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _stockXAccessToken = data['access_token'] as String;
        final expiresIn = data['expires_in'] as int;
        _stockXTokenExpiry =
            DateTime.now().add(Duration(seconds: expiresIn - 60));
        debugPrint('[StockX OAuth] Client credentials token acquired');
        return _stockXAccessToken;
      } else {
        debugPrint('[StockX OAuth] Client credentials failed: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[StockX OAuth] Client credentials error: $e');
      return null;
    }
  }

  Future<String?> _refreshStockXToken() async {
    try {
      debugPrint('[StockX OAuth] Refreshing access token...');
      final response = await http.post(
        Uri.parse('https://accounts.stockx.com/oauth/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'client_id': _stockXClientId,
          'client_secret': _stockXClientSecret,
          'refresh_token': _stockXRefreshToken!,
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('[StockX OAuth] Refresh status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _stockXAccessToken = data['access_token'] as String;
        final newRefresh = data['refresh_token'] as String?;
        if (newRefresh != null) _stockXRefreshToken = newRefresh;
        final expiresIn = data['expires_in'] as int;
        _stockXTokenExpiry =
            DateTime.now().add(Duration(seconds: expiresIn - 60));

        // Save to Firebase
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await _database.child('stockxTokens').child(user.uid).set({
            'accessToken': _stockXAccessToken,
            'refreshToken': _stockXRefreshToken,
            'expiresAt': DateTime.now()
                .add(Duration(seconds: expiresIn))
                .millisecondsSinceEpoch,
          });
        }
        debugPrint('[StockX OAuth] Token refreshed successfully');
        return _stockXAccessToken;
      } else {
        debugPrint('[StockX OAuth] Refresh failed: ${response.body}');
        _stockXAccessToken = null;
        _stockXTokenExpiry = null;
        _stockXRefreshToken = null;
        return null;
      }
    } catch (e) {
      debugPrint('[StockX OAuth] Refresh error: $e');
      return null;
    }
  }

  static Future<void> launchStockXOAuth() async {
    final uri = Uri.parse(
      'https://accounts.stockx.com/authorize'
      '?response_type=code'
      '&client_id=$_stockXClientId'
      '&redirect_uri=${Uri.encodeComponent(_stockXRedirectUri)}'
      '&audience=gateway.stockx.com'
      '&scope=openid',
    );
    debugPrint('[StockX OAuth] Launching: $uri');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
            final scanData = Map<String, dynamic>.from(
              scanSnapshot.value as Map,
            );
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
          final cached = Map<String, dynamic>.from(
            cachedSnapshot.value as Map,
          );
          // Determine identity confirmation from cache
          bool confirmed = false;
          if (_isStyleCode) {
            final bool hasRealCode =
                widget.labelName == null || widget.code != widget.labelName;
            confirmed = hasRealCode && cached['notFound'] != true;
          } else {
            confirmed = cached['gtinVerified'] == true;
          }

          setState(() {
            _productInfo = cached;
            _gtinVerified = cached['gtinVerified'] == true;
            _identityConfirmed = confirmed;
            _isLoading = false;
            _computeMatchConfidence();
          });
          // Fetch marketplace prices in background
          _fetchAllPrices();
          return;
        }
      }

      // If not cached, try to look up the product
      await _lookupProduct();
      // Fetch marketplace prices after product lookup
      _fetchAllPrices();
    } catch (e) {
      setState(() {
        _error = 'Failed to load product info';
        _isLoading = false;
      });
    }
  }

  /// Look up a barcode via Retailed.io variant database.
  /// Returns a product info map with retailedStockXSlug if found, null otherwise.
  Future<Map<String, dynamic>?> _lookupRetailedBarcode() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://app.retailed.io/api/v1/db/variants'
              '?where[or][0][and][0][id][equals]=${Uri.encodeComponent(widget.code)}',
            ),
            headers: {'x-api-key': _retailedApiKey},
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('Retailed barcode lookup status: ${response.statusCode}');
      debugPrint(
        'Retailed barcode body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
      );

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;

      final docs = body['docs'] as List?;
      if (docs == null || docs.isEmpty) return null;

      final doc = docs[0] as Map<String, dynamic>;
      final title = (doc['title'] ?? '').toString();
      final brand = (doc['brand'] ?? '').toString();
      final sku = (doc['sku'] ?? '').toString();
      final category = (doc['category'] ?? '').toString();

      // Validate it looks like footwear
      final compatProduct = <String, dynamic>{
        'title': title,
        'brand': brand,
        'category': category,
        'slug': '',
      };
      if (!_looksLikeFootwear(compatProduct)) {
        debugPrint('Retailed barcode skip (not footwear): "$title"');
        return null;
      }

      // Extract StockX slug from products array
      String? stockXSlug;
      final products = doc['products'] as List?;
      if (products != null) {
        for (final p in products) {
          final url = (p['url'] ?? '').toString();
          if (url.contains('stockx.com')) {
            final slug = (p['urlSlug'] ?? '').toString();
            if (slug.isNotEmpty) {
              stockXSlug = slug;
              break;
            }
          }
        }
      }

      debugPrint('Retailed barcode matched: "$title" slug="$stockXSlug" sku="$sku"');
      return <String, dynamic>{
        'title': title,
        'brand': brand,
        'description': '',
        'category': category.isNotEmpty ? category : 'Sneakers',
        'images': <String>[],
        'retailPrice': null,
        'styleCode': sku.isNotEmpty ? sku : widget.code,
        'sku': sku,
        'gtinVerified': true, // Queried by exact GTIN
        'lastUpdated': ServerValue.timestamp,
        if (stockXSlug != null && stockXSlug.isNotEmpty)
          'retailedStockXSlug': stockXSlug,
      };
    } catch (e) {
      debugPrint('Retailed barcode error: $e');
      return null;
    }
  }

  Future<void> _lookupProduct() async {
    if (_isStyleCode) {
      await _lookupProductByStyleCode();
      return;
    }

    Map<String, dynamic>? productInfo;
    String? retailPrice;

    try {
      // Normalize the scanned GTIN for comparison
      final normalizedGtin = _normalizeGtin(widget.code);

      // Try Retailed.io barcode lookup first (exact GTIN match)
      productInfo = await _lookupRetailedBarcode();
      if (productInfo != null) {
        productInfo['lastUpdated'] = ServerValue.timestamp;
        await _database.child('products').child(widget.code).set(productInfo);
        setState(() {
          _productInfo = productInfo;
          _gtinVerified = true; // Retailed queried by exact GTIN
          _identityConfirmed = true; // Exact GTIN match → confirmed
          _isLoading = false;
        });
        return;
      }

      // Fallback: Try UPCitemdb API (free tier)
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

        // Verify GTIN match: compare normalized scanned barcode against product UPC/EAN
        final productUpc = (productInfo['upc'] ?? productInfo['ean'] ?? '').toString();
        final gtinMatch = productUpc.isNotEmpty &&
            _normalizeGtin(productUpc) == normalizedGtin;

        setState(() {
          _productInfo = productInfo;
          _gtinVerified = gtinMatch;
          _identityConfirmed = gtinMatch && _looksLikeFootwear(productInfo!);
          _isLoading = false;
        });
        return;
      }

      // If all API lookups fail, set as not found
      setState(() {
        _productInfo = {
          'title': 'Product Not Found',
          'brand': '',
          'description':
              'We couldn\'t find information for this barcode. Try searching on eBay.',
          'upc': widget.code,
          'notFound': true,
        };
        _identityConfirmed = false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _productInfo = {
          'title': 'Product Not Found',
          'brand': '',
          'description':
              'We couldn\'t find information for this barcode. Try searching on eBay.',
          'upc': widget.code,
          'notFound': true,
        };
        _identityConfirmed = false;
        _isLoading = false;
      });
    }
  }

  /// Known footwear brands — if the API result is from one of these,
  /// we trust it as a shoe without needing keyword heuristics.
  static const _knownFootwearBrands = {
    'nike',
    'jordan',
    'adidas',
    'new balance',
    'asics',
    'converse',
    'vans',
    'puma',
    'reebok',
    'on',
    'hoka',
    'salomon',
    'saucony',
    'under armour',
    'brooks',
    'mizuno',
    'diadora',
    'fila',
    'timberland',
    'dr. martens',
    'ugg',
    'birkenstock',
    'crocs',
    'yeezy',
    'off-white',
    'fear of god',
    'rick owens',
  };

  /// Retailer / private-label brands that sell mixed categories.
  /// These don't exist on StockX/GOAT, so results are always wrong.
  static const _retailerLabels = {
    'goodfellow',
    'cat & jack',
    'cat and jack',
    'universal thread',
    'a new day',
    'all in motion',
    'wild fable',
    'prologue',
    'george',
    'wonder nation',
    'time and tru',
    'athletic works',
    'no boundaries',
    'kirkland',
    'amazon essentials',
    'wrangler',
    'fruit of the loom',
    'hanes',
    'starter',
    'and1',
    'champion c9',
    'avia',
  };

  /// Footwear-related keywords for products from non-listed brands.
  static const _footwearKeywords = [
    'sneakers',
    'sneaker',
    'shoes',
    'shoe',
    'footwear',
    'boots',
    'boot',
    'sandals',
    'sandal',
    'slides',
    'slide',
    'clogs',
    'clog',
    'mules',
    'mule',
    'slippers',
    'slipper',
    'trainers',
    'trainer',
    'runners',
    'runner',
    'dunk',
    'jordan',
    'yeezy',
    'air max',
    'air force',
    'foam runner',
    'new balance',
    'ultraboost',
    'gel-',
  ];

  /// Returns true if the KicksDB product looks like footwear.
  /// Known footwear brands pass automatically; others need keyword evidence.
  bool _looksLikeFootwear(Map<String, dynamic> product) {
    final brand = (product['brand'] ?? '').toString().toLowerCase().trim();

    // Known footwear brand → always footwear (require 2+ chars to avoid
    // empty-string matching — ''.contains('') is always true in Dart)
    if (brand.length >= 2 &&
        _knownFootwearBrands.any(
          (b) => brand.contains(b) || b.contains(brand),
        )) {
      return true;
    }

    // Fall back to keyword scan of category + title + slug
    final category = (product['category'] ?? '').toString().toLowerCase();
    final title = (product['title'] ?? product['name'] ?? '')
        .toString()
        .toLowerCase();
    final slug = (product['slug'] ?? '').toString().toLowerCase();
    final combined = '$category $title $slug';
    return _footwearKeywords.any((kw) => combined.contains(kw));
  }

  /// Returns true if [text] contains a retailer / private-label brand name.
  static bool _isRetailerLabel(String text) {
    final lower = text.toLowerCase();
    return _retailerLabels.any((label) => lower.contains(label));
  }

  /// Returns true if [product] from KicksDB plausibly matches the scanned
  /// label text (brand + keyword overlap).
  bool _resultMatchesLabel(Map<String, dynamic> product, String query) {
    final apiTitle = (product['title'] ?? product['name'] ?? '')
        .toString()
        .toLowerCase();
    final apiBrand = (product['brand'] ?? '').toString().toLowerCase();
    final queryLower = query.toLowerCase();

    // Extract significant words (3+ chars) from query and API title
    final queryWords = queryLower
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();
    final apiWords = '$apiBrand $apiTitle'
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();

    if (queryWords.isEmpty) return false;

    final overlap = queryWords.intersection(apiWords);
    // Require at least 2 overlapping significant words, or >50% of query words
    return overlap.length >= 2 || overlap.length > queryWords.length * 0.5;
  }

  /// Search KicksDB StockX for a product by query string.
  /// [isStyleCodeSearch] true when the query is an exact style code (e.g. DD1391-100).
  /// Returns the first validated product info map, or null if nothing appropriate is found.
  Future<Map<String, dynamic>?> _searchKicksDb(
    String query, {
    bool isStyleCodeSearch = false,
  }) async {
    // Label-name searches from retailer/private labels won't exist on StockX
    if (!isStyleCodeSearch && _isRetailerLabel(query)) {
      debugPrint('KicksDB skip: query "$query" is a retailer/private label');
      return null;
    }

    final response = await http
        .get(
          Uri.parse(
            'https://api.kicks.dev/v3/stockx/products'
            '?query=${Uri.encodeComponent(query)}&limit=5'
            '&display[prices]=true&display[variants]=false',
          ),
          headers: {'Authorization': 'Bearer $_kicksDbApiKey'},
        )
        .timeout(const Duration(seconds: 10));

    debugPrint('KicksDB lookup ($query) status: ${response.statusCode}');
    debugPrint(
      'KicksDB lookup body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
    );

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body);
    List<dynamic> items = [];
    if (body is Map<String, dynamic> &&
        body.containsKey('data') &&
        body['data'] is List) {
      items = body['data'];
    } else if (body is List) {
      items = body;
    }

    if (items.isEmpty) return null;

    // Walk candidates and pick the first that passes validation
    for (final item in items) {
      final product = item as Map<String, dynamic>;
      final title = product['title'] ?? product['name'] ?? 'Unknown Product';
      final brand = product['brand'] ?? '';
      final image = product['image'] ?? product['thumbnail'] ?? '';
      final retailPrice = product['retail_price']?.toString();
      final styleId = (product['style_id'] ?? '')
          .toString()
          .replaceAll(' ', '-')
          .toUpperCase();

      // --- Validation gates ---

      // 1. Reject retailer / private-label brands
      if (_isRetailerLabel(brand.toString())) {
        debugPrint('KicksDB skip (retailer label): "$title" brand="$brand"');
        continue;
      }

      // 2. Must look like footwear
      if (!_looksLikeFootwear(product)) {
        debugPrint('KicksDB skip (not footwear): "$title"');
        continue;
      }

      // 3. Style-code search: the style code must appear in the product data
      if (isStyleCodeSearch) {
        final queryNorm = query.replaceAll(' ', '-').toUpperCase();
        // Check style_id first (most reliable)
        if (styleId.isNotEmpty && styleId == queryNorm) {
          // exact match — accept
        } else {
          // Fallback: check if the style code appears anywhere in the
          // product's title, slug, or description (handles APIs that omit
          // style_id but embed it in the title, e.g. "Nike Dunk Low DD1391-100")
          final titleUpper = title.toString().toUpperCase();
          final slugUpper = (product['slug'] ?? '')
              .toString()
              .replaceAll('-', ' ')
              .toUpperCase();
          if (!titleUpper.contains(queryNorm) &&
              !titleUpper.contains(queryNorm.replaceAll('-', ' ')) &&
              !slugUpper.contains(queryNorm.replaceAll('-', ' '))) {
            debugPrint(
              'KicksDB skip (style code "$queryNorm" not found in product): "$title" style_id="$styleId"',
            );
            continue;
          }
        }
      }

      // 4. Label-name search: require brand/keyword overlap
      if (!isStyleCodeSearch && !_resultMatchesLabel(product, query)) {
        debugPrint(
          'KicksDB skip (label mismatch): "$title" for query "$query"',
        );
        continue;
      }

      return <String, dynamic>{
        'title': title,
        'brand': brand,
        'description': '',
        'category': (product['category'] ?? 'Sneakers').toString(),
        'images': image is String && image.isNotEmpty ? [image] : [],
        'retailPrice': retailPrice,
        'styleCode': widget.code,
        'gtinVerified': isStyleCodeSearch, // exact style_id match
        'lastUpdated': ServerValue.timestamp,
      };
    }

    debugPrint(
      'KicksDB: no valid match for "$query" out of ${items.length} candidates',
    );
    return null;
  }

  /// Search Retailed.io StockX for a product by query string.
  /// [isStyleCodeSearch] true when the query is an exact style code.
  /// Returns the first validated product info map, or null if nothing found.
  Future<Map<String, dynamic>?> _searchRetailed(
    String query, {
    bool isStyleCodeSearch = false,
  }) async {
    // Label-name searches from retailer/private labels won't exist on StockX
    if (!isStyleCodeSearch && _isRetailerLabel(query)) {
      debugPrint('Retailed skip: query "$query" is a retailer/private label');
      return null;
    }

    try {
      final response = await http
          .get(
            Uri.parse(
              'https://app.retailed.io/api/v1/stockx/search'
              '?query=${Uri.encodeComponent(query)}',
            ),
            headers: {'x-api-key': _retailedApiKey},
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('Retailed search ($query) status: ${response.statusCode}');
      debugPrint(
        'Retailed search body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
      );

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      List<dynamic> items = [];
      if (body is List) {
        items = body;
      } else if (body is Map<String, dynamic> && body.containsKey('data') && body['data'] is List) {
        items = body['data'];
      }

      if (items.isEmpty) return null;

      for (final item in items) {
        final product = item as Map<String, dynamic>;
        final name = (product['name'] ?? '').toString();
        final brand = (product['brand'] ?? '').toString();
        final sku = (product['sku'] ?? '').toString();
        final slug = (product['slug'] ?? '').toString();
        final category = (product['category'] ?? '').toString();
        final image = (product['image'] ?? '').toString();

        // 1. Reject retailer / private-label brands
        if (_isRetailerLabel(brand)) {
          debugPrint('Retailed skip (retailer label): "$name" brand="$brand"');
          continue;
        }

        // 2. Must look like footwear (map name→title for compatibility)
        final compatProduct = <String, dynamic>{
          'title': name,
          'brand': brand,
          'category': category,
          'slug': slug,
        };
        if (!_looksLikeFootwear(compatProduct)) {
          debugPrint('Retailed skip (not footwear): "$name"');
          continue;
        }

        // 3. Style-code search: sku must match query
        if (isStyleCodeSearch) {
          final queryNorm = query.replaceAll(' ', '-').toUpperCase();
          final skuNorm = sku.replaceAll(' ', '-').toUpperCase();
          if (skuNorm.isEmpty || skuNorm != queryNorm) {
            // Also check if SKU appears in name
            final nameUpper = name.toUpperCase();
            if (!nameUpper.contains(queryNorm) &&
                !nameUpper.contains(queryNorm.replaceAll('-', ' '))) {
              debugPrint(
                'Retailed skip (style code "$queryNorm" != sku "$skuNorm"): "$name"',
              );
              continue;
            }
          }
        }

        // 4. Label-name search: require brand/keyword overlap
        if (!isStyleCodeSearch && !_resultMatchesLabel(compatProduct, query)) {
          debugPrint(
            'Retailed skip (label mismatch): "$name" for query "$query"',
          );
          continue;
        }

        debugPrint('Retailed matched: "$name" slug="$slug"');
        return <String, dynamic>{
          'title': name,
          'brand': brand,
          'description': '',
          'category': category.isNotEmpty ? category : 'Sneakers',
          'images': image.isNotEmpty ? [image] : [],
          'retailPrice': null,
          'styleCode': widget.code,
          'gtinVerified': isStyleCodeSearch, // exact sku match
          'lastUpdated': ServerValue.timestamp,
          'retailedStockXSlug': slug,
        };
      }

      debugPrint(
        'Retailed: no valid match for "$query" out of ${items.length} candidates',
      );
      return null;
    } catch (e) {
      debugPrint('Retailed search error: $e');
      return null;
    }
  }

  /// Search SneakerDB (RapidAPI) for a product by exact style code (sku filter).
  /// Returns the first product whose sku matches [styleCode] exactly, or null.
  Future<Map<String, dynamic>?> _searchSneakerDb(String styleCode) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://the-sneaker-database.p.rapidapi.com/sneakers'
              '?limit=10&sku=${Uri.encodeComponent(styleCode)}',
            ),
            headers: {
              'x-rapidapi-host': 'the-sneaker-database.p.rapidapi.com',
              'x-rapidapi-key': _sneakerDbApiKey,
            },
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('SneakerDB lookup ($styleCode) status: ${response.statusCode}');
      debugPrint(
        'SneakerDB body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
      );

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;

      final results = body['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final queryNorm = styleCode.replaceAll(' ', '-').toUpperCase();

      for (final item in results) {
        final product = item as Map<String, dynamic>;
        final sku = (product['sku'] ?? '').toString().replaceAll(' ', '-').toUpperCase();
        final name = (product['name'] ?? '').toString();
        final brand = (product['brand'] ?? '').toString();

        // Exact sku match only
        if (sku != queryNorm) {
          debugPrint('SneakerDB skip (sku "$sku" != "$queryNorm"): "$name"');
          continue;
        }

        // Extract image
        final imageData = product['image'] as Map<String, dynamic>?;
        final image = (imageData?['original'] ?? imageData?['small'] ?? '').toString();

        // Extract retail price
        final retailPrice = product['retailPrice'];
        final retailPriceStr = retailPrice != null && retailPrice != 0
            ? retailPrice.toString()
            : null;

        // Extract StockX slug from links
        String? stockXSlug;
        final links = product['links'] as Map<String, dynamic>?;
        if (links != null) {
          final stockXUrl = (links['stockX'] ?? '').toString();
          if (stockXUrl.contains('stockx.com/')) {
            stockXSlug = stockXUrl.split('stockx.com/').last.split('?').first;
          }
        }

        // Extract GOAT slug from links
        String? goatSlug;
        if (links != null) {
          final goatUrl = (links['goat'] ?? '').toString();
          if (goatUrl.contains('goat.com/sneakers/')) {
            goatSlug = goatUrl.split('goat.com/sneakers/').last.split('?').first;
          }
        }

        debugPrint('SneakerDB matched: "$name" sku="$sku" stockXSlug="$stockXSlug"');
        return <String, dynamic>{
          'title': name,
          'brand': brand,
          'description': (product['story'] ?? '').toString(),
          'category': 'Sneakers',
          'colorway': (product['colorway'] ?? '').toString(),
          'images': image.isNotEmpty ? [image] : [],
          'retailPrice': retailPriceStr,
          'styleCode': widget.code,
          'gtinVerified': true, // exact sku match
          'lastUpdated': ServerValue.timestamp,
          'estimatedMarketValue': product['estimatedMarketValue'],
          if (stockXSlug != null && stockXSlug.isNotEmpty)
            'retailedStockXSlug': stockXSlug,
          if (goatSlug != null && goatSlug.isNotEmpty)
            'goatSlug': goatSlug,
        };
      }

      debugPrint('SneakerDB: no exact sku match for "$styleCode"');
      return null;
    } catch (e) {
      debugPrint('SneakerDB search error: $e');
      return null;
    }
  }

  /// Look up product info by style code: KicksDB → SneakerDB → Retailed → NOT_FOUND.
  /// Requires exact style code match at each step — does not guess.
  Future<void> _lookupProductByStyleCode() async {
    try {
      // Determine if we have a real style code vs only a labelName echo
      final bool hasRealCode =
          widget.labelName == null || widget.code != widget.labelName;

      Map<String, dynamic>? productInfo;

      if (hasRealCode) {
        // === Identity Phase: exact style code matching only ===

        // 1. KicksDB — search by style code, accept only exact style_id match
        debugPrint('Identity phase 1: KicksDB style code search for ${widget.code}');
        productInfo = await _searchKicksDb(
          widget.code,
          isStyleCodeSearch: true,
        );

        // 2. SneakerDB — search by sku filter, accept only exact sku match
        if (productInfo == null) {
          debugPrint('Identity phase 2: SneakerDB style code search for ${widget.code}');
          productInfo = await _searchSneakerDb(widget.code);
        }

        // 3. Retailed — only if both above fail, must verify returned style code
        if (productInfo == null) {
          debugPrint('Identity phase 3: Retailed style code search for ${widget.code}');
          productInfo = await _searchRetailed(
            widget.code,
            isStyleCodeSearch: true,
          );
        }
      }

      // If no real style code (label name only), try label-name searches as fallback
      if (productInfo == null && widget.labelName != null && !hasRealCode) {
        debugPrint('No real style code, trying label name searches: ${widget.labelName}');
        productInfo = await _searchKicksDb(
          widget.labelName!,
          isStyleCodeSearch: false,
        );
        productInfo ??= await _searchRetailed(
          widget.labelName!,
          isStyleCodeSearch: false,
        );
      }

      if (productInfo != null) {
        final title = productInfo['title'];
        final isVerified = productInfo['gtinVerified'] == true;
        final image = isVerified &&
                (productInfo['images'] as List?)?.isNotEmpty == true
            ? productInfo['images'][0]
            : null;
        final retailPrice = productInfo['retailPrice'];

        // Cache in Firebase
        await _database.child('products').child(widget.code).set(productInfo);

        // Update scan record (only include title/image/price if GTIN verified)
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && widget.scanId.isNotEmpty) {
          await _database
              .child('scans')
              .child(user.uid)
              .child(widget.scanId)
              .update({
                'productTitle': isVerified ? title : null,
                'productImage': isVerified && image is String && image.isNotEmpty
                    ? image
                    : null,
                'retailPrice': isVerified ? retailPrice : null,
              });
        }

        setState(() {
          _productInfo = productInfo;
          _gtinVerified = isVerified;
          // Identity confirmed only if we had a real style code AND got an exact match
          _identityConfirmed = hasRealCode;
          _isLoading = false;
          _computeMatchConfidence();
        });
        return;
      }

      // Not found — use labelName as title if available
      setState(() {
        _productInfo = {
          'title': widget.labelName ?? 'Product Not Found',
          'brand': '',
          'description': widget.labelName != null
              ? 'No exact match found. Prices may still load below.'
              : 'No product found for style code ${widget.code}. Prices may still load below.',
          'styleCode': widget.code,
          'notFound': true,
        };
        _identityConfirmed = false;
        _isLoading = false;
        _computeMatchConfidence();
      });
    } catch (e) {
      debugPrint('Style code lookup error: $e');
      setState(() {
        _productInfo = {
          'title': widget.labelName ?? 'Product Not Found',
          'brand': '',
          'description': widget.labelName != null
              ? 'No exact match found. Prices may still load below.'
              : 'No product found for style code ${widget.code}. Prices may still load below.',
          'styleCode': widget.code,
          'notFound': true,
        };
        _identityConfirmed = false;
        _isLoading = false;
        _computeMatchConfidence();
      });
    }
  }

  Future<Map<String, dynamic>?> _tryUpcItemDb() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://api.upcitemdb.com/prod/trial/lookup?upc=${widget.code}',
            ),
          )
          .timeout(const Duration(seconds: 10));

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
            final lrp = double.tryParse(
              item['lowest_recorded_price'].toString(),
            );
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
      final response = await http
          .get(
            Uri.parse(
              'https://world.openfoodfacts.org/api/v0/product/${widget.code}.json',
            ),
          )
          .timeout(const Duration(seconds: 8));

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
      final response = await http
          .get(
            Uri.parse('https://go-upc.com/api/v1/code/${widget.code}'),
            headers: {
              'Authorization':
                  'Bearer YOUR_GO_UPC_API_KEY', // Replace with your key
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['product'] != null) {
          final product = data['product'];
          String? retailPrice;

          // Extract price if available
          if (product['specs'] != null) {
            final specs = product['specs'];
            if (specs['msrp'] != null) {
              final msrp = double.tryParse(
                specs['msrp'].toString().replaceAll(RegExp(r'[^\d.]'), ''),
              );
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
    final bool hasRealStyleCode =
        _isStyleCode &&
        (widget.labelName == null || widget.code != widget.labelName);

    // 1. Style code (only if real — not just labelName echoed back)
    if (hasRealStyleCode) {
      return widget.code;
    }

    // 2. Brand + model from product info
    if (brand != null &&
        brand.isNotEmpty &&
        model != null &&
        model.isNotEmpty) {
      return '$brand $model';
    }

    // 3. Title from product info (truncated for StockX)
    if (title != null && title != 'Product Not Found') {
      if (forStockX) {
        final words = title.split(' ');
        if (words.length > 6) {
          return words.take(6).join(' ');
        }
      }
      return title;
    }

    // 4. Fallback
    return widget.labelName ?? widget.code;
  }

  Future<void> _openEbaySearch() async {
    final searchQuery = _buildSearchQuery();
    final url = Uri.parse(
      'https://www.ebay.com/sch/i.html?_nkw=${Uri.encodeComponent(searchQuery)}',
    );
    await launchUrl(url, mode: LaunchMode.platformDefault);
  }

  Future<void> _openStockXSearch() async {
    if (_stockXSlug != null && _stockXSlug!.isNotEmpty) {
      final url = Uri.parse('https://stockx.com/$_stockXSlug');
      await launchUrl(url, mode: LaunchMode.platformDefault);
    } else {
      // Fallback: search by product title on StockX
      final title = _productInfo?['title'] as String?;
      if (title != null) {
        final url = Uri.parse(
          'https://stockx.com/search?s=${Uri.encodeComponent(title)}',
        );
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    }
  }

  Future<void> _openGoatSearch() async {
    if (_goatSlug != null && _goatSlug!.isNotEmpty) {
      final url = Uri.parse('https://www.goat.com/sneakers/$_goatSlug');
      await launchUrl(url, mode: LaunchMode.platformDefault);
    } else {
      // Fallback: search by product title on GOAT
      final title = _productInfo?['title'] as String?;
      if (title != null) {
        final url = Uri.parse(
          'https://www.goat.com/search?query=${Uri.encodeComponent(title)}',
        );
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
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

      final credentials = base64Encode(
        utf8.encode('$_ebayClientId:$_ebayClientSecret'),
      );

      final response = await http
          .post(
            Uri.parse('$baseUrl/identity/v1/oauth2/token'),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Authorization': 'Basic $credentials',
            },
            body:
                'grant_type=client_credentials&scope=https://api.ebay.com/oauth/api_scope',
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _ebayAccessToken = data['access_token'];
        final expiresIn = data['expires_in'] as int;
        _ebayTokenExpiry = DateTime.now().add(
          Duration(seconds: expiresIn - 60),
        ); // Buffer
        return _ebayAccessToken;
      }
    } catch (e) {
      debugPrint('eBay OAuth error: $e');
    }
    return null;
  }

  Future<void> _fetchEbayPrices() async {
    if (_productInfo == null) return;
    final stopwatch = Stopwatch()..start();

    setState(() {
      _isLoadingEbayPrices = true;
      _ebayError = null;
    });

    try {
      final token = await _getEbayAccessToken();

      if (token == null) {
        debugPrint('[eBay] API not configured, skipping');
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

      final requestUrl = '$baseUrl/buy/browse/v1/item_summary/search?'
          'q=${Uri.encodeComponent(searchQuery)}'
          '&category_ids=93427'
          '&limit=50'
          '&sort=price';
      debugPrint('[eBay] Request: $requestUrl');

      final response = await http
          .get(
            Uri.parse(requestUrl),
            headers: {
              'Authorization': 'Bearer $token',
              'X-EBAY-C-MARKETPLACE-ID': 'EBAY_US',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('[eBay] Status: ${response.statusCode}');
      debugPrint('[eBay] Body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');

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
            debugPrint('[eBay] avg=\$${(totalPrice / validPrices).toStringAsFixed(2)} '
                'lowest=\$${lowestPrice?.toStringAsFixed(2)} '
                'listings=$validPrices (${stopwatch.elapsedMilliseconds}ms)');
            setState(() {
              _ebayLowestPrice = lowestPrice;
              _ebayAveragePrice = totalPrice / validPrices;
              _ebayListingCount = validPrices;
              _isLoadingEbayPrices = false;
            });
            return;
          }
        }
      }

      debugPrint('[eBay] No listings found (${stopwatch.elapsedMilliseconds}ms)');
      setState(() {
        _isLoadingEbayPrices = false;
        _ebayError = 'No listings found';
      });
    } catch (e) {
      debugPrint('[eBay] Error: $e (${stopwatch.elapsedMilliseconds}ms)');
      setState(() {
        _isLoadingEbayPrices = false;
        _ebayError = 'Failed to fetch prices';
      });
    }
  }

  /// Checks if an API result matches the scanned product by comparing brand
  /// and key words from the product title. Returns false if the result is
  /// clearly for a different product (e.g. a jacket when we scanned a shoe).
  bool _isProductMatch(Map<String, dynamic> apiProduct) {
    // Must be footwear regardless of scan type
    if (!_looksLikeFootwear(apiProduct)) return false;

    final scannedBrand =
        (_productInfo?['brand'] as String?)?.toLowerCase().trim() ?? '';
    final scannedTitle =
        (_productInfo?['title'] as String?)?.toLowerCase().trim() ?? '';
    final scannedModel =
        (_productInfo?['model'] as String?)?.toLowerCase().trim() ?? '';

    final apiTitle =
        ((apiProduct['title'] ?? apiProduct['name'] ?? '') as String)
            .toLowerCase()
            .trim();
    final apiBrand = ((apiProduct['brand'] ?? '') as String)
        .toLowerCase()
        .trim();

    // If we have no scanned product info, can't validate further
    if (scannedBrand.isEmpty && scannedTitle.isEmpty) return true;

    // Check brand match
    if (scannedBrand.isNotEmpty && apiBrand.isNotEmpty) {
      if (!apiBrand.contains(scannedBrand) &&
          !scannedBrand.contains(apiBrand)) {
        return false;
      }
    }

    // Check if the API title shares key words with scanned title/model
    if (scannedModel.isNotEmpty && apiTitle.contains(scannedModel)) return true;

    // Check for overlapping significant words (3+ chars) between titles
    final scannedWords = scannedTitle
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();
    final apiWords = apiTitle
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();
    final overlap = scannedWords.intersection(apiWords);

    // Require at least 2 overlapping words to consider it a match
    if (scannedWords.isNotEmpty && apiWords.isNotEmpty && overlap.length < 2) {
      return false;
    }

    return true;
  }

  // Shared price cache TTL: 24 hours (matches KicksDB data refresh rate)
  static const int _priceCacheTtlMs = 24 * 60 * 60 * 1000;
  static const bool _priceCacheEnabled =
      false; // Toggle to true to re-enable price caching

  Future<void> _fetchAllPrices() async {
    if (_productInfo == null) return;

    setState(() {
      _isLoadingStockXPrice = true;
      _isLoadingGoatPrice = true;
    });

    // Check shared price cache first
    if (_priceCacheEnabled) {
      try {
        final cacheSnapshot = await _database
            .child('priceCache')
            .child(widget.code)
            .get();

        if (cacheSnapshot.exists) {
          final cacheData = Map<String, dynamic>.from(
            cacheSnapshot.value as Map,
          );
          final cachedAt = cacheData['cachedAt'] as int?;
          final now = DateTime.now().millisecondsSinceEpoch;

          if (cachedAt != null && (now - cachedAt) < _priceCacheTtlMs) {
            final cachedStockX = double.tryParse(
              (cacheData['stockxPrice'] ?? '').toString(),
            );
            final cachedGoat = double.tryParse(
              (cacheData['goatPrice'] ?? '').toString(),
            );
            setState(() {
              _stockXPrice = (cachedStockX != null && cachedStockX > 0)
                  ? cachedStockX
                  : null;
              _stockXSlug = (cachedStockX != null && cachedStockX > 0)
                  ? cacheData['stockxSlug'] as String?
                  : null;
              _goatPrice = (cachedGoat != null && cachedGoat > 0)
                  ? cachedGoat
                  : null;
              _goatSlug = (cachedGoat != null && cachedGoat > 0)
                  ? cacheData['goatSlug'] as String?
                  : null;
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
    }

    // Gate: only fetch prices if identity is confirmed
    if (!_identityConfirmed) {
      debugPrint('');
      debugPrint('╔══════════════════════════════════════════════════════════════╗');
      debugPrint('║  PRICING SKIPPED — running fuzzy SneakerDB search instead');
      debugPrint('║  Code: ${widget.code}');
      debugPrint('╚══════════════════════════════════════════════════════════════╝');
      debugPrint('');
      setState(() {
        _isLoadingStockXPrice = false;
        _isLoadingGoatPrice = false;
      });
      await _fetchSneakerDbFuzzyCandidates();
      return;
    }

    final totalStopwatch = Stopwatch()..start();
    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════════════════════╗');
    debugPrint('║  PRICING WATERFALL START: ${widget.code}');
    debugPrint('╚══════════════════════════════════════════════════════════════╝');

    // ═══ STEP 1: KicksDB ═══
    debugPrint('');
    debugPrint('═══ STEP 1: KicksDB ═══');
    await _fetchKicksDbStockXPrice();
    await _fetchKicksDbGoatPrice();
    debugPrint('[KicksDB] Result: stockx=\$${_stockXPrice?.toStringAsFixed(2) ?? "N/A"} '
        'goat=\$${_goatPrice?.toStringAsFixed(2) ?? "N/A"}');

    // STOP CHECK: if StockX or GOAT found → skip to eBay
    final resellFound1 = _stockXPrice != null || _goatPrice != null;
    if (resellFound1) {
      debugPrint('');
      debugPrint('>>> STOP CHECK: Resell=$resellFound1 → skipping to eBay');
    }

    if (!resellFound1) {
      // ═══ STEP 2: Retailed ═══
      debugPrint('');
      debugPrint('═══ STEP 2: Retailed ═══');
      if (_stockXPrice == null) {
        await _fetchRetailedStockXPrice();
      } else {
        debugPrint('[Retailed StockX] Skipped — StockX price already found');
      }
      if (_goatPrice == null) {
        await _fetchRetailedGoatPrice();
      } else {
        debugPrint('[Retailed GOAT] Skipped — GOAT price already found');
      }
      debugPrint('[Retailed] Result: stockx=\$${_stockXPrice?.toStringAsFixed(2) ?? "N/A"} '
          'goat=\$${_goatPrice?.toStringAsFixed(2) ?? "N/A"}');

      // STOP CHECK: if StockX or GOAT found → skip to eBay
      final resellFound2 = _stockXPrice != null || _goatPrice != null;
      if (resellFound2) {
        debugPrint('');
        debugPrint('>>> STOP CHECK: Resell=$resellFound2 → skipping to eBay');
      }
    }

    // ═══ STEP 3: eBay ═══
    debugPrint('');
    debugPrint('═══ STEP 3: eBay ═══');
    await _fetchEbayPrices();
    debugPrint('[eBay] Result: avg=\$${_ebayAveragePrice?.toStringAsFixed(2) ?? "N/A"} '
        'lowest=\$${_ebayLowestPrice?.toStringAsFixed(2) ?? "N/A"} '
        'listings=${_ebayListingCount ?? 0} error=${_ebayError ?? "none"}');

    _finalizePricing(totalStopwatch);
  }

  void _finalizePricing(Stopwatch totalStopwatch) {
    // Ensure loading states are cleared
    setState(() {
      _isLoadingStockXPrice = false;
      _isLoadingGoatPrice = false;
    });

    // Write to shared price cache
    if (_priceCacheEnabled && (_stockXPrice != null || _goatPrice != null)) {
      try {
        final cacheData = <String, dynamic>{'cachedAt': ServerValue.timestamp};
        if (_stockXPrice != null) {
          cacheData['stockxPrice'] = _stockXPrice!.toStringAsFixed(2);
          cacheData['stockxSlug'] = _stockXSlug;
        }
        if (_goatPrice != null) {
          cacheData['goatPrice'] = _goatPrice!.toStringAsFixed(2);
          cacheData['goatSlug'] = _goatSlug;
        }
        _database.child('priceCache').child(widget.code).set(cacheData);
      } catch (e) {
        debugPrint('Price cache write error: $e');
      }
    }

    _savePricesToDatabase();

    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════════════════════╗');
    debugPrint('║  PRICING WATERFALL COMPLETE (${totalStopwatch.elapsedMilliseconds}ms)');
    debugPrint('║  eBay: avg=\$${_ebayAveragePrice?.toStringAsFixed(2) ?? "N/A"} lowest=\$${_ebayLowestPrice?.toStringAsFixed(2) ?? "N/A"}');
    debugPrint('║  StockX: \$${_stockXPrice?.toStringAsFixed(2) ?? "N/A"}');
    debugPrint('║  GOAT: \$${_goatPrice?.toStringAsFixed(2) ?? "N/A"}');
    debugPrint('╚══════════════════════════════════════════════════════════════╝');
    debugPrint('');
  }

  Future<void> _fetchRetailedStockXPrice() async {
    if (_stockXPrice != null) return; // Already found
    final stopwatch = Stopwatch()..start();
    // Use a dedicated client to avoid connection pool contention with prior
    // KicksDB requests on iOS (NSURLSession can hold half-closed connections).
    final client = http.Client();
    try {
      String? slug = _productInfo?['retailedStockXSlug'] as String?;

      // If no pre-resolved slug, search for one (skip for barcodes — numbers are meaningless queries)
      if (slug == null && _isStyleCode) {
        final query = _buildSearchQuery(forStockX: true);
        final searchUri = Uri.parse(
          'https://app.retailed.io/api/v1/scraper/stockx/search'
          '?query=${Uri.encodeComponent(query)}',
        );
        debugPrint('[Retailed StockX] Search query: "$query"');
        debugPrint('[Retailed StockX] Request: $searchUri');
        final searchResponse = await client
            .get(
              searchUri,
              headers: {'x-api-key': _retailedApiKey},
            )
            .timeout(const Duration(seconds: 30));

        debugPrint('[Retailed StockX] Search status: ${searchResponse.statusCode} (${stopwatch.elapsedMilliseconds}ms)');

        if (searchResponse.statusCode == 200) {
          final searchBody = jsonDecode(searchResponse.body);
          final List<dynamic> items = searchBody is List
              ? searchBody
              : (searchBody is Map<String, dynamic> && searchBody['data'] is List)
                  ? searchBody['data']
                  : [];
          for (final item in items) {
            final product = item as Map<String, dynamic>;
            final compatProduct = <String, dynamic>{
              ...product,
              'title': product['name'] ?? product['title'],
            };
            if (_isProductMatch(compatProduct)) {
              final foundSlug = (product['slug'] ?? '').toString();
              if (foundSlug.isNotEmpty) {
                slug = foundSlug;
                debugPrint('[Retailed StockX] Slug found: $slug');
                break;
              }
            }
          }
        }
      }

      // Hit product endpoint if we have a slug
      if (slug != null && slug.isNotEmpty) {
        final productUri = Uri.parse(
          'https://app.retailed.io/api/v1/scraper/stockx/product'
          '?query=${Uri.encodeComponent(slug)}&country=US&currency=USD',
        );
        debugPrint('[Retailed StockX] Product endpoint: $slug');
        debugPrint('[Retailed StockX] Request: $productUri');
        final productResponse = await client
            .get(
              productUri,
              headers: {'x-api-key': _retailedApiKey},
            )
            .timeout(const Duration(seconds: 30));

        debugPrint('[Retailed StockX] Product status: ${productResponse.statusCode} (${stopwatch.elapsedMilliseconds}ms)');
        debugPrint('[Retailed StockX] Product body: ${productResponse.body.length > 500 ? productResponse.body.substring(0, 500) : productResponse.body}');

        if (productResponse.statusCode == 200) {
          final productBody = jsonDecode(productResponse.body);
          if (productBody is Map<String, dynamic>) {
            double? lowestAsk;
            final market = productBody['market'] as Map<String, dynamic>?;
            if (market != null) {
              final bids = market['bids'] as Map<String, dynamic>?;
              if (bids != null) {
                lowestAsk = double.tryParse(
                  (bids['lowest_ask'] ?? '').toString(),
                );
              }
            }

            // Also try to extract retail price from traits
            if (_productInfo != null && _productInfo!['retailPrice'] == null) {
              final traits = productBody['traits'] as List?;
              if (traits != null) {
                for (final trait in traits) {
                  if ((trait['name'] ?? '').toString() == 'Retail Price') {
                    final retailVal = (trait['value'] ?? '').toString()
                        .replaceAll('\$', '')
                        .replaceAll(',', '')
                        .trim();
                    if (retailVal.isNotEmpty) {
                      _productInfo!['retailPrice'] = retailVal;
                    }
                    break;
                  }
                }
              }
            }

            if (lowestAsk != null && lowestAsk > 0) {
              debugPrint('[Retailed StockX] Price: \$$lowestAsk (${stopwatch.elapsedMilliseconds}ms)');
              setState(() {
                _stockXPrice = lowestAsk;
                _stockXSlug = slug;
                _isLoadingStockXPrice = false;
              });
              return;
            }
          }
        }
      }
      debugPrint('[Retailed StockX] No price found (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      debugPrint('[Retailed StockX] Error: $e (${stopwatch.elapsedMilliseconds}ms)');
    } finally {
      client.close();
    }
  }

  Future<void> _fetchKicksDbStockXPrice() async {
    if (_stockXPrice != null) return; // Already found
    final stopwatch = Stopwatch()..start();
    debugPrint('[KicksDB StockX] Starting fallback lookup');
    try {
      final attempts = <Uri>[];
      if (!_isStyleCode) {
        attempts.add(
          Uri.parse(
            'https://api.kicks.dev/v3/stockx/products'
            '?productId=${Uri.encodeComponent(widget.code)}&limit=1'
            '&display[prices]=true',
          ),
        );
      } else {
        final query = _buildSearchQuery(forStockX: true);
        attempts.add(
          Uri.parse(
            'https://api.kicks.dev/v3/stockx/products'
            '?query=${Uri.encodeComponent(query)}&limit=5'
            '&display[prices]=true&display[variants]=true',
          ),
        );
      }

      for (final uri in attempts) {
        final response = await http
            .get(uri, headers: {'Authorization': 'Bearer $_kicksDbApiKey'})
            .timeout(const Duration(seconds: 10));

        debugPrint('[KicksDB StockX] Request: $uri');
        debugPrint('[KicksDB StockX] Status: ${response.statusCode}');

        if (response.statusCode != 200) continue;

        final body = jsonDecode(response.body);

        final List<Map<String, dynamic>> candidates = [];
        if (body is Map<String, dynamic>) {
          if (body.containsKey('data') && body['data'] is List) {
            for (var item in body['data']) {
              candidates.add(item as Map<String, dynamic>);
            }
          } else if (body.containsKey('title') || body.containsKey('slug')) {
            candidates.add(body);
          }
        } else if (body is List) {
          for (var item in body) {
            candidates.add(item as Map<String, dynamic>);
          }
        }

        for (final product in candidates) {
          if (!_isProductMatch(product)) {
            debugPrint('[KicksDB StockX] Skip mismatch: "${product['title']}"');
            continue;
          }

          double? lowestAsk;
          final minPrice = double.tryParse(
            (product['min_price'] ?? '').toString(),
          );
          if (minPrice != null && minPrice > 0) lowestAsk = minPrice;

          if (lowestAsk == null) {
            final avgPrice = double.tryParse(
              (product['avg_price'] ?? '').toString(),
            );
            if (avgPrice != null && avgPrice > 0) lowestAsk = avgPrice;
          }

          if (lowestAsk == null) {
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
          }

          if (lowestAsk != null && lowestAsk > 0) {
            debugPrint('[KicksDB StockX] Price: \$$lowestAsk (${stopwatch.elapsedMilliseconds}ms)');
            setState(() {
              _stockXPrice = lowestAsk;
              _stockXSlug = product['slug'] as String?;
              _isLoadingStockXPrice = false;
            });
            return;
          }
        }
      }

      debugPrint('[KicksDB StockX] No price found (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      debugPrint('[KicksDB StockX] Error: $e (${stopwatch.elapsedMilliseconds}ms)');
    }
  }

  Future<void> _fetchRetailedGoatPrice() async {
    if (_goatPrice != null) return; // Already found
    final stopwatch = Stopwatch()..start();
    try {
      String? goatQuery;
      if (!_isStyleCode) {
        goatQuery = (_productInfo?['styleCode'] ?? _productInfo?['sku'] ?? '')
            .toString();
        if (goatQuery.isEmpty) goatQuery = null;
      } else {
        goatQuery = _buildSearchQuery();
      }

      if (goatQuery != null) {
        final goatSearchUri = Uri.parse(
          'https://app.retailed.io/api/v1/scraper/goat/search'
          '?query=${Uri.encodeComponent(goatQuery)}',
        );
        debugPrint('[Retailed GOAT] Search: "$goatQuery"');
        debugPrint('[Retailed GOAT] Request: $goatSearchUri');
        final searchResponse = await http
            .get(
              goatSearchUri,
              headers: {'x-api-key': _retailedApiKey},
            )
            .timeout(const Duration(seconds: 10));

        debugPrint('[Retailed GOAT] Search status: ${searchResponse.statusCode}');

        if (searchResponse.statusCode == 200) {
          final searchBody = jsonDecode(searchResponse.body);
          final List<dynamic> items = searchBody is List
              ? searchBody
              : (searchBody is Map<String, dynamic> && searchBody['data'] is List)
                  ? searchBody['data']
                  : [];

          String? goatSlug;
          for (final item in items) {
            final product = item as Map<String, dynamic>;
            final compatProduct = <String, dynamic>{
              ...product,
              'title': product['name'] ?? product['title'],
            };
            if (!_looksLikeFootwear(compatProduct)) {
              debugPrint('[Retailed GOAT] Skip (not footwear): "${product['name']}"');
              continue;
            }
            if (_isStyleCode && !_isProductMatch(compatProduct)) {
              debugPrint('[Retailed GOAT] Skip (mismatch): "${product['name']}"');
              continue;
            }
            final foundSlug = (product['slug'] ?? '').toString();
            if (foundSlug.isNotEmpty) {
              goatSlug = foundSlug;
              debugPrint('[Retailed GOAT] Slug found: $goatSlug');
              break;
            }
          }

          if (goatSlug != null) {
            final goatProductUri = Uri.parse(
              'https://app.retailed.io/api/v1/scraper/goat/product'
              '?query=${Uri.encodeComponent(goatSlug)}',
            );
            debugPrint('[Retailed GOAT] Product endpoint: $goatSlug');
            debugPrint('[Retailed GOAT] Request: $goatProductUri');
            final productResponse = await http
                .get(
                  goatProductUri,
                  headers: {'x-api-key': _retailedApiKey},
                )
                .timeout(const Duration(seconds: 15));

            debugPrint('[Retailed GOAT] Product status: ${productResponse.statusCode}');
            debugPrint('[Retailed GOAT] Product body: ${productResponse.body.length > 500 ? productResponse.body.substring(0, 500) : productResponse.body}');

            if (productResponse.statusCode == 200) {
              final productBody = jsonDecode(productResponse.body);
              if (productBody is Map<String, dynamic>) {
                // CRITICAL: GOAT prices are in CENTS, divide by 100
                double? goatPrice;
                final lowestCents = double.tryParse(
                  (productBody['lowest_price_cents'] ?? '').toString(),
                );
                if (lowestCents != null && lowestCents > 0) {
                  goatPrice = lowestCents / 100;
                }
                if (goatPrice == null) {
                  final newLowestCents = double.tryParse(
                    (productBody['new_lowest_price_cents'] ?? '').toString(),
                  );
                  if (newLowestCents != null && newLowestCents > 0) {
                    goatPrice = newLowestCents / 100;
                  }
                }

                if (goatPrice != null && goatPrice > 0) {
                  debugPrint('[Retailed GOAT] Price: \$$goatPrice (${stopwatch.elapsedMilliseconds}ms)');
                  setState(() {
                    _goatPrice = goatPrice;
                    _goatSlug = goatSlug;
                    _isLoadingGoatPrice = false;
                  });
                  return;
                }
              }
            }
          }
        }
      }
      debugPrint('[Retailed GOAT] No price found (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      debugPrint('[Retailed GOAT] Error: $e (${stopwatch.elapsedMilliseconds}ms)');
    }
  }

  Future<void> _fetchKicksDbGoatPrice() async {
    if (_goatPrice != null) return; // Already found
    final stopwatch = Stopwatch()..start();
    debugPrint('[KicksDB GOAT] Starting fallback lookup');
    try {
      final attempts = <Uri>[];
      if (!_isStyleCode) {
        attempts.add(
          Uri.parse(
            'https://api.kicks.dev/v3/goat/products'
            '?productId=${Uri.encodeComponent(widget.code)}&limit=1'
            '&display[prices]=true',
          ),
        );
      } else {
        final query = _buildSearchQuery();
        attempts.add(
          Uri.parse(
            'https://api.kicks.dev/v3/goat/products'
            '?query=${Uri.encodeComponent(query)}&limit=5'
            '&display[prices]=true&display[variants]=true',
          ),
        );
      }

      for (final uri in attempts) {
        final response = await http
            .get(uri, headers: {'Authorization': 'Bearer $_kicksDbApiKey'})
            .timeout(const Duration(seconds: 10));

        debugPrint('[KicksDB GOAT] Request: $uri');
        debugPrint('[KicksDB GOAT] Status: ${response.statusCode}');

        if (response.statusCode != 200) continue;

        final body = jsonDecode(response.body);

        final List<Map<String, dynamic>> candidates = [];
        if (body is Map<String, dynamic>) {
          if (body.containsKey('data') && body['data'] is List) {
            for (var item in body['data']) {
              candidates.add(item as Map<String, dynamic>);
            }
          } else if (body.containsKey('name') || body.containsKey('slug')) {
            candidates.add(body);
          }
        } else if (body is List) {
          for (var item in body) {
            candidates.add(item as Map<String, dynamic>);
          }
        }

        for (final product in candidates) {
          if (!_isProductMatch(product)) {
            debugPrint('[KicksDB GOAT] Skip mismatch: "${product['name'] ?? product['title']}"');
            continue;
          }

          double? lowestAsk;
          final minPrice = double.tryParse(
            (product['min_price'] ?? '').toString(),
          );
          if (minPrice != null && minPrice > 0) lowestAsk = minPrice;

          if (lowestAsk == null) {
            final avgPrice = double.tryParse(
              (product['avg_price'] ?? '').toString(),
            );
            if (avgPrice != null && avgPrice > 0) lowestAsk = avgPrice;
          }

          if (lowestAsk == null) {
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
          }

          if (lowestAsk != null && lowestAsk > 0) {
            debugPrint('[KicksDB GOAT] Price: \$$lowestAsk (${stopwatch.elapsedMilliseconds}ms)');
            setState(() {
              _goatPrice = lowestAsk;
              _goatSlug = (product['slug'] ?? product['id'] ?? product['name'])
                  ?.toString();
              _isLoadingGoatPrice = false;
            });
            return;
          }
        }
      }

      debugPrint('[KicksDB GOAT] No price found (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      debugPrint('[KicksDB GOAT] Error: $e (${stopwatch.elapsedMilliseconds}ms)');
    }
  }

  Future<void> _fetchStockXOfficialPrice() async {
    final stopwatch = Stopwatch()..start();
    final token = await _getStockXAccessToken();
    if (token == null) {
      debugPrint('[StockX Official] Not connected, skipping');
      return;
    }

    try {
      final query = _isStyleCode
          ? _buildSearchQuery(forStockX: true)
          : widget.code;
      debugPrint('[StockX Official] Search query: "$query"');

      final searchUri = Uri.parse(
        'https://api.stockx.com/v2/catalog/search'
        '?query=${Uri.encodeComponent(query)}',
      );
      var searchResponse = await http.get(searchUri, headers: {
        'Authorization': 'Bearer $token',
        'x-api-key': _stockXApiKey,
      }).timeout(const Duration(seconds: 15));

      debugPrint('[StockX Official] Search status: ${searchResponse.statusCode}');
      debugPrint('[StockX Official] Search body: ${searchResponse.body.length > 500 ? searchResponse.body.substring(0, 500) : searchResponse.body}');

      // If 401, try refresh and retry once
      if (searchResponse.statusCode == 401) {
        debugPrint('[StockX Official] 401 received, attempting token refresh...');
        final newToken = await _refreshStockXToken();
        if (newToken == null) {
          debugPrint('[StockX Official] Token refresh failed, skipping');
          return;
        }
        searchResponse = await http.get(searchUri, headers: {
          'Authorization': 'Bearer $newToken',
          'x-api-key': _stockXApiKey,
        }).timeout(const Duration(seconds: 15));
        debugPrint('[StockX Official] Retry status: ${searchResponse.statusCode}');
      }

      if (searchResponse.statusCode != 200) {
        debugPrint('[StockX Official] Search failed with ${searchResponse.statusCode}');
        return;
      }

      final searchBody = jsonDecode(searchResponse.body);
      final products = searchBody['products'] as List? ?? [];
      debugPrint('[StockX Official] Found ${products.length} results');

      String? productId;
      for (final product in products) {
        final p = product as Map<String, dynamic>;
        final compatProduct = <String, dynamic>{
          ...p,
          'title': p['title'] ?? p['name'] ?? '',
          'brand': p['brand'] ?? '',
        };
        if (_isProductMatch(compatProduct)) {
          productId = (p['productId'] ?? p['id'] ?? '').toString();
          debugPrint('[StockX Official] Matched product: "${p['title']}" id=$productId');
          // Also grab slug if available
          final slug = (p['urlKey'] ?? p['slug'] ?? '').toString();
          if (slug.isNotEmpty && _stockXSlug == null) {
            _stockXSlug = slug;
          }
          break;
        } else {
          debugPrint('[StockX Official] Skip mismatch: "${p['title']}"');
        }
      }

      if (productId == null || productId.isEmpty) {
        debugPrint('[StockX Official] No matching product found (${stopwatch.elapsedMilliseconds}ms)');
        return;
      }

      // Fetch market data
      final currentToken = _stockXAccessToken ?? token;
      final marketUri = Uri.parse(
        'https://api.stockx.com/v2/products/$productId/market',
      );
      final marketResponse = await http.get(marketUri, headers: {
        'Authorization': 'Bearer $currentToken',
        'x-api-key': _stockXApiKey,
      }).timeout(const Duration(seconds: 15));

      debugPrint('[StockX Official] Market status: ${marketResponse.statusCode}');
      debugPrint('[StockX Official] Market body: ${marketResponse.body.length > 500 ? marketResponse.body.substring(0, 500) : marketResponse.body}');

      if (marketResponse.statusCode == 200) {
        final marketBody = jsonDecode(marketResponse.body);
        double? lowestAsk;

        // Try different fields for price
        lowestAsk = double.tryParse(
          (marketBody['lowestAsk'] ?? marketBody['lowest_ask'] ?? '').toString(),
        );
        if (lowestAsk == null || lowestAsk <= 0) {
          lowestAsk = double.tryParse(
            (marketBody['lastSale'] ?? marketBody['last_sale'] ?? '').toString(),
          );
        }

        if (lowestAsk != null && lowestAsk > 0) {
          debugPrint('[StockX Official] Price: \$$lowestAsk (${stopwatch.elapsedMilliseconds}ms)');
          setState(() {
            _stockXPrice = lowestAsk;
            _isLoadingStockXPrice = false;
          });
          return;
        }
      }

      debugPrint('[StockX Official] No price found (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      debugPrint('[StockX Official] Error: $e (${stopwatch.elapsedMilliseconds}ms)');
    }
  }

  Future<void> _fetchSneakerDbPrices() async {
    final stopwatch = Stopwatch()..start();
    try {
      final query = _productInfo?['styleCode'] as String? ?? widget.code;
      debugPrint('[SneakerDB] Searching for prices with query: "$query"');

      final response = await http.get(
        Uri.parse(
          'https://the-sneaker-database.p.rapidapi.com/sneakers'
          '?limit=10&sku=${Uri.encodeComponent(query)}',
        ),
        headers: {
          'x-rapidapi-key': _sneakerDbApiKey,
          'x-rapidapi-host': 'the-sneaker-database.p.rapidapi.com',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('[SneakerDB] Status: ${response.statusCode}');
      debugPrint('[SneakerDB] Body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');

      if (response.statusCode != 200) {
        debugPrint('[SneakerDB] Failed with ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)');
        return;
      }

      final body = jsonDecode(response.body);
      final results = body['results'] as List? ?? (body is List ? body : []);

      for (final item in results) {
        final product = item as Map<String, dynamic>;
        final compatProduct = <String, dynamic>{
          ...product,
          'title': product['shoeName'] ?? product['name'] ?? product['title'] ?? '',
          'brand': product['brand'] ?? '',
        };
        if (!_isProductMatch(compatProduct)) {
          debugPrint('[SneakerDB] Skip mismatch: "${compatProduct['title']}"');
          continue;
        }

        final resellPrices = product['resellPrices'] as Map<String, dynamic>?;
        if (resellPrices == null) {
          debugPrint('[SneakerDB] No resellPrices for "${compatProduct['title']}"');
          continue;
        }

        // StockX price from SneakerDB
        if (_stockXPrice == null) {
          final stockXData = resellPrices['stockX'] as Map<String, dynamic>?;
          if (stockXData != null) {
            // SneakerDB returns prices by size or as a direct value
            double? price;
            for (final entry in stockXData.entries) {
              final p = double.tryParse(entry.value.toString());
              if (p != null && p > 0) {
                if (price == null || p < price) price = p;
              }
            }
            if (price != null) {
              debugPrint('[SneakerDB] StockX price: \$$price');
              setState(() {
                _stockXPrice = price;
                _isLoadingStockXPrice = false;
              });
            }
          }
        }

        // GOAT price from SneakerDB
        if (_goatPrice == null) {
          final goatData = resellPrices['goat'] as Map<String, dynamic>?;
          if (goatData != null) {
            double? price;
            for (final entry in goatData.entries) {
              final p = double.tryParse(entry.value.toString());
              if (p != null && p > 0) {
                if (price == null || p < price) price = p;
              }
            }
            if (price != null) {
              debugPrint('[SneakerDB] GOAT price: \$$price');
              setState(() {
                _goatPrice = price;
                _isLoadingGoatPrice = false;
              });
            }
          }
        }

        debugPrint('[SneakerDB] Done (${stopwatch.elapsedMilliseconds}ms)');
        return; // Found a match, done
      }

      debugPrint('[SneakerDB] No matching results (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      debugPrint('[SneakerDB] Error: $e (${stopwatch.elapsedMilliseconds}ms)');
    }
  }

  /// Fuzzy name search via SneakerDB when identity is NOT confirmed.
  /// Populates [_sneakerDbCandidates] with possible matches.
  Future<void> _fetchSneakerDbFuzzyCandidates() async {
    final query = _productInfo?['title'] as String? ?? widget.labelName ?? widget.code;
    if (query.isEmpty) return;

    debugPrint('[SneakerDB Fuzzy] Starting fuzzy search for: "$query"');
    setState(() => _isLoadingCandidates = true);

    try {
      final response = await http.get(
        Uri.parse(
          'https://the-sneaker-database.p.rapidapi.com/sneakers'
          '?limit=10&name=${Uri.encodeComponent(query)}',
        ),
        headers: {
          'x-rapidapi-key': _sneakerDbApiKey,
          'x-rapidapi-host': 'the-sneaker-database.p.rapidapi.com',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('[SneakerDB Fuzzy] Status: ${response.statusCode}');
      debugPrint(
        '[SneakerDB Fuzzy] Body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
      );

      if (response.statusCode != 200) {
        debugPrint('[SneakerDB Fuzzy] Failed with ${response.statusCode}');
        setState(() => _isLoadingCandidates = false);
        return;
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        setState(() => _isLoadingCandidates = false);
        return;
      }

      final results = body['results'] as List? ?? [];
      debugPrint('[SneakerDB Fuzzy] Got ${results.length} raw results');

      final candidates = <Map<String, dynamic>>[];
      for (final item in results) {
        final product = item as Map<String, dynamic>;
        final name = (product['name'] ?? '').toString();
        final brand = (product['brand'] ?? '').toString();

        // Filter through _looksLikeFootwear
        final compatProduct = <String, dynamic>{
          ...product,
          'title': name,
          'brand': brand,
        };
        if (!_looksLikeFootwear(compatProduct)) {
          debugPrint('[SneakerDB Fuzzy] Skip non-footwear: "$name"');
          continue;
        }

        // Extract image
        final imageData = product['image'] as Map<String, dynamic>?;
        final image = (imageData?['original'] ?? imageData?['small'] ?? '').toString();

        // Extract retail price
        final retailPrice = product['retailPrice'];
        final retailPriceNum = retailPrice != null && retailPrice != 0
            ? double.tryParse(retailPrice.toString())
            : null;

        // Extract estimated market value
        final emv = product['estimatedMarketValue'];
        final emvNum = emv != null && emv != 0
            ? double.tryParse(emv.toString())
            : null;

        // Extract SKU
        final sku = (product['sku'] ?? '').toString();

        // Extract StockX slug from links
        String? stockXSlug;
        String? goatSlug;
        final links = product['links'] as Map<String, dynamic>?;
        if (links != null) {
          final stockXUrl = (links['stockX'] ?? '').toString();
          if (stockXUrl.contains('stockx.com/')) {
            stockXSlug = stockXUrl.split('stockx.com/').last.split('?').first;
          }
          final goatUrl = (links['goat'] ?? '').toString();
          if (goatUrl.contains('goat.com/sneakers/')) {
            goatSlug = goatUrl.split('goat.com/sneakers/').last.split('?').first;
          }
        }

        candidates.add({
          'title': name,
          'brand': brand,
          'image': image,
          'retailPrice': retailPriceNum,
          'estimatedMarketValue': emvNum,
          'sku': sku,
          'stockXSlug': stockXSlug,
          'goatSlug': goatSlug,
        });
        debugPrint('[SneakerDB Fuzzy] Candidate: "$name" sku="$sku" retail=\$${retailPriceNum ?? "N/A"} emv=\$${emvNum ?? "N/A"}');
      }

      debugPrint('[SneakerDB Fuzzy] ${candidates.length} footwear candidates after filtering');
      setState(() {
        _sneakerDbCandidates = candidates;
        _isLoadingCandidates = false;
      });
    } catch (e) {
      debugPrint('[SneakerDB Fuzzy] Error: $e');
      setState(() => _isLoadingCandidates = false);
    }
  }

  Future<void> _savePricesToDatabase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.scanId.isEmpty) return;

    try {
      final updateData = <String, dynamic>{};

      // Add retail price if available
      final retailPriceStr = _productInfo?['retailPrice'] as String?;
      final retailPrice =
          retailPriceStr ?? (_manualRetailPrice?.toStringAsFixed(2));
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
        await _database
            .child('scans')
            .child(user.uid)
            .child(widget.scanId)
            .update(updateData);
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
              top: BorderSide(color: const Color(0xFF2A2A2A), width: 1),
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
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.grey[600],
                    ),
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
                    // Match confidence banner
                    if (_matchConfidence != MatchConfidence.verified) ...[
                      _buildConfidenceBanner()!,
                      const SizedBox(height: 16),
                    ],

                    // Product Image or Placeholder
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child:
                          _gtinVerified &&
                              _productInfo?['images'] != null &&
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

                    // Product Title (only show API title if GTIN verified)
                    Text(
                      _gtinVerified
                          ? (_productInfo?['title'] ?? 'Unknown Product')
                          : (_isStyleCode ? widget.code : 'Scanned Product'),
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Brand (only show if GTIN verified)
                    if (_gtinVerified &&
                        _productInfo?['brand'] != null &&
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

                    // Price Section (only show if GTIN verified — could be wrong product's price)
                    if (_gtinVerified && _productInfo?['retailPrice'] != null) ...[
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
                                _productInfo!['lowestPrice'] !=
                                    _productInfo!['highestPrice']) ...[
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
                      _isStyleCode ? 'Style Code' : 'Barcode',
                      widget.code,
                      _isStyleCode ? Icons.label : Icons.qr_code,
                    ),
                    if (widget.labelName != null) ...[
                      const SizedBox(height: 12),
                      _buildInfoCard(
                        'Label Name',
                        widget.labelName!,
                        Icons.text_fields,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildInfoCard(
                      'Format',
                      _isStyleCode ? 'OCR Label Scan' : widget.format,
                      Icons.category,
                    ),
                    if (_gtinVerified &&
                        _productInfo?['category'] != null &&
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

                    // Description (only show if GTIN verified)
                    if (_gtinVerified &&
                        _productInfo?['description'] != null &&
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

                    // Scan Again / Confirm Match for unverified scans
                    if (_matchConfidence == MatchConfidence.unverified &&
                        !_matchConfirmed) ...[
                      _buildScanAgainPrompt(),
                      const SizedBox(height: 10),
                      _buildConfirmMatchButton(),
                      const SizedBox(height: 24),
                    ],

                    // Profit Calculator Section (gated by confidence)
                    if (_matchConfidence == MatchConfidence.verified ||
                        _matchConfidence == MatchConfidence.likely ||
                        _matchConfirmed) ...[
                      _buildProfitCalculator(),
                      if (_matchConfidence == MatchConfidence.likely &&
                          !_matchConfirmed)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Profit is estimated — confirm style code for exact numbers.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.blue[300],
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],

                    // Fuzzy SneakerDB candidates (shown when identity NOT confirmed)
                    if (_isLoadingCandidates) ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: CircularProgressIndicator(
                            color: Color(0xFF646CFF),
                          ),
                        ),
                      ),
                    ] else if (_sneakerDbCandidates.isNotEmpty) ...[
                      _buildCandidatesList(),
                      const SizedBox(height: 24),
                    ],

                    // eBay Button (only if price was found)
                    if (_ebayAveragePrice != null) ...[
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
                    ],

                    // StockX Button (only if exact product found)
                    if (_stockXPrice != null) ...[
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
                    ],

                    // GOAT Button (only if exact product found)
                    if (_goatPrice != null) ...[
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
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  Widget? _buildConfidenceBanner() {
    switch (_matchConfidence) {
      case MatchConfidence.verified:
        return null;
      case MatchConfidence.unverified:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "We couldn't read a style code. Results below are approximate.",
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.orange[200],
                  ),
                ),
              ),
            ],
          ),
        );
      case MatchConfidence.likely:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Match based on label text. Verify the style code for best accuracy.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.blue[200],
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildConfirmMatchButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          setState(() {
            _matchConfirmed = true;
          });
        },
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Confirm Match'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.green[400],
          side: BorderSide(color: Colors.green[400]!),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildScanAgainPrompt() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.pop(context, 'scanAnother');
        },
        icon: const Icon(Icons.qr_code_scanner, size: 18),
        label: const Text('Scan Again'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.orange[400],
          side: BorderSide(color: Colors.orange[400]!),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildCandidatesList() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: const Color(0xFF646CFF),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Possible Matches',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'We couldn\'t confirm the exact product. These may be matches:',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 12),
          ..._sneakerDbCandidates.map((candidate) {
            final title = (candidate['title'] ?? '').toString();
            final brand = (candidate['brand'] ?? '').toString();
            final image = (candidate['image'] ?? '').toString();
            final retailPrice = candidate['retailPrice'] as double?;
            final emv = candidate['estimatedMarketValue'] as double?;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF333333), width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: image.isNotEmpty
                          ? Image.network(
                              image,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (_, e, s) => Container(
                                width: 60,
                                height: 60,
                                color: const Color(0xFF333333),
                                child: Icon(
                                  Icons.image_not_supported,
                                  color: Colors.grey[600],
                                  size: 24,
                                ),
                              ),
                            )
                          : Container(
                              width: 60,
                              height: 60,
                              color: const Color(0xFF333333),
                              child: Icon(
                                Icons.image_not_supported,
                                color: Colors.grey[600],
                                size: 24,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    // Product details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            brand,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (retailPrice != null) ...[
                                Text(
                                  'Retail: \$${retailPrice.toStringAsFixed(0)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.green[400],
                                  ),
                                ),
                              ],
                              if (retailPrice != null && emv != null)
                                const SizedBox(width: 12),
                              if (emv != null) ...[
                                Text(
                                  'Est: \$${emv.toStringAsFixed(0)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.blue[300],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProfitCalculator() {
    final retailPriceStr = _productInfo?['retailPrice'] as String?;
    final fetchedRetailPrice = retailPriceStr != null
        ? double.tryParse(retailPriceStr)
        : null;

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
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
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
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF252525),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.green[400]!,
                                    width: 1,
                                  ),
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
                                _manualRetailPrice = double.tryParse(
                                  _retailPriceController.text,
                                );
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
                                color: Colors.green[400]!.withValues(
                                  alpha: 0.2,
                                ),
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
                            onTap: () =>
                                setState(() => _showRetailEntry = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
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
            productFound: ebayPrice != null,
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
            productFound: _stockXPrice != null,
            onOpenMarketplace: _stockXPrice != null ? _openStockXSearch : null,
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
            productFound: _goatPrice != null,
            onOpenMarketplace: _goatPrice != null ? _openGoatSearch : null,
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
    VoidCallback? onOpenMarketplace,
    bool productFound = true,
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
              else if (!productFound)
                Text(
                  'Not found on $label',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                )
              else if (onOpenMarketplace != null)
                GestureDetector(
                  onTap: onOpenMarketplace,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
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
                            color: profit >= 0
                                ? Colors.green[400]
                                : Colors.red[400],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: (profit >= 0 ? Colors.green : Colors.red)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${profitPercent! >= 0 ? '+' : ''}${profitPercent.toStringAsFixed(1)}%',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: profit >= 0
                                  ? Colors.green[400]
                                  : Colors.red[400],
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
          Icon(Icons.directions_run, size: 64, color: Colors.grey[700]),
          const SizedBox(height: 8),
          Text(
            'No image available',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
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
            colors: [const Color(0xFF1E2A3A), const Color(0xFF1A2230)],
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
              style: GoogleFonts.inter(color: Colors.grey[400], fontSize: 14),
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
            colors: [const Color(0xFF1E2A3A), const Color(0xFF1A2230)],
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
                Container(width: 1, height: 40, color: Colors.grey[700]),
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
          border: Border.all(color: Colors.grey[800]!, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey[500], size: 18),
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
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
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
            child: Icon(icon, color: const Color(0xFF646CFF), size: 20),
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
                  style: (label == 'Barcode' || label == 'Style Code')
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

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _stockXConnected = false;
  bool _checkingStockX = true;

  @override
  void initState() {
    super.initState();
    _checkStockXConnection();
  }

  Future<void> _checkStockXConnection() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final snapshot = await FirebaseDatabase.instance
            .ref()
            .child('stockxTokens')
            .child(user.uid)
            .get();
        if (mounted) {
          setState(() {
            _stockXConnected = snapshot.exists;
            _checkingStockX = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _checkingStockX = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _checkingStockX = false;
        });
      }
    }
  }

  Future<void> _disconnectStockX() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseDatabase.instance
          .ref()
          .child('stockxTokens')
          .child(user.uid)
          .remove();
      _ScanDetailPageState._stockXAccessToken = null;
      _ScanDetailPageState._stockXRefreshToken = null;
      _ScanDetailPageState._stockXTokenExpiry = null;
      _ScanDetailPageState._stockXTokensLoaded = false;
      if (mounted) {
        setState(() {
          _stockXConnected = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('StockX disconnected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

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
            border: Border.all(color: const Color(0xFF333333), width: 1),
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
                border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
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
                border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
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

            // Integrations Section
            Text(
              'INTEGRATIONS',
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
                border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
              ),
              child: _buildSettingsTile(
                icon: Icons.store_rounded,
                iconColor: _stockXConnected ? Colors.green : Colors.grey,
                title: 'StockX',
                subtitle: _checkingStockX
                    ? 'Checking...'
                    : (_stockXConnected ? 'Connected' : 'Not connected'),
                onTap: () {
                  if (_stockXConnected) {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1A1A1A),
                        title: Text(
                          'StockX Connected',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        content: Text(
                          'Your StockX account is connected. Would you like to disconnect?',
                          style: GoogleFonts.inter(color: Colors.grey[400]),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.inter(color: Colors.grey[400]),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _disconnectStockX();
                            },
                            child: Text(
                              'Disconnect',
                              style: GoogleFonts.inter(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    _ScanDetailPageState.launchStockXOAuth();
                  }
                },
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
                border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
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
                border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
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
              child: Icon(icon, color: iconColor, size: 22),
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
              Icon(Icons.chevron_right, color: Colors.grey[600], size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, color: Colors.grey[800]),
    );
  }
}
