import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart' show routeObserver;
import '../models/scan_data.dart';
import '../services/gtin_utils.dart';
import '../services/subscription_service.dart';
import 'main_screen.dart';
import 'paywall_page.dart';
import 'scan_detail/scan_detail_page.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, this.activeNotifier});

  final ValueNotifier<bool>? activeNotifier;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage>
    with WidgetsBindingObserver
    implements RouteAware {
  bool _isProcessing = false;
  bool _isCameraStarting = false;

  static const _ocrChannel = MethodChannel('com.sneakerscanner/ocr');

  final ImagePicker _imagePicker = ImagePicker();
  final MobileScannerController _previewController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
    autoStart: false,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.activeNotifier?.addListener(_onActiveChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    widget.activeNotifier?.removeListener(_onActiveChanged);
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _previewController.dispose();
    super.dispose();
  }

  void _onActiveChanged() {
    if (widget.activeNotifier?.value == true) {
      _startCamera();
    } else {
      _previewController.stop();
    }
  }

  // Atomic guard: prevents concurrent start() calls (e.g. didPopNext() and
  // didChangeAppLifecycleState(resumed) firing at the same time).
  Future<void> _startCamera() async {
    if (_isCameraStarting || _previewController.value.isRunning) return;
    _isCameraStarting = true;
    try {
      await _previewController.start();
    } finally {
      _isCameraStarting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _previewController.stop();
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  // RouteAware — stop camera when another route is pushed on top, restart on return
  @override
  void didPushNext() {
    _previewController.stop();
  }

  @override
  void didPopNext() {
    _startCamera();
  }

  @override
  void didPush() {}

  @override
  void didPop() {}

  ScanData _parseLabelInfo(String text) {
    // Normalize: collapse whitespace, uppercase
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

    // sep = flexible separator: dash, space, slash, dot, or nothing
    const sep = r'[-\s/.]*';

    // --- Brand extraction (first, so we can validate SKU candidates) ---
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

    String? foundBrand;
    final brandLabelMatch = RegExp(
      r'BRAND[:\s]+([A-Z][A-Z&\s]+)',
    ).firstMatch(normalized);
    if (brandLabelMatch != null) {
      foundBrand = brandLabelMatch.group(1)!.trim();
    }

    if (foundBrand == null) {
      for (final brand in knownBrands) {
        if (normalized.contains(brand)) {
          foundBrand = brand;
          break;
        }
      }
    }

    // Split original text into lines (preserves line boundaries for context checks)
    final lines = text.split(RegExp(r'[\n\r]+'));

    // --- Code extraction (with brand-aware validation) ---
    String? code;

    // --- Pass 1: Collect ALL labeled code candidates (raw OCR form) ---
    final labeledCandidates = <String>[];
    for (final label in ['STYLE', 'SKU', 'ITEM']) {
      final match = RegExp(
        '$label[#:\\s]+([A-Z0-9][A-Z0-9\\-\\s/.]+[A-Z0-9])',
      ).firstMatch(normalized);
      if (match != null) {
        labeledCandidates.add(match.group(1)!.trim());
      }
    }
    // DPCI labeled (lower priority — preserve raw OCR separator)
    final dpciLabeled = RegExp(
      'DPCI[:\\s]+(\\d{3}$sep\\d{2}$sep\\d{4})',
    ).firstMatch(normalized);
    if (dpciLabeled != null) {
      labeledCandidates.add(dpciLabeled.group(1)!.trim());
    }

    // --- Pass 2: Collect ALL pattern-match candidates (raw OCR form) ---
    final patternCandidates = <String>[];
    final codePatterns = <RegExp>[
      // Nike/Jordan: DD1391-100, CT8012 170, FB8896/100, CW1590.100, DH9765002
      RegExp('\\b[A-Z]{2,3}\\d{4}$sep\\d{3}\\b'),
      // Jordan/UA 6-digit: 555088-134, 555088 134, 3026175-001
      RegExp('\\b\\d{6,7}$sep\\d{3}\\b'),
      // Puma: 374915-01, 374915 01
      RegExp('\\b\\d{6}$sep\\d{2}\\b'),
      // Adidas: GW2871, HP5582, IF1477 (2 letters + 4 digits)
      RegExp(r'\b[A-Z]{2}\d{4}\b'),
      // New Balance: M990GL6, ML574EVG, M1080B12
      RegExp(r'\bM[A-Z]?\d{3,4}[A-Z]{1,3}\d{0,2}\b'),
      // Converse: 162050C
      RegExp(r'\b\d{6}C\b'),
      // Skechers: 232123/BLK, M232301-BBK, 149550 NVY, 200291W/BLK
      RegExp(r'\b[MW]?\d{5,6}[A-Z]?[-\s/.]+[A-Z]{2,4}\b'),
      // Vans: VN0A38FRX9C, VN0A4BV6...
      RegExp(r'\bVN0[A-Z0-9]{6,8}\b'),
    ];

    for (final pattern in codePatterns) {
      final match = pattern.firstMatch(normalized);
      if (match != null) {
        patternCandidates.add(match.group(0)!);
      }
    }

    // --- Pick the first candidate that passes all validation ---
    final allCandidates = [...labeledCandidates, ...patternCandidates];
    for (final candidate in allCandidates) {
      if (_isDisqualifiedByContext(candidate, lines)) {
        debugPrint('SKU candidate disqualified by label context: "$candidate"');
        continue;
      }
      if (_isValidSku(candidate, foundBrand)) {
        code = _formatSkuForBrand(candidate, foundBrand);
        break;
      }
    }
    if (code == null && allCandidates.isNotEmpty) {
      debugPrint(
        'All SKU candidates rejected for brand "${foundBrand ?? 'unknown'}": $allCandidates',
      );
    }

    // --- Size extraction ---
    String? size;
    final sizeMatch = RegExp(
      r'(?:SIZE|US|UK|EU)[:\s]*(\d{1,2}(?:\.\d)?)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (sizeMatch != null) {
      final parsed = double.tryParse(sizeMatch.group(1)!);
      if (parsed != null && parsed >= 1 && parsed <= 20) {
        size = sizeMatch.group(1)!;
      }
    }

    // Title-case the brand for storage
    String? brandForStorage;
    if (foundBrand != null) {
      brandForStorage = _titleCase(foundBrand);
    }

    return ScanData(
      brand: brandForStorage,
      sku: code,
      size: size,
      ocrText: normalized,
    );
  }

  String _titleCase(String s) => s
      .split(' ')
      .map(
        (w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
      )
      .join(' ');

  // Brand SKU patterns derived from sku_brand_awareness.json
  static final Map<String, List<RegExp>> _brandSkuPatterns = {
    'all': [
      RegExp(r'^([A-Z0-9]{6})-([0-9]{3})$'),
      RegExp(r'^([A-Z0-9]{6})([0-9]{3})$'),
      RegExp(r'^([A-Z0-9]{6})[\s./\-–_]+([0-9]{3})$'),
      RegExp(r'^([A-Z0-9]{6})-([0-9]{4})$'),
      RegExp(r'^([A-Z0-9]{6})([0-9]{4})$'),
      RegExp(r'^([A-Z0-9]{7})-([0-9]{3})$'),
      RegExp(r'^([A-Z0-9]{7})([0-9]{3})$'),
      RegExp(r'^([0-9]{4}[A-Z][0-9]{3})-([0-9]{3})$'),
      RegExp(r'^([A-Z0-9]{8})-([0-9]{2,3})$'),
      RegExp(r'^([A-Z0-9]{8})[\s./\-–_]+([0-9]{2,3})$'),
      RegExp(r'^([A-Z0-9]{8})([0-9]{3})$'),
      RegExp(r'^([0-9]{6})-([0-9]{2})$'),
      RegExp(r'^([0-9]{6})-([0-9]{2,3})$'),
      RegExp(r'^([0-9]{6})[\s./\-–_]+([0-9]{2,3})$'),
      RegExp(r'^(?:[MWU])([0-9]{4}[A-Z]?)([A-Z]{2,6})$'),
      RegExp(r'^([A-Z]{2}[0-9]{3})([A-Z0-9]{2,6})$'),
      RegExp(r'^([A-Z]{2})([0-9]{4})$'),
      RegExp(r'^([A-Z0-9]{6})$'),
      RegExp(r'^([A-Z][0-9]{5}[A-Z])$'),
      // Skechers: 232123/BLK, M232123-BBK, 200291W/BLK
      RegExp(r'^(?:[MW])?([0-9]{5,6}[A-Z]?)[\s./\-–_]+([A-Z]{2,4})$'),
      // Vans: VN0A38FRX9C, VN0A4BV6...
      RegExp(r'^VN0[A-Z0-9]{6,8}$'),
      RegExp(r'^(VN0[A-Z0-9]{4})([A-Z0-9]{2,4})$'),
      RegExp(r'^([A-Z0-9]{9,11})$'),
      RegExp(r'^VN0[A-Z0-9]{3,5}[\s./\-–_]*[A-Z0-9]{2,4}$'),
    ],
    'nike': [
      RegExp(r'^([A-Z0-9]{6})-([0-9]{3})$'),
      RegExp(r'^([A-Z0-9]{6})([0-9]{3})$'),
      RegExp(r'^([A-Z0-9]{6})[\s./\-–_]+([0-9]{3})$'),
      RegExp(r'^([A-Z0-9]{6})-([0-9]{4})$'),
      RegExp(r'^([A-Z0-9]{6})([0-9]{4})$'),
      RegExp(r'^([A-Z0-9]{7})-([0-9]{3})$'),
      RegExp(r'^([A-Z0-9]{7})([0-9]{3})$'),
    ],
    'asics': [
      RegExp(r'^([0-9]{4}[A-Z][0-9]{3})-([0-9]{3})$'),
      RegExp(r'^([A-Z0-9]{8})-([0-9]{2,3})$'),
      RegExp(r'^([A-Z0-9]{8})[\s./\-–_]+([0-9]{2,3})$'),
      RegExp(r'^([A-Z0-9]{8})([0-9]{3})$'),
    ],
    'puma': [
      RegExp(r'^([0-9]{6})-([0-9]{2})$'),
      RegExp(r'^([0-9]{6})-([0-9]{2,3})$'),
      RegExp(r'^([0-9]{6})[\s./\-–_]+([0-9]{2,3})$'),
    ],
    'new_balance': [
      RegExp(r'^(?:[MWU])([0-9]{4}[A-Z]?)([A-Z]{2,6})$'),
      RegExp(r'^([A-Z]{2}[0-9]{3})([A-Z0-9]{2,6})$'),
    ],
    'adidas': [RegExp(r'^([A-Z0-9]{6})$'), RegExp(r'^([A-Z]{2})([0-9]{4})$')],
    'reebok': [RegExp(r'^([A-Z]{2}[0-9]{4})$'), RegExp(r'^([A-Z0-9]{6})$')],
    'converse': [RegExp(r'^([A-Z][0-9]{5}[A-Z])$')],
    'skechers': [
      RegExp(r'^(?:[MW])?([0-9]{5,6}[A-Z]?)[\s./\-–_]+([A-Z]{2,4})$'),
      RegExp(r'^(?:[MW])?([0-9]{5,6}[A-Z]?)([A-Z]{2,4})$'),
      RegExp(r'^(?:[MW])?([0-9]{5,6}[A-Z]?)$'),
    ],
    'vans': [
      RegExp(r'^VN0[A-Z0-9]{6,8}$'),
      RegExp(r'^(VN0[A-Z0-9]{4})([A-Z0-9]{2,4})$'),
      RegExp(r'^([A-Z0-9]{9,11})$'),
      RegExp(r'^VN0[A-Z0-9]{3,5}[\s./\-–_]*[A-Z0-9]{2,4}$'),
    ],
  };

  static String? _brandKeyFromName(String? brand) {
    if (brand == null) return null;
    switch (brand.toUpperCase()) {
      case 'NIKE':
      case 'JORDAN':
        return 'nike';
      case 'NEW BALANCE':
        return 'new_balance';
      case 'ADIDAS':
        return 'adidas';
      case 'PUMA':
        return 'puma';
      case 'ASICS':
        return 'asics';
      case 'REEBOK':
        return 'reebok';
      case 'CONVERSE':
        return 'converse';
      case 'SKECHERS':
      case 'SKETCHERS':
        return 'skechers';
      case 'VANS':
        return 'vans';
      default:
        return null;
    }
  }

  // Strong disqualifiers from sku_validation.json
  static final _strongDisqualifiers = [
    RegExp(r'^[0-9]{12,14}$'), // GTIN / UPC / EAN
    RegExp(r'^(US|UK|EU|CM|MM)?\s?[0-9]{1,2}(\.[0-9])?$'), // Size value
    RegExp(r'^[A-Z]{2}[0-9]{2}$'), // Season code (FW23, SP24)
    RegExp(r'^(19|20)[0-9]{2}$'), // 4-digit year
    RegExp(r'^[A-Z]{6,11}$'), // All letters, no digits
  ];

  bool _isValidSku(String code, String? brand) {
    final upper = code.toUpperCase();
    final alphanumOnly = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (alphanumOnly.length < 6 || alphanumOnly.length > 11) return false;

    // Must contain at least one digit
    if (!alphanumOnly.contains(RegExp(r'[0-9]'))) return false;

    // Check strong disqualifiers against both raw and alphanumeric forms
    if (_strongDisqualifiers.any((p) => p.hasMatch(alphanumOnly))) return false;
    if (_strongDisqualifiers.any((p) => p.hasMatch(upper))) return false;

    // Validate raw form against brand patterns (patterns already handle
    // various separators: hyphens, spaces, dots, slashes)
    final brandKey = _brandKeyFromName(brand);
    final patterns =
        (brandKey != null && _brandSkuPatterns.containsKey(brandKey))
        ? _brandSkuPatterns[brandKey]!
        : _brandSkuPatterns['all']!;
    return patterns.any((p) => p.hasMatch(upper));
  }

  static const _disqualifyingKeywords = [
    'UPC',
    'U.P.C.',
    'BARCODE',
    'PO#',
    'PO ',
    'P.O.',
    'PURCHASE ORDER',
    'ORDER#',
    'ORDER ',
  ];

  /// Check if a candidate appears on an OCR line preceded (within 12 chars)
  /// by a disqualifying keyword like UPC, PO#, BARCODE, etc.
  bool _isDisqualifiedByContext(String candidate, List<String> ocrLines) {
    for (final line in ocrLines) {
      final upperLine = line.trim().toUpperCase();
      final idx = upperLine.indexOf(candidate);
      if (idx < 0) continue;
      final prefixStart = (idx - 12).clamp(0, idx);
      final prefix = upperLine.substring(prefixStart, idx);
      if (_disqualifyingKeywords.any((kw) => prefix.contains(kw))) {
        return true;
      }
    }
    return false;
  }

  /// Returns the normalized SKU ready to send to APIs.
  /// For most brands: just uppercase + trim.
  /// For Skechers: also corrects OCR misreading '/' as 'I'
  /// (e.g. 200291WIBLK → 200291W/BLK).
  /// Preserve the exact OCR form of the SKU — just uppercase and trim.
  String _formatSkuForBrand(String rawCode, String? brand) {
    return rawCode.trim().toUpperCase();
  }

  /// Returns true if the user can start a scan (has available scans or active subscription).
  /// If not, shows the paywall and returns true only if they then subscribe.
  Future<bool> _checkSubscription() async {
    final sub = SubscriptionService.instance;
    if (sub.status == SubscriptionStatus.loading) {
      // Brief wait for the initial Firebase snapshot
      await Future.delayed(const Duration(milliseconds: 600));
    }
    if (sub.canScan) return true;
    if (!mounted) return false;
    final subscribed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const PaywallPage(),
      ),
    );
    return subscribed == true;
  }

  Future<void> _captureAndProcess() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) return;

      setState(() => _isProcessing = true);

      // Run OCR — Apple Vision on iOS, ML Kit on Android.
      final String fullText;
      if (Platform.isIOS) {
        fullText =
            await _ocrChannel.invokeMethod<String>('recognizeText', {
              'imagePath': photo.path,
            }) ??
            '';
        debugPrint('OCR text (Vision): $fullText');
      } else {
        final inputImage = InputImage.fromFilePath(photo.path);
        final textRecognizer = TextRecognizer();
        try {
          final recognizedText = await textRecognizer.processImage(inputImage);
          fullText = recognizedText.text;
          debugPrint('OCR text (ML Kit): $fullText');
        } finally {
          textRecognizer.close();
        }
      }

      // Parse OCR text into ScanData
      final scanData = _parseLabelInfo(fullText);

      debugPrint('═══ SCAN RESULT ═══');
      if (scanData.sku != null) {
        debugPrint('SKU found: ${scanData.sku}');
      } else {
        debugPrint('SKU: not found');
      }
      debugPrint(
        'Brand: ${scanData.brand ?? 'n/a'}, '
        'Size: ${scanData.size ?? 'n/a'}',
      );
      debugPrint('═══════════════════');

      if (scanData.sku != null) {
        // SKU found — go directly to detail page
        if (mounted) {
          final nav = Navigator.of(context);
          await _previewController.stop();
          await SubscriptionService.instance.incrementScanCount();
          final result = await nav.push<String>(
            MaterialPageRoute(
              builder: (context) => ScanDetailPage(
                scanId: '',
                scanData: scanData,
                timestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            ),
          );
          if (mounted && result == 'noResults') {
            _showNoResultsModal(
              scanData,
              onEnterManually: () => _showManualSkuDialog(fullText, scanData),
            );
          } else if (mounted && result == 'scanAnother') {
            // camera restarted by didPopNext()
          } else if (mounted) {
            context.findAncestorStateOfType<MainScreenState>()?.switchToTab(1);
          }
        }
      } else {
        // No SKU — show dialog with option to enter manually or proceed without
        if (mounted) {
          _showManualSkuDialog(fullText, scanData);
        }
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to process image: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _scanBarcode(String ocrText, ScanData currentScanData) async {
    // Release the camera before pushing the barcode scanner — iOS only allows
    // one active capture session at a time.
    await _previewController.stop();
    if (!mounted) return;

    final gtin = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const _BarcodeScannerPage()),
    );

    if (!mounted) return;

    if (gtin != null) {
      debugPrint('═══ BARCODE SCAN ═══');
      debugPrint('GTIN found: $gtin');
      debugPrint('═══════════════════');

      final data = currentScanData.copyWith(gtin: gtin);
      if (mounted) {
        await SubscriptionService.instance.incrementScanCount();
        if (!mounted) return;
        final result = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (context) => ScanDetailPage(
              scanId: '',
              scanData: data,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
        );
        if (mounted && result == 'noResults') {
          _showNoResultsModal(data);
        } else if (mounted && result == 'scanAnother') {
          // camera restarted by didPopNext()
        } else if (mounted) {
          context.findAncestorStateOfType<MainScreenState>()?.switchToTab(1);
        }
      }
    } else {
      // User cancelled — wait for the barcode scanner's camera session to
      // fully release (triggered by PopScope) before reactivating our preview.
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      await _startCamera();
      if (mounted) _showManualSkuDialog(ocrText, currentScanData);
    }
  }

  void _showManualSkuDialog(String ocrText, ScanData currentScanData) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
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
                ocrText.isEmpty ? 'Enter SKU' : 'No SKU Found',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ocrText.isEmpty
                    ? 'Type the SKU from the shoe label.'
                    : 'We couldn\'t detect a SKU. Enter it manually or scan the barcode.',
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
                      onPressed: () async {
                        final sku = controller.text.trim().toUpperCase();
                        if (sku.isEmpty) return;
                        Navigator.of(dialogContext).pop();
                        await _previewController.stop();
                        final data = currentScanData.copyWith(sku: sku);
                        if (mounted) {
                          await SubscriptionService.instance
                              .incrementScanCount();
                          if (!mounted) return;
                          final result = await Navigator.of(context)
                              .push<String>(
                                MaterialPageRoute(
                                  builder: (context) => ScanDetailPage(
                                    scanId: '',
                                    scanData: data,
                                    timestamp:
                                        DateTime.now().millisecondsSinceEpoch,
                                  ),
                                ),
                              );
                          if (mounted && result == 'noResults') {
                            _showNoResultsModal(data);
                          } else if (mounted && result == 'scanAnother') {
                            // camera restarted by didPopNext()
                          } else if (mounted) {
                            context
                                .findAncestorStateOfType<MainScreenState>()
                                ?.switchToTab(1);
                          }
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    if (!await _checkSubscription()) return;
                    // Drop any OCR-derived SKU so the barcode GTIN is the
                    // sole identifier — avoids SKU taking priority over GTIN.
                    _scanBarcode(
                      ocrText,
                      ScanData(brand: currentScanData.brand),
                    );
                  },
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan Barcode'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey[600]!),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    if (!await _checkSubscription()) return;
                    _showTitleSearchDialog(currentScanData);
                  },
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Search by Title'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey[600]!),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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

  void _showTitleSearchDialog(ScanData currentScanData) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
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
                'Search by Title',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the shoe name, model, colorway, or any text from the label.',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.inter(fontSize: 15, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. Nike Air Max 90 White',
                  hintStyle: GoogleFonts.inter(
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
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final title = controller.text.trim();
                        if (title.isEmpty) return;
                        Navigator.of(dialogContext).pop();
                        final nav = Navigator.of(context);
                        await _previewController.stop();
                        final data = ScanData(
                          brand: currentScanData.brand,
                          titleSearch: title,
                        );
                        if (!mounted) return;
                        await SubscriptionService.instance.incrementScanCount();
                        final result = await nav.push<String>(
                          MaterialPageRoute(
                            builder: (context) => ScanDetailPage(
                              scanId: '',
                              scanData: data,
                              timestamp: DateTime.now().millisecondsSinceEpoch,
                            ),
                          ),
                        );
                        if (mounted && result == 'noResults') {
                          _showNoResultsModal(data);
                        } else if (mounted && result == 'scanAnother') {
                          // camera restarted by didPopNext()
                        } else if (mounted) {
                          context
                              .findAncestorStateOfType<MainScreenState>()
                              ?.switchToTab(1);
                        }
                      },
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Search'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF646CFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
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

  void _showNoResultsModal(ScanData scanData, {VoidCallback? onEnterManually}) {
    final identifier = scanData.sku ?? scanData.gtin ?? 'the scanned item';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
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
              Icon(Icons.search_off, size: 48, color: Colors.grey[500]),
              const SizedBox(height: 16),
              Text(
                'No Results Found',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No marketplace listings were found for $identifier.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF646CFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('OK'),
                ),
              ),
              if (onEnterManually != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Wrong SKU detected?',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      onEnterManually();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey[600]!),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Enter SKU Manually'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
              'Take a photo of a shoe label on the box',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),

            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 300,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _previewController,
                      onDetect: (_) {},
                      errorBuilder: (context, error) =>
                          const ColoredBox(color: Colors.black),
                    ),
                    if (_isProcessing)
                      Container(
                        color: Colors.black54,
                        child: Center(
                          child: Column(
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
                                  color: Colors.white70,
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
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () async {
                        if (await _checkSubscription()) _captureAndProcess();
                      },
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
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () async {
                        if (await _checkSubscription()) {
                          _showManualSkuDialog('', const ScanData());
                        }
                      },
                icon: const Icon(Icons.keyboard, size: 18),
                label: const Text('Enter SKU Manually'),
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
          ],
        ),
      ),
    );
  }
}

/// Full-screen live barcode scanner that auto-detects barcodes.
/// Returns the normalized GTIN string via Navigator.pop, or null if cancelled.
class _BarcodeScannerPage extends StatefulWidget {
  const _BarcodeScannerPage();

  @override
  State<_BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  static const double _boxWidth = 280;
  static const double _boxHeight = 160;

  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
    formats: [BarcodeFormat.ean13, BarcodeFormat.upcA],
  );
  bool _hasPopped = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasPopped) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        final normalized = normalizeGtin(raw);
        if (normalized.length >= 12) {
          _hasPopped = true;
          Navigator.of(context).pop(normalized);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final bodyHeight = size.height - topPadding - kToolbarHeight;
    final scanWindow = Rect.fromLTWH(
      (size.width - _boxWidth) / 2,
      (bodyHeight - _boxHeight) / 2,
      _boxWidth,
      _boxHeight,
    );

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _controller.stop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            'Scan Barcode',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              icon: ValueListenableBuilder(
                valueListenable: _controller,
                builder: (context, state, child) {
                  return Icon(
                    state.torchState == TorchState.on
                        ? Icons.flash_on
                        : Icons.flash_off,
                  );
                },
              ),
              onPressed: () => _controller.toggleTorch(),
            ),
          ],
        ),
        body: Stack(
          children: [
            MobileScanner(
              controller: _controller,
              scanWindow: scanWindow,
              onDetect: _onDetect,
              errorBuilder: (context, error) =>
                  const ColoredBox(color: Colors.black),
            ),
            // Scan overlay — dimensions must match scanWindow above
            Center(
              child: Container(
                width: _boxWidth,
                height: _boxHeight,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF646CFF), width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            // Instruction text
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Text(
                'Point camera at the barcode',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 15, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
