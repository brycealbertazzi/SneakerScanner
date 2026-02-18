import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/scan_data.dart';
import '../services/gtin_utils.dart';
import 'main_screen.dart';
import 'scan_detail/scan_detail_page.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  bool _isProcessing = false;

  final ImagePicker _imagePicker = ImagePicker();
  final MobileScannerController _previewController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _previewController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _previewController.stop();
    } else if (state == AppLifecycleState.resumed) {
      _previewController.start();
    }
  }

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
      debugPrint('All SKU candidates rejected for brand "${foundBrand ?? 'unknown'}": $allCandidates');
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
    'adidas': [
      RegExp(r'^([A-Z0-9]{6})$'),
      RegExp(r'^([A-Z]{2})([0-9]{4})$'),
    ],
    'reebok': [
      RegExp(r'^([A-Z]{2}[0-9]{4})$'),
      RegExp(r'^([A-Z0-9]{6})$'),
    ],
    'converse': [
      RegExp(r'^([A-Z][0-9]{5}[A-Z])$'),
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
      default:
        return null;
    }
  }

  // Strong disqualifiers from sku_validation.json
  static final _strongDisqualifiers = [
    RegExp(r'^[0-9]{12,14}$'),                          // GTIN / UPC / EAN
    RegExp(r'^(US|UK|EU|CM|MM)?\s?[0-9]{1,2}(\.[0-9])?$'), // Size value
    RegExp(r'^[A-Z]{2}[0-9]{2}$'),                      // Season code (FW23, SP24)
    RegExp(r'^(19|20)[0-9]{2}$'),                        // 4-digit year
    RegExp(r'^[A-Z]{6,11}$'),                            // All letters, no digits
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
    final patterns = (brandKey != null && _brandSkuPatterns.containsKey(brandKey))
        ? _brandSkuPatterns[brandKey]!
        : _brandSkuPatterns['all']!;
    return patterns.any((p) => p.hasMatch(upper));
  }

  // Brands whose SKUs use a hyphen between base and suffix
  static const _hyphenatedBrands = {'nike', 'puma', 'asics'};

  static const _disqualifyingKeywords = [
    'UPC', 'U.P.C.', 'BARCODE', 'PO#', 'PO ', 'P.O.', 'PURCHASE ORDER',
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

  /// Format the chosen SKU for storage using brand-specific conventions.
  /// Called only AFTER validation passes — raw OCR form goes in, formatted comes out.
  String _formatSkuForBrand(String rawCode, String? brand) {
    final upper = rawCode.toUpperCase();
    final brandKey = _brandKeyFromName(brand);

    if (brandKey != null && _hyphenatedBrands.contains(brandKey)) {
      // For hyphenated brands: match against brand patterns to find groups
      final patterns = _brandSkuPatterns[brandKey]!;
      for (final pattern in patterns) {
        final match = pattern.firstMatch(upper);
        if (match != null && match.groupCount >= 2) {
          final parts = <String>[];
          for (int i = 1; i <= match.groupCount; i++) {
            if (match.group(i) != null) parts.add(match.group(i)!);
          }
          return parts.join('-');
        } else if (match != null) {
          return match.groupCount >= 1 ? match.group(1)! : match.group(0)!;
        }
      }
    } else if (brandKey != null) {
      // Non-hyphenated brands (adidas, NB, reebok, converse): strip separators
      return upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    }

    // Unknown brand: replace OCR separators (space/dot/slash) with hyphen
    // where they exist, but don't add hyphens where there were none
    final cleaned = upper.replaceAll(RegExp(r'[\s./]+'), '-');
    // Collapse multiple hyphens and trim trailing/leading hyphens
    return cleaned.replaceAll(RegExp(r'-{2,}'), '-').replaceAll(RegExp(r'^-|-$'), '');
  }

  Future<void> _captureAndProcess() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) return;

      setState(() => _isProcessing = true);

      final inputImage = InputImage.fromFilePath(photo.path);

      // Run OCR on the captured image
      final textRecognizer = TextRecognizer();

      try {
        final recognizedText = await textRecognizer.processImage(inputImage);

        final fullText = recognizedText.text;
        debugPrint('OCR text: $fullText');

        // Parse OCR text into ScanData
        final scanData = _parseLabelInfo(fullText);

        debugPrint('═══ SCAN RESULT ═══');
        if (scanData.sku != null) {
          debugPrint('SKU found: ${scanData.sku}');
        } else {
          debugPrint('SKU: not found');
        }
        debugPrint('Brand: ${scanData.brand ?? 'n/a'}, '
            'Size: ${scanData.size ?? 'n/a'}');
        debugPrint('═══════════════════');

        if (scanData.sku != null) {
          // SKU found — go directly to detail page
          if (mounted) {
            final result = await Navigator.of(context).push<String>(
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
      } finally {
        textRecognizer.close();
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
      MaterialPageRoute(
        builder: (context) => const _BarcodeScannerPage(),
      ),
    );

    if (!mounted) return;

    if (gtin != null) {
      debugPrint('═══ BARCODE SCAN ═══');
      debugPrint('GTIN found: $gtin');
      debugPrint('═══════════════════');

      final data = currentScanData.copyWith(gtin: gtin);
      if (mounted) {
        final result = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (context) => ScanDetailPage(
              scanId: '',
              scanData: data,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
        );
        // User returned from ScanDetailPage — safe to restart camera now
        // (barcode scanner controller is long disposed by this point).
        if (mounted) await _previewController.start();
        if (mounted && result == 'noResults') {
          _showNoResultsModal(data);
        } else if (mounted) {
          context.findAncestorStateOfType<MainScreenState>()?.switchToTab(1);
        }
      }
    } else {
      // User cancelled — barcode scanner is disposed, restart camera before
      // showing the dialog again.
      await _previewController.start();
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
                    ? 'Type the SKU from the shoe label or box.'
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
                        final data = currentScanData.copyWith(sku: sku);
                        if (mounted) {
                          final result = await Navigator.of(context).push<String>(
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
                          } else if (mounted) {
                            context.findAncestorStateOfType<MainScreenState>()?.switchToTab(1);
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
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _scanBarcode(ocrText, currentScanData);
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
              'Take a photo of a shoe label or box',
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
                onPressed: _isProcessing ? null : _captureAndProcess,
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
                    : () => _showManualSkuDialog('', const ScanData()),
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

    return Scaffold(
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
              style: GoogleFonts.inter(
                fontSize: 15,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
